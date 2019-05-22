//
//  ViewController.m
//  FaceTest
//
//  Created by BTI-HXW on 2019/5/13.
//  Copyright © 2019 BTI-HXW. All rights reserved.
//

#import "ViewController.h"

#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<AVCaptureVideoDataOutputSampleBufferDelegate, AVCaptureMetadataOutputObjectsDelegate>
@property (nonatomic,strong) AVCaptureSession *session;
@property (nonatomic,strong) dispatch_queue_t sample;
/**
 视频输出展示layer，系统自带
 */
@property (nonatomic, strong) AVCaptureVideoPreviewLayer *previewLayer;
/**
 视频输出的单帧数据
 */
@property (nonatomic) CMSampleBufferRef p;
/**
 截图timer
 */
@property (nonatomic, strong) NSTimer *timer;

/**
 脸部识别结果数据，识别脸部成功有数据
 */
@property (nonatomic, copy) NSArray *metadatas;
/**
 将脸部原始数据转换坐标系统后的临时数据（原始脸部数据所在的坐标系统与开发者用的坐标系不一样，需要转换）
 */
@property (nonatomic, strong) NSMutableArray *tempArr;

/**
 脸部识别框所在layer层
 */
@property (nonatomic, strong) CALayer *overLayer;
/**
 标记脸部位置集合layers ，以AVMetadataFaceObject为key，layer为value
 */
@property (nonatomic, strong) NSMutableDictionary<AVMetadataFaceObject*,CAShapeLayer*> *shapLs;
/**
 截图按钮点击标记
 */
@property (nonatomic, assign) BOOL clicked;
- (IBAction)click:(id)sender;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
//    [self.view addSubview: self.cameraView];
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    _sample = dispatch_queue_create("sample", NULL);
    self.metadatas = [NSArray new];
    self.tempArr = [NSMutableArray new];
    [self setAVCaptureSession];
    
}
- (void) setAVCaptureSession{
    NSArray *devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
    AVCaptureDevice *deviceF;
    for (AVCaptureDevice *device in devices )
    {
        if ( device.position == AVCaptureDevicePositionFront )
        {
            deviceF = device;
            break;
        }
    }
    ///拿到采集设备，这里用的是前置摄像头
    AVCaptureDeviceInput*input = [[AVCaptureDeviceInput alloc] initWithDevice:deviceF error:nil];
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    ///设置代理及视频流输出队列，这里采用的是自定义一个子队列，窜行队列
    [output setSampleBufferDelegate:self queue:_sample];
    ///创建AVCaptureSession
    self.session = [[AVCaptureSession alloc] init];
    [self.session beginConfiguration];
    ///添加输入流
    if ([self.session canAddInput:input]) {
        [self.session addInput:input];
    }
    ///设置分辨率
    if ([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {
        [self.session setSessionPreset:AVCaptureSessionPreset640x480];
    }
    ///添加视频输出流
    if ([self.session canAddOutput:output]) {
        [self.session addOutput:output];
    }
    ///设置输出流参数
    NSString     *key           = (NSString *)kCVPixelBufferPixelFormatTypeKey;
    NSNumber     *value         = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];
    NSDictionary *videoSettings = [NSDictionary dictionaryWithObject:value forKey:key];
    [output setVideoSettings:videoSettings];
    ///初始化添加AVCaptureMetadataOutput
    AVCaptureMetadataOutput* metaOutput = [AVCaptureMetadataOutput new];
    [self.session addOutput:metaOutput];
    ///设置识别人脸AVMetadataObjectTypeFace（如果是二维码，那就是AVMetadataObjectTypeQRCode）
    [metaOutput setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];
    ///设置人脸识别输出流代理及队列，窜行子队列，检测到人脸，代理输出数据流
    [metaOutput setMetadataObjectsDelegate:self queue:dispatch_queue_create("face", NULL)];
    metaOutput.rectOfInterest = self.view.bounds;
    ///提交session设置
    [self.session commitConfiguration];

    AVCaptureSession* session = (AVCaptureSession *)self.session;
    //前置摄像头一定要设置一下 要不然画面是镜像
    for (AVCaptureVideoDataOutput* output in session.outputs) {
        for (AVCaptureConnection * av in output.connections) {
            //判断是否是前置摄像头状态
            if (av.supportsVideoMirroring) {
                //镜像设置
                av.videoOrientation = AVCaptureVideoOrientationPortrait;
                av.videoMirrored = YES;
            }
        }
    }
    ///设置输出流展示AVCaptureVideoPreviewLayer
    AVCaptureVideoPreviewLayer* previewLayer = [AVCaptureVideoPreviewLayer layerWithSession:self.session];
    previewLayer.videoGravity = AVLayerVideoGravityResizeAspectFill;
    previewLayer.frame = self.view.bounds;
    [self.view.layer insertSublayer:previewLayer atIndex:0];
    self.previewLayer = previewLayer;
    ///开始任务
    [self.session startRunning];
}
- (void)viewDidDisappear:(BOOL)animated{
    [super viewDidDisappear:animated];
    [self.timer invalidate];
    self.timer = nil;
    [self.session stopRunning];
}

#pragma mark - AVCaptureSession Delegate -
///摄像头输出流
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection
{
    [self.tempArr removeAllObjects];
    self.p = sampleBuffer;
    for (AVMetadataFaceObject *faceobject in self.metadatas) {
        AVMetadataFaceObject *face = (AVMetadataFaceObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:faceobject];
        [self.tempArr addObject:face];
        
    }
    [self detectForFacesInUIImage:nil];
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        
//        weakSelf.cameraView.image = image;
        if (hasFace) {
            @synchronized (weakSelf) {
                [weakSelf.shapLs.allKeys enumerateObjectsUsingBlock:^(AVMetadataFaceObject * _Nonnull faceObject, NSUInteger idx, BOOL * _Nonnull stop) {
                    CAShapeLayer* shapLayer = [weakSelf.shapLs objectForKey:faceObject];
                    shapLayer.transform = CATransform3DIdentity;
                    if (faceObject.hasYawAngle) {
                        CATransform3D transform = [self transformDegressyawAngle:faceObject.yawAngle];
                        shapLayer.transform = CATransform3DConcat(shapLayer.transform, transform);
                    }
                    if (faceObject.hasRollAngle) {
                        CATransform3D transform = [self transformDegressyawAngle:faceObject.rollAngle];
                        shapLayer.transform = CATransform3DConcat(shapLayer.transform, transform);
                    }
                    [weakSelf.overLayer addSublayer:shapLayer];
                }];
            }
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                @synchronized (self) {
                    [weakSelf.shapLs.allValues makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
                    [weakSelf.shapLs removeAllObjects];
                    [weakSelf.overLayer removeFromSuperlayer];
                    weakSelf.overLayer = nil;
                }
            });
        }
        
    });
}
///人脸识别代理
-(void)captureOutput:(AVCaptureOutput *)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)metadataObjects fromConnection:(AVCaptureConnection *)connection{
    self.metadatas = metadataObjects;
}


///重新开始人脸识别
- (IBAction)restart:(id)sender {
    [[NSRunLoop currentRunLoop] addTimer:self.timer forMode:NSRunLoopCommonModes];
    [self.shapLs.allValues makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [self.shapLs removeAllObjects];
    self.clicked = NO;
    [self.session startRunning];
    
    
}
///截图
- (IBAction)click:(id)sender {
    
    @synchronized (self) {
        self.clicked = YES;
        if (hasFace) {
            
            [self timerFire:nil];

            
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                [self showNoFaceToast]; });
        }
        
    }
}
-(AVCaptureVideoOrientation)avOrientationForDeviceOrientation:(UIDeviceOrientation)deviceOrientation
{
    AVCaptureVideoOrientation result = (AVCaptureVideoOrientation)deviceOrientation;
    if ( deviceOrientation == UIDeviceOrientationLandscapeLeft )
        result = AVCaptureVideoOrientationLandscapeRight;
    else if ( deviceOrientation == UIDeviceOrientationLandscapeRight )
        result = AVCaptureVideoOrientationLandscapeLeft;
    return result;
}

///检测人脸
static BOOL hasFace = NO;
- (void)detectForFacesInUIImage:(UIImage*)facePicture {
    @synchronized (self) {
        [self.shapLs.allValues makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
        [self.shapLs removeAllObjects];
    }
    
    @synchronized (self) {
        hasFace = self.tempArr.count > 0;
    }

   ///人脸识别后处理
    for (AVMetadataFaceObject *faceObject  in self.tempArr) {
       
        CGRect modifiedFaceBounds = faceObject.bounds;
        @synchronized (self) {
            if (!self.clicked) {
                CAShapeLayer* shapLayer = [self getFaceLayer:modifiedFaceBounds];
                
                [self.shapLs setObject:shapLayer forKey:faceObject];
            }
        }
    }
}
//眼睛到物体的距离
- (CATransform3D)CATransform3DMakePerspective:(CGFloat)eyePosition {
    CATransform3D transform = CATransform3DIdentity;
    //m34: 透视效果; 近大远小
    transform.m34 = -1 / eyePosition;
    return transform;
}
//处理倾斜角问题
-(CATransform3D) transformDegressyawAngle:(CGFloat)yawAngle {
    CGFloat yaw = [self degreesToRadians:yawAngle];
    //围绕Y轴旋转
    CATransform3D yawTran = CATransform3DMakeRotation(yaw, 0, -1, 0);
    //红框旋转问题
    return CATransform3DConcat(yawTran, CATransform3DIdentity);
}

//处理偏转角问题
- (CATransform3D)transformDegress:(CGFloat)rollAngle{
    CGFloat roll = [self degreesToRadians:rollAngle];
    //围绕Z轴旋转
    return CATransform3DMakeRotation(roll, 0, 0, 1);
}

//角度转换
-(CGFloat) degreesToRadians:(CGFloat)degress{
    return degress * M_PI / 180.0;
}

///根据脸部位置生成layer
- (CAShapeLayer*)getFaceLayer:(CGRect)rect{
    
    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:0];
    CAShapeLayer *pathLayer = [CAShapeLayer layer];
    pathLayer.lineWidth = 2;
    pathLayer.strokeColor = [UIColor greenColor].CGColor;
    pathLayer.path = path.CGPath;
    [pathLayer setFillColor:[UIColor clearColor].CGColor];
    return pathLayer;
}
-(NSMutableDictionary<AVMetadataFaceObject * ,CAShapeLayer*> *)shapLs{
    if (!_shapLs) {
        _shapLs = [[NSMutableDictionary alloc]init];
    }
    return _shapLs;
}
- (CGFloat)getScale:(CALayer*)imageView image:(UIImage*)image {
    CGSize viewSize = imageView.frame.size;
    CGSize imageSize = image.size;
    
    CGFloat widthScale = imageSize.width / viewSize.width;
    CGFloat heightScale = imageSize.height / viewSize.height;
    
    return widthScale > heightScale ? widthScale : heightScale;
}
- (void) showNoFaceToast{
    UIAlertView* alert = [[UIAlertView alloc]initWithTitle:@"人脸识别失败" message:@"没有识别到人脸，不能截图" delegate:nil cancelButtonTitle:@"知道了" otherButtonTitles:nil];
    [alert show];
}
-(CALayer *)overLayer{
    if (!_overLayer) {
        _overLayer = [[CALayer alloc]init];
        _overLayer.frame = self.view.bounds;
        _overLayer.sublayerTransform = [self CATransform3DMakePerspective:1000];
        [self.view.layer addSublayer:_overLayer];
    }
    return _overLayer;
}
-(NSTimer *)timer{
    if (!_timer) {
        __weak typeof(self) weakSelf = self;
        if (@available(iOS 10.0, *)) {
            _timer = [NSTimer scheduledTimerWithTimeInterval:10.0 repeats:YES block:^(NSTimer * _Nonnull timer) {
                @synchronized (weakSelf) {
                    if (hasFace) {
                        [weakSelf.session stopRunning];
                        [weakSelf.shapLs.allValues makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
                        [weakSelf.shapLs removeAllObjects];
                        [weakSelf.overLayer removeFromSuperlayer];
                        weakSelf.overLayer = nil;
                        UIImage* img = [weakSelf imageFromPixelBuffer:weakSelf.p];
                        [weakSelf.overLayer setContents:img];
                        [weakSelf.timer invalidate];
                        weakSelf.timer = nil;
                    }
                }
            }];
        } else {
            _timer = [NSTimer scheduledTimerWithTimeInterval:10.0 target:self selector:@selector(timerFire:) userInfo:nil repeats:YES];
        }
    }
    return _timer;
}
-(void)timerFire:(NSTimer*)timer{
    @synchronized (self) {
        if (hasFace) {
            [self.session stopRunning];
            [self.shapLs.allValues makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
            [self.shapLs removeAllObjects];
            [self.overLayer removeFromSuperlayer];
            self.overLayer = nil;
            UIImage* img = [self imageFromPixelBuffer:self.p];
            [self.overLayer setContents:img];
            [self.timer invalidate];
            self.timer = nil;
            
        }else{
            [self showNoFaceToast];
        }
    }
}
///samplebuffer转image
- (UIImage*)imageFromPixelBuffer:(CMSampleBufferRef)p {
    //    cmpv
    CVImageBufferRef buffer;
    buffer = CMSampleBufferGetImageBuffer(p);
    
    CVPixelBufferLockBaseAddress(buffer, 0);
    uint8_t *base;
    size_t width, height, bytesPerRow;
    base = (uint8_t *)CVPixelBufferGetBaseAddress(buffer);
    width = CVPixelBufferGetWidth(buffer);
    height = CVPixelBufferGetHeight(buffer);
    bytesPerRow = CVPixelBufferGetBytesPerRow(buffer);
    
    CGColorSpaceRef colorSpace;
    CGContextRef cgContext;
    colorSpace = CGColorSpaceCreateDeviceRGB();
    cgContext = CGBitmapContextCreate(base, width, height, 8, bytesPerRow, colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
    CVPixelBufferUnlockBaseAddress(buffer, 0);
    CGColorSpaceRelease(colorSpace);
    
    CGImageRef cgImage;
    UIImage *image;
    cgImage = CGBitmapContextCreateImage(cgContext);
    image = [UIImage imageWithCGImage:cgImage];
    CGImageRelease(cgImage);
    CGContextRelease(cgContext);
    
    return image;
}

@end

# DetectorFaceDemo
人脸识别demo

系统API主要是AVCaptureMetadataOutput和CIDetector，是两种不同的方式，前者是需要配合AVCaptureSession使用，属于AVFoundation层，后者可以直接拿到图片image识别，属于CoreImage层，我暂且把区分为动态跟静态。

一、AVCaptureMetadataOutput的用法：

1、设置输入输出流：

///拿到采集设备，这里用的是前置摄像头

    AVCaptureDeviceInput*input = [[AVCaptureDeviceInput alloc] initWithDevice:deviceF error:nil];

    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];

    ///设置代理及视频流输出队列，这里采用的是自定义一个子队列，窜行队列

    [output setSampleBufferDelegate:self queue:_sample];

    ///创建AVCaptureSession

    self.session = [[AVCaptureSession alloc] init];

    [self.session beginConfiguration];

    ///添加输入流

    if([self.session canAddInput:input]) {

        [self.session addInput:input];

    }

    ///设置分辨率

    if ([self.session canSetSessionPreset:AVCaptureSessionPreset640x480]) {

        [self.session setSessionPreset:AVCaptureSessionPreset640x480];

    }

    ///添加视频输出流

    if([self.session canAddOutput:output]) {

        [self.session addOutput:output];

    }

    ///设置输出流参数

    NSString    *key          = (NSString *)kCVPixelBufferPixelFormatTypeKey;

    NSNumber    *value        = [NSNumber numberWithUnsignedInt:kCVPixelFormatType_32BGRA];

    NSDictionary*videoSettings = [NSDictionary dictionaryWithObject:valueforKey:key];

    [output setVideoSettings:videoSettings];

    ///初始化添加AVCaptureMetadataOutput

    AVCaptureMetadataOutput* metaOutput = [AVCaptureMetadataOutput new];

    [self.session addOutput:metaOutput];

    ///设置识别人脸AVMetadataObjectTypeFace（如果是二维码，那就是AVMetadataObjectTypeQRCode）

    [metaOutput setMetadataObjectTypes:@[AVMetadataObjectTypeFace]];

    ///设置人脸识别输出流代理及队列，窜行子队列，检测到人脸，代理输出数据流

    [metaOutput setMetadataObjectsDelegate:self  queue:dispatch_queue_create("face", NULL)];

    metaOutput.rectOfInterest = self.view.bounds;

    ///提交session设置

    [self.session commitConfiguration];

    ///开始任务    

     [self.session startRunning];
2、代理方法输出：

///人脸识别代理

-(void)captureOutput:(AVCaptureOutput*)output didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject*> *)metadataObjects fromConnection:(AVCaptureConnection*)connection{

    self.metadatas= metadataObjects;///如果有人脸，则不为空

}
3、转换坐标系

///转换坐标系，AVMetadataFaceObject原始的坐标系与UIView的坐标系相反，然后

    for(AVMetadataFaceObject*faceobject in self.metadatas) {

        AVMetadataFaceObject *face = (AVMetadataFaceObject*)[self.previewLayer transformedMetadataObjectForMetadataObject:faceobject];

        [self.tempArraddObject:face];

    }
4、根据AVMetadataFaceObject的位置添加脸框

///根据脸部位置生成layer，rect为AVMetadataFaceObject的bounds属性

- (CAShapeLayer*)getFaceLayer:(CGRect)rect{

    UIBezierPath *path = [UIBezierPath bezierPathWithRoundedRect:rect cornerRadius:0];

    CAShapeLayer *pathLayer = [CAShapeLayer layer];

    pathLayer.lineWidth=2;

    pathLayer.strokeColor = [UIColor greenColor].CGColor;

    pathLayer.path= path.CGPath;

    [pathLayer setFillColor:[UIColorclearColor].CGColor];

    return pathLayer;

}
具体见demo。

二、CIDetector的用法：

CIImage* image = [CIImage imageWithCGImage:aImage.CGImage];

NSDictionary  *opts = [NSDictionary dictionaryWithObject:CIDetectorAccuracyHigh forKey:CIDetectorAccuracy];

CIDetector* detector = [CIDetector detectorOfType:CIDetectorTypeFace context:nil options:opts];

    //得到面部数据

 NSArray<CIFaceFeature*>* features = [detector featuresInImage:image];
CIFaceFeature也有对应的bounds，faceAngle等属性，可以通过这些属性添加识别框。

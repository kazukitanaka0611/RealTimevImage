//
//  ViewController.m
//  RealTimevImage
//
//  Created by kazuki_tanaka on 12/06/29.
//  Copyright (c) 2012年 __MyCompanyName__. All rights reserved.
//

#import "ViewController.h"

#import <QuartzCore/QuartzCore.h>
#import <Accelerate/Accelerate.h>
#import <AVFoundation/AVFoundation.h>

#import <AssetsLibrary/AssetsLibrary.h>

@interface ViewController ()
    <AVCaptureVideoDataOutputSampleBufferDelegate>

@property (strong, nonatomic) AVCaptureSession *session;
@property (strong, nonatomic) AVCaptureStillImageOutput *stillImageOutput;
@property (strong, nonatomic) AVCaptureMovieFileOutput* movieFileOutput;
@property (strong, nonatomic) IBOutlet UIImageView *imageView;
@property (strong, nonatomic) CALayer *previewLayer;

@end

@implementation ViewController

@synthesize session = _session;
@synthesize stillImageOutput = _stillImageOutput;
@synthesize movieFileOutput = _movieFileOutput;
@synthesize imageView = _imageView;
@synthesize previewLayer = _previewLayer;

enum {
    CAMERA_BUTTON_TAG,
    VIDEO_BUTTON_TAG
};

const int16_t kernel[3][9] = {
    {1, 2, 1, 2, 4, 2, 1, 2, 1},
    {-2, -2, 0, -2, 6, 0, 0, 0, 0},
    {-1, -1, -1, 0, 0, 0, 1, 1, 1}
};

int32_t divisor[3] = { 16, 1, 1 };

- (void)setAVCaptre
{
    // AVCaptureSession
    self.session = [[AVCaptureSession alloc] init];
    [self.session setSessionPreset:AVCaptureSessionPresetLow];
    
    // Input
    AVCaptureDeviceInput* input = [AVCaptureDeviceInput deviceInputWithDevice:
                                   [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo]
                                                                        error:nil];
    if ([self.session canAddInput:input])
        [self.session addInput:input];
    
    // Preview
    self.previewLayer = [CALayer layer];
    self.previewLayer.bounds = CGRectMake(0, 0, self.imageView.frame.size.height, self.imageView.frame.size.width);
    self.previewLayer.position = CGPointMake(self.view.frame.size.width/2., self.view.frame.size.height/2.);
    self.previewLayer.affineTransform = CGAffineTransformMakeRotation(M_PI/2);
    [self.imageView.layer addSublayer:self.previewLayer];
    
    // Output
    AVCaptureVideoDataOutput *output = [[AVCaptureVideoDataOutput alloc] init];
    output.videoSettings = [NSDictionary dictionaryWithObject:[NSNumber numberWithInt:kCVPixelFormatType_32BGRA]
                                                       forKey:(id)kCVPixelBufferPixelFormatTypeKey];
    [output setAlwaysDiscardsLateVideoFrames:YES];
    
    if ([self.session canAddOutput:output])
        [self.session addOutput:output];
    
    // StillImageOutput
    self.stillImageOutput = [[AVCaptureStillImageOutput alloc] init];
    if ([self.session canAddOutput:self.stillImageOutput])
        [self.session addOutput:self.stillImageOutput];
    
//    // MovieOutput
//    self.movieFileOutput = [[AVCaptureMovieFileOutput alloc] init];
//    if ([self.session canAddOutput:self.movieFileOutput])
//        [self.session addOutput:self.movieFileOutput];
    
    [self.session commitConfiguration];
    
    dispatch_queue_t queue = dispatch_queue_create("VideoQueue", DISPATCH_QUEUE_SERIAL);
    [output setSampleBufferDelegate:self queue:queue];
    //[output setSampleBufferDelegate:self queue:dispatch_get_main_queue()];
    
    if (!self.session.isRunning)
        [self.session startRunning];
}

- (void)captureOutput:(AVCaptureOutput *)captureOutput
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
       fromConnection:(AVCaptureConnection *)connection
{
    @autoreleasepool {
        
        CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
        CVPixelBufferLockBaseAddress(imageBuffer, 0);
        
        //    size_t width = CVPixelBufferGetWidthOfPlane(imageBuffer, 0);
        //    size_t height = CVPixelBufferGetHeightOfPlane(imageBuffer, 0);
        //    size_t bytesPerRow = CVPixelBufferGetBytesPerRowOfPlane(imageBuffer, 0);
        
        size_t width = CVPixelBufferGetWidth(imageBuffer);
        size_t height = CVPixelBufferGetHeight(imageBuffer);
        size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);
        
        UInt8 *inBuffer = CVPixelBufferGetBaseAddress(imageBuffer);
        vImage_Buffer src = {inBuffer, height, width, bytesPerRow};
        
        UInt8 *outBuffer = (UInt8 *)calloc(width * height * 4, sizeof(UInt8));
        vImage_Buffer dest = {outBuffer, height, width, bytesPerRow};
        
        //vImageMax_PlanarF(&src, &dest, NULL, 0, 0, 7, 7, kvImageCopyInPlace);
        //vImageConvolve_ARGB8888(&src, &dest, NULL, 0, 0, kernel, 3, 3, 1, NULL, kvImageCopyInPlace);
        
        Pixel_8888 bgColor = { 0, 0, 0, 0 };
        vImageConvolveWithBias_ARGB8888(&src, &dest, NULL, 0, 0, kernel[1], 3, 3,
                                        divisor[1], 128, bgColor, kvImageBackgroundColorFill);
        
        //    Pixel_8 *inBuffer = CVPixelBufferGetBaseAddressOfPlane(imageBuffer, 0);    
        //    const vImage_Buffer inImage = { inBuffer, height, width, bytesPerRow };
        //    
        //    Pixel_8 *outBuffer = (Pixel_8 *)calloc(width*height, sizeof(Pixel_8));            
        //    const vImage_Buffer outImage = { outBuffer, height, width, bytesPerRow };
        //    
        //    vImageMin_Planar8(&inImage, &outImage, NULL, 0, 0, 7, 7, kvImageDoNotTile);
        
        CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
        
        CGContextRef context = CGBitmapContextCreate(dest.data,
                                                     width,
                                                     height,
                                                     8,
                                                     bytesPerRow,
                                                     colorSpace,
                                                     kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);
        
        CGImageRef cgImage = CGBitmapContextCreateImage(context);
        
        dispatch_sync(dispatch_get_main_queue(), ^{
            self.previewLayer.contents = (__bridge id)cgImage;
        });
        
        CGImageRelease(cgImage);
        CGContextRelease(context);
        CGColorSpaceRelease(colorSpace);
        
        CVPixelBufferUnlockBaseAddress(imageBuffer, 0);
    }
}

- (IBAction)saveImage:(id)sender
{
    AVCaptureConnection *videoConnection = nil;
    for (AVCaptureConnection *connection in self.stillImageOutput.connections) {
        for (AVCaptureInputPort *port in [connection inputPorts]) {
            if ([[port mediaType] isEqual:AVMediaTypeVideo]) {
                videoConnection = connection;
                break;
            }
        }
        
        if (videoConnection) {
            break;
        }
    }
    
    [self.stillImageOutput captureStillImageAsynchronouslyFromConnection:videoConnection
                                                       completionHandler:
     ^(CMSampleBufferRef imageSampleBuffer, NSError *error) {
         
         if (imageSampleBuffer != NULL) {
             
             //NSData *data = [AVCaptureStillImageOutput jpegStillImageNSDataRepresentation:imageSampleBuffer];
             //UIImage *image = [[UIImage alloc] initWithData:data];
             
             ALAssetsLibrary *libray = [[ALAssetsLibrary alloc] init];
             
             UIGraphicsBeginImageContext(CGSizeMake(self.imageView.frame.size.height, self.imageView.frame.size.width));
             CGContextRef context = UIGraphicsGetCurrentContext();
             [self.previewLayer renderInContext:context];
             UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
             UIGraphicsEndImageContext();
             
             [libray writeImageToSavedPhotosAlbum:image.CGImage
                                      orientation:(ALAssetOrientation)UIImageOrientationRight
                                  completionBlock:^(NSURL *url, NSError *error){}];
         }
     }];
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view, typically from a nib.
    
    [self setAVCaptre];
}

- (void)viewDidUnload
{
    [super viewDidUnload];
    // Release any retained subviews of the main view.
    
    self.session = nil;
    self.stillImageOutput = nil;
    self.imageView = nil;
    self.previewLayer = nil;
}

@end

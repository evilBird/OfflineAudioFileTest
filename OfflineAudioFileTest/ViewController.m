//
//  ViewController.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "OfflineAudioFileProcessor.h"
#import "AudioSpectrumProcessor.h"

@interface ViewController (){
    NSUInteger kSampleRate;
    AVAudioFrameCount kBufferSize;
}
@property (nonatomic,strong)                        OfflineAudioFileProcessor       *myProcessor;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerA;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerB;
@property (strong, nonatomic)   IBOutlet            UILabel                         *progressLabel;
@property (strong, nonatomic) IBOutlet              UISlider                        *crossFadeSlider;
@property (strong, nonatomic) IBOutlet UIButton *pauseButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;

- (IBAction)crossFadeSliderAction:(id)sender;
- (IBAction)pauseButtonAction:(id)sender;
- (IBAction)cancelButtonAction:(id)sender;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.crossFadeSlider.enabled = NO;
    kBufferSize = 1024;
        [self testCoolerStuff];
    // Do any additional setup after loading the view, typically from a nib.
}

+ (NSString *)rawSoloFilePath
{
    NSString *rawSoloFileName = @"queen_bohemian_rhapsody.000.48k";
    NSString *path = [[NSBundle mainBundle]pathForResource:rawSoloFileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

+ (NSString *)rawAccompFilePath
{
    NSString *rawAccompFileName = @"queen_bohemian_rhapsody.000.48o";
    NSString *path = [[NSBundle mainBundle]pathForResource:rawAccompFileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

- (void)testOtherCoolStuff
{
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:[OfflineAudioFileProcessor testAccompFileName]];
    
    self.myProcessor = [OfflineAudioFileProcessor doDefaultProcessingWithSourceFile:testFilePath onProgress:^(double progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.text = [NSString stringWithFormat:@"progress: %f",progress];
        });
    } onSuccess:^(NSURL *resultFile) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.text = @"SUCCESS!";
            NSLog(@"SUCCESS: %@",resultFile.path);
        });
    } onFailure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressLabel.text = @"FAILURE";
            NSLog(@"FAILURE: %@",error);
        });
    }];
}

- (void)testCoolerStuff
{
    NSString *rawFilePath = [ViewController rawAccompFilePath];
    __weak ViewController *weakself = self;
    self.myProcessor = [OfflineAudioFileProcessor convertAndProcessRawFile:rawFilePath
                                                                onProgress:^(double progress) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        weakself.progressLabel.text = [NSString stringWithFormat:@"PROCESSING...%.2f",progress];
                                                                    });
                                                                } onSuccess:^(NSURL *resultFile) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        
                                                                        weakself.pauseButton.hidden = YES;
                                                                        weakself.cancelButton.hidden = YES;
                                                                        weakself.crossFadeSlider.enabled = YES;
                                                                        
                                                                        if ([weakself playAudioFile:resultFile]) {
                                                                            weakself.progressLabel.text = @"PLAYBACK ERROR!";
                                                                        }else{
                                                                            weakself.progressLabel.text = @"SUCCESS! PLAYING RESULT...";
                                                                        }
                                                                        NSLog(@"convert and process finished writing to file: %@",resultFile.path);
                                                                    });

                                                                } onFailure:^(NSError *error) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        weakself.pauseButton.hidden = YES;
                                                                        weakself.cancelButton.hidden = YES;
                                                                        weakself.progressLabel.text = @"ERROR!";
                                                                    });
                                                                    
                                                                    NSLog(@"PROCESSING FAILED WITH ERROR: %@",error);
                                                                }];
}

- (void)testCoolStuff
{
    __weak ViewController *weakself = self;
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:[OfflineAudioFileProcessor testAccompFileName]];
    NSURL *fileAURL = [NSURL fileURLWithPath:testFilePath];
    self.myProcessor = [OfflineAudioFileProcessor processFile:testFilePath
                                          withAudioBufferSize:kBufferSize
                                                     compress:YES
                                                       reverb:YES
                                              progressHandler:^(double progress) {
                                                  dispatch_async(dispatch_get_main_queue(), ^{
                                                      weakself.progressLabel.text = [NSString stringWithFormat:@"PROCESSING...%.2f",progress];
                                                  });
                                              } completionHandler:^(NSURL *fileURL, NSError *error) {
                                                  if (error) {
                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          weakself.pauseButton.hidden = YES;
                                                          weakself.cancelButton.hidden = YES;
                                                          weakself.progressLabel.text = @"PROCESSING ERROR";
                                                      });
                                                  }else{
                                                      NSLog(@"finished main processing to path: %@",fileURL.path);
                                                      dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                          [[NSOperationQueue new]addOperationWithBlock:^{
                                                              [weakself normalizeFile:fileURL originalFile:fileAURL];
                                                          }];
                                                      });
                                                  }
                                              }];
    dispatch_async(dispatch_get_main_queue(), ^{
        self.pauseButton.hidden = NO;
        self.cancelButton.hidden = NO;
    });
    
    [self.myProcessor start];
    
}

- (void)normalizeFile:(NSURL *)toNormalize originalFile:(NSURL *)origFile
{
    Float32 normConstant = self.myProcessor.normalizeConstant;
    self.myProcessor = nil;
    __weak ViewController *weakself = self;
    self.myProcessor = [OfflineAudioFileProcessor normalizeFile:toNormalize.path
                                            withAudioBufferSize:1024
                                              normalizeConstant:normConstant
                                                  progressBlock:^(double progress) {
                                                      dispatch_async(dispatch_get_main_queue(), ^{
                                                          weakself.progressLabel.text = [NSString stringWithFormat:@"POST-PROCESSING...%.2f",progress];
                                                      });
                                                  } completionBlock:^(NSURL *fileURL, NSError *error) {
                                                      if (error) {
                                                          dispatch_async(dispatch_get_main_queue(), ^{
                                                              weakself.pauseButton.hidden = YES;
                                                              weakself.cancelButton.hidden = YES;
                                                              weakself.progressLabel.text = @"POST-PROCESSING ERROR";
                                                          });
                                                      }else{
                                                          NSLog(@"finished post-processing to path: %@",fileURL.path);
                                                          dispatch_async(dispatch_get_main_queue(), ^{
                                                              
                                                              dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                                                                  weakself.pauseButton.hidden = YES;
                                                                  weakself.cancelButton.hidden = YES;
                                                                  [weakself playAudioFileA:origFile andAudioFileB:fileURL];
                                                                  weakself.crossFadeSlider.enabled = YES;
                                                              });
                                                              
                                                          });
                                                      }
                                                  }];
    [self.myProcessor start];
}

- (NSError *)playAudioFile:(NSURL *)fileURL
{
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:YES error:&err];
    
    if (err) {
        return err;
    }
    
    [session setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) {
        return err;
    }
    
    self.audioPlayerA = [[AVAudioPlayer alloc]initWithContentsOfURL:fileURL error:&err];
    self.audioPlayerA.volume = 1.0;
    self.crossFadeSlider.hidden = YES;
    [self.audioPlayerA play];

    return nil;
}

- (NSError *)playAudioFileA:(NSURL *)fileAURL andAudioFileB:(NSURL *)fileBURL
{
    NSParameterAssert(fileAURL);
    NSParameterAssert(fileBURL);
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:YES error:&err];
    
    if (err) {
        return err;
    }
    
    [session setCategory:AVAudioSessionCategoryPlayback error:&err];
    if (err) {
        return err;
    }
    
    self.audioPlayerA = [[AVAudioPlayer alloc]initWithContentsOfURL:fileAURL error:&err];
    self.audioPlayerA.volume = 0.5;
    
    if (err) {
        return err;
    }
    
    self.audioPlayerB = [[AVAudioPlayer alloc]initWithContentsOfURL:fileBURL error:&err];
    self.audioPlayerB.volume = 0.5;
    if (err) {
        return err;
    }
    
    [self.audioPlayerA play];
    [self.audioPlayerB play];
    
    return nil;
}

- (IBAction)crossFadeSliderAction:(id)sender {
    
    UISlider *slider = (UISlider *)sender;
    double value = slider.value;
    double scaledValue = M_PI+(value*M_PI);
    double cosValue = cos(scaledValue);
    double scaledCosValue = (cosValue+1.0)*0.5;
    double fileAVolume = 1.0-scaledCosValue;
    double fileBVolume = scaledCosValue;
    self.audioPlayerA.volume = fileAVolume;
    self.audioPlayerB.volume = fileBVolume;
}

- (IBAction)pauseButtonAction:(id)sender {
    
    if (self.myProcessor.isRunning) {
        self.pauseButton.selected = YES;
        [self.myProcessor pause];
    }else if (self.myProcessor.isPaused){
        self.pauseButton.selected = NO;
        [self.myProcessor resume];

    }
}

- (IBAction)cancelButtonAction:(id)sender {
    [self.myProcessor cancel];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

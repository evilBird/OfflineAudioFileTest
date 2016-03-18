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
#import "NSObject+AudioSessionManager.h"

@interface ViewController (){
    AVAudioFrameCount kBufferSize;
}

@property (nonatomic,strong)                        OfflineAudioFileProcessor       *myProcessor;
@property (nonatomic,strong)                        NSString                        *myRawFilePath;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerA;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerB;
@property (strong, nonatomic) IBOutlet              UILabel                         *progressLabel;
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
    kBufferSize = 1024;
    self.myRawFilePath = [ViewController hugeRawAccompFilePath];
    [OfflineAudioFileProcessor deleteTempFilesForFile:[self.myRawFilePath lastPathComponent]];
    [self defaultUISetup];
    [self startPlaybackAudioSessionError:nil];
    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)startProcessing
{
    __weak ViewController *weakself = self;
    [self processorWillBeginProcessing];
    self.myProcessor = [OfflineAudioFileProcessor __convertAndProcessRawFile:self.myRawFilePath
                                                                onProgress:^(double progress) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        [weakself.progressLabel setText:[NSString stringWithFormat:@"Processing...progress: %.2f",progress]];
                                                                    });
                                                                } onSuccess:^(NSURL *resultFile) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        [weakself processorDidSucceedWithResult:resultFile];
                                                                    });
                                                                    
                                                                } onFailure:^(NSError *error) {
                                                                    dispatch_async(dispatch_get_main_queue(), ^{
                                                                        [weakself processorDidFailWithError:error];
                                                                    });
                     
                                                                }];
}

#pragma mark - IBActions

- (IBAction)crossFadeSliderAction:(id)sender {
    
    UISlider *slider = (UISlider *)sender;
    double value = slider.value;
    if (self.audioPlayerA && !self.audioPlayerB) {
        self.audioPlayerA.volume = value;
    }else if (self.audioPlayerA && self.audioPlayerB){
        [self crossFadeWithSliderValue:value];
    }
}

- (void)crossFadeWithSliderValue:(double)value
{
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
        self.progressLabel.text = @"PAUSED";
        [self.myProcessor pause];
    }else if (self.myProcessor.isPaused){
        self.pauseButton.selected = NO;
        self.progressLabel.text = @"RESUMING...";
        [self.myProcessor resume];
    }
}

- (IBAction)cancelButtonAction:(id)sender {
    
    if (!self.myProcessor) {
        [self startProcessing];
    }else if (self.myProcessor.isRunning || self.myProcessor.isPaused ){
        [self.myProcessor cancel];
        self.myProcessor = nil;
        self.progressLabel.text = @"CANCELLED";
        [self defaultUISetup];
    }
}

#pragma mark - UI Update Helpers

- (void)defaultUISetup
{
    [self.cancelButton setTitle:@"Process" forState:UIControlStateNormal];
    self.cancelButton.hidden = NO;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.hidden = YES;
}

- (void)processorWillBeginProcessing
{
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.hidden = NO;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.hidden = NO;
}

- (void)processorDidFailWithError:(NSError *)error
{
    self.progressLabel.text = @"ERROR";
    NSLog(@"ERROR: %@",error);
    [self defaultUISetup];
}

- (void)processorDidSucceedWithResult:(NSURL *)resultFile
{
    self.cancelButton.hidden = YES;
    self.pauseButton.hidden = YES;
    NSLog(@"SUCCESS: %@",resultFile.path);
    NSError *err = [self playAudioFile:resultFile];
    if (err) {
        return [self processorDidFailWithError:err];
    }
    
    self.crossFadeSlider.hidden = NO;
    self.progressLabel.text = @"SUCCESS! PLAYING RESULT.";
}


#pragma mark - Audio Playback Helpers

- (void)startPlaybackAudioSessionError:(NSError *__autoreleasing *)error
{
    __weak ViewController *weakself = self;
    __block BOOL playerAWasPlaying = NO;
    __block BOOL playerBWasPlaying = NO;
    NSError *err = nil;
    [self startDefaultAudioSessionWithCategory:AVAudioSessionCategoryPlayback
                                onInterruption:^(AVAudioSessionInterruptionType type, AVAudioSessionInterruptionOptions shouldResume) {
                                    if (type == AVAudioSessionInterruptionTypeBegan) {
                                        NSLog(@"Session Interruption");
                                        playerAWasPlaying = ( weakself.audioPlayerA.isPlaying );
                                        if (playerAWasPlaying) {
                                            [weakself.audioPlayerA pause];
                                        }
                                        playerBWasPlaying =  ( weakself.audioPlayerB.isPlaying );
                                        if (playerBWasPlaying) {
                                            [weakself.audioPlayerB pause];
                                        }
                                    }else{
                                        NSLog(@"Session interruption ended");
                                        if (shouldResume) {
                                            if (playerAWasPlaying) {
                                                [weakself.audioPlayerA play];
                                            }
                                            if (playerBWasPlaying) {
                                                [weakself.audioPlayerB play];
                                            }
                                        }
                                    }
                                }
                               onBackgrounding:^(BOOL isBackgrounded, BOOL wasBackgrounded){
                                   if (isBackgrounded) {
                                       NSLog(@"entering background");
                                   }else{
                                       NSLog(@"exiting background");
                                   }
                               }
                                         error:&err];
    if (err) {
        if (error) {
            *error = err;
        }
    }
}

- (NSError *)playAudioFile:(NSURL *)fileURL
{
    NSError *err = nil;
    [self startPlaybackAudioSessionError:&err];
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
    [self startPlaybackAudioSessionError:&err];
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


#pragma mark - Helpers

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

+ (NSString *)hugeRawAccompFilePath
{
    NSString *rawAccompFileName = @"brahms_accomp.raw";
    NSString *path = [[NSBundle mainBundle]pathForResource:rawAccompFileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

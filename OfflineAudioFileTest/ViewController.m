//
//  ViewController.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "ViewController.h"
#import <AVFoundation/AVFoundation.h>
#import "SonaAudioFileMixPlayer.h"
#import "OfflineAudioFileProcessor+Functions.h"
#import "AudioSpectrumProcessor.h"
#import "NSObject+AudioSessionManager.h"
#import "OfflineAudioFileProcessor+Analysis.h"

#define ANALYZE_INSTEAD true


@interface ViewController () <SonaAudioFileMixPlayerDelegate>
{
    AVAudioFrameCount   kBufferSize;
    Float32             vDetectedFileBPM;
    Float32             vDetectedUserBPM;
    Float32             vCalculatedPlaybackRate;
    NSMutableArray      *vTapIntervals;
    NSDate              *vPreviousTapEventDate;
    NSUInteger           vTapIntervalIndex;
}

@property (nonatomic,strong)                        OfflineAudioFileProcessor       *myProcessor;
@property (nonatomic,strong)                        NSString                        *myRawFilePath;
@property (nonatomic,strong)                        SonaAudioFileMixPlayer          *filePlayer;
@property (strong, nonatomic) IBOutlet              UILabel                         *progressLabel;
@property (strong, nonatomic) IBOutlet              UISlider                        *crossFadeSlider;

@property (strong, nonatomic) IBOutlet UIButton *pauseButton;
@property (strong, nonatomic) IBOutlet UIButton *cancelButton;

- (IBAction)crossFadeSliderAction:(id)sender;
- (IBAction)pauseButtonAction:(id)sender;
- (IBAction)cancelButtonAction:(id)sender;
- (IBAction)tapTempAction:(id)sender;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    kBufferSize = 1024;
    
    if (ANALYZE_INSTEAD == true) {
        [self analysisUISetup];
    }else{
        [self defaultUISetup];
    }
    
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)startAnalyzing
{
    [self processorWillBeginProcessing];

    NSString *filePath = [ViewController doIWannaKnowFilePath];
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    
    __weak ViewController *weakself = self;
    
    self.myProcessor = [OfflineAudioFileProcessor detectBPMOfFile:filePath allowedRange:NSRangeFromString(@"30, 180") onProgress:^(double progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakself updateProgress:progress];
        });
    } onSuccess:^(Float32 detectedTempo) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakself analysisOfFile:fileURL didSucceedWithTempo:detectedTempo];
        });
    } onFailure:^(NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [weakself processorDidFailWithError:error];
        });
    }];
}

- (void)startProcessing
{
    __weak ViewController *weakself = self;
    [self processorWillBeginProcessing];

    self.myRawFilePath = [ViewController hugeRawAccompFilePath];

    self.myProcessor = [OfflineAudioFileProcessor convertAndProcessRawFile:self.myRawFilePath
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
    if (self.filePlayer.player1 && !self.filePlayer.player2) {
        self.filePlayer.player1.volume = value;
    }else if (self.filePlayer.player1 && self.filePlayer.player2){
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
    self.filePlayer.player1.volume = fileAVolume;
    self.filePlayer.player2.volume = fileBVolume;
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
    }else if (self.myProcessor.isDone && ANALYZE_INSTEAD == true){
        if (self.filePlayer.isPlaying) {
            [self.filePlayer stop];
            self.pauseButton.selected = NO;
        }else{
            [self.filePlayer play];
            self.pauseButton.selected = YES;
        }
    }
}

- (IBAction)cancelButtonAction:(id)sender {
    
    if (!self.myProcessor) {
        
        if (ANALYZE_INSTEAD == true) {
            [self startAnalyzing];
        }else{
            [self startProcessing];
        }
        
    }else if (self.myProcessor.isRunning || self.myProcessor.isPaused ){
        [self.myProcessor cancel];
        self.myProcessor = nil;
        self.progressLabel.text = @"CANCELLED";
        
        if (ANALYZE_INSTEAD == true) {
            [self analysisUISetup];
        }else{
            [self defaultUISetup];
        }
    }
}

- (IBAction)tapTempAction:(id)sender {
    
    if (ANALYZE_INSTEAD == true && self.myProcessor.isDone && self.filePlayer.isPlaying){
        
        [self tapTempoEvent];
    }
}

- (void)tapTempoEvent
{
    NSTimeInterval maxUserInterval = 2.0;
    
    if (!vPreviousTapEventDate) {
        vPreviousTapEventDate = [NSDate date];
        return;
    }
    
    NSDate *now = [NSDate date];
    NSTimeInterval interval = [now timeIntervalSinceDate:vPreviousTapEventDate];
    vPreviousTapEventDate = now;
    
    if (interval==0.0 || interval >= maxUserInterval) {
        return;
    }
    
    vDetectedUserBPM = 60.0/interval;
    vCalculatedPlaybackRate = vDetectedUserBPM/vDetectedFileBPM;
    self.progressLabel.text = [NSString stringWithFormat:@"Tapped Tempo: %.f, Playback Rate = %.2f",vDetectedUserBPM,vCalculatedPlaybackRate];
    self.filePlayer.timePitch1.rate = vCalculatedPlaybackRate;
    
}

#pragma mark - UI Update Helpers

- (void)defaultUISetup
{
    [self.cancelButton setTitle:@"Process" forState:UIControlStateNormal];
    self.cancelButton.hidden = NO;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.hidden = YES;
}

- (void)analysisUISetup
{
    [self.cancelButton setTitle:@"Analyze" forState:UIControlStateNormal];
    self.cancelButton.hidden = NO;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.hidden = YES;
    self.progressLabel.text = @"Tap 'Analyze' to start";
}

- (void)processorWillBeginProcessing
{
    [self.cancelButton setTitle:@"Cancel" forState:UIControlStateNormal];
    self.cancelButton.hidden = NO;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.hidden = NO;
}

- (void)updateProgress:(double)progress
{
    self.progressLabel.text = [NSString stringWithFormat:@"Progress: %.2f",progress];
}
- (void)processorDidFailWithError:(NSError *)error
{
    self.progressLabel.text = @"ERROR";
    NSLog(@"ERROR: %@",error);
    [self defaultUISetup];
}

- (void)analysisOfFile:(NSURL *)audioFile didSucceedWithTempo:(Float32)tempo
{
    [self.cancelButton setTitle:@"Tap Tempo" forState:UIControlStateNormal];
    [self.pauseButton setTitle:@"Play" forState:UIControlStateNormal];
    [self.pauseButton setTitle:@"Stop" forState:UIControlStateSelected];
    
    self.progressLabel.text = [NSString stringWithFormat:@"BPM: %.f",roundf(tempo)];
    vDetectedFileBPM = tempo;
    self.cancelButton.hidden = NO;
    self.pauseButton.hidden = NO;
    [self playAudioFile:audioFile];
}

- (void)processorDidSucceedWithResult:(NSURL *)resultFile
{
    self.cancelButton.hidden = YES;
    self.pauseButton.hidden = YES;
    NSLog(@"SUCCESS: %@",resultFile.path);
    
    NSError *err = nil;
    [self playAudioFile:resultFile];
    
    if (err) {
        return [self processorDidFailWithError:err];
    }
    
    self.crossFadeSlider.hidden = NO;
    self.progressLabel.text = @"SUCCESS! PLAYING RESULT.";
}

#pragma mark - Audio Playback Helpers


- (void)playAudioFile:(NSURL *)fileURL
{
    self.filePlayer = nil;
    self.crossFadeSlider.hidden = YES;
    self.pauseButton.selected = YES;
    self.pauseButton.enabled = NO;
    self.filePlayer = [[SonaAudioFileMixPlayer alloc]initWithFile:fileURL.path delegate:self];
}

- (void)playAudioFileA:(NSURL *)fileAURL andAudioFileB:(NSURL *)fileBURL
{
    self.filePlayer = nil;
    self.crossFadeSlider.hidden = NO;
    self.pauseButton.hidden = YES;
    self.filePlayer = [[SonaAudioFileMixPlayer alloc]initWithFile1:fileAURL.path file2:fileBURL.path delegate:self];
    
}

#pragma mark - SonaAudioFileMixPlayerDelegate

- (void)audioFileMixPlayer:(id)sender didFailWithError:(NSError *)error
{
    __weak ViewController *weakself = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        [weakself processorDidFailWithError:error];
    });
}

- (void)audioFileMixPlayerFinishedLoading:(id)sender
{
    if (ANALYZE_INSTEAD) {
        self.pauseButton.enabled = YES;
        [self.filePlayer play];
        self.pauseButton.selected = YES;
    }else{
        [self.filePlayer play];
    }
}

- (void)audioFileMixPlayerFinishedPlayback:(id)sender
{
    self.pauseButton.selected = NO;
}

#pragma mark - Helpers

+ (NSString *)floriDadaFilePath
{
    NSString *fileName = @"FloriDada.wav";
    return [ViewController bundlePathForFile:fileName];
}

+ (NSString *)doIWannaKnowFilePath
{
    NSString *fileName = @"Do I Wanna Know.wav";
    return [ViewController bundlePathForFile:fileName];
}

+ (NSString *)americanSteelFilePath
{
    NSString *fileName = @"Got a Backbeat.wav";
    return [ViewController bundlePathForFile:fileName];
}

+ (NSString *)bundlePathForFile:(NSString *)fileName
{
    NSString *path = [[NSBundle mainBundle]pathForResource:fileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

+ (NSString *)soloViolinFilePath
{
    NSString *rawSoloFileName = @"faure_sicilienne_violin.48k.wav";
    NSString *path = [[NSBundle mainBundle]pathForResource:rawSoloFileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

+ (NSString *)accompFilePath
{
    NSString *rawSoloFileName = @"faure_sicilienne_violin.48o.wav";
    NSString *path = [[NSBundle mainBundle]pathForResource:rawSoloFileName ofType:nil];
    NSParameterAssert(path);
    return path;
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

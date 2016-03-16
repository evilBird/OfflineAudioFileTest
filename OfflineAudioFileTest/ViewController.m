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
    AVAudioFrameCount kBlockSize;
}
@property (nonatomic,strong)                        OfflineAudioFileProcessor       *myProcessor;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerA;
@property (nonatomic,strong)                        AVAudioPlayer                   *audioPlayerB;
@property (strong, nonatomic)   IBOutlet            UILabel                         *progressLabel;
@property (strong, nonatomic) IBOutlet              UISlider                        *crossFadeSlider;

- (IBAction)crossFadeSliderAction:(id)sender;

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.crossFadeSlider.enabled = NO;
    [self testOtherStuff];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)testStuff
{
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:[OfflineAudioFileProcessor testAccompFileName]];
    __weak ViewController *weakself = self;
    NSTimeInterval startTime = [[NSDate date]timeIntervalSince1970];
    
    [OfflineAudioFileProcessor doDefaultProcessingWithSourceFile:testFilePath onProgress:^(double progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.progressLabel.text = [NSString stringWithFormat:@"PROCESSING...%.2f",progress];
        });
    } onSuccess:^(NSURL *resultFile) {
        NSURL *fileAURL = [NSURL fileURLWithPath:testFilePath];
        NSError *error = [weakself playAudioFileA:fileAURL andAudioFileB:resultFile];
        NSTimeInterval endTime = [[NSDate date]timeIntervalSince1970];
        NSTimeInterval processingTime = endTime-startTime;
        NSLog(@"\nPROCESSING FINISHED IN %fs...Result path: %@",processingTime,resultFile.path);
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakself.progressLabel.text = @"PLAYBACK ERROR";
            });
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                weakself.crossFadeSlider.enabled = YES;
                weakself.progressLabel.text = @"PLAYING";
            });
        }
    } onFailure:^(NSError *error) {
        NSLog(@"Offline file processor failed with error: %@",error);
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.progressLabel.text = @"PROCESSING ERROR";
        });
    }];
}

- (void)testOtherStuff
{
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:[OfflineAudioFileProcessor testAccompFileName]];
    __weak ViewController *weakself = self;
    NSUInteger maxBuffer = 1024;
    NSUInteger sampleRate = [OfflineAudioFileProcessor sampleRateForFile:testFilePath];
    
    self.myProcessor = [[OfflineAudioFileProcessor alloc]initWithSourceFile:testFilePath maxBufferSize:maxBuffer];
    
    AudioProcessingBlock reverbBlock = [self.myProcessor mediumReverbProcessingBlock];
    AudioProcessingBlock compressionBlock = [OfflineAudioFileProcessor vcompressionProcessingBlockWithSampleRate:sampleRate];
    
    [self.myProcessor setProcessingBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        reverbBlock(buffer,bufferSize);
        compressionBlock(buffer,bufferSize);
        return noErr;
    }];
    
    [self.myProcessor setProgressBlock:^(double progress) {
        dispatch_async(dispatch_get_main_queue(), ^{
            weakself.progressLabel.text = [NSString stringWithFormat:@"PROCESSING...%.2f",progress];
        });
    }];
    
    [self.myProcessor setCompletionBlock:^(NSURL *resultFile, NSError *error) {
        if (error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                weakself.progressLabel.text = @"PROCESSING ERROR";
            });
        }else{
            NSLog(@"\nResult path: %@",resultFile.path);
            NSURL *fileAURL = [NSURL fileURLWithPath:testFilePath];
            NSError *pe = [weakself playAudioFileA:fileAURL andAudioFileB:resultFile];
            if (pe) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakself.progressLabel.text = @"PLAYBACK ERROR";
                });
            }else{
                dispatch_async(dispatch_get_main_queue(), ^{
                    weakself.crossFadeSlider.enabled = YES;
                    weakself.progressLabel.text = @"PLAYING";
                });
            }
        }
    }];
    
    [self.myProcessor start];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self.myProcessor pause];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(2.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self.myProcessor resume];
        });
    });
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

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

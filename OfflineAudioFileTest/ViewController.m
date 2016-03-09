//
//  ViewController.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "ViewController.h"
#import "OfflineAudioFileProcessor.h"
#import "AudioSpectrumProcessor.h"

@interface ViewController (){
    NSUInteger kSampleRate;
    AVAudioFrameCount kBlockSize;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self testStuff];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)testStuff
{
    kBlockSize = 1024;
    kSampleRate = 48000;
    NSString *testFileName = [OfflineAudioFileProcessor testSoloFileName];
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:testFileName];
    NSString *intermediateFilePath = [OfflineAudioFileProcessor tempFilePathForFile:testFileName];
    NSString *resultFilePath = [OfflineAudioFileProcessor testResultPathForFile:testFileName];
    
    __block Float32 myPeak = 0.0;
    
    AudioProcessingBlock compressorBlock = [OfflineAudioFileProcessor
                                            compressionProcessingBlockWithSampleRate:kSampleRate];
    
    AudioProcessingBlock freeverbBlock = [OfflineAudioFileProcessor
                                          freeverbProcessingBlockWithSampleRate:kSampleRate
                                          wetMix:0.4
                                          dryMix:0.6
                                          roomSize:0.33
                                          width:0.83
                                          damping:0.51];
    
    [OfflineAudioFileProcessor processFile:testFilePath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        
        compressorBlock(buffer,bufferSize);
        freeverbBlock(buffer,bufferSize);
        Float32 thisPeak = [OfflineAudioFileProcessor getPeakMagnitudeForBuffer:buffer bufferSize:(NSUInteger)bufferSize];
        myPeak = ( thisPeak > myPeak ) ? ( thisPeak ) : ( myPeak );
        
        return noErr;
    } maxBufferSize:kBlockSize resultPath:intermediateFilePath completion:^(NSString *resultPath, NSError *error) {
        NSAssert(nil==error, @"ERROR: %@",error);
        NSLog(@"Finished writing compressed file to path: %@",resultPath);
        NSLog(@"MY PEAK: %@",@(myPeak));
        [OfflineAudioFileProcessor freebverbCleanup];
        
        AudioProcessingBlock normalizerBlock = [OfflineAudioFileProcessor normalizeProcessingBlockWithPeakMagnitude:myPeak];
        
        [OfflineAudioFileProcessor
         processFile:resultPath
         withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
             return normalizerBlock(buffer, bufferSize);
         }
         maxBufferSize:kBlockSize
         resultPath:resultFilePath
         completion:^(NSString *resultPath, NSError *error) {
             NSAssert(nil==error, @"ERROR: %@",error);
             NSLog(@"Finished writing audio file to path: %@",resultPath);
             [OfflineAudioFileProcessor deleteTempFilesForFile:testFileName];
         }];
        
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

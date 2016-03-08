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
    NSString *testFileName = [OfflineAudioFileProcessor testFileName];
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePath];
    NSString *intermediateFilePath = [OfflineAudioFileProcessor tempFilePathForFile:testFileName];
    NSString *resultFilePath = [OfflineAudioFileProcessor testResultPath];
    
    __block Float32 myPeak = 0.0;
    
    AudioProcessingBlock compressorBlock = [OfflineAudioFileProcessor compressionProcessingBlockWithSampleRate:kSampleRate];
    
    [OfflineAudioFileProcessor processFile:testFilePath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        
        OSStatus status = compressorBlock(buffer,bufferSize);
        
        Float32 thisPeak = [OfflineAudioFileProcessor getPeakMagnitudeForBuffer:buffer bufferSize:(NSUInteger)bufferSize];
        myPeak = ( thisPeak > myPeak ) ? ( thisPeak ) : ( myPeak );

        return status;
    } maxBufferSize:kBlockSize resultPath:intermediateFilePath completion:^(NSString *resultPath, NSError *error) {
        NSAssert(nil==error, @"ERROR: %@",error);
        NSLog(@"Finished writing compressed file to path: %@",resultPath);
        NSLog(@"MY PEAK: %@",@(myPeak));
        
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

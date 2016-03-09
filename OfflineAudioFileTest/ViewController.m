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
    
    NSString *testFileName = [OfflineAudioFileProcessor testAccompFileName];
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:testFileName];
    NSString *intermediateFilePath = [OfflineAudioFileProcessor tempFilePathForFile:testFileName];
    NSString *resultFilePath = [OfflineAudioFileProcessor testResultPathForFile:testFileName];
    
    AudioProcessingBlock compressorBlock = [OfflineAudioFileProcessor
                                            compressionProcessingBlockWithSampleRate:kSampleRate
                                            threshold:0.4
                                            slope:0.5
                                            lookaheadTime:5.0
                                            windowTime:2.0
                                            attackTime:0.1
                                            releaseTime:300.0];
    
    AudioProcessingBlock freeverbBlock = [OfflineAudioFileProcessor
                                          freeverbProcessingBlockWithSampleRate:kSampleRate
                                          wetMix:0.4
                                          dryMix:0.6
                                          roomSize:0.33
                                          width:0.83
                                          damping:0.51];
    
    [OfflineAudioFileProcessor processFile:testFilePath
                                 withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
                                     
                                     compressorBlock(buffer,bufferSize);
                                     freeverbBlock(buffer,bufferSize);
                                     
                                     return noErr;
                                 } maxBufferSize:kBlockSize
                                resultPath:intermediateFilePath
                                completion:^(NSString *resultPath, NSError *error) {
                                    NSAssert(nil==error, @"ERROR: %@",error);
                                    NSLog(@"Finished writing intermediate audio file to path: %@",resultPath);
                                    
                                    AudioProcessingBlock normalizerBlock = [OfflineAudioFileProcessor
                                                                            normalizeProcessingBlockForAudioFile:resultPath
                                                                            maximumMagnitude:0.99];
                                    [OfflineAudioFileProcessor processFile:resultPath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
                                        return normalizerBlock(buffer,bufferSize);
                                    } maxBufferSize:kBlockSize resultPath:resultFilePath completion:^(NSString *resultPath, NSError *error) {
                                        NSAssert(nil==error, @"ERROR: %@",error);
                                        NSLog(@"Finished writing final audio file to path: %@",resultPath);
                                        [OfflineAudioFileProcessor deleteTempFilesForFile:testFileName];
                                    }];
                                    
                                }];

}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

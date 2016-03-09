//
//  OfflineAudioFileProcessor+ConvenienceMethods.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/9/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"
@implementation OfflineAudioFileProcessor (ConvenienceMethods)

+ (UInt32)sampleRateForFile:(NSString *)filePath
{
    NSParameterAssert(filePath);
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    AVAudioFile *audioFile = [[AVAudioFile alloc]initForReading:fileURL error:nil];
    UInt32 samplingRate = audioFile.processingFormat.sampleRate;
    audioFile = nil;
    return samplingRate;
}

+ (AVAudioFrameCount)frameLengthForFile:(NSString *)filePath
{
    NSParameterAssert(filePath);
    NSURL *fileURL = [NSURL fileURLWithPath:filePath];
    AVAudioFile *audioFile = [[AVAudioFile alloc]initForReading:fileURL error:nil];
    AVAudioFrameCount frameCount = (AVAudioFrameCount)audioFile.length;
    audioFile = nil;
    return frameCount;
}

+ (void)doDefaultProcessingWithSourceFile:(NSString *)sourceFilePath
                               onProgress:(void(^)(double progress))progressBlock
                                onSuccess:(void(^)(NSURL *resultFile))successBlock
                                onFailure:(void(^)(NSError *error))failureBlock
{
    UInt32 kBlockSize = 1024;
    UInt32 kSampleRate = [OfflineAudioFileProcessor sampleRateForFile:sourceFilePath];
    
    NSString *sourceFileName = [sourceFilePath lastPathComponent];
    NSString *tempFilePath1 = [OfflineAudioFileProcessor tempFilePathForFile:sourceFileName];
    NSString *tempFilePath2 = [OfflineAudioFileProcessor tempFilePathForFile:sourceFileName];
    
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
    UInt32 kFileLength = [OfflineAudioFileProcessor frameLengthForFile:sourceFilePath];
    UInt32 kFileNumBuffers = (UInt32)round(((double)kFileLength/(double)kBlockSize));
    UInt32 totalBuffersToProcess = (kFileNumBuffers * 2);
    __block UInt32 numBuffersProcessed = 0;
    __block double myProgress = 0.0;
    progressBlock(myProgress);
    [OfflineAudioFileProcessor processFile:sourceFilePath
                                 withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
                                     
                                     compressorBlock(buffer,bufferSize);
                                     freeverbBlock(buffer,bufferSize);
                                     numBuffersProcessed++;
                                     myProgress = (double)numBuffersProcessed/(double)totalBuffersToProcess;
                                     progressBlock(myProgress);
                                     return noErr;
                                 } maxBufferSize:kBlockSize
                                resultPath:tempFilePath1
                                completion:^(NSString *resultPath, NSError *error) {
                                    
                                    if (error) {
                                        return failureBlock(error);
                                    }
                                    
                                    AudioProcessingBlock normalizerBlock = [OfflineAudioFileProcessor
                                                                            normalizeProcessingBlockForAudioFile:resultPath
                                                                            maximumMagnitude:0.99];
                                    
                                    [OfflineAudioFileProcessor processFile:resultPath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
                                        normalizerBlock (buffer,bufferSize);
                                        numBuffersProcessed++;
                                        myProgress = (double)numBuffersProcessed/(double)totalBuffersToProcess;
                                        progressBlock(myProgress);
                                        return noErr;
                                        
                                    } maxBufferSize:kBlockSize resultPath:tempFilePath2 completion:^(NSString *resultPath, NSError *error) {
                                        
                                        myProgress = 1.0;
                                        progressBlock(myProgress);
                                        if (error) {
                                            return failureBlock(error);
                                        }
                                        
                                        NSURL *resultURL = [NSURL fileURLWithPath:resultPath];
                                        successBlock(resultURL);
                                    }];
                                    
                                }];

}

@end
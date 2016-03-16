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

+ (void)processFile:(NSString *)sourceFilePath withBlock:(AudioProcessingBlock)processingBlock maxBufferSize:(AVAudioFrameCount)maxBufferSize resultPath:(NSString *)resultPath completion:(void(^)(NSString *resultPath, NSError *error))completion
{
    NSError *err = nil;
    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryAudioProcessing error:&err];
    if (err) {
        return completion(nil,err);
    }
    [[AVAudioSession sharedInstance]setActive:YES error:&err];
    if (err) {
        return completion(nil,err);
    }
    
    NSURL *sourceFileURL = [NSURL fileURLWithPath:sourceFilePath];
    AVAudioFile *sourceFile = [[AVAudioFile alloc]initForReading:sourceFileURL error:&err];
    if (err) {
        return completion(nil,err);
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:resultPath]) {
        [fm removeItemAtPath:resultPath error:nil];
    }
    
    AVAudioFormat *sourceFileFormat = sourceFile.processingFormat;
    NSMutableDictionary *resultFileSettings = [NSMutableDictionary dictionary];
    resultFileSettings[AVSampleRateKey] = @(sourceFileFormat.sampleRate);
    resultFileSettings[AVNumberOfChannelsKey] = @(sourceFileFormat.channelCount);
    NSURL *resultFileURL = [NSURL fileURLWithPath:resultPath];
    
    BOOL interleaved = (sourceFileFormat.channelCount > 1);
    AVAudioFile *resultFile = [[AVAudioFile alloc]initForWriting:resultFileURL settings:resultFileSettings commonFormat:AVAudioPCMFormatFloat32 interleaved:interleaved error:&err];
    if (err) {
        return completion(nil,err);
    }
    
    AVAudioFrameCount numSourceFrames = (AVAudioFrameCount)sourceFile.length;
    AVAudioFrameCount numSourceFramesRemaining = numSourceFrames;
    sourceFile.framePosition = 0;
    while (numSourceFramesRemaining) {
        
        AVAudioFrameCount bufferSize = ( numSourceFramesRemaining >= maxBufferSize ) ? ( maxBufferSize ) : ( numSourceFramesRemaining );
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFileFormat frameCapacity:bufferSize];
        
        [sourceFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
        if (err) {
            break;
        }
        
        AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
        OSStatus status = processingBlock(bufferList, bufferSize);
        
        if (status!=noErr) {
            break;
        }
        
        [resultFile writeFromBuffer:buffer error:&err];
        
        if (err) {
            break;
        }
        
        numSourceFramesRemaining-=bufferSize;
        if (sourceFile.framePosition != resultFile.framePosition) {
            NSLog(@"FRAME POSITIONS DIFFER: SOURCE = %lld, RESULT = %lld",sourceFile.framePosition,resultFile.framePosition);
        }
    }
    sourceFile = nil;
    resultFile = nil;
    [[AVAudioSession sharedInstance]setActive:NO error:nil];
    completion(resultPath,err);
}

+ (void)analyzeFile:(NSString *)sourceFilePath
          withBlock:(AudioAnalysisBlock)analysisBlock
      maxBufferSize:(AVAudioFrameCount)maxBufferSize
         completion:(void(^)(NSError *error))completion
{
    NSError *err = nil;
    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryAudioProcessing error:&err];
    if (err) {
        return completion(err);
    }
    [[AVAudioSession sharedInstance]setActive:YES error:&err];
    
    if (err) {
        return completion(err);
    }
    
    NSURL *sourceFileURL = [NSURL fileURLWithPath:sourceFilePath];
    AVAudioFile *sourceFile = [[AVAudioFile alloc]initForReading:sourceFileURL error:&err];
    if (err) {
        return completion(err);
    }
    
    AVAudioFormat *sourceFileFormat = sourceFile.processingFormat;
    AVAudioFrameCount numSourceFrames = (AVAudioFrameCount)sourceFile.length;
    AVAudioFrameCount numSourceFramesRemaining = numSourceFrames;
    sourceFile.framePosition = 0;
    while (numSourceFramesRemaining) {
        
        AVAudioFrameCount bufferSize = ( numSourceFramesRemaining >= maxBufferSize ) ? ( maxBufferSize ) : ( numSourceFramesRemaining );
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFileFormat frameCapacity:bufferSize];
        
        [sourceFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
        
        if (err) {
            break;
        }
        
        AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
        OSStatus status = analysisBlock(bufferList, bufferSize);
        if (status!=noErr) {
            break;
        }
        
        numSourceFramesRemaining-=bufferSize;
    }
    [[AVAudioSession sharedInstance]setActive:NO error:nil];
    sourceFile = nil;
    completion(err);
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
    
    AudioProcessingBlock compressorBlock = [OfflineAudioFileProcessor vcompressionProcessingBlockWithSampleRate:kSampleRate];
    
    AudioProcessingBlock freeverbBlock = [OfflineAudioFileProcessor
                                          freeverbProcessingBlockWithSampleRate:kSampleRate
                                          wetMix:0.25
                                          dryMix:0.75
                                          roomSize:0.4
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
//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor

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

@end

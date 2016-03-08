//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor

+ (void)test
{
    NSString *fileName = @"faure_sicilienne_violin.48o.wav";
    NSString *sourceFilePath = [[NSBundle bundleForClass:[self class]]pathForResource:[fileName stringByDeletingPathExtension] ofType:[fileName pathExtension]];
    NSString *tempFolderPath = NSTemporaryDirectory();
    NSString *resultFilePath = [tempFolderPath stringByAppendingPathComponent:fileName];
    [OfflineAudioFileProcessor processFile:sourceFilePath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        Float32 *samples = (Float32 *)(buffer->mBuffers[0].mData);
        Float32 scale = 2.0;
        vDSP_vsmul(samples, 1, &scale, samples, 1, bufferSize);
        return noErr;
    } maxBufferSize:1024 resultPath:resultFilePath completion:^(NSString *resultPath, NSError *error) {
        if (!error) {
            NSLog(@"finished writing audio file to path: %@",resultPath);
        }else{
            NSAssert(nil==error, @"ERROR WRITING FILE: %@",error);
        }
    }];
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

    completion(resultPath,err);
}


@end

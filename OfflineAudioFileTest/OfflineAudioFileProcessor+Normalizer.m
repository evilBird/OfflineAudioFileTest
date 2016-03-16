//
//  OfflineAudioFileProcessor+Normalizer.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Normalizer)

OSStatus NormalizeAudioBuffer(AudioBufferList *bufferList, Float32 peakMagnitude, Float32 maxMagnitude, UInt32 bufferSize)
{
    Float32 scalar = ( peakMagnitude > 0.0 ) ? ( maxMagnitude/peakMagnitude ) : ( 1.0 );
    UInt32 numChannels = bufferList->mNumberBuffers;
    for (UInt32 i = 0; i < numChannels; i++) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vsmul(samples, 1, &scalar, samples, 1, bufferSize);
    }
    return noErr;
}

+ (Float32)getPeakMagnitudeForAudioFile:(NSURL *)audioFileURL
{
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc]initForReading:audioFileURL error:&err];
    NSAssert(nil==err,@"ERROR READING FILE: %@",err);
    NSAssert(nil!=file,@"ERROR: SOURCE FILE IS NIL (PATH = %@)",audioFileURL.path);
    AVAudioFrameCount numSourceFrames = (AVAudioFrameCount)file.length;
    NSAssert(numSourceFrames>0,@"ERROR: SOURCE FILE HAS INVALID FRAME COUNT %@",@(numSourceFrames));
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:file.processingFormat frameCapacity:numSourceFrames];
    NSAssert(nil!=buffer,@"ERROR: UNABLE TO READ SOURCE FILE DATA INTO BUFFER");
    [file readIntoBuffer:buffer error:&err];
    NSAssert(nil==err,@"ERROR READING FILE INTO BUFFER: %@",err);
    AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
    UInt32 numChannels = bufferList->mNumberBuffers;
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32) * (UInt32)numSourceFrames);
    Float32 myPeakMag = 0.0;
    for (UInt32 i = 0; i < numChannels; i ++) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        memset(tempBuffer, 0, sizeof(Float32) * (UInt32)numSourceFrames);
        vDSP_vabs(samples, 1, tempBuffer, 1, numSourceFrames);
        vDSP_vsort(tempBuffer, numSourceFrames, -1);
        Float32 maxSamp = tempBuffer[0];
        myPeakMag = ( maxSamp > myPeakMag ) ? ( maxSamp ) : ( myPeakMag );
    }
    NSAssert(myPeakMag!=0.0,@"ERROR: PEAK MAGNITUDE IS ZERO FOR FILE %@",audioFileURL.path);
    free(tempBuffer);
    return myPeakMag;
}

- (Float32)peakMagnitudeForAudioFile:(AVAudioFile *)audioFile error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(audioFile);
    AVAudioFrameCount length = (AVAudioFrameCount)audioFile.length;
    NSParameterAssert(length>0);
    AVAudioFormat *format = audioFile.processingFormat;
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:format frameCapacity:length];
    NSError *err = nil;
    [audioFile readIntoBuffer:buffer error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        
        return 0.0;
    }
    
    AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
    UInt32 bufferSize = (UInt32)(length);
    UInt32 sampleRate = (UInt32)(format.sampleRate);
    UInt32 windowSize = 512;
    Float32 result = GetPeakRMS(bufferList, sampleRate, bufferSize, windowSize);
    return result;
}


- (AudioProcessingBlock)normalizeProcessingBlockWithConstant:(Float32)normConstant
{

    AudioProcessingBlock normalizeBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        UInt32 numChannels = bufferList->mNumberBuffers;
        
        for (UInt32 i = 0; i < numChannels; i++) {
            Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
            vDSP_vsmul(samples, 1, &normConstant, samples, 1, bufferSize);
        }
        
        return noErr;
    };
    
    return [normalizeBlock copy];
}

+ (AudioProcessingBlock)normalizeProcessingBlockForAudioFile:(NSString *)audioFilePath maximumMagnitude:(Float32)maximumMagnitude
{
    NSParameterAssert(audioFilePath);
    NSURL *audioFileURL = [NSURL fileURLWithPath:audioFilePath];
    
    Float32 peakMagnitude = [OfflineAudioFileProcessor getPeakMagnitudeForAudioFile:audioFileURL];
    
    AudioProcessingBlock normalizeBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        return NormalizeAudioBuffer(bufferList, peakMagnitude, maximumMagnitude,(UInt32)bufferSize);
    };
    
    return [normalizeBlock copy];
}

@end

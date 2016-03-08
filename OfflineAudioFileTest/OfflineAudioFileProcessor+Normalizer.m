//
//  OfflineAudioFileProcessor+Normalizer.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Normalizer)

Float32 GetPeakMagnitude(AudioBufferList *bufferList, UInt32 bufferSize)
{
    UInt32 numChannels = bufferList->mNumberBuffers;
    Float32 myPeak = 0.0;
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32) * bufferSize);
    for (UInt32 i = 0; i < numChannels; i ++ ) {
        memset(tempBuffer, 0, sizeof(Float32) * bufferSize);
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vabs(samples, 1, tempBuffer, 1, bufferSize);
        vDSP_vsort(tempBuffer, bufferSize, -1);
        Float32 max = tempBuffer[0];
        myPeak = ( max > myPeak ) ? ( max ) : ( myPeak );
    }
    
    free(tempBuffer);
    return myPeak;
}

OSStatus NormalizeAudioBuffer(AudioBufferList *bufferList, Float32 peakMagnitude, UInt32 bufferSize)
{
    Float32 scalar = ( peakMagnitude > 0.0 ) ? ( 1.0/peakMagnitude ) : ( 1.0 );
    UInt32 numChannels = bufferList->mNumberBuffers;
    for (UInt32 i = 0; i < numChannels; i++) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vsmul(samples, 1, &scalar, samples, 1, bufferSize);
    }
    return noErr;
}

+ (Float32)getPeakMagnitudeForBuffer:(AudioBufferList *)bufferList bufferSize:(NSUInteger)bufferSize
{
    return GetPeakMagnitude(bufferList, (UInt32)bufferSize);
}


+ (AudioProcessingBlock)normalizeProcessingBlockWithPeakMagnitude:(Float32)peakMagnitude
{
    AudioProcessingBlock normalizeBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        return NormalizeAudioBuffer(bufferList, peakMagnitude, (UInt32)bufferSize);
    };
    
    return [normalizeBlock copy];
}

@end

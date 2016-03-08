//
//  AudioNormalizeProcessor.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "AudioNormalizeProcessor.h"

@interface AudioNormalizeProcessor ()
{
    Float32 kPreviousNormalizingFactor;
}

@end

@implementation AudioNormalizeProcessor

- (instancetype)init
{
    self = [super init];
    if (self) {
        kPreviousNormalizingFactor = 1.0;
    }
    return self;
}

Float32 GetNormalizingFactor(AudioBufferList *bufferList, UInt32 inNumFrames)
{
    UInt32 numChannels = bufferList->mNumberBuffers;
    if (numChannels==0) {
        return 0.0;
    }
    
    Float32 factorSum = 0.0;
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32) * inNumFrames);
    printf("\n");
    for (UInt32 i = 0; i < numChannels; i ++) {
        memset(tempBuffer, 0, sizeof(Float32) * inNumFrames);
        Float32 *audioData = bufferList->mBuffers[i].mData;
        vDSP_vabs(audioData, 1, tempBuffer, 1, inNumFrames);
        Float32 maxVal;
        vDSP_maxmgv(tempBuffer, 1, &maxVal, inNumFrames);
        Float32 factor = ( maxVal > 0 ) ? ( 1.0/maxVal ) : 1.0;
        factorSum+=factor;
    }
    
    Float32 result = factorSum/(Float32)(numChannels);
    Float32 logResult = log2f(1.+result);
    free(tempBuffer);
    return logResult;
}

int ApplyNormalizationFactors(AudioBufferList *bufferList, Float32 startFactor, Float32 endFactor, UInt32 inNumFrames)
{
    UInt32 numChannels = bufferList->mNumberBuffers;
    Float32 *normalizingVector = (Float32 *)malloc(sizeof(Float32)*inNumFrames);
    Float32 df = startFactor-endFactor;
    Float32 dfPerFrame = df/(Float32)(inNumFrames-1);
    vDSP_vramp(&startFactor, &dfPerFrame, normalizingVector, 1, inNumFrames);
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32) * inNumFrames);
    for (UInt32 i = 0; i < numChannels; i ++) {
        memset(tempBuffer, 0, sizeof(Float32)*inNumFrames);
        Float32 *audioData = bufferList->mBuffers[i].mData;
        vDSP_vmul(audioData, 1, normalizingVector, 1, audioData, 1, inNumFrames);
        Float32 maxVal;
        vDSP_maxmgv(audioData, 1, tempBuffer, inNumFrames);
        vDSP_maxv(tempBuffer, 1, &maxVal, inNumFrames);
        Float32 scalar = ( maxVal < 0.96 ) ? ( 1.0 ) : ( 1.0/maxVal );
        vDSP_vsmul(audioData, 1, &scalar, audioData, 1, inNumFrames);
    }
    free(normalizingVector);
    return 0;
}

- (OSStatus)processBuffer:(AudioBufferList *)bufferList withSize:(NSUInteger)bufferSize
{
    UInt32 inNumFrames = (UInt32)bufferSize;
    Float32 normalizingFactor = GetNormalizingFactor(bufferList, inNumFrames);
    ApplyNormalizationFactors(bufferList, kPreviousNormalizingFactor, normalizingFactor, inNumFrames);
    kPreviousNormalizingFactor = normalizingFactor;
    return noErr;
}

@end

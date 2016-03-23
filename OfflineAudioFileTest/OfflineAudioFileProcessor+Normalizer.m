//
//  OfflineAudioFileProcessor+Normalizer.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor+Functions.h"

@implementation OfflineAudioFileProcessor (Normalizer)

- (AudioProcessingBlock)normalizeProcessingBlockWithConstant:(Float32)normConstant
{
    AudioProcessingBlock normalizeBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        OSStatus err = noErr;
        UInt32 numChannels = bufferList->mNumberBuffers;
        for (UInt32 i = 0; i < numChannels; i++) {
            Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
            vDSP_vsmul(samples, 1, &normConstant, samples, 1, bufferSize);
        }
        return err;
    };
    
    return [normalizeBlock copy];
}

- (AudioProcessingBlock)rampProcessingBlockWithFadeInDuration:(Float32)fadeInSecs fadeOutDuration:(Float32)fadeOutSecs
{
    UInt32 sampleRate = (UInt32)self.sourceFormat.sampleRate;
    UInt32 sampleLength = (UInt32)self.sourceLength;
    UInt32 fadeInNumSamples = fadeInSecs*sampleRate;
    Float32 fadeInDeltaPerSample = 1.0/(Float32)fadeInNumSamples;
    UInt32 fadeOutNumSamples = fadeOutSecs*sampleRate;
    Float32 fadeOutDeltaPerSample = -1.0/(Float32)fadeOutNumSamples;
    UInt32 fadeOutStartSample = sampleLength-fadeOutNumSamples;
    __block UInt32 numSamplesProcessed = 0;
    __block Float32 prevRampEndValue = 0.0;
    
    AudioProcessingBlock myBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        OSStatus err = noErr;
        UInt32 expectedNumSamplesProcessed = (numSamplesProcessed+(UInt32)bufferSize);
        UInt32 numChannels = bufferList->mNumberBuffers;
        Float32 *ramp = NULL;
        Float32 rampStartVal,rampEndVal;
        UInt32 bufferLength = (UInt32)bufferSize;
        UInt32 rampNumSamples = bufferLength;
        
        if (numSamplesProcessed < fadeInNumSamples) {
            
            rampStartVal = prevRampEndValue;
            UInt32 numSamplesLeftInRamp = fadeInNumSamples-numSamplesProcessed;
            bool shortRamp = ( numSamplesLeftInRamp > bufferLength ) ? ( false ) : ( true );
            rampNumSamples = ( shortRamp ) ? ( numSamplesLeftInRamp ) : ( bufferLength );
            
            if (shortRamp) {
                ramp = GenerateFloatBuffer(bufferLength, 1.0);
                rampStartVal = prevRampEndValue;
                rampEndVal = 1.0;
                prevRampEndValue = rampEndVal;
                
            }else{
                ramp = GenerateFloatBuffer(bufferLength, 0.0);
                rampStartVal = prevRampEndValue;
                rampEndVal = rampStartVal + ((Float32)rampNumSamples * fadeInDeltaPerSample);
                prevRampEndValue = rampEndVal;
            }
            
            vDSP_vgen(&rampStartVal, &rampEndVal, ramp, 1, rampNumSamples);
            vDSP_vmul(ramp, 1, ramp, 1, ramp, 1, bufferLength);
            
        }else if (expectedNumSamplesProcessed >= fadeOutStartSample){
            UInt32 rampStartOffset = ( numSamplesProcessed >= fadeOutStartSample ) ? ( 0 ) : ( fadeOutStartSample - numSamplesProcessed);
            UInt32 numSamplesLeftInRamp = ( rampStartOffset > 0 ) ? ( fadeOutNumSamples ) : ( sampleLength - numSamplesProcessed );
            rampStartVal = prevRampEndValue;
            bool shortRamp = ( numSamplesLeftInRamp > bufferLength ) ? ( false ) : ( true );
            
            if (shortRamp&&!rampStartOffset) {
                
                ramp = GenerateFloatBuffer(bufferLength, 0.0);
                rampStartVal = prevRampEndValue;
                rampEndVal = 0.0;
                prevRampEndValue = rampEndVal;
                rampNumSamples = numSamplesLeftInRamp;
                
            }else if (shortRamp&&rampStartOffset){
                
                ramp = GenerateFloatBuffer(bufferLength, 0.0);
                rampStartVal = prevRampEndValue;
                rampEndVal = 0.0;
                rampNumSamples = numSamplesLeftInRamp;
                
            }else if (!shortRamp&&rampStartOffset){
                
                ramp = GenerateFloatBuffer(bufferLength, 1.0);
                rampStartVal = prevRampEndValue;
                rampNumSamples = bufferLength-rampStartOffset;
                rampEndVal = rampStartVal + ((Float32)rampNumSamples * fadeOutDeltaPerSample);
                prevRampEndValue = rampEndVal;
                
            }else{
                
                ramp = GenerateFloatBuffer(bufferLength, 0.0);
                rampStartVal = prevRampEndValue;
                rampEndVal = rampStartVal + ((Float32)rampNumSamples * fadeOutDeltaPerSample);
                rampNumSamples = bufferLength;
                prevRampEndValue = rampEndVal;
            }
            
            Float32 *rampPointer = ramp+rampStartOffset;
            vDSP_vgen(&rampStartVal, &rampEndVal, rampPointer, 1, rampNumSamples);
            vDSP_vmul(ramp, 1, ramp, 1, ramp, 1, bufferLength);
            
        }
        
        numSamplesProcessed = expectedNumSamplesProcessed;
        
        if (!ramp) {
            return err;
        }
        
        for (UInt32 i = 0; i < numChannels; i++) {
            Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
            vDSP_vmul(samples, 1, ramp, 1, samples, 1, bufferLength);
        }
        
        free(ramp);
        
        return err;
    };
    
    return [myBlock copy];

}

- (AudioProcessingBlock)postProcessingBlockWithNormalizingConstant:(Float32)normConstant fadeInRampTime:(Float32)fadeInSecs fadeOutRampTime:(Float32)fadeOutSecs
{
    AudioProcessingBlock normalizeBlock = [self normalizeProcessingBlockWithConstant:normConstant];
    AudioProcessingBlock rampBlock = [self rampProcessingBlockWithFadeInDuration:fadeInSecs fadeOutDuration:fadeOutSecs];
    
    AudioProcessingBlock postProcessingBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        OSStatus err = noErr;
        err = normalizeBlock(bufferList, bufferSize);
        err = rampBlock(bufferList, bufferSize);
        return err;
    };
    
    return [postProcessingBlock copy];
}

- (AudioProcessingBlock)normalizeProcessingBlockWithConstant:(Float32)normConstant fadeInDuration:(Float32)fadeInSecs fadeOutDuration:(Float32)fadeOutSecs
{
    AudioProcessingBlock normalizeBlock = [self normalizeProcessingBlockWithConstant:normConstant];
    AudioProcessingBlock postProcessingBlock = [self rampProcessingBlockWithFadeInDuration:fadeInSecs fadeOutDuration:fadeOutSecs];
    
    AudioProcessingBlock myBlock = ^(AudioBufferList *bufferList, AVAudioFrameCount bufferSize){
        OSStatus err = noErr;
        err = normalizeBlock(bufferList, bufferSize);
        err = postProcessingBlock(bufferList, bufferSize);
        return err;
    };
    
    return [myBlock copy];
}

@end

//
//  OfflineAudioFileProcessor+Normalizer.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Normalizer)

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


@end

//
//  OfflineAudioFileProcessor+Functions.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/17/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor+Functions.h"

@implementation OfflineAudioFileProcessor (Functions)

AudioBufferList *AllocateAndInitAudioBufferList(AudioStreamBasicDescription audioFormat, int frameCount) {
    int numberOfBuffers = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? audioFormat.mChannelsPerFrame : 1;
    int channelsPerBuffer = audioFormat.mFormatFlags & kAudioFormatFlagIsNonInterleaved ? 1 : audioFormat.mChannelsPerFrame;
    int bytesPerBuffer = audioFormat.mBytesPerFrame * frameCount;
    AudioBufferList *audio = malloc(sizeof(AudioBufferList) + (numberOfBuffers - 1) * sizeof(AudioBuffer));
    if (!audio) {
        return NULL;
    }
    audio->mNumberBuffers = numberOfBuffers;
    for (int i = 0; i < numberOfBuffers; i++) {
        if (bytesPerBuffer > 0) {
            audio->mBuffers[i].mData = calloc(bytesPerBuffer, 1);
            if (!audio->mBuffers[i].mData) {
                for (int j = 0; j < i; j++) free(audio->mBuffers[j].mData);
                free(audio);
                return NULL;
            }
        } else {
            audio->mBuffers[i].mData = NULL;
        }
        audio->mBuffers[i].mDataByteSize = bytesPerBuffer;
        audio->mBuffers[i].mNumberChannels = channelsPerBuffer;
    }
    return audio;
}

AudioBufferList* CreateAudioBufferList(AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize)
{
    const AudioStreamBasicDescription *asbd = [audioFormat streamDescription];
    int ct = (int)maxBufferSize;
    return AllocateAndInitAudioBufferList(*asbd, ct);
}

OSStatus ResizeAudioBufferList(AudioBufferList *bufferList, AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize)
{
    UInt32 bufferSize = (UInt32)maxBufferSize;
    UInt32 numberOfChannels = bufferList->mNumberBuffers;
    UInt32 bytesPerBuffer = (audioFormat.streamDescription->mBytesPerFrame) * bufferSize;
    
    for (UInt32 i = 0; i < numberOfChannels; i++) {
        if (bytesPerBuffer > 0) {
            bufferList->mBuffers[i].mData = realloc(bufferList->mBuffers[i].mData, bytesPerBuffer);
            if (!bufferList->mBuffers[i].mData) {
                for (int j = 0; j < i; j++) free(bufferList->mBuffers[j].mData);
                free(bufferList);
                return -1;
            }
        } else {
            bufferList->mBuffers[i].mData = NULL;
        }
        
        bufferList->mBuffers[i].mDataByteSize = bytesPerBuffer;
        bufferList->mBuffers[i].mNumberChannels = 1;
    }
    
    return noErr;
}

void PrintAudioBufferList(AudioBufferList *bufferList, AVAudioFrameCount bufferSize, const char *tag)
{
    UInt32 numChannels = bufferList->mNumberBuffers;
    for (UInt32 i = 0; i < numChannels; i ++) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        print_samples(samples, (UInt32)bufferSize, tag);
    }
}

OSStatus CopyMonoAudioBufferListToStereo(AudioBufferList *stereoBufferList, AudioBufferList *monoBufferList, AVAudioFrameCount bufferSize)
{
    Float32 *monoSamples = (Float32 *)(monoBufferList->mBuffers[0].mData);
    UInt32 numChannels = stereoBufferList->mNumberBuffers;
    Float32 normConstant = 1.0/(Float32)(numChannels);
    UInt32 numSamples = (UInt32)bufferSize;
    for (UInt32 i = 0; i < numChannels; i ++) {
        Float32 *stereoSamples = (Float32 *)(stereoBufferList->mBuffers[i].mData);
        vDSP_vsmul(monoSamples, 1, &normConstant, stereoSamples, 1, numSamples);
    }
    return noErr;
}

void ClearAudioBufferList(AudioBufferList *bufferList)
{
    for (int bufferIndex = 0; bufferIndex < bufferList->mNumberBuffers; bufferIndex++) {
        memset(bufferList->mBuffers[bufferIndex].mData, 0, bufferList->mBuffers[bufferIndex].mDataByteSize);
    }
}

void FreeAudioBufferList(AudioBufferList *bufferList) {
    for (int i = 0; i < bufferList->mNumberBuffers; i++) {
        if (bufferList->mBuffers[i].mData) free(bufferList->mBuffers[i].mData);
    }
    free(bufferList);
}

@end

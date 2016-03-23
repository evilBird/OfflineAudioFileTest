//
//  OfflineAudioFileProcessor+Functions.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/17/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@interface OfflineAudioFileProcessor (Functions)

AudioBufferList* CreateAudioBufferList(AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize);
OSStatus ResizeAudioBufferList(AudioBufferList *bufferList, AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize);
OSStatus CopyMonoAudioBufferListToStereo(AudioBufferList *stereoBufferList, AudioBufferList *monoBufferList, AVAudioFrameCount bufferSize);
void PrintAudioBufferList(AudioBufferList *bufferList, AVAudioFrameCount bufferSize, const char *tag);

void ClearAudioBufferList(AudioBufferList *bufferList);

void FreeAudioBufferList(AudioBufferList *bufferList);

void print_samples(Float32 *samples, UInt32 numSamples, const char *tag);

Float32 GetPeakRMS(AudioBufferList *buffer, UInt32 sampleRate, UInt32 bufferSize, UInt32 windowSize);

Float32 GetBufferMaximumMagnitude(AudioBufferList *bufferList, UInt32 bufferSize);

Float32* GenerateFloatBuffer(UInt32 bufferLength, Float32 initalValue);

Float32* GetRMSVector(AudioBufferList *bufferList,
                      UInt32 sampleRate,
                      UInt32 bufferSize,
                      UInt32 windowSize);

Float32 GetBufferMaximumMagnitude(AudioBufferList *bufferList, UInt32 bufferSize);

Float32 GetPeakRMSTime(AudioBufferList *buffer, UInt32 sampleRate, UInt32 bufferSize, UInt32 windowSize, Float32 *peakRMS);

void FillFloatBuffer(Float32 *floatBuffer, Float32 fillValue, UInt32 bufferSize);

void ClearFloatBuffer(Float32 *floatBuffer, UInt32 bufferSize);

Float32* GetFloatBuffer(UInt32 bufferLength);

@end

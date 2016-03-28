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

Float32 interval_triple_likelihood(Float32 value1, Float32 value2);
Float32 interval_duple_likelihood(Float32 value1, Float32 value2);
Float32 weight_value_in_range(Float32 value, Float32 range_min, Float32 range_max, Float32 bias);
Float32 weight_for_value_in_range(Float32 value, Float32 range_min, Float32 range_max);
Float32 round_float_to_sig_digs(Float32 myFloat, UInt32 sigDigs);

Float32 compare_beats_as_duples_get_error(Float32 beat1_length, Float32 beat2_length, Float32 *beat_ratio);
Float32 compare_beats_as_tuples_get_error(Float32 beat1_length, Float32 beat2_length, Float32 *beat_ratio);

@end

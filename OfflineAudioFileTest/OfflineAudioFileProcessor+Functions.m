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

void print_samples(Float32 *samples, UInt32 numSamples, const char *tag){
    printf("\nPRINT BUFFER: %s (n = %u)",tag,numSamples);
    UInt32 max_i = numSamples/10;
    for (UInt32 i = 0; i < max_i; i++) {
        printf("\n");
        for (UInt32 j = 0; j < 10; ++j) {
            UInt32 index = (i*10)+j;
            Float32 samp = samples[index];
            printf("%.8f\t",samp);
        }
    }
    printf("\n");
}

Float32* GenerateFloatRamp(UInt32 bufferLength, Float32 startValue, Float32 endValue)
{
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32)*bufferLength);
    vDSP_vgen(&startValue, &endValue, tempBuffer, 1, bufferLength);
    return tempBuffer;
}

Float32* GenerateFloatBuffer(UInt32 bufferLength, Float32 initalValue)
{
    return GenerateFloatRamp(bufferLength, initalValue, initalValue);
}

void FillFloatBuffer(Float32 *floatBuffer, Float32 fillValue, UInt32 bufferSize)
{
    vDSP_vgen(&fillValue, &fillValue, floatBuffer, 1, bufferSize);
}

void ClearFloatBuffer(Float32 *floatBuffer, UInt32 bufferSize)
{
    FillFloatBuffer(floatBuffer, 0.0, bufferSize);
}

Float32* GetFloatBuffer(UInt32 bufferLength)
{
    return GenerateFloatBuffer(bufferLength, 0.0);
}


Float32* GetRMSVector(AudioBufferList *bufferList,
                      UInt32 sampleRate,
                      UInt32 bufferSize,
                      UInt32 windowSize)
{
    UInt32 numChannels = bufferList->mNumberBuffers;
    Float32 normalizeScalar = 1.0/((Float32)numChannels);
    Float32 *rmsBuffer = GetFloatBuffer(bufferSize);
    Float32 *tempBuffer1 = GetFloatBuffer(bufferSize);
    Float32 *tempBuffer2 = GetFloatBuffer(bufferSize);
    
    for (UInt32 i = 0; i < numChannels; i++) {
        
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vsmul(samples, 1, &normalizeScalar, tempBuffer1, 1, bufferSize);
        vDSP_vsq(tempBuffer1, 1, tempBuffer2, 1, bufferSize);
        ClearFloatBuffer(tempBuffer1, bufferSize);
        vDSP_vswsum(tempBuffer2, 1, tempBuffer1, 1, bufferSize-windowSize, windowSize);
        ClearFloatBuffer(tempBuffer2, bufferSize);
        Float32 den = (Float32)windowSize;
        vDSP_vsdiv(tempBuffer1, 1, &den, tempBuffer2, 1, bufferSize);
        ClearFloatBuffer(tempBuffer1, bufferSize);
        int n = (int)bufferSize;
        vvsqrtf(tempBuffer1,tempBuffer2,&n);
        ClearFloatBuffer(tempBuffer2, bufferSize);
        vDSP_vadd(rmsBuffer, 1, tempBuffer1, 1, rmsBuffer, 1, bufferSize);
        ClearFloatBuffer(tempBuffer1, bufferSize);
    }
    
    
    free(tempBuffer1);
    free(tempBuffer2);
    
    return rmsBuffer;
}

Float32 GetPeakRMS(AudioBufferList *buffer, UInt32 sampleRate, UInt32 bufferSize, UInt32 windowSize)
{
    Float32 *rmsVector = NULL;
    rmsVector = GetRMSVector(buffer, sampleRate, bufferSize, windowSize);
    if (NULL == rmsVector) {
        return 0.0;
    }
    Float32 peakRMS;
    vDSP_maxv(rmsVector, 1, &peakRMS, bufferSize);
    free(rmsVector);
    return peakRMS;
}

Float32 GetPeakRMSTime(AudioBufferList *buffer, UInt32 sampleRate, UInt32 bufferSize, UInt32 windowSize, Float32 *peakRMS)
{
    Float32 *rmsVector = NULL;
    rmsVector = GetRMSVector(buffer, sampleRate, bufferSize, windowSize);
    
    if (NULL == rmsVector) {
        return 0.0;
    }
    
    Float32 myPeakRMS;
    vDSP_Length peakIndex;
    vDSP_maxvi(rmsVector, 1, &myPeakRMS, &peakIndex, bufferSize);
    free(rmsVector);
    
    if (peakRMS) {
        *peakRMS = peakIndex;
    }
    
    Float32 secondsPerSample = 1.0/(Float32)sampleRate;
    Float32 peakSampleTime = (Float32)(peakIndex) * secondsPerSample;
    return peakSampleTime;
}

Float32 GetBufferMaximumMagnitude(AudioBufferList *bufferList, UInt32 bufferSize)
{
    UInt32 numChannels = (UInt32)(bufferList->mNumberBuffers);
    Float32 maxVal;
    Float32 myMaxVal = 0;
    for (UInt32 i = 0; i < numChannels; i ++ ) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_maxmgv(samples, 1, &maxVal, bufferSize);
        myMaxVal = ( maxVal >= myMaxVal ) ? ( maxVal ) : ( myMaxVal );
    }
    
    return myMaxVal;
}

Float32 interval_triple_likelihood(Float32 value1, Float32 value2)
{
    Float32 num,den;
    num = ( value1 > value2 ) ? ( value1 ) : ( value2 );
    den = ( value1 > value2 ) ? ( value2 ) : ( value1 );
    Float32 logRatio = log2f(num/den);
    Float32 triple_error = fabsf(logRatio)-log2f(3.0);
    Float32 integral_error = fabsf(triple_error-roundf(triple_error));
    return (1.0 - integral_error);
}

Float32 round_float_to_sig_digs(Float32 myFloat, UInt32 sigDigs)
{
    Float32 pow10np = powf(10., (Float32)sigDigs);
    Float32 result = roundf(myFloat*pow10np) / pow10np;
    return result;
}

Float32 compare_beats_as_duples_get_error(Float32 beat1_length, Float32 beat2_length, Float32 *beat_ratio)
{
    beat1_length = round_float_to_sig_digs(beat1_length, 3);
    beat2_length = round_float_to_sig_digs(beat2_length, 3);
    
    if (beat1_length <= 0.0 || beat2_length <= 0.0) {
        if (beat_ratio) {
            *beat_ratio = 0.0;
        }
        return 1.0;
    }
    
    if (beat1_length == beat2_length ) {
        if (beat_ratio) {
            *beat_ratio = 1.0;
        }
        
        return 0.0;
    }
    
    BOOL beat1_is_longer = ( beat1_length > beat2_length );
    
    Float32 length_ratio;
    
    if (beat1_is_longer){
        length_ratio = beat1_length/beat2_length;
    }else{
        length_ratio = beat2_length/beat1_length;
    }
    
    Float32 duple_err = log2f(length_ratio) - log2f(2.0) + 1.0;
    
    Float32 e = round_float_to_sig_digs(duple_err, 1);
    
    Float32 duple_ratio = powf(2.0, e);
    
    Float32 my_beat_ratio = ( beat1_is_longer ) ? ( duple_ratio ) : ( 1.0/duple_ratio );
    
    if (beat_ratio) {
        *beat_ratio = round_float_to_sig_digs(my_beat_ratio, 2);
    }
    
    Float32 error = duple_ratio-roundf(duple_ratio);
    Float32 err = (duple_err-duple_ratio);
    return error*my_beat_ratio;
}

Float32 compare_beats_as_tuples_get_error(Float32 beat1_length, Float32 beat2_length, Float32 *beat_ratio)
{
    beat1_length = round_float_to_sig_digs(beat1_length, 3);
    beat2_length = round_float_to_sig_digs(beat2_length, 3);
    
    if (beat1_length <= 0.0 || beat2_length <= 0.0) {
        if (beat_ratio) {
            *beat_ratio = 0.0;
        }
        return 1.0;
    }
    
    if (beat1_length == beat2_length ) {
        if (beat_ratio) {
            *beat_ratio = 1.0;
        }
        
        return 0.0;
    }
    
    BOOL beat1_is_longer = ( beat1_length > beat2_length );
    Float32 length_ratio;
    
    if (beat1_is_longer){
        length_ratio = beat1_length/beat2_length;
    }else{
        length_ratio = beat2_length/beat1_length;
    }
    
    Float32 tuple_err = log2f(length_ratio) - log2f(3.0) + 1.0;
    
    Float32 e = round_float_to_sig_digs(tuple_err, 1);
    
    Float32 tuple_ratio = powf(3.0, e);
    
    Float32 my_beat_ratio = ( beat1_is_longer ) ? ( tuple_ratio ) : ( 1.0/tuple_ratio );
    
    if (beat_ratio) {
        *beat_ratio = round_float_to_sig_digs(my_beat_ratio, 2);
    }
    
    Float32 error = tuple_ratio-roundf(tuple_ratio);
    Float32 err = (tuple_err - tuple_ratio);
    return error * my_beat_ratio;
}

Float32 interval_duple_likelihood(Float32 value1, Float32 value2)
{
    Float32 num,den;
    num = ( value1 > value2 ) ? ( value1 ) : ( value2 );
    den = ( value1 > value2 ) ? ( value2 ) : ( value1 );
    Float32 logRatio = log2f(num/den);
    Float32 duple_error = fabsf(logRatio)-log2f(2.0);
    Float32 integral_error = fabsf(duple_error-roundf(duple_error));
    return (1.0 - integral_error);
}

Float32 weight_value_in_range(Float32 value, Float32 range_min, Float32 range_max, Float32 bias)
{
    Float32 range = range_max-range_min;
    Float32 norm_interval = (value-range_min)/range;
    Float32 ci = norm_interval*M_PI+(M_PI*(0.5+bias));
    Float32 cv = cosf(ci);
    Float32 cv2 = ((cv * 0.5)+0.5);
    return (1.0-cv2);
}

Float32 weight_for_value_in_range(Float32 value, Float32 range_min, Float32 range_max)
{
    // this is also vector optimized
    
    if (value < range_min || value > range_max) {
        return 0.0;
    }
    
    Float32 two_pi = M_PI*2.0;
    Float32 range = range_max-range_min;
    Float32 w = two_pi/range;
    Float32 n = (value - range_min);
    Float32 result = (0.5 - 0.5 * cos(w * n));
    return result;
}

@end

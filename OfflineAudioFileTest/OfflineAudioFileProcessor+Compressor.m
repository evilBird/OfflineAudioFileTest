//
//  OfflineAudioFileProcessor+Compressor.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Compressor)

#define DEFAULT_LOOKAHEAD_MS   0.5
#define DEFAULT_ATTACK_MS      0.1
#define DEFAULT_RELEASE_MS     30.0
#define DEFAULT_WINDOW_MS      3.0
#define DEFAULT_SLOPE          0.5
#define DEFAULT_THRESHOLD      0.2

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

OSStatus vcompress
(
 AudioBufferList*  audioBufferList,     // signal
 UInt32   n,          // N samples
 Float32  threshold,  // threshold (percents)
 Float32  slope,      // slope angle (percents)
 UInt32   sampleRate,         // sample rate (smp/sec)
 Float32  lookaheadtime_ms,        // lookahead  (ms)
 Float32  windowtime_ms,       // window time (ms)
 Float32  attacktime_ms,       // attack time  (ms)
 Float32  releasetime_ms        // release time (ms)
)
{
    
    //threshold *= 0.01;          // threshold to unity (0...1)
    //slope *= 0.01;              // slope to unity
    lookaheadtime_ms *= 1e-3;                // lookahead time to seconds
    windowtime_ms *= 1e-3;               // window time to seconds
    attacktime_ms *= 1e-3;               // attack time to seconds
    releasetime_ms *= 1e-3;               // release time to seconds
    
    // attack and release "per sample decay"
    Float32  att = (attacktime_ms == 0.0) ? (0.0) : exp (-1.0 / (sampleRate * attacktime_ms));
    Float32  rel = (releasetime_ms == 0.0) ? (0.0) : exp (-1.0 / (sampleRate * releasetime_ms));
    
    // envelope
    Float32  env = 0.0;
    
    // sample offset to lookahead wnd start
    UInt32     lookahead_num_samples = (UInt32) (sampleRate * lookaheadtime_ms);
    
    // samples count in lookahead window
    UInt32     window_num_samples = (UInt32) (sampleRate * windowtime_ms);
    
    UInt32 numChannels = audioBufferList->mNumberBuffers;
    Float32 channelNormalizeScalar = 1.0/(Float32)numChannels;
    
    for (UInt32 i = 0; i < numChannels; i++) {
        
        Float32 *samples = (Float32 *)(audioBufferList->mBuffers[i].mData);
        
        //print_samples(samples, n, "RAW SAMPLES");
        
        Float32 *tempBuffer = GetFloatBuffer(n);
        
        Float32 *samplePtr = samples;
        
        samplePtr+=lookahead_num_samples;
        
        memcpy(tempBuffer, samplePtr, sizeof(Float32)*(n-lookahead_num_samples));
        
        //print_samples(tempBuffer, n, "LOOKAHEAD SAMPLES");
        
        Float32 *tempBuffer1 = GetFloatBuffer(n);
        
        vDSP_vsmul(tempBuffer, 1, &channelNormalizeScalar, tempBuffer1, 1, n);
        
        //print_samples(tempBuffer1, n, "NORMALIZED SAMPLES");
        
        free(tempBuffer);
        
        Float32 *tempBuffer2 = GetFloatBuffer(n);
        
        vDSP_vsq(tempBuffer1, 1, tempBuffer2, 1, n);
        
        //print_samples(tempBuffer2, n, "SQUARED NORMALIZED SAMPLES");
        
        free(tempBuffer1);
        
        Float32 *tempBuffer3 = GetFloatBuffer(n);
        
        vDSP_vswsum(tempBuffer2, 1, tempBuffer3, 1, n-window_num_samples, window_num_samples);
        
        //print_samples(tempBuffer3, n, "SLIDING WINDOW SUMS");
        
        free(tempBuffer2);
        
        Float32 den = (Float32)window_num_samples;
        
        Float32 *tempBuffer4 = GetFloatBuffer(n);
        
        vDSP_vsdiv(tempBuffer3, 1, &den, tempBuffer4, 1, n);
        
        free(tempBuffer3);
        
        int ct = (int)n;
        
        Float32 *tempBuffer5 = GetFloatBuffer(n);
        
        vvsqrtf(tempBuffer5,tempBuffer4,&ct);
        
        free(tempBuffer4);
        
        //print_samples(tempBuffer5, n, "RMS");
        
        Float32 *envBuffer = GetFloatBuffer(n);
        Float32 *gainBuffer = GetFloatBuffer(n);
        
        for (UInt32 j = 0; j < n; j++) {
            Float32 rms = tempBuffer5[j];
            Float32 prev_env = ( j == 0 ) ? ( 0.0 ) : ( envBuffer[j-1] );
            // dynamic selection: attack or release?
            Float32  theta = rms > prev_env ? att : rel;
            env = (1.0 - theta) * rms + theta * env;
            envBuffer[j] = env;
            // the very easy hard knee 1:N compressor
            Float32  gain = ( env <= threshold ) ? ( 1.0 ) : ( 1.0 - (env-threshold) * slope );
            gainBuffer[j] = gain;
            
        }
        
        free(tempBuffer5);
        //print_samples(envBuffer, n, "ENVELOPE BUFFER");
        //print_samples(gainBuffer, n, "GAIN BUFFER");
        vDSP_vmul(samples, 1, gainBuffer, 1, samples, 1, n);
        //print_samples(samples, n, "COMPRESSED SAMPLES");
        free(envBuffer);
        free(gainBuffer);
    }
    
    
    
    
    return noErr;
}

OSStatus compress
(
 AudioBufferList*  audioBufferList,     // signal
 UInt32   n,          // N samples
 Float32  threshold,  // threshold (percents)
 Float32  slope,      // slope angle (percents)
 UInt32   sampleRate,         // sample rate (smp/sec)
 Float32  lookaheadtime_ms,        // lookahead  (ms)
 Float32  windowtime_ms,       // window time (ms)
 Float32  attacktime_ms,       // attack time  (ms)
 Float32  releasetime_ms        // release time (ms)
)
{
    UInt32 numChannels = audioBufferList->mNumberBuffers;
    
    threshold *= 0.01;          // threshold to unity (0...1)
    slope *= 0.01;              // slope to unity
    lookaheadtime_ms *= 1e-3;                // lookahead time to seconds
    windowtime_ms *= 1e-3;               // window time to seconds
    attacktime_ms *= 1e-3;               // attack time to seconds
    releasetime_ms *= 1e-3;               // release time to seconds
    
    // attack and release "per sample decay"
    Float32  att = (attacktime_ms == 0.0) ? (0.0) : exp (-1.0 / (sampleRate * attacktime_ms));
    Float32  rel = (releasetime_ms == 0.0) ? (0.0) : exp (-1.0 / (sampleRate * releasetime_ms));
    
    // envelope
    Float32  env = 0.0;
    
    // sample offset to lookahead wnd start
    UInt32     lhsmp = (UInt32) (sampleRate * lookaheadtime_ms);
    
    // samples count in lookahead window
    UInt32     nrms = (UInt32) (sampleRate * windowtime_ms);
    
    // for each sample...
    for (UInt32 i = 0; i < n; ++i)
    {
        // now compute RMS
        Float32  summ = 0;
        
        // for each sample in window
        for (UInt32 j = 0; j < nrms; ++j)
        {
            UInt32     lki = i + j + lhsmp;
            Float32  smp;
            
            // if we in bounds of signal?
            // if so, convert to mono
            if (lki < n)
            {
                smp = 0.0;//0.5 * wav[lki][0] + 0.5 * wav[lki][1];
                for (UInt32 k = 0; k < numChannels; k++) {
                    Float32 norm = 1.0/(Float32)numChannels;
                    Float32 *samps = (Float32 *)(audioBufferList->mBuffers[k].mData);
                    Float32 samp = samps[lki];
                    smp += (samp * norm);
                }
                
            }
            else
            {
                smp = 0.0;      // if we out of bounds we just get zero in smp
            }
            summ += smp * smp;  // square em..
        }
        
        Float32  rms = sqrt (summ / nrms);   // root-mean-square
        
        // dynamic selection: attack or release?
        Float32  theta = rms > env ? att : rel;
        
        // smoothing with capacitor, envelope extraction...
        // here be aware of pIV denormal numbers glitch
        env = (1.0 - theta) * rms + theta * env;
        
        // the very easy hard knee 1:N compressor
        Float32  gain = 1.0;
        if (env > threshold)
            gain = gain - (env - threshold) * slope;
        
        // result - two hard kneed compressed channels...
        for (UInt32 k = 0; k < numChannels; k ++) {
            Float32 *samps = (Float32 *)(audioBufferList->mBuffers[k].mData);
            samps[i] *= gain;
        }
    }
    
    return noErr;
}

- (AudioProcessingBlock)vectorCompressionProcessingBlock
{
    NSUInteger sampleRate = (NSUInteger)self.sourceFormat.sampleRate;
    AudioProcessingBlock compressionBlock = ^(AudioBufferList *buffer, AVAudioFrameCount bufferSize){
        
        OSStatus err =  vcompress(buffer,
                                  (UInt32)bufferSize,
                                  DEFAULT_THRESHOLD,
                                  DEFAULT_SLOPE,
                                  (UInt32)sampleRate,
                                  DEFAULT_LOOKAHEAD_MS,
                                  DEFAULT_WINDOW_MS,
                                  DEFAULT_ATTACK_MS,
                                  DEFAULT_RELEASE_MS);
        return err;
    };
    
    return [compressionBlock copy];
}




@end

//
//  OfflineAudioFileProcessor+ProcessingBlocks.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (ProcessingBlocks)


#define DEFAULT_LOOKAHEAD_MS   3.0
#define DEFAULT_ATTACK_MS      0.1
#define DEFAULT_RELEASE_MS     300.0
#define DEFAULT_WINDOW_MS      1.0
#define DEFAULT_SLOPE          0.5
#define DEFAULT_THRESHOLD      0.5

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


+ (AudioProcessingBlock)compressionProcessingBlockWithSampleRate:(NSUInteger)sampleRate
{
    AudioProcessingBlock compressionBlock = ^(AudioBufferList *buffer, AVAudioFrameCount bufferSize){
        
        return compress(buffer,
                        (UInt32)bufferSize,
                        DEFAULT_THRESHOLD,
                        DEFAULT_SLOPE,
                        (UInt32)sampleRate,
                        DEFAULT_LOOKAHEAD_MS,
                        DEFAULT_WINDOW_MS,
                        DEFAULT_ATTACK_MS,
                        DEFAULT_RELEASE_MS);
    };
    
    return [compressionBlock copy];
}


@end

//
//  OfflineAudioFileProcessor+Freeverb.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

#ifdef _MSC_VER
#pragma warning( disable : 4091 )
#pragma warning( disable : 4244 )
#pragma warning( disable : 4305 )
#define inline __inline
#endif

#include <math.h>
#include <string.h>

#define LOGTEN 2.302585092994

#define	numcombs		8
#define	numallpasses	4
#define	muted			0
#define	fixedgain		0.015
#define scalewet		3.0
#define scaledry		2.0
#define scaledamp		0.4
#define scaleroom		0.28
#define offsetroom		0.7
#define initialroom		0.5
#define initialdamp		0.5
#define initialwet		1.0/scalewet
#define initialdry		0.0
#define initialwidth	1.0
#define initialmode		0
#define initialbypass   0
#define freezemode		0.5
#define	stereospread	23

#define smallroom_size      0.2
#define smallroom_damp      0.7
#define smallroom_width     0.5
#define smallroom_wet       0.3
#define smallroom_dry       0.7

/* these values assume 44.1KHz sample rate
 they will probably be OK for 48KHz sample rate
 but would need scaling for 96KHz (or other) sample rates.
 the values were obtained by listening tests.                */
static const SInt32 combtuningL[numcombs]
= { 1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617 };
static const SInt32 combtuningR[numcombs]
= { 1116+stereospread, 1188+stereospread, 1277+stereospread, 1356+stereospread,
    1422+stereospread, 1491+stereospread, 1557+stereospread, 1617+stereospread };

static const SInt32 allpasstuningL[numallpasses]
= { 556, 441, 341, 225 };
static const SInt32 allpasstuningR[numallpasses]
= { 556+stereospread, 441+stereospread, 341+stereospread, 225+stereospread };

typedef union ulf
{
    unsigned long   ul;
    float           f;
} ulf;

static inline float fix_denorm_nan_float(float v);

static inline float fix_denorm_nan_float(float v)
{
#ifndef IRIX
    ulf u;
    
    u.f = v;
    if ((((u.ul & 0x7f800000) == 0L) && (u.f != 0.f)) || ((u.ul & 0x7f800000) == 0x7f800000))
    /* if the float is denormal or NaN, return 0.0 */
        v = 0.0f;
    //return 0.0f;
#endif //IRIX
    return v;
}

/* freeverb stuff */
Float32	x_gain;
Float32	x_roomsize,x_roomsize1;
Float32	x_damp,x_damp1;
Float32	x_wet,x_wet1,x_wet2;
Float32	x_dry;
Float32	x_width;
Float32	x_mode;
Float32 x_bypass;
SInt32  x_skip;

Float32	x_allpassfeedback;			/* feedback of allpass filters */
Float32	x_combfeedback;				/* feedback of comb filters */
Float32 x_combdamp1;
Float32 x_combdamp2;
Float32 x_filterstoreL[numcombs];	/* stores last sample value */
Float32 x_filterstoreR[numcombs];

/* buffers for the combs */
Float32	*x_bufcombL[numcombs];
Float32	*x_bufcombR[numcombs];
SInt32 x_combidxL[numcombs];
SInt32 x_combidxR[numcombs];

/* buffers for the allpasses */
Float32	*x_bufallpassL[numallpasses];
Float32	*x_bufallpassR[numallpasses];
SInt32 x_allpassidxL[numallpasses];
SInt32 x_allpassidxR[numallpasses];

/* we'll make local copies adjusted to fit our sample rate */
SInt32 x_combtuningL[numcombs];
SInt32 x_combtuningR[numcombs];

SInt32 x_allpasstuningL[numallpasses];
SInt32 x_allpasstuningR[numallpasses];

Float32 x_float;

@implementation OfflineAudioFileProcessor (Freeverb)

/* -------------------- comb filter stuff ----------------------- */
static void comb_setdamp(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 val)
{
    x_combdamp1 = val;
    x_combdamp2 = 1-val;
}

static void comb_setfeedback(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 val)
{
    x_combfeedback = val;
}

// Big to inline - but crucial for speed
static inline Float32 comb_processL(__unsafe_unretained OfflineAudioFileProcessor *x, SInt32 filteridx, Float32 input)
{
    Float32 output;
    SInt32 bufidx = x_combidxL[filteridx];
    
    output = x_bufcombL[filteridx][bufidx];
    fix_denorm_nan_float(output);
    
    x_filterstoreL[filteridx] = (output*x_combdamp2) + (x_filterstoreL[filteridx]*x_combdamp1);
    fix_denorm_nan_float(x_filterstoreL[filteridx]);
    
    x_bufcombL[filteridx][bufidx] = input + (x_filterstoreL[filteridx]*x_combfeedback);
    
    if(++x_combidxL[filteridx] >= x_combtuningL[filteridx]) x_combidxL[filteridx] = 0;
    
    return output;
}

static inline Float32 comb_processR(__unsafe_unretained OfflineAudioFileProcessor *x, SInt32 filteridx, Float32 input)
{
    Float32 output;
    SInt32 bufidx = x_combidxR[filteridx];
    
    output = x_bufcombR[filteridx][bufidx];
    fix_denorm_nan_float(output);
    
    x_filterstoreR[filteridx] = (output*x_combdamp2) + (x_filterstoreR[filteridx]*x_combdamp1);
    fix_denorm_nan_float(x_filterstoreR[filteridx]);
    
    x_bufcombR[filteridx][bufidx] = input + (x_filterstoreR[filteridx]*x_combfeedback);
    
    if(++x_combidxR[filteridx] >= x_combtuningR[filteridx]) x_combidxR[filteridx] = 0;
    
    return output;
}

/* -------------------- allpass filter stuff ----------------------- */
static void allpass_setfeedback(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 val)
{
    x_allpassfeedback = val;
}

// Big to inline - but crucial for speed
static inline Float32 allpass_processL(__unsafe_unretained OfflineAudioFileProcessor *x, SInt32 filteridx, Float32 input)
{
    Float32 output;
    Float32 bufout;
    SInt32 bufidx = x_allpassidxL[filteridx];
    
    bufout = (Float32)x_bufallpassL[filteridx][bufidx];
    fix_denorm_nan_float(bufout);
    
    output = -input + bufout;
    x_bufallpassL[filteridx][bufidx] = input + (bufout*x_allpassfeedback);
    
    if(++x_allpassidxL[filteridx] >= x_allpasstuningL[filteridx])
        x_allpassidxL[filteridx] = 0;
    
    return output;
}

static inline Float32 allpass_processR(__unsafe_unretained OfflineAudioFileProcessor *x, SInt32 filteridx, Float32 input)
{
    Float32 output;
    Float32 bufout;
    SInt32 bufidx = x_allpassidxR[filteridx];
    
    bufout = (Float32)x_bufallpassR[filteridx][bufidx];
    //FIX_DENORM_NAN_FLOAT(bufout);
    fix_denorm_nan_float(bufout);
    
    output = -input + bufout;
    x_bufallpassR[filteridx][bufidx] = input + (bufout*x_allpassfeedback);
    
    if(++x_allpassidxR[filteridx] >= x_allpasstuningR[filteridx])
        x_allpassidxR[filteridx] = 0;
    
    return output;
}

/* -------------------- general DSP stuff ----------------------- */
OSStatus freeverb_perform(__unsafe_unretained OfflineAudioFileProcessor *x, AudioBufferList *buffer, UInt32 bufferSize)
{
    UInt32 numChannels = buffer->mNumberBuffers;
    UInt32 idx1 = 0;
    UInt32 idx2 = ( numChannels > 1 ) ? ( 1 ) : ( 0 );

    Float32 *in1 = (Float32 *)(buffer->mBuffers[idx1].mData);
    Float32 *in2 = (Float32 *)(buffer->mBuffers[idx2].mData);
    Float32 *out1 = (Float32 *)(buffer->mBuffers[idx1].mData);
    Float32 *out2 = (Float32 *)(buffer->mBuffers[idx2].mData);
    SInt32 n = bufferSize;
    SInt32 i;
    Float32 outL, outR, inL, inR, input;
    
    if(!(x_bypass))
    {
        // DSP loop
        while(n--)
        {
            outL = outR = 0.;
            inL = *in1++;
            inR = *in2++;
            input = (inL + inR) * x_gain;
            
            // Accumulate comb filters in parallel
            for(i=0; i < numcombs; i++)
            {
                outL += comb_processL(x, i, input);
                outR += comb_processR(x, i, input);
            }
            
            // Feed through allpasses in series
            for(i=0; i < numallpasses; i++)
            {
                outL = allpass_processL(x, i, outL);
                outR = allpass_processR(x, i, outR);
            }
            
            // Calculate output REPLACING anything already there
            *out1++ = outL*x_wet1 + outR*x_wet2 + inL*x_dry;
            *out2++ = outR*x_wet1 + outL*x_wet2 + inR*x_dry;
        }
    }
    
    return noErr;
}

// This is a hand unrolled version of the perform routine for
// DSP vector sizes that are multiples of 8
OSStatus freeverb_perf8(__unsafe_unretained OfflineAudioFileProcessor *x, AudioBufferList *buffer, UInt32 bufferSize)
{
    UInt32 numChannels = buffer->mNumberBuffers;
    bool mono_mix = ( numChannels == 1 ) ? ( true ) : ( false );
    bool stereo_mix = ( numChannels == 2 ) ? ( true ) : ( false );
    Float32 *in1,*in2,*out1,*out2;
    
    if (mono_mix) {
    
        in1 = (Float32 *)(buffer->mBuffers[0].mData);
        in2 = (Float32 *)(buffer->mBuffers[0].mData);
        out1 = (Float32 *)(buffer->mBuffers[0].mData);
        out2 = (Float32 *)(buffer->mBuffers[0].mData);
        
    }else if (stereo_mix) {
        
        in1 = (Float32 *)(buffer->mBuffers[0].mData);
        in2 = (Float32 *)(buffer->mBuffers[1].mData);
        out1 = (Float32 *)(buffer->mBuffers[0].mData);
        out2 = (Float32 *)(buffer->mBuffers[1].mData);
        
    }else{
        
        return (OSStatus)(-1);
    }
    
    
    SInt32 n = bufferSize;
    SInt32 i;
    
    Float32 outL[8], outR[8], inL[8], inR[8], input[8];
    
    if(x_bypass)
    {
        // Bypass, so just copy input to output
        for(; n; n -= 8, out1 += 8, out2 += 8, in1 += 8, in2 += 8)
        {
            inL[0] = in1[0];	// We have to copy first before we can write to output
            inR[0] = in2[0];	// since this might be at the same memory position
            out1[0] = inL[0];
            out2[0] = inR[0];
            inL[1] = in1[1];
            inR[1] = in2[1];
            out1[1] = inL[1];
            out2[1] = inR[1];
            inL[2] = in1[2];
            inR[2] = in2[2];
            out1[2] = inL[2];
            out2[2] = inR[2];
            inL[3] = in1[3];
            inR[3] = in2[3];
            out1[3] = inL[3];
            out2[3] = inR[3];
            inL[4] = in1[4];
            inR[4] = in2[4];
            out1[4] = inL[4];
            out2[4] = inR[4];
            inL[5] = in1[5];
            inR[5] = in2[5];
            out1[5] = inL[5];
            out2[5] = inR[5];
            inL[6] = in1[6];
            inR[6] = in2[6];
            out1[6] = inL[6];
            out2[6] = inR[6];
            inL[7] = in1[7];
            inR[7] = in2[7];
            out1[7] = inL[7];
            out2[7] = inR[7];
        }
    }
    else
    {
        // DSP loop
        for(; n; n -= 8, out1 += 8, out2 += 8, in1 += 8, in2 += 8)
        {
            outL[0] = outR [0]= 0.;
            inL[0] = in1[0];
            inR[0] = in2[0];
            input[0] = (inL[0] + inR[0]) * x_gain;
            
            outL[1] = outR [1]= 0.;
            inL[1] = in1[1];
            inR[1] = in2[1];
            input[1] = (inL[1] + inR[1]) * x_gain;
            
            outL[2] = outR [2]= 0.;
            inL[2] = in1[2];
            inR[2] = in2[2];
            input[2] = (inL[2] + inR[2]) * x_gain;
            
            outL[3] = outR [3]= 0.;
            inL[3] = in1[3];
            inR[3] = in2[3];
            input[3] = (inL[3] + inR[3]) * x_gain;
            
            outL[4] = outR [4]= 0.;
            inL[4] = in1[4];
            inR[4] = in2[4];
            input[4] = (inL[4] + inR[4]) * x_gain;
            
            outL[5] = outR [5]= 0.;
            inL[5] = in1[5];
            inR[5] = in2[5];
            input[5] = (inL[5] + inR[5]) * x_gain;
            
            outL[6] = outR [6]= 0.;
            inL[6] = in1[6];
            inR[6] = in2[6];
            input[6] = (inL[6] + inR[6]) * x_gain;
            
            outL[7] = outR [7]= 0.;
            inL[7] = in1[7];
            inR[7] = in2[7];
            input[7] = (inL[7] + inR[7]) * x_gain;
            
            // Accumulate comb filters in parallel
            for(i=0; i < numcombs; i++)
            {
                outL[0] += comb_processL(x, i, input[0]);
                outR[0] += comb_processR(x, i, input[0]);
                outL[1] += comb_processL(x, i, input[1]);
                outR[1] += comb_processR(x, i, input[1]);
                outL[2] += comb_processL(x, i, input[2]);
                outR[2] += comb_processR(x, i, input[2]);
                outL[3] += comb_processL(x, i, input[3]);
                outR[3] += comb_processR(x, i, input[3]);
                outL[4] += comb_processL(x, i, input[4]);
                outR[4] += comb_processR(x, i, input[4]);
                outL[5] += comb_processL(x, i, input[5]);
                outR[5] += comb_processR(x, i, input[5]);
                outL[6] += comb_processL(x, i, input[6]);
                outR[6] += comb_processR(x, i, input[6]);
                outL[7] += comb_processL(x, i, input[7]);
                outR[7] += comb_processR(x, i, input[7]);
            }
            
            // Feed through allpasses in series
            for(i=0; i < numallpasses; i++)
            {
                outL[0] = allpass_processL(x, i, outL[0]);
                outR[0] = allpass_processR(x, i, outR[0]);
                outL[1] = allpass_processL(x, i, outL[1]);
                outR[1] = allpass_processR(x, i, outR[1]);
                outL[2] = allpass_processL(x, i, outL[2]);
                outR[2] = allpass_processR(x, i, outR[2]);
                outL[3] = allpass_processL(x, i, outL[3]);
                outR[3] = allpass_processR(x, i, outR[3]);
                outL[4] = allpass_processL(x, i, outL[4]);
                outR[4] = allpass_processR(x, i, outR[4]);
                outL[5] = allpass_processL(x, i, outL[5]);
                outR[5] = allpass_processR(x, i, outR[5]);
                outL[6] = allpass_processL(x, i, outL[6]);
                outR[6] = allpass_processR(x, i, outR[6]);
                outL[7] = allpass_processL(x, i, outL[7]);
                outR[7] = allpass_processR(x, i, outR[7]);
            }
            
            // Calculate output REPLACING anything already there
            out1[0] = outL[0]*x_wet1 + outR[0]*x_wet2 + inL[0]*x_dry;
            out2[0] = outR[0]*x_wet1 + outL[0]*x_wet2 + inR[0]*x_dry;
            
            out1[1] = outL[1]*x_wet1 + outR[1]*x_wet2 + inL[1]*x_dry;
            out2[1] = outR[1]*x_wet1 + outL[1]*x_wet2 + inR[1]*x_dry;
            out1[2] = outL[2]*x_wet1 + outR[2]*x_wet2 + inL[2]*x_dry;
            out2[2] = outR[2]*x_wet1 + outL[2]*x_wet2 + inR[2]*x_dry;
            out1[3] = outL[3]*x_wet1 + outR[3]*x_wet2 + inL[3]*x_dry;
            out2[3] = outR[3]*x_wet1 + outL[3]*x_wet2 + inR[3]*x_dry;
            out1[4] = outL[4]*x_wet1 + outR[4]*x_wet2 + inL[4]*x_dry;
            out2[4] = outR[4]*x_wet1 + outL[4]*x_wet2 + inR[4]*x_dry;
            out1[5] = outL[5]*x_wet1 + outR[5]*x_wet2 + inL[5]*x_dry;
            out2[5] = outR[5]*x_wet1 + outL[5]*x_wet2 + inR[5]*x_dry;
            out1[6] = outL[6]*x_wet1 + outR[6]*x_wet2 + inL[6]*x_dry;
            out2[6] = outR[6]*x_wet1 + outL[6]*x_wet2 + inR[6]*x_dry;
            out1[7] = outL[7]*x_wet1 + outR[7]*x_wet2 + inL[7]*x_dry;
            out2[7] = outR[7]*x_wet1 + outL[7]*x_wet2 + inR[7]*x_dry;
        }
    }

    return noErr;
}

static OSStatus dsp_do_freeverb(__unsafe_unretained OfflineAudioFileProcessor *x, AudioBufferList *buffer, UInt32 bufferSize)
{
    if(bufferSize & 7)	{// check whether block size is multiple of 8
        return freeverb_perform(x, buffer, bufferSize);
    }else{
        return freeverb_perf8(x, buffer, bufferSize);
    }
}
// ----------- general parameter & calculation stuff -----------

// recalculate SInt32ernal values after parameter change
static void freeverb_update(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    SInt32 i;
    
    x_wet1 = x_wet*(x_width/2 + 0.5);
    x_wet2 = x_wet*((1-x_width)/2);
    
    if (x_mode >= freezemode)
    {
        x_roomsize1 = 1.;
        x_damp1 = 0.;
        x_gain = muted;
    }
    else
    {
        x_roomsize1 = x_roomsize;
        x_damp1 = x_damp;
        x_gain = (float)fixedgain;
    }
    
    comb_setfeedback(x, x_roomsize1);
    comb_setdamp(x, x_damp1);
}

// the following functions set / get the parameters
static void freeverb_setroomsize(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_roomsize = (value*scaleroom) + offsetroom;
    freeverb_update(x);
}

static float freeverb_getroomsize(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    return (x_roomsize-offsetroom)/scaleroom;
}

static void freeverb_setdamp(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_damp = value*scaledamp;
    freeverb_update(x);
}

static float freeverb_getdamp(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    return x_damp/scaledamp;
}

static void freeverb_setwet(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_wet = value*scalewet;
    freeverb_update(x);
}

static float freeverb_getwet(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    return (x_wet/scalewet);
}

static void freeverb_setdry(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_dry = value*scaledry;
}

static float freeverb_getdry(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    return (x_dry/scaledry);
}

static void freeverb_setwidth(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_width = value;
    freeverb_update(x);
}

static float freeverb_getwidth(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    return x_width;
}

static void freeverb_setmode(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_mode = value;
    freeverb_update(x);
}

static float freeverb_getmode(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    if (x_mode >= freezemode)
        return 1;
    else
        return 0;
}

static void freeverb_setbypass(__unsafe_unretained OfflineAudioFileProcessor *x, Float32 value)
{
    x_bypass = value;
    if(x_bypass)freeverb_mute(x);
}

// fill delay lines with silence
static void freeverb_mute(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    SInt32 i;
    
    if (freeverb_getmode(x) >= freezemode)
        return;
    
    for (i=0;i<numcombs;i++)
    {
        memset(x_bufcombL[i], 0x0, x_combtuningL[i]*sizeof(Float32));
        memset(x_bufcombR[i], 0x0, x_combtuningR[i]*sizeof(Float32));
    }
    for (i=0;i<numallpasses;i++)
    {
        memset(x_bufallpassL[i], 0x0, x_allpasstuningL[i]*sizeof(Float32));
        memset(x_bufallpassR[i], 0x0, x_allpasstuningR[i]*sizeof(Float32));
    }
}

// convert gain factor into dB
static float freeverb_getdb(float f)
{
    if (f <= 0)	// equation does not work for 0...
    {
        return (-96);	// ...so we output max. damping
    }
    else
    {
        float val = (20./LOGTEN * log(f));
        return (val);
    }
}

static void freeverb_print(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    printf("freeverb~:");
    if(x_bypass) {
        printf("  bypass: on");
    } else printf("  bypass: off");
    if(!freeverb_getmode(x)) {
        printf("  mode: normal");
    } else printf("  mode: freeze");
    printf("  roomsize: %g", freeverb_getroomsize(x)*scaleroom+offsetroom);
    printf("  damping: %g %%", freeverb_getdamp(x)*100);
    printf("  width: %g %%", x_width * 100);
    printf("  wet level: %g dB", freeverb_getdb(freeverb_getwet(x)*scalewet));
    printf("  dry level: %g dB", freeverb_getdb(freeverb_getdry(x)*scaledry));
}

// clean up
static void freeverb_free(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    SInt32 i;
    // free memory used by delay lines
    for(i = 0; i < numcombs; i++)
    {
        free(x_bufcombL[i]);
        free(x_bufcombR[i]);
    }
    
    for(i = 0; i < numallpasses; i++)
    {
        free(x_bufallpassL[i]);
        free(x_bufallpassR[i]);
    }
}

void freeverb_reset_parms(__unsafe_unretained OfflineAudioFileProcessor *x)
{
    // set default values
    x_allpassfeedback = 0.5;
    x_skip = 1;	// we use every sample
    freeverb_setwet(x, initialwet);
    freeverb_setroomsize(x, initialroom);
    freeverb_setdry(x, initialdry);
    freeverb_setdamp(x, initialdamp);
    freeverb_setwidth(x, initialwidth);
    freeverb_setmode(x, initialmode);
    freeverb_setbypass(x, initialbypass);
}

void freeverb_setup(__unsafe_unretained OfflineAudioFileProcessor *x, UInt32 sampleRate)
{
    SInt32 i;
    SInt32 sr = (SInt32)sampleRate;
    // recalculate the reverb parameters in case we don't run at 44.1kHz
    for(i = 0; i < numcombs; i++)
    {
        x_combtuningL[i] = (SInt32)(combtuningL[i] * sr / sr);
        x_combtuningR[i] = (SInt32)(combtuningR[i] * sr / sr);
    }
    for(i = 0; i < numallpasses; i++)
    {
        x_allpasstuningL[i] = (SInt32)(allpasstuningL[i] * sr / sr);
        x_allpasstuningR[i] = (SInt32)(allpasstuningR[i] * sr / sr);
    }
    
    // get memory for delay lines
    for(i = 0; i < numcombs; i++)
    {
        x_bufcombL[i] = (Float32*) malloc((x_combtuningL[i])*sizeof(Float32));
        x_bufcombR[i] = (Float32*) malloc((x_combtuningR[i])*sizeof(Float32));
        x_combidxL[i] = 0;
        x_combidxR[i] = 0;
    }
    for(i = 0; i < numallpasses; i++)
    {
        x_bufallpassL[i] = (Float32*) malloc((x_allpasstuningL[i])*sizeof(Float32));
        x_bufallpassR[i] = (Float32*) malloc((x_allpasstuningR[i])*sizeof(Float32));
        x_allpassidxL[i] = 0;
        x_allpassidxR[i] = 0;
    }
    
    // set default values
    freeverb_reset_parms(x);
    
    // buffers will be full of rubbish - so we MUST mute them
    freeverb_mute(x);
}

- (AudioProcessingBlock)mediumReverbProcessingBlock
{
    freeverb_setup(self, (UInt32)self.sourceFormat.sampleRate);
    freeverb_setwet(self, 0.35);
    freeverb_setdry(self, 0.65);
    freeverb_setroomsize(self, 0.45);
    freeverb_setwidth(self, 0.8);
    freeverb_setdamp(self, 0.45);
    __weak OfflineAudioFileProcessor *weakself = self;
    AudioProcessingBlock freeverbBlock = ^(AudioBufferList *buffer, AVAudioFrameCount bufferSize){
        return dsp_do_freeverb(weakself, buffer, bufferSize);
    };
    
    return [freeverbBlock copy];
}

- (void)freeverbBlockCleanup
{
    freeverb_reset_parms(self);
    freeverb_free(self);
}



@end
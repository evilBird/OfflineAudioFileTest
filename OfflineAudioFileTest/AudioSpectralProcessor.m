//
//  AudioSpectralProcessor.m
//  SonaShareProject
//
//  Created by Travis Henspeter on 2/4/16.
//  Copyright © 2016 Sonation. All rights reserved.
//

#import "AudioSpectralProcessor.h"
#if !defined(__COREAUDIO_USE_FLAT_INCLUDES__)
#include <CoreAudio/CoreAudioTypes.h>
#include <CoreFoundation/CoreFoundation.h>
#else
#include <CoreAudioTypes.h>
#include <CoreFoundation.h>
#endif

#define OFFSETOF(class, field)((size_t)&((class*)0)->field)

const double two_pi = 2. * M_PI;

UInt32 CountLeadingZeroes(UInt32 arg)
{
    // GNUC / LLVM have a builtin
#if defined(__GNUC__) || defined(__llvm___)
#if (TARGET_CPU_X86 || TARGET_CPU_X86_64)
    if (arg == 0) return 32;
#endif	// TARGET_CPU_X86 || TARGET_CPU_X86_64
    return __builtin_clz(arg);
#elif TARGET_OS_WIN32
    UInt32 tmp;
    __asm{
        bsr eax, arg
        mov ecx, 63
        cmovz eax, ecx
        xor eax, 31
        mov tmp, eax	// this moves the result in tmp to return.
    }
    return tmp;
#else
#error "Unsupported architecture"
#endif	// defined(__GNUC__)
}


UInt32 Log2Ceil(UInt32 x)
{
    return 32 - CountLeadingZeroes(x - 1);
}

UInt32 NextPowerOfTwo(UInt32 x)
{
    return 1 << Log2Ceil(x);
}

void AudioSpectralProcessorHanningWindow(AudioSpectralProcessor *x)
{
    // this is also vector optimized
    
    double w = two_pi / (double)((x->mFFTSize) - 1);
    for (UInt32 i = 0; i < (x->mFFTSize); ++i)
    {
        x->mWindow[i] = (0.5 - 0.5 * cos(w * (double)i));
    }
}

void AudioSpectralProcessorSineWindow(AudioSpectralProcessor *x)
{
    double w = M_PI / (double)((x->mFFTSize) - 1);
    for (UInt32 i = 0; i < (x->mFFTSize); ++i)
    {
        x->mWindow[i] = sin(w * (double)i);
    }
}

void AudioSpectralProcessorReset(AudioSpectralProcessor *x)
{
    x->mInputPos = 0;
    x->mOutputPos = -(x->mFFTSize) & (x->mIOMask);
    x->mInFFTPos = 0;
    x->mOutFFTPos = 0;
    
    for (UInt32 i = 0; i < (x->mNumChannels); ++i)
    {
        memset(x->mChannels[i].mInputBuf, 0, x->mIOBufSize * sizeof(Float32));
        memset(x->mChannels[i].mOutputBuf, 0, x->mIOBufSize * sizeof(Float32));
        memset(x->mChannels[i].mFFTBuf, 0, x->mFFTSize * sizeof(Float32));
    }
}

int AudioSpectralProcessorPrintBuffer(Float32 *buffer, UInt32 inNumFrames, const char *tag)
{
    printf("\n*******************************\n");
    printf("\n%s\n",tag);
    int lineBreak = 10;
    for (UInt32 i = 0 ; i < inNumFrames ; i ++ ) {
        int index = (int)i;
        int midx = index%lineBreak;
        BOOL doLineBreak = (midx == 0);
        if ( doLineBreak ) {
            printf("\nidx %lu\t\t",(long unsigned)i);
        }
        printf("%f\t\t",buffer[i]);
    }
    return 0;
}

int AudioSpectralProcessorPrintSpectralBufferList(AudioSpectralProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    AudioSpectralBufferList *mSpectralBufferList = x->mSpectralBufferList;
    UInt32 half = mFFTSize >> 1;
    for (UInt32 i=0; i<mNumChannels; ++i) {
        DSPSplitComplex freqData = mSpectralBufferList->mDSPSplitComplex[i];
        for (UInt32 j=0; j<half; j++){
            printf(" bin[%d]: %lf + %lfi\n", (int) j, freqData.realp[j], freqData.imagp[j]);
        }
    }
    
    return 0;
}

int AudioSpectralProcessorCreate(AudioSpectralProcessor *x, UInt32 inFFTSize, UInt32 inHopSize, UInt32 inNumChannels, UInt32 inMaxFrames)
{
    x->mFFTSize = inFFTSize;
    x->mMaxFrames = inMaxFrames;
    x->mNumChannels = inNumChannels;
    x->mHopSize = inHopSize;
    x->mLog2FFTSize = Log2Ceil(inFFTSize);
    x->mFFTMask = (inFFTSize - 1);
    x->mFFTByteSize = (inFFTSize * sizeof(Float32));
    x->mIOBufSize = (NextPowerOfTwo(inFFTSize + inMaxFrames));
    x->mIOMask = ((x->mIOBufSize) - 1);
    x->mInputSize = 0;
    x->mInputPos = 0;
    x->mOutputPos = (-inFFTSize & (x->mIOMask));
    x->mInFFTPos = 0;
    x->mOutFFTPos = 0;
    x->mWindow = (Float32 *)malloc(sizeof(Float32) * (x->mFFTSize));
    AudioSpectralProcessorSineWindow(x);
    x->mChannels = malloc(sizeof(AudioSpectralChannel)* inNumChannels);
    x->mSpectralBufferList = (malloc(OFFSETOF(AudioSpectralBufferList, mDSPSplitComplex[inNumChannels])));
    x->mSpectralBufferList->mNumberSpectra = inNumChannels;
    
    for (UInt32 i = 0; i < inNumChannels; i ++ ) {

        x->mChannels[i].mInputBuf = malloc(sizeof(Float32) * (x->mIOBufSize));
        x->mChannels[i].mOutputBuf = malloc(sizeof(Float32) * (x->mIOBufSize));
        x->mChannels[i].mFFTBuf = malloc(sizeof(Float32) * (x->mFFTSize));
        x->mChannels[i].mSplitFFTBuf = malloc(sizeof(Float32) * (x->mFFTSize));
        x->mSpectralBufferList->mDSPSplitComplex[i].realp = x->mChannels[i].mSplitFFTBuf;
        x->mSpectralBufferList->mDSPSplitComplex[i].imagp = x->mChannels[i].mSplitFFTBuf + ((x->mFFTSize) >> 1);
    }
    
    x->mFFTSetup = vDSP_create_fftsetup(x->mLog2FFTSize, FFT_RADIX2);
    
    return 0;
}

void AudioSpectralProcessorCopyInput(AudioSpectralProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput)
{
    
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mInputPos = x->mInputPos;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    AudioSpectralChannel *mChannels = x->mChannels;
    
    UInt32 numBytes = inNumFrames * sizeof(Float32);
    UInt32 firstPart = mIOBufSize - mInputPos;
    
    if (firstPart < inNumFrames) {
        UInt32 firstPartBytes = firstPart * sizeof(Float32);
        UInt32 secondPartBytes = numBytes - firstPartBytes;
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(mChannels[i].mInputBuf + mInputPos, inInput->mBuffers[i].mData, firstPartBytes);
            memcpy(mChannels[i].mInputBuf, (UInt8*)inInput->mBuffers[i].mData + firstPartBytes, secondPartBytes);
        }
    } else {
        UInt32 numBytes = inNumFrames * sizeof(Float32);
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(mChannels[i].mInputBuf + mInputPos, inInput->mBuffers[i].mData, numBytes);
        }
    }
    //printf("CopyInput %g %g\n", mChannels[0].mInputBuf[mInputPos], mChannels[0].mInputBuf[(mInputPos + 200) & mIOMask]);
    //printf("CopyInput mInputPos %u   mIOBufSize %u\n", (unsigned)mInputPos, (unsigned)mIOBufSize);
    x->mInputSize += inNumFrames;
    x->mInputPos = (mInputPos + inNumFrames) & mIOMask;
}

void AudioSpectralProcessorCopyInputToFFT(AudioSpectralProcessor *x)
{
    
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mInFFTPos = x->mInFFTPos;
    UInt32 mFFTByteSize = x->mFFTByteSize;
    UInt32 mHopSize = x->mHopSize;
    
    AudioSpectralChannel *mChannels = x->mChannels;
    
    //printf("CopyInputToFFT mInFFTPos %u\n", (unsigned)mInFFTPos);
    UInt32 firstPart = mIOBufSize - mInFFTPos;
    UInt32 firstPartBytes = firstPart * sizeof(Float32);
    if (firstPartBytes < mFFTByteSize) {
        UInt32 secondPartBytes = mFFTByteSize - firstPartBytes;
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(mChannels[i].mFFTBuf, mChannels[i].mInputBuf + mInFFTPos, firstPartBytes);
            memcpy((UInt8*)mChannels[i].mFFTBuf + firstPartBytes, mChannels[i].mInputBuf, secondPartBytes);
        }
    } else {
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(mChannels[i].mFFTBuf, mChannels[i].mInputBuf + mInFFTPos, mFFTByteSize);
        }
    }
    x->mInputSize -= mHopSize;
    x->mInFFTPos = (mInFFTPos + mHopSize) & mIOMask;
    //printf("CopyInputToFFT %g %g\n", mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
}

void AudioSpectralProcessorDoWindowing(AudioSpectralProcessor *x)
{
    Float32 *win = x->mWindow;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mFFTSize = x->mFFTSize;
    AudioSpectralChannel *mChannels = x->mChannels;
    
    if (!win) return;
    for (UInt32 i=0; i<mNumChannels; ++i) {
        Float32 *buf = mChannels[i].mFFTBuf;
        vDSP_vmul(buf, 1, win, 1, buf, 1, mFFTSize);
    }
}

void AudioSpectralProcessorDoFwdFFT(AudioSpectralProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    FFTSetup mFFTSetup = x->mFFTSetup;
    UInt32 mLog2FFTSize = x->mLog2FFTSize;
    
    AudioSpectralBufferList *mSpectralBufferList = x->mSpectralBufferList;
    AudioSpectralChannel *mChannels = x->mChannels;
    
    //printf("->DoFwdFFT %g %g\n", mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
    UInt32 half = mFFTSize >> 1;
    for (UInt32 i=0; i<mNumChannels; ++i)
    {
        vDSP_ctoz((DSPComplex*)mChannels[i].mFFTBuf, 2, &mSpectralBufferList->mDSPSplitComplex[i], 1, half);
        vDSP_fft_zrip(mFFTSetup, &mSpectralBufferList->mDSPSplitComplex[i], 1, mLog2FFTSize, FFT_FORWARD);
    }
}

void AudioSpectralProcessorDoInvFFT(AudioSpectralProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    FFTSetup mFFTSetup = x->mFFTSetup;
    UInt32 mLog2FFTSize = x->mLog2FFTSize;
    
    AudioSpectralBufferList *mSpectralBufferList = x->mSpectralBufferList;
    AudioSpectralChannel *mChannels = x->mChannels;
    
    //printf("->DoInvFFT %g %g\n", mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
    UInt32 half = mFFTSize >> 1;
    
    for (UInt32 i=0; i<mNumChannels; ++i)
    {
        vDSP_fft_zrip(mFFTSetup, &mSpectralBufferList->mDSPSplitComplex[i], 1, mLog2FFTSize, FFT_INVERSE);
        vDSP_ztoc(&mSpectralBufferList->mDSPSplitComplex[i], 1, (DSPComplex*)mChannels[i].mFFTBuf, 2, half);
        float scale = 0.5 / mFFTSize;
        vDSP_vsmul(mChannels[i].mFFTBuf, 1, &scale, mChannels[i].mFFTBuf, 1, mFFTSize );
    }
    //printf("<-DoInvFFT %g %g\n", direction, mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
}

void AudioSpectralProcessorOverlapAddOutput(AudioSpectralProcessor *x)
{
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mHopSize = x->mHopSize;
    UInt32 mOutFFTPos = x->mOutFFTPos;
    UInt32 mFFTSize = x->mFFTSize;
    
    AudioSpectralChannel *mChannels = x->mChannels;
    
    //printf("OverlapAddOutput mOutFFTPos %u\n", (unsigned)mOutFFTPos);
    UInt32 firstPart = mIOBufSize - mOutFFTPos;
    if (firstPart < mFFTSize) {
        UInt32 secondPart = mFFTSize - firstPart;
        for (UInt32 i=0; i<mNumChannels; ++i) {
            float* out1 = mChannels[i].mOutputBuf + mOutFFTPos;
            vDSP_vadd(out1, 1, mChannels[i].mFFTBuf, 1, out1, 1, firstPart);
            float* out2 = mChannels[i].mOutputBuf;
            vDSP_vadd(out2, 1, mChannels[i].mFFTBuf + firstPart, 1, out2, 1, secondPart);
        }
    } else {
        for (UInt32 i=0; i<mNumChannels; ++i) {
            float* out1 = mChannels[i].mOutputBuf + mOutFFTPos;
            vDSP_vadd(out1, 1, mChannels[i].mFFTBuf, 1, out1, 1, mFFTSize);
        }
    }
    //printf("OverlapAddOutput %g %g\n", mChannels[0].mOutputBuf[mOutFFTPos], mChannels[0].mOutputBuf[(mOutFFTPos + 200) & mIOMask]);
    x->mOutFFTPos = (mOutFFTPos + mHopSize) & mIOMask;
}


void AudioSpectralProcessorCopyOutput(AudioSpectralProcessor *x, UInt32 inNumFrames, AudioBufferList* outOutput)
{
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mOutputPos = x->mOutputPos;
    
    AudioSpectralChannel *mChannels = x->mChannels;
    //printf("->CopyOutput %g %g\n", mChannels[0].mOutputBuf[mOutputPos], mChannels[0].mOutputBuf[(mOutputPos + 200) & mIOMask]);
    //printf("CopyOutput mOutputPos %u\n", (unsigned)mOutputPos);
    UInt32 numBytes = inNumFrames * sizeof(Float32);
    UInt32 firstPart = mIOBufSize - mOutputPos;
    if (firstPart < inNumFrames) {
        UInt32 firstPartBytes = firstPart * sizeof(Float32);
        UInt32 secondPartBytes = numBytes - firstPartBytes;
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(outOutput->mBuffers[i].mData, mChannels[i].mOutputBuf + mOutputPos, firstPartBytes);
            memcpy((UInt8*)outOutput->mBuffers[i].mData + firstPartBytes, mChannels[i].mOutputBuf, secondPartBytes);
            memset(mChannels[i].mOutputBuf + mOutputPos, 0, firstPartBytes);
            memset(mChannels[i].mOutputBuf, 0, secondPartBytes);
        }
    } else {
        for (UInt32 i=0; i<mNumChannels; ++i) {
            memcpy(outOutput->mBuffers[i].mData, mChannels[i].mOutputBuf + mOutputPos, numBytes);
            memset(mChannels[i].mOutputBuf + mOutputPos, 0, numBytes);
        }
    }
    //printf("<-CopyOutput %g %g\n", ((Float32*)outOutput->mBuffers[0].mData)[0], ((Float32*)outOutput->mBuffers[0].mData)[200]);
    x->mOutputPos = (mOutputPos + inNumFrames) & mIOMask;
}

int AudioSpectralProcessorProcessSpectrum(AudioSpectralProcessor *x, UInt32 inFFTSize, AudioSpectralBufferList* inSpectra)
{
    return 0;
}

int ProcessBackwards(AudioSpectralProcessor *x, UInt32 inNumFrames, AudioBufferList* outOutput)
{
    AudioSpectralProcessorProcessSpectrum(x , x->mFFTSize, x->mSpectralBufferList);
    AudioSpectralProcessorDoInvFFT(x);
    AudioSpectralProcessorDoWindowing(x);
    AudioSpectralProcessorOverlapAddOutput(x);
    // copy from output buffer to buffer list
    AudioSpectralProcessorCopyOutput(x, inNumFrames, outOutput);
    return 0;
}

int AudioSpectralProcessorProcessForwards(AudioSpectralProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput)
{
    // copy from buffer list to input buffer
    AudioSpectralProcessorCopyInput(x, inNumFrames, inInput);
    
    int processed = 1;
    // if enough input to process, then process.
    while ((x->mInputSize) >= (x->mFFTSize))
    {
        AudioSpectralProcessorCopyInputToFFT(x); // copy from input buffer to fft buffer
        AudioSpectralProcessorDoWindowing(x);
        AudioSpectralProcessorDoFwdFFT(x);
        AudioSpectralProcessorProcessSpectrum(x,x->mFFTSize, x->mSpectralBufferList); // here you would copy the fft results out to a buffer indicated in mUserData, say for sonogram drawing
        processed = 0;
    }
    
    return processed;
}

int AudioSpectralProcessorPerform(AudioSpectralProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput, AudioBufferList* outOutput)
{
    // copy from buffer list to input buffer
    AudioSpectralProcessorCopyInput(x, inNumFrames, inInput);
    // if enough input to process, then process.
    while (x->mInputSize >= (x->mFFTSize))
    {
        AudioSpectralProcessorCopyInputToFFT(x); // copy from input buffer to fft buffer
        AudioSpectralProcessorDoWindowing(x);
        AudioSpectralProcessorDoFwdFFT(x);
        AudioSpectralProcessorProcessSpectrum(x, x->mFFTSize, x->mSpectralBufferList);
        AudioSpectralProcessorDoInvFFT(x);
        AudioSpectralProcessorDoWindowing(x);
        AudioSpectralProcessorOverlapAddOutput(x);
    }
    
    // copy from output buffer to buffer list
    AudioSpectralProcessorCopyOutput(x, inNumFrames, outOutput);
    
    return 0;
}

int AudioSpectralProcessorDestroy(AudioSpectralProcessor *x)
{
    UInt32 mNumChannels = x->mNumChannels;
    AudioSpectralChannel *mChannels = x->mChannels;
    
    for (UInt32 i = 0; i < mNumChannels; i++) {
        free(mChannels[i].mInputBuf);
        free(mChannels[i].mOutputBuf);
        free(mChannels[i].mFFTBuf);
        free(mChannels[i].mSplitFFTBuf);
    }
    
    free(mChannels);
    
    AudioSpectralBufferList *mSpectralBufferList = x->mSpectralBufferList;
    free(mSpectralBufferList);
    free(x->mWindow);
    vDSP_destroy_fftsetup(x->mFFTSetup);
    return 0;
}


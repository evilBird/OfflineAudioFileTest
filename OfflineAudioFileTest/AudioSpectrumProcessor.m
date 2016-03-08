//
//  AudioSpectrumProcessor.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "AudioSpectrumProcessor.h"
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

typedef struct
{
    Float32 *mInputBuf;		// log2ceil(FFT size + max frames)
    Float32 *mOutputBuf;		// log2ceil(FFT size + max frames)
    Float32 *mFFTBuf;		// FFT size
    Float32 *mSplitFFTBuf;	// FFT size
}AudioSpectrumChannel;

@interface AudioSpectrumProcessor () {
    
    UInt32 mLog2FFTSize;
    UInt32 mFFTMask;
    UInt32 mFFTByteSize;
    UInt32 mIOBufSize;
    UInt32 mIOMask;
    UInt32 mInputSize;
    UInt32 mInputPos;
    UInt32 mOutputPos;
    UInt32 mInFFTPos;
    UInt32 mOutFFTPos;
    UInt32 mFFTSize;
    UInt32 mHopSize;
    UInt32 mNumChannels;
    UInt32 mMaxFrames;
    FFTSetup mFFTSetup;
    Float32 *mWindow;
    
    AudioSpectrumProcessingBlock    mProcessingBlock;
    AudioSpectrumChannel            *mChannels;
    AudioSpectrumBufferList         *mSpectrumBufferList;
    
}

@end

@implementation AudioSpectrumProcessor

int AudioSpectrumProcessorPrintBuffer(Float32 *buffer, UInt32 inNumFrames, const char *tag)
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

int AudioSpectrumProcessorPrintSpectralBufferList(__unsafe_unretained AudioSpectrumProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    AudioSpectrumBufferList *mSpectrumBufferList = x->mSpectrumBufferList;
    UInt32 half = mFFTSize >> 1;
    for (UInt32 i=0; i<mNumChannels; ++i) {
        DSPSplitComplex freqData = mSpectrumBufferList->mDSPSplitComplex[i];
        for (UInt32 j=0; j<half; j++){
            printf(" bin[%d]: %lf + %lfi\n", (int) j, freqData.realp[j], freqData.imagp[j]);
        }
    }
    
    return 0;
}

void AudioSpectrumProcessorHanningWindow(__unsafe_unretained AudioSpectrumProcessor *x)
{
    // this is also vector optimized
    
    double w = two_pi / (double)((x->mFFTSize) - 1);
    for (UInt32 i = 0; i < (x->mFFTSize); ++i)
    {
        x->mWindow[i] = (0.5 - 0.5 * cos(w * (double)i));
    }
}

void AudioSpectrumProcessorSineWindow(__unsafe_unretained AudioSpectrumProcessor *x)
{
    double w = M_PI / (double)((x->mFFTSize) - 1);
    for (UInt32 i = 0; i < (x->mFFTSize); ++i)
    {
        x->mWindow[i] = sin(w * (double)i);
    }
}

void AudioSpectrumProcessorReset(__unsafe_unretained AudioSpectrumProcessor *x)
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

void AudioSpectrumProcessorCopyInput(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput)
{
    
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mInputPos = x->mInputPos;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    AudioSpectrumChannel *mChannels = x->mChannels;
    
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

void AudioSpectrumProcessorCopyInputToFFT(__unsafe_unretained AudioSpectrumProcessor *x)
{
    
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mInFFTPos = x->mInFFTPos;
    UInt32 mFFTByteSize = x->mFFTByteSize;
    UInt32 mHopSize = x->mHopSize;
    
    AudioSpectrumChannel *mChannels = x->mChannels;
    
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

void AudioSpectrumProcessorDoWindowing(__unsafe_unretained AudioSpectrumProcessor *x)
{
    Float32 *win = x->mWindow;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mFFTSize = x->mFFTSize;
    AudioSpectrumChannel *mChannels = x->mChannels;
    
    if (!win) return;
    for (UInt32 i=0; i<mNumChannels; ++i) {
        Float32 *buf = mChannels[i].mFFTBuf;
        vDSP_vmul(buf, 1, win, 1, buf, 1, mFFTSize);
    }
}

void AudioSpectrumProcessorDoFwdFFT(__unsafe_unretained AudioSpectrumProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    FFTSetup mFFTSetup = x->mFFTSetup;
    UInt32 mLog2FFTSize = x->mLog2FFTSize;
    
    AudioSpectrumBufferList *mSpectrumBufferList = x->mSpectrumBufferList;
    AudioSpectrumChannel *mChannels = x->mChannels;
    
    //printf("->DoFwdFFT %g %g\n", mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
    UInt32 half = mFFTSize >> 1;
    for (UInt32 i=0; i<mNumChannels; ++i)
    {
        vDSP_ctoz((DSPComplex*)mChannels[i].mFFTBuf, 2, &mSpectrumBufferList->mDSPSplitComplex[i], 1, half);
        vDSP_fft_zrip(mFFTSetup, &mSpectrumBufferList->mDSPSplitComplex[i], 1, mLog2FFTSize, FFT_FORWARD);
    }
}

void AudioSpectrumProcessorDoInvFFT(__unsafe_unretained AudioSpectrumProcessor *x)
{
    UInt32 mFFTSize = x->mFFTSize;
    UInt32 mNumChannels = x->mNumChannels;
    FFTSetup mFFTSetup = x->mFFTSetup;
    UInt32 mLog2FFTSize = x->mLog2FFTSize;
    
    AudioSpectrumBufferList *mSpectrumBufferList = x->mSpectrumBufferList;
    AudioSpectrumChannel *mChannels = x->mChannels;
    
    //printf("->DoInvFFT %g %g\n", mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
    UInt32 half = mFFTSize >> 1;
    
    for (UInt32 i=0; i<mNumChannels; ++i)
    {
        vDSP_fft_zrip(mFFTSetup, &mSpectrumBufferList->mDSPSplitComplex[i], 1, mLog2FFTSize, FFT_INVERSE);
        vDSP_ztoc(&mSpectrumBufferList->mDSPSplitComplex[i], 1, (DSPComplex*)mChannels[i].mFFTBuf, 2, half);
        float scale = 0.5 / mFFTSize;
        vDSP_vsmul(mChannels[i].mFFTBuf, 1, &scale, mChannels[i].mFFTBuf, 1, mFFTSize );
    }
    //printf("<-DoInvFFT %g %g\n", direction, mChannels[0].mFFTBuf()[0], mChannels[0].mFFTBuf()[200]);
}

void AudioSpectrumProcessorOverlapAddOutput(__unsafe_unretained AudioSpectrumProcessor *x)
{
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mHopSize = x->mHopSize;
    UInt32 mOutFFTPos = x->mOutFFTPos;
    UInt32 mFFTSize = x->mFFTSize;
    
    AudioSpectrumChannel *mChannels = x->mChannels;
    
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


void AudioSpectrumProcessorCopyOutput(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inNumFrames, AudioBufferList* outOutput)
{
    UInt32 mIOBufSize = x->mIOBufSize;
    UInt32 mNumChannels = x->mNumChannels;
    UInt32 mIOMask = x->mIOMask;
    UInt32 mOutputPos = x->mOutputPos;
    
    AudioSpectrumChannel *mChannels = x->mChannels;
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

int AudioSpectrumProcessorProcessSpectrum(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inFFTSize, AudioSpectrumBufferList* inSpectra)
{
    if (x->mProcessingBlock) {
        x->mProcessingBlock(inSpectra, inFFTSize);
    }
    return 0;
}

int ProcessBackwards(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inNumFrames, AudioBufferList* outOutput)
{
    AudioSpectrumProcessorProcessSpectrum(x , x->mFFTSize, x->mSpectrumBufferList);
    AudioSpectrumProcessorDoInvFFT(x);
    AudioSpectrumProcessorDoWindowing(x);
    AudioSpectrumProcessorOverlapAddOutput(x);
    // copy from output buffer to buffer list
    AudioSpectrumProcessorCopyOutput(x, inNumFrames, outOutput);
    return 0;
}

int AudioSpectrumProcessorProcessForwards(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput)
{
    // copy from buffer list to input buffer
    AudioSpectrumProcessorCopyInput(x, inNumFrames, inInput);
    
    int processed = 1;
    // if enough input to process, then process.
    while ((x->mInputSize) >= (x->mFFTSize))
    {
        AudioSpectrumProcessorCopyInputToFFT(x); // copy from input buffer to fft buffer
        AudioSpectrumProcessorDoWindowing(x);
        AudioSpectrumProcessorDoFwdFFT(x);
        AudioSpectrumProcessorProcessSpectrum(x,x->mFFTSize, x->mSpectrumBufferList); // here you would copy the fft results out to a buffer indicated in mUserData, say for sonogram drawing
        processed = 0;
    }
    
    return processed;
}

int AudioSpectrumProcessorPerform(__unsafe_unretained AudioSpectrumProcessor *x, UInt32 inNumFrames, AudioBufferList* inInput, AudioBufferList* outOutput)
{
    // copy from buffer list to input buffer
    AudioSpectrumProcessorCopyInput(x, inNumFrames, inInput);
    // if enough input to process, then process.
    while (x->mInputSize >= (x->mFFTSize))
    {
        AudioSpectrumProcessorCopyInputToFFT(x); // copy from input buffer to fft buffer
        AudioSpectrumProcessorDoWindowing(x);
        AudioSpectrumProcessorDoFwdFFT(x);
        AudioSpectrumProcessorProcessSpectrum(x, x->mFFTSize, x->mSpectrumBufferList);
        AudioSpectrumProcessorDoInvFFT(x);
        AudioSpectrumProcessorDoWindowing(x);
        AudioSpectrumProcessorOverlapAddOutput(x);
    }
    
    // copy from output buffer to buffer list
    AudioSpectrumProcessorCopyOutput(x, inNumFrames, outOutput);
    
    return 0;
}

- (void)setupBuffers
{
    //Create sine window
    mWindow = (Float32 *)malloc(sizeof(Float32) * (mFFTSize));
    double w = M_PI / (double)((mFFTSize) - 1);
    for (UInt32 i = 0; i < (mFFTSize); ++i)
    {
        mWindow[i] = sin(w * (double)i);
    }
    
    mChannels = malloc(sizeof(AudioSpectrumChannel)* mNumChannels);
    mSpectrumBufferList = (malloc(OFFSETOF(AudioSpectrumBufferList, mDSPSplitComplex[mNumChannels])));
    mSpectrumBufferList->mNumberSpectra = mNumChannels;
    
    for (UInt32 i = 0; i < mNumChannels; i ++ ) {
        
        mChannels[i].mInputBuf = malloc(sizeof(Float32) * (mIOBufSize));
        mChannels[i].mOutputBuf = malloc(sizeof(Float32) * (mIOBufSize));
        mChannels[i].mFFTBuf = malloc(sizeof(Float32) * (mFFTSize));
        mChannels[i].mSplitFFTBuf = malloc(sizeof(Float32) * (mFFTSize));
        mSpectrumBufferList->mDSPSplitComplex[i].realp = mChannels[i].mSplitFFTBuf;
        mSpectrumBufferList->mDSPSplitComplex[i].imagp = mChannels[i].mSplitFFTBuf + ((mFFTSize) >> 1);
    }
    
    mFFTSetup = vDSP_create_fftsetup(mLog2FFTSize, FFT_RADIX2);
}

- (instancetype)initWithFFTSize:(UInt32)inFFTSize hopSize:(UInt32)inHopSize numChannels:(UInt32)inNumChannels maxFrames:(UInt32)inMaxFrames
{
    self = [super init];
    if (self) {
        mFFTSize = inFFTSize;
        mMaxFrames = inMaxFrames;
        mNumChannels = inNumChannels;
        mHopSize = inHopSize;
        mLog2FFTSize = Log2Ceil(inFFTSize);
        mFFTMask = (inFFTSize - 1);
        mFFTByteSize = (inFFTSize * sizeof(Float32));
        mIOBufSize = (NextPowerOfTwo(inFFTSize + inMaxFrames));
        mIOMask = (mIOBufSize - 1);
        mInputSize = 0;
        mInputPos = 0;
        mOutputPos = (-inFFTSize & (mIOMask));
        mInFFTPos = 0;
        mOutFFTPos = 0;
        [self setupBuffers];
    }
    
    return self;
}

+ (instancetype)spectrumProcessorWithBlock:(OSStatus (^)(AudioSpectrumBufferList *inSpectra, UInt32 inFFTSize))processingBlock
                               numChannels:(NSUInteger)numChannels
                             maxBufferSize:(NSUInteger)maxBufferSize
{
    UInt32 channelCt = (UInt32)numChannels;
    UInt32 maxLength = (UInt32)maxBufferSize;
    UInt32 fftLength = maxLength >> 1;
    UInt32 hopSize = fftLength >> 1;
    AudioSpectrumProcessor *audioSpectrumProcessor = [[AudioSpectrumProcessor alloc]initWithFFTSize:fftLength hopSize:hopSize numChannels:channelCt maxFrames:maxLength];
    [audioSpectrumProcessor setProcessingBlock:processingBlock];
    return audioSpectrumProcessor;
}

+ (void)printFloatBuffer:(Float32 *)floatBuffer withTag:(NSString *)tag length:(NSUInteger)bufferLength
{
    AudioSpectrumProcessorPrintBuffer(floatBuffer, (UInt32)bufferLength, [tag UTF8String]);
}

- (void)printSpectrumBufferList
{
    AudioSpectrumProcessorPrintSpectralBufferList(self);
}

- (void)setProcessingBlock:(OSStatus (^)(AudioSpectrumBufferList *inSpectra, UInt32 inFFTSize))processingBlock
{
    mProcessingBlock = [processingBlock copy];
}

- (OSStatus)processAudioBuffer:(AudioBufferList *)audioBufferList bufferSize:(NSUInteger)bufferSize
{
    OSStatus status = AudioSpectrumProcessorPerform(self, (UInt32)bufferSize, audioBufferList, audioBufferList);
    return status;
}

- (void)reset
{
    AudioSpectrumProcessorReset(self);
}

- (void)dealloc
{
    for (UInt32 i = 0; i < mNumChannels; i++) {
        free(mChannels[i].mInputBuf);
        free(mChannels[i].mOutputBuf);
        free(mChannels[i].mFFTBuf);
        free(mChannels[i].mSplitFFTBuf);
    }
    
    free(mChannels);
    free(mSpectrumBufferList);
    free(mWindow);
    vDSP_destroy_fftsetup(mFFTSetup);
    mProcessingBlock = nil;
}

@end

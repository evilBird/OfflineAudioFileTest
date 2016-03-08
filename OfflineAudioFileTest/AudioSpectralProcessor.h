//
//  AudioSpectralProcessor.h
//  SonaShareProject
//
//  Created by Travis Henspeter on 2/4/16.
//  Copyright © 2016 Sonation. All rights reserved.
//

#ifndef AudioSpectralProcessor_h
#define AudioSpectralProcessor_h

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

typedef struct
{
    UInt32 mNumberSpectra;
    DSPSplitComplex mDSPSplitComplex[1];
}AudioSpectralBufferList;

typedef struct
{
    Float32 *mInputBuf;		// log2ceil(FFT size + max frames)
    Float32 *mOutputBuf;		// log2ceil(FFT size + max frames)
    Float32 *mFFTBuf;		// FFT size
    Float32 *mSplitFFTBuf;	// FFT size
}AudioSpectralChannel;

typedef int (^AudioSpectralProcessingBlock)(AudioSpectralBufferList *inSpectra, UInt32 inFFTSize);

typedef struct {
    
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
    AudioSpectralProcessingBlock    mProcessingBlock;
    AudioSpectralChannel            *mChannels;
    AudioSpectralBufferList         *mSpectralBufferList;
    
} AudioSpectralProcessor;

int AudioSpectralProcessorCreate(AudioSpectralProcessor *x,
                            UInt32 inFFTSize,
                            UInt32 inHopSize,
                            UInt32 inNumChannels,
                            UInt32 inMaxFrames);

void AudioSpectralProcessorReset(AudioSpectralProcessor *x);

int AudioSpectralProcessorDestroy(AudioSpectralProcessor *x);

int AudioSpectralProcessorPrintSpectralBufferList(AudioSpectralProcessor *x);

int AudioSpectralProcessorPrintBuffer(Float32 *buffer,
                                      UInt32 bufferFrames,
                                      const char *tag);

#endif /* AudioSpectralProcessor_h */

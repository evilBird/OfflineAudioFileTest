//
//  AudioSpectrumProcessor.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

typedef struct
{
    UInt32 mNumberSpectra;
    DSPSplitComplex mDSPSplitComplex[1];
    
} AudioSpectrumBufferList;

typedef OSStatus (^AudioSpectrumProcessingBlock)(AudioSpectrumBufferList *inSpectra, UInt32 inFFTSize);

@interface AudioSpectrumProcessor : NSObject

+ (instancetype)spectrumProcessorWithBlock:(OSStatus (^)(AudioSpectrumBufferList *inSpectra, UInt32 inFFTSize))processingBlock
                              numChannels:(NSUInteger)numChannels
                             maxBufferSize:(NSUInteger)maxBufferSize;

- (OSStatus)processAudioBuffer:(AudioBufferList *)audioBufferList bufferSize:(NSUInteger)bufferSize;

- (instancetype)initWithFFTSize:(UInt32)inFFTSize
                        hopSize:(UInt32)inHopSize
                    numChannels:(UInt32)inNumChannels
                      maxFrames:(UInt32)inMaxFrames;

- (void)setProcessingBlock:(OSStatus (^)(AudioSpectrumBufferList *inSpectra, UInt32 inFFTSize))processingBlock;

+ (void)printFloatBuffer:(Float32 *)floatBuffer withTag:(NSString *)tag length:(NSUInteger)bufferLength;

- (void)printSpectrumBufferList;

- (void)reset;

@end

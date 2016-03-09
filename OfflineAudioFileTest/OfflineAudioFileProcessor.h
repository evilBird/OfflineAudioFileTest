//
//  OfflineAudioFile.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

typedef OSStatus (^AudioProcessingBlock)(AudioBufferList *buffer, AVAudioFrameCount bufferSize);
typedef OSStatus (^AudioAnalysisBlock)(AudioBufferList *buffer, AVAudioFrameCount bufferSize);

@interface OfflineAudioFileProcessor : NSObject

+ (void)processFile:(NSString *)sourceFilePath
          withBlock:(AudioProcessingBlock)processingBlock
      maxBufferSize:(AVAudioFrameCount)maxBufferSize
         resultPath:(NSString *)resultPath
         completion:(void(^)(NSString *resultPath, NSError *error))completion;

+ (void)analyzeFile:(NSString *)sourceFilePath
          withBlock:(AudioAnalysisBlock)analysisBlock
      maxBufferSize:(AVAudioFrameCount)maxBufferSize
         completion:(void(^)(NSError *error))completion;

@end


@interface OfflineAudioFileProcessor (Compressor)

+ (AudioProcessingBlock)compressionProcessingBlockWithSampleRate:(NSUInteger)sampleRate;

@end

@interface OfflineAudioFileProcessor (Normalizer)

+ (Float32)getPeakMagnitudeForBuffer:(AudioBufferList *)bufferList bufferSize:(NSUInteger)bufferSize;
+ (AudioProcessingBlock)normalizeProcessingBlockWithPeakMagnitude:(Float32)peakMagnitude;

@end

@interface OfflineAudioFileProcessor (Freeverb)

+ (AudioProcessingBlock)freeverbProcessingBlockWithSampleRate:(NSUInteger)sampleRate;

+ (AudioProcessingBlock)freeverbProcessingBlockWithSampleRate:(NSUInteger)sampleRate
                                                       wetMix:(Float32)wetMix
                                                       dryMix:(Float32)dryMix
                                                     roomSize:(Float32)roomsize
                                                        width:(Float32)width
                                                      damping:(Float32)damping;

+ (void)freeverbPrintParms;
+ (void)freebverbCleanup;

@end

@interface OfflineAudioFileProcessor (Test)

+ (void)test;
+ (NSString *)testFileName;
+ (NSString *)testSourceFilePath;
+ (NSString *)testTempFilePath;
+ (NSString *)testResultPath;
+ (NSString *)tempFilePathForFile:(NSString *)fileName;
+ (void)deleteTempFilesForFile:(NSString *)fileName;

@end
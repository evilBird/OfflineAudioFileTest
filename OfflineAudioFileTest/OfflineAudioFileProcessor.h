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

+ (AudioProcessingBlock)compressionProcessingBlockWithSampleRate:(NSUInteger)sampleRate
                                                       threshold:(Float32)threshold
                                                           slope:(Float32)slope
                                                   lookaheadTime:(Float32)lookahead_ms
                                                      windowTime:(Float32)window_ms
                                                      attackTime:(Float32)attack_ms
                                                     releaseTime:(Float32)release_ms;

@end

@interface OfflineAudioFileProcessor (Normalizer)

+ (AudioProcessingBlock)normalizeProcessingBlockForAudioFile:(NSString *)audioFilePath maximumMagnitude:(Float32)maximumMagnitude;

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

@interface OfflineAudioFileProcessor (ConvenienceMethods)

+ (void)doDefaultProcessingWithSourceFile:(NSString *)sourceFilePath
                               onProgress:(void(^)(double progress))progressBlock
                                onSuccess:(void(^)(NSURL *resultFile))successBlock
                                onFailure:(void(^)(NSError *error))failureBlock;

@end

@interface OfflineAudioFileProcessor (Test)

+ (void)testFile:(NSString *)testFileName;
+ (NSString *)testSoloFileName;
+ (NSString *)testAccompFileName;
+ (NSString *)testSourceFilePathForFile:(NSString *)testFileName;
+ (NSString *)tempFilePathForFile:(NSString *)fileName;
+ (NSString *)testResultPathForFile:(NSString *)fileName;
+ (void)deleteTempFilesForFile:(NSString *)fileName;

@end
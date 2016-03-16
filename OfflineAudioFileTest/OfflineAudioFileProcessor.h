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
typedef void (^AudioProcessingProgressBlock)(double progress);
typedef void (^AudioProcessingCompletionBlock)(NSURL *resultFile, NSError *error);

@interface OfflineAudioFileProcessor : NSObject

@property (nonatomic,strong,readonly)               NSString                *sourceFilePath;
@property (nonatomic,strong,readonly)               NSString                *resultFilePath;

@property (nonatomic,readonly)                      NSUInteger              maxBufferSize;
@property (nonatomic,readonly)                      NSUInteger              sourceSampleRate;
@property (nonatomic,readonly)                      AVAudioFrameCount       sourceLength;
@property (nonatomic,readonly)                      AVAudioFramePosition    sourcePosition;
@property (nonatomic,readonly)                      AVAudioFormat           *sourceFormat;

@property (nonatomic,readonly)                      double                  progress;
@property (nonatomic,readonly,getter=isRunning)     bool                    running;
@property (nonatomic,readonly,getter=isPaused)      bool                    paused;
@property (nonatomic,readonly,getter=isDone)        bool                    done;
@property (nonatomic,readonly,getter=isCancelled)   bool                    cancelled;

@property (nonatomic,strong,readonly)               NSError                 *error;
@property (nonatomic)                               bool                    freeverbNeedsCleanup;

+ (instancetype)processorWithSource:(NSString *)sourceFilePath
                          maxBuffer:(NSUInteger)maxBufferSize
                    processingBlock:(AudioProcessingBlock)processingBlock
                      progressBlock:(AudioProcessingProgressBlock)progressBlock
                    completionBlock:(AudioProcessingCompletionBlock)completionBlock;

- (instancetype)initWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize;

- (void)setProgressBlock:(void(^)(double progress))progressBlock;
- (void)setProcessingBlock:(OSStatus (^)(AudioBufferList *buffer, AVAudioFrameCount bufferSize))processingBlock;
- (void)setCompletionBlock:(void(^)(NSURL *resultFile, NSError *error))completionBlock;

- (void)start;
- (void)pause;
- (void)resume;
- (void)cancel;

@end


@interface OfflineAudioFileProcessor (Compressor)

+ (AudioProcessingBlock)vcompressionProcessingBlockWithSampleRate:(NSUInteger)sampleRate;

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

+ (AudioProcessingBlock)freeverbSmallRoomProcessingBlockWithSampleRate:(NSUInteger)sampleRate;

+ (AudioProcessingBlock)freeverbProcessingBlockWithSampleRate:(NSUInteger)sampleRate
                                                       wetMix:(Float32)wetMix
                                                       dryMix:(Float32)dryMix
                                                     roomSize:(Float32)roomsize
                                                        width:(Float32)width
                                                      damping:(Float32)damping;

+ (void)freeverbPrintParms;
+ (void)freebverbCleanup;
- (AudioProcessingBlock)mediumReverbProcessingBlock;
- (void)freeverbBlockCleanup;

@end

@interface OfflineAudioFileProcessor (ConvenienceMethods)

Float32 GetMaxSampleValueInBuffer(AudioBufferList *bufferList, UInt32 bufferSize);
OSStatus NormalizeBufferList(AudioBufferList *bufferList, UInt32 bufferSize, Float32 constant);

+ (UInt32)sampleRateForFile:(NSString *)filePath;

+ (AVAudioFrameCount)frameLengthForFile:(NSString *)filePath;

+ (void)processFile:(NSString *)sourceFilePath
          withBlock:(AudioProcessingBlock)processingBlock
      maxBufferSize:(AVAudioFrameCount)maxBufferSize
         resultPath:(NSString *)resultPath
         completion:(void(^)(NSString *resultPath, NSError *error))completion;

+ (void)analyzeFile:(NSString *)sourceFilePath
          withBlock:(AudioAnalysisBlock)analysisBlock
      maxBufferSize:(AVAudioFrameCount)maxBufferSize
         completion:(void(^)(NSError *error))completion;


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
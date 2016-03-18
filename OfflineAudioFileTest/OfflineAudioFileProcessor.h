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

@property (nonatomic,strong)                            NSString                *sourceFilePath;
@property (nonatomic,strong)                            NSString                *resultFilePath;

@property (nonatomic,readonly)                          NSUInteger              maxBufferSize;

@property (nonatomic,readonly)                          Float32                 maxMeasuredOutputMagnitude;
@property (nonatomic,readonly)                          Float32                 maxAllowedPerChannelMagnitude;
@property (nonatomic)                                   Float32                 normalizeConstant;

@property (nonatomic,readonly)                          AVAudioFrameCount       sourceLength;
@property (nonatomic,readonly)                          AVAudioFramePosition    sourcePosition;

@property (nonatomic,strong,readonly)                   AVAudioFormat           *sourceFormat;
@property (nonatomic,strong)                            AVAudioFormat           *targetFormat;

@property (nonatomic,getter=doesNormalize)              bool                    doNormalize;
@property (nonatomic,getter=doesReverb)                 bool                    doReverb;
@property (nonatomic,getter=doesCompression)            bool                    doCompression;

@property (nonatomic,readonly)                          double                  progress;
@property (nonatomic,readonly,getter=isReady)           bool                    ready;
@property (nonatomic,readonly,getter=isRunning)         bool                    running;
@property (nonatomic,readonly,getter=isPaused)          bool                    paused;
@property (nonatomic,readonly,getter=isDone)            bool                    done;
@property (nonatomic,readonly,getter=isCancelled)       bool                    cancelled;

@property (nonatomic,strong,readonly)                   NSError                 *error;

+ (instancetype)normalizeFile:(NSString *)sourceFilePath
          withAudioBufferSize:(NSUInteger)maxBufferSize
            normalizeConstant:(Float32)normConstant
                progressBlock:(void(^)(double progress))progressHandler
              completionBlock:(void(^)(NSURL *fileURL, NSError *error))completionHandler;

+ (instancetype)processFile:(NSString *)sourceFilePath
        withAudioBufferSize:(NSUInteger)maxBufferSize
                   compress:(BOOL)compress
                     reverb:(BOOL)reverb
            progressHandler:(void(^)(double progress))progressHandler
          completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler;

- (void)configureToProcessFile:(NSString *)sourceFilePath
           withAudioBufferSize:(NSUInteger)maxBufferSize
                      compress:(BOOL)compress
                        reverb:(BOOL)reverb
                   postProcess:(BOOL)postProcess
               progressHandler:(void(^)(double progress))progressHandler
             completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler;

- (instancetype)initWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize;
- (void)initializeProcessorWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize;

- (void)setProgressBlock:(void(^)(double progress))progressBlock;
- (void)setProcessingBlock:(OSStatus (^)(AudioBufferList *buffer, AVAudioFrameCount bufferSize))processingBlock;
- (void)setCompletionBlock:(void(^)(NSURL *resultFile, NSError *error))completionBlock;

- (void)start;
- (void)pause;
- (void)resume;
- (void)cancel;

@end


@interface OfflineAudioFileProcessor (Compressor)

void print_samples(Float32 *samples, UInt32 numSamples, const char *tag);

Float32 GetPeakRMS(AudioBufferList *buffer, UInt32 sampleRate, UInt32 bufferSize, UInt32 windowSize);

Float32 GetBufferMaximumMagnitude(AudioBufferList *bufferList, UInt32 bufferSize);

Float32* GenerateFloatBuffer(UInt32 bufferLength, Float32 initalValue);

- (AudioProcessingBlock)vectorCompressionProcessingBlock;

@end

@interface OfflineAudioFileProcessor (Normalizer)

- (AudioProcessingBlock)normalizeProcessingBlockWithConstant:(Float32)normConstant;
- (AudioProcessingBlock)rampProcessingBlockWithFadeInDuration:(Float32)fadeInSecs fadeOutDuration:(Float32)fadeOutSecs;
- (AudioProcessingBlock)postProcessingBlockWithNormalizingConstant:(Float32)normConstant fadeInRampTime:(Float32)fadeInSecs fadeOutRampTime:(Float32)fadeOutSecs;

- (AudioProcessingBlock)normalizeProcessingBlockWithConstant:(Float32)normConstant fadeInDuration:(Float32)fadeInSecs fadeOutDuration:(Float32)fadeOutSecs;

@end

@interface OfflineAudioFileProcessor (Freeverb)

- (AudioProcessingBlock)mediumReverbProcessingBlock;
- (void)freeverbBlockCleanup;

@end

@interface OfflineAudioFileProcessor (Raw2Wav)

- (NSString *)defaultRaw2Wav:(NSString *)rawFilePath error:(NSError *__autoreleasing *)error;

@end

@interface OfflineAudioFileProcessor (ConvenienceMethods)

+ (instancetype)doDefaultProcessingWithSourceFile:(NSString *)sourceFilePath
                                       onProgress:(void(^)(double progress))progressBlock
                                        onSuccess:(void(^)(NSURL *resultFile))successBlock
                                        onFailure:(void(^)(NSError *error))failureBlock;

+ (NSString *)tempFilePathForFile:(NSString *)fileName;
+ (NSString *)tempFilePathForFile:(NSString *)fileName extension:(NSString *)extension;
+ (void)deleteTempFilesForFile:(NSString *)fileName;

@end

@interface OfflineAudioFileProcessor (Test)

+ (NSString *)testSoloFileName;
+ (NSString *)testAccompFileName;
+ (NSString *)testSourceFilePathForFile:(NSString *)testFileName;
+ (NSString *)testResultPathForFile:(NSString *)fileName;

@end
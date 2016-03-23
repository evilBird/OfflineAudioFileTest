//
//  OfflineAudioFileProcessor+Analysis.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/19/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

typedef     OSStatus    (^AudioAnalysisBlock)   (AudioBufferList    *buffer,
                                                UInt32              bufferSize,
                                                UInt32              framesRead,
                                                UInt32              framesRemaining,
                                                UInt32              sampleRate,
                                                void                *userInfo);

typedef     void                                (^AudioAnalysisCompletionHandler)                   (void *userInfo,
                                                                                                    NSError *error);

static NSString *kStartTime = @"frame_start_time_s";
static NSString *kPeakRMS = @"peak_RMS";
static NSString *kPeakRMSTime = @"peak_RMS_time_s";
static NSString *kIsPeak = @"is_peak";
static NSString *kObservations = @"observations";
static NSString *kInterval = @"interval";

@interface  OfflineAudioFileProcessor           (Analysis)

+ (instancetype)analyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize analysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(NSURL *resultFile))successHandler onFailure:(void(^)(NSError *error))failureHandler;

- (void)configureToAnalyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize usingAnalysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onCompletion:(AudioProcessingCompletionBlock)completionHandler;

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
                 progressBlock:(AudioProcessingProgressBlock)progressBlock
                         error:(NSError * __autoreleasing *)error;

+ (void)detectBPMOfFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(Float32 detectedTempo))successHandler onFailure:(void(^)(NSError *error))failureHandler;

@end

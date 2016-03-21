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

@interface  OfflineAudioFileProcessor           (Analysis)

+ (instancetype)analyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize analysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(NSURL *resultFile))successHandler onFailure:(void(^)(NSError *error))failureHandler;

- (void)configureToAnalyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize usingAnalysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onCompletion:(AudioProcessingCompletionBlock)completionHandler;

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
                 progressBlock:(AudioProcessingProgressBlock)progressBlock
                         error:(NSError * __autoreleasing *)error;

@end

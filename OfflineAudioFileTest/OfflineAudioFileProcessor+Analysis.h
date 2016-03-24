//
//  OfflineAudioFileProcessor+Analysis.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/19/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@interface  OfflineAudioFileProcessor           (Analysis)

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
                 progressBlock:(AudioProcessingProgressBlock)progressBlock
                         error:(NSError * __autoreleasing *)error;

+ (OfflineAudioFileProcessor *)detectBPMOfFile:(NSString *)sourceFilePath
                                  allowedRange:(NSRange)tempoRange
                                    onProgress:(AudioProcessingProgressBlock)progressHandler
                                     onSuccess:(void (^)(Float32 detectedTempo))successHandler
                                     onFailure:(void(^)(NSError *error))failureHandler;

@end

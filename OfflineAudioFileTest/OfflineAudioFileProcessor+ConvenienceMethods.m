//
//  OfflineAudioFileProcessor+ConvenienceMethods.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/9/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

#define DEFAULT_BUFFERSIZE 1024

@implementation OfflineAudioFileProcessor (ConvenienceMethods)

+ (instancetype)doDefaultProcessingWithSourceFile:(NSString *)sourceFilePath
                                       onProgress:(void(^)(double progress))progressBlock
                                        onSuccess:(void(^)(NSURL *resultFile))successBlock
                                        onFailure:(void(^)(NSError *error))failureBlock
{
    __block OfflineAudioFileProcessor *processor = nil;
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        
        processor = [OfflineAudioFileProcessor processFile:sourceFilePath
                                       withAudioBufferSize:DEFAULT_BUFFERSIZE
                                                  compress:YES
                                                    reverb:YES
                                           progressHandler:progressBlock
                                         completionHandler:^(NSURL *fileURL, NSError *error) {
                                             
                                             if (error) {
                                                 return failureBlock(error);
                                             }else{
                                                 
                                                 Float32 normConst = processor.normalizeConstant;
                                                 processor = nil;
                                                 [NSThread sleepForTimeInterval:0.2];
                                                 [[NSOperationQueue mainQueue]addOperationWithBlock:^{
                                                     [[NSOperationQueue new]addOperationWithBlock:^{
                                                         
                                                         processor = [OfflineAudioFileProcessor normalizeFile:fileURL.path
                                                                                                                withAudioBufferSize:DEFAULT_BUFFERSIZE
                                                                                                                  normalizeConstant:normConst
                                                                                                                      progressBlock:progressBlock
                                                                                                                    completionBlock:^(NSURL *fileURL, NSError *error) {
                                                                                                                        if (error) {
                                                                                                                            return failureBlock(error);
                                                                                                                        }else{
                                                                                                                            return successBlock(fileURL);
                                                                                                                        }
                                                                                                                    }];
                                                         [NSThread sleepForTimeInterval:0.1];
                                                         [processor start];
                                                     }];
                                                 }];
                                                 
                                             }
                                         }];
        
        [NSThread sleepForTimeInterval:0.1];
        [processor start];
    }];
    
    return processor;
}

@end
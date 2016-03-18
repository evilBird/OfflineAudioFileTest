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

+ (instancetype)convertAndProcessRawFile:(NSString *)rawFilePath
                                onProgress:(void(^)(double progress))progressBlock
                                 onSuccess:(void(^)(NSURL *resultFile))successBlock
                                 onFailure:(void(^)(NSError *error))failureBlock
{
    __block OfflineAudioFileProcessor *processor = [OfflineAudioFileProcessor new];
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        
        NSError *err = nil;
        NSString *wavFilePath = [processor defaultRaw2Wav:rawFilePath error:&err];
        if (err) {
            return failureBlock(err);
        }
        
        [processor configureToProcessFile:wavFilePath withAudioBufferSize:DEFAULT_BUFFERSIZE compress:YES reverb:YES postProcess:NO progressHandler:progressBlock completionHandler:^(NSURL *fileURL, NSError *error) {
            
            if (error) {
                return failureBlock(error);
            }
            
            [processor configureToProcessFile:fileURL.path withAudioBufferSize:DEFAULT_BUFFERSIZE compress:NO reverb:NO postProcess:YES progressHandler:progressBlock completionHandler:^(NSURL *fileURL, NSError *error) {
                
                if (error) {
                    return failureBlock(error);
                }
                
                return successBlock(fileURL);
            }];
            
            [processor start];
        }];
        
        [processor start];
        
    }];
    
    return processor;
}


+ (NSString *)tempFilePathForFile:(NSString *)fileName
{
    return [OfflineAudioFileProcessor tempFilePathForFile:fileName extension:nil];
}
+ (NSString *)tempFilePathForFile:(NSString *)fileName extension:(NSString *)extension
{
    NSString *tempFolderPath = NSTemporaryDirectory();
    NSNumber *randomTag = [NSNumber numberWithInteger:arc4random_uniform(1000000)];
    NSString *tempFileName = [NSString stringWithFormat:@"temp-%@-%@",randomTag,fileName];
    NSString *tempFilePath = nil;
    if (!extension) {
        tempFilePath = [tempFolderPath stringByAppendingPathComponent:tempFileName];
    }else{
        tempFilePath = [[tempFolderPath stringByAppendingPathComponent:tempFileName]stringByAppendingPathExtension:extension];
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:tempFilePath]) {
        [fm removeItemAtPath:tempFilePath error:nil];
    }
    return tempFilePath;
}
+ (void)deleteTempFilesForFile:(NSString *)fileName
{
    NSString *tempDir = NSTemporaryDirectory();
    NSFileManager *fm = [NSFileManager defaultManager];
    NSArray *contentsOfTempDir = [fm contentsOfDirectoryAtPath:tempDir error:nil];
    if (!contentsOfTempDir.count){
        return;
    }
    NSPredicate *tempFilesPredicate = [NSPredicate predicateWithFormat:@"SELF CONTAINS 'temp'"];
    NSArray *tempFiles = [contentsOfTempDir filteredArrayUsingPredicate:tempFilesPredicate];
    for (NSString *aTempFile in tempFiles) {
        NSString *aTempFilePath = [tempDir stringByAppendingPathComponent:aTempFile];
        [fm removeItemAtPath:aTempFilePath error:nil];
    }
}

@end
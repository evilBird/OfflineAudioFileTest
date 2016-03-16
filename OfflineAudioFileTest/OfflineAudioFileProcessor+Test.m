//
//  OfflineAudioFileProcessor+Test.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/8/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Test)

+ (NSString *)testAccompFileName
{
    NSString *fileName = @"faure_sicilienne_violin.48o.wav";
    return fileName;
}

+ (NSString *)testSoloFileName
{
    NSString *fileName = @"faure_sicilienne_violin.48k.wav";
    return fileName;
}

+ (NSString *)testSourceFilePathForFile:(NSString *)testFileName
{
    NSString *sourceFilePath = [[NSBundle bundleForClass:[self class]]pathForResource:[testFileName stringByDeletingPathExtension] ofType:[testFileName pathExtension]];
    return sourceFilePath;
}

+ (NSString *)tempFilePathForFile:(NSString *)fileName
{
    NSString *tempFolderPath = NSTemporaryDirectory();
    NSNumber *randomTag = [NSNumber numberWithInteger:arc4random_uniform(1000000)];
    NSString *tempFileName = [NSString stringWithFormat:@"temp-%@-%@",randomTag,fileName];
    NSString *tempFilePath = [tempFolderPath stringByAppendingPathComponent:tempFileName];
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:tempFilePath]) {
        [fm removeItemAtPath:tempFilePath error:nil];
    }
    return tempFilePath;
}


+ (NSString *)testResultPathForFile:(NSString *)fileName
{
    NSString *tempFolderPath = NSTemporaryDirectory();
    NSString *resultFilePath = [tempFolderPath stringByAppendingPathComponent:fileName];
    return resultFilePath;
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


+ (void)testFile:(NSString *)testFileName
{
    NSString *sourceFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:testFileName];
    NSString *resultFilePath = [OfflineAudioFileProcessor testResultPathForFile:testFileName];
    
    [OfflineAudioFileProcessor processFile:sourceFilePath withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        Float32 *samples = (Float32 *)(buffer->mBuffers[0].mData);
        Float32 scale = 2.0;
        vDSP_vsmul(samples, 1, &scale, samples, 1, bufferSize);
        return noErr;
    } maxBufferSize:1024 resultPath:resultFilePath completion:^(NSString *resultPath, NSError *error) {
        if (!error) {
            NSLog(@"finished writing audio file to path: %@",resultPath);
        }else{
            NSAssert(nil==error, @"ERROR WRITING FILE: %@",error);
        }
    }];
}

@end
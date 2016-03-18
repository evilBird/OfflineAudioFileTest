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

+ (NSString *)testResultPathForFile:(NSString *)fileName
{
    NSString *tempFolderPath = NSTemporaryDirectory();
    NSString *resultFilePath = [tempFolderPath stringByAppendingPathComponent:fileName];
    return resultFilePath;
}




@end
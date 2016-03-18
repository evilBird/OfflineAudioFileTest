//
//  OfflineAudioFileProcessor+Raw2Wav.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/17/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@implementation OfflineAudioFileProcessor (Raw2Wav)

+ (NSError *)converterError
{
    return [NSError errorWithDomain:@"OfflineAudioFileProcessor+Raw2Wav" code:0 userInfo:nil];
}

+ (void)convertRaw2Wav:(NSString *)rawFilePath completion:(void (^)(NSString *wavFilePath, NSError *error))completion
{
    [[NSOperationQueue new]addOperationWithBlock:^{
        OfflineAudioFileProcessor *p = [OfflineAudioFileProcessor new];
        NSError *myErr = nil;
        NSString *resultPath = [p defaultRaw2Wav:rawFilePath error:&myErr];
        if (myErr) {
            return completion(nil,myErr);
        }else{
            return completion(resultPath,nil);
        }
    }];
}

- (NSString *)defaultRaw2Wav:(NSString *)rawFilePath error:(NSError *__autoreleasing *)error
{
    NSString *fileName = [rawFilePath lastPathComponent];
    NSString *destinationPath = [OfflineAudioFileProcessor tempFilePathForFile:fileName extension:@"wav"];

    return [self
            convertRaw:rawFilePath
            toWav:destinationPath
            numChannels:1
            samplingRate:48000
            bitsPerSample:16
            error:error];
}

- (NSString *)convertRaw:(NSString *)rawFilePath
                   toWav:(NSString *)wavFilePath
             numChannels:(short)numChannels
            samplingRate:(int)samplingRate
           bitsPerSample:(short)bitsPerSample
                   error:(NSError *__autoreleasing *)error
{
    
    if (self.isCancelled) {
        return nil;
    }
    
    NSFileManager *fm = [NSFileManager defaultManager];
    NSError *err = nil;
    
    if (![fm fileExistsAtPath:rawFilePath]) {
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    if ([fm fileExistsAtPath:wavFilePath]) {
        [fm removeItemAtPath:wavFilePath error:nil];
    }
    
    FILE *fout;
    
    short NumChannels = numChannels;
    short BitsPerSample = bitsPerSample;
    int SamplingRate = samplingRate;
    int numOfSamples = (int)[[NSData dataWithContentsOfFile:rawFilePath] length];
    if (numOfSamples == 0) {
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    int ByteRate = NumChannels*BitsPerSample*SamplingRate/8;
    short BlockAlign = NumChannels*BitsPerSample/8;
    int DataSize = NumChannels*numOfSamples*BitsPerSample/8;
    int chunkSize = BitsPerSample;
    int totalSize = DataSize - 8;
    int fileSize = DataSize-44;
    short audioFormat = 1;
    
    if((fout = fopen([wavFilePath cStringUsingEncoding:1], "w")) == NULL)
    {
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    size_t size = 0;
    size = fwrite("RIFF", sizeof(char), 4,fout);
    size = fwrite(&totalSize, sizeof(int), 1, fout);
    size = fwrite("WAVE", sizeof(char), 4, fout);
    size = fwrite("fmt ", sizeof(char), 4, fout);
    size = fwrite(&chunkSize, sizeof(int),1,fout);
    size = fwrite(&audioFormat, sizeof(short), 1, fout);
    size = fwrite(&NumChannels, sizeof(short),1,fout);
    size = fwrite(&SamplingRate, sizeof(int), 1, fout);
    size = fwrite(&ByteRate, sizeof(int), 1, fout);
    size = fwrite(&BlockAlign, sizeof(short), 1, fout);
    size = fwrite(&BitsPerSample, sizeof(short), 1, fout);
    size = fwrite("data", sizeof(char), 4, fout);
    size = fwrite(&fileSize, sizeof(int), 1, fout);
    fclose(fout);
    
    int headerSize = (int)([NSData dataWithContentsOfFile:wavFilePath].length);
    
    if (headerSize != 44) {
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    NSMutableData *pamdata = [NSMutableData dataWithContentsOfFile:rawFilePath];
    NSFileHandle *handle;
    handle = [NSFileHandle fileHandleForUpdatingAtPath:wavFilePath];
    [handle seekToEndOfFile];
    [handle writeData:pamdata];
    [handle closeFile];
    
    handle = nil;
    pamdata = nil;
    
    NSData *wavData = [NSData dataWithContentsOfFile:wavFilePath];
    if (wavData.length <= 44) {
        
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    
    handle = [NSFileHandle fileHandleForUpdatingAtPath:wavFilePath];
    
    int totalFileSize = (int)(wavData.length);
    int subchunkSize = (totalFileSize-8);
    void *subchunkSizeData = NULL;
    subchunkSizeData = (void *)malloc(sizeof(int));
    memcpy(subchunkSizeData, &subchunkSize, sizeof(int));
    NSData *subchunkData = [NSData dataWithBytes:subchunkSizeData length:sizeof(int)];
    [handle seekToFileOffset:4];
    [handle writeData:subchunkData];
    
    
    void *dataSizeData = NULL;
    dataSizeData = (void *)malloc(sizeof(int));
    int totalDataSize = (totalFileSize - headerSize);
    memcpy(dataSizeData, &totalDataSize, sizeof(int));
    NSData *sizeData = [NSData dataWithBytes:dataSizeData length:sizeof(int)];
    [handle seekToFileOffset:40];
    [handle writeData:sizeData];
    [handle closeFile];
    
    wavData = nil;
    handle = nil;
    free(subchunkSizeData);
    free(dataSizeData);
    
    wavData = [NSData dataWithContentsOfFile:wavFilePath];
    
    if (wavData.length <= 44) {
        err = [OfflineAudioFileProcessor converterError];
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    return wavFilePath;
}


@end


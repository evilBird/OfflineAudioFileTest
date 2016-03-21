//
//  OfflineAudioFileProcessor+Analysis.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/19/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor+Analysis.h"

static void *vUserInfo;
static AudioAnalysisBlock kAnalysisBlock;
/*
@interface OfflineAudioFileProcessor () {
    void *vUserInfo;
    AudioAnalysisBlock kAnalysisBlock;
}
@end
*/
@implementation OfflineAudioFileProcessor (Analysis)

+ (instancetype)analyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize analysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(NSURL *resultFile))successHandler onFailure:(void(^)(NSError *error))failureHandler
{
    __block OfflineAudioFileProcessor *analyzer = [OfflineAudioFileProcessor new];
    [[NSOperationQueue new]addOperationWithBlock:^{
        [analyzer configureToAnalyzeFile:sourceFilePath maxBlockSize:maxBlockSize usingAnalysisBlock:[analysisBlock copy] userInfo:userInfo onProgress:[progressHandler copy] onCompletion:^(NSURL *resultFile, NSError *error) {
            if (error) {
                return failureHandler(error);
            }
            
            return successHandler(resultFile);
        }];
        
        [analyzer start];
    }];
    
    return analyzer;
}

- (void)configureToAnalyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize usingAnalysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onCompletion:(AudioProcessingCompletionBlock) completionHandler
{
    vUserInfo = userInfo;
    kAnalysisBlock = [analysisBlock copy];
    [self initializeAnalyzerWithSourceFile:sourceFilePath maxBufferSize:maxBlockSize];
    [self setProgressBlock:[progressHandler copy]];
    __weak OfflineAudioFileProcessor *weakself = self;
    [self setCompletionBlock:^(NSURL *resultFile, NSError *error){
        
        NSError *err = nil;
        NSString *writeToPath = [OfflineAudioFileProcessor tempFilePathForFile:[sourceFilePath lastPathComponent] extension:@"txt"];
        NSURL *writeToURL = [NSURL fileURLWithPath:writeToPath];
        [weakself writeAnalysisDataToURL:writeToURL error:&err];
        
        if (err) {
            return completionHandler(nil,err);
        }
        
        return completionHandler(writeToURL, nil);
    }];
}

- (void)writeAnalysisDataToURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    id dataObject = (__bridge id)(vUserInfo);
    if ([dataObject isKindOfClass:[NSDictionary class]]) {
        NSDictionary *analysisDictionary = (NSDictionary *)dataObject;
        if (![analysisDictionary writeToURL:targetURL atomically:NO]) {
            NSError *e = [NSError errorWithDomain:@"OfflineAudioFileProcessor+Analysis.m" code:37 userInfo:nil];
            *error = e;
            return;
        }
    }
}

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
       progressBlock:(AudioProcessingProgressBlock)progressBlock
               error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    AVAudioFrameCount maxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFrameCount numFramesToRead = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
    AVAudioFrameCount numFramesRead = (AVAudioFrameCount)sourceFile.framePosition;
    
    while (numFramesToRead && !self.isCancelled && !self.isPaused) {
        
        AVAudioFrameCount bufferSize = ( numFramesToRead >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToRead );
        AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:sourceBuffer frameCount:bufferSize error:&err];
        AudioBufferList *sourceBufferList = (AudioBufferList *)(sourceBuffer.audioBufferList);
        
        if (err) {
            break;
        }
        UInt32 nfr = (UInt32)numFramesRead;
        UInt32 ntr = (UInt32)numFramesToRead;
        UInt32 sr = (UInt32)sourceFile.processingFormat.sampleRate;
        OSStatus status = kAnalysisBlock(sourceBufferList, bufferSize, nfr,ntr,sr,vUserInfo);
        
        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor+Analysis.m" code:80 userInfo:nil];
            break;
        }
        
        if (err) {
            break;
        }
        
        numFramesToRead = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
        
        if (progressBlock) {
            double currentProgress = (double)(sourceFile.framePosition)/(double)(sourceFile.length);
            progressBlock(currentProgress);
        }
    }
    
    if (err) {
        if (error) {
            *error = err;
        }
        
        return;
    }
}

@end

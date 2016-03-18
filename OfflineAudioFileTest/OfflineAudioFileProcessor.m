//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"
#import "OfflineAudioFileProcessor+Functions.h"

@interface OfflineAudioFileProcessor () {
}

@property (nonatomic,strong,readwrite)                  NSString                           *fileName;
@property (nonatomic,strong,readwrite)                  NSString                           *sourceFilePath;
@property (nonatomic,strong)                            NSString                           *tempResultFilePath;
@property (nonatomic,strong,readwrite)                  NSString                           *resultFilePath;

@property (nonatomic,strong)                            AVAudioFile                        *sourceAudioFile;
@property (nonatomic,strong)                            AVAudioFile                        *tempResultAudioFile;
@property (nonatomic,strong)                            AVAudioFile                        *resultAudioFile;

@property (nonatomic,readwrite)                         NSUInteger                         maxBufferSize;
@property (nonatomic,readwrite)                         NSUInteger                         sourceSampleRate;
@property (nonatomic,readwrite)                         AVAudioFrameCount                  sourceLength;
@property (nonatomic,readwrite)                         AVAudioFramePosition               sourcePosition;
@property (nonatomic,readwrite)                         AVAudioFormat                      *sourceFormat;
@property (nonatomic,readwrite)                         Float32                            maxMeasuredOutputMagnitude;
@property (nonatomic,readwrite)                         Float32                            maxAllowedPerChannelMagnitude;
@property (nonatomic,readwrite)                         Float32                            normalizeConstant;

@property (nonatomic,readwrite)                         bool                               forceStereo;
@property (nonatomic,readwrite)                         double                             progress;
@property (nonatomic,readwrite,getter=isReady)          bool                               ready;
@property (nonatomic,readwrite,getter=isRunning)        bool                               running;
@property (nonatomic,readwrite,getter=isPaused)         bool                               paused;
@property (nonatomic,readwrite,getter=isDone)           bool                               done;
@property (nonatomic,readwrite,getter=isCancelled)      bool                               cancelled;

@property (nonatomic,strong,readwrite)                  NSError                            *error;

@property (nonatomic,copy)                              AudioProcessingProgressBlock        myProgressBlock;
@property (nonatomic,copy)                              AudioProcessingCompletionBlock      myCompletionBlock;
@property (nonatomic,copy)                              AudioProcessingBlock                myProcessingBlock;


@end

@implementation OfflineAudioFileProcessor

+ (instancetype)normalizeFile:(NSString *)sourceFilePath
          withAudioBufferSize:(NSUInteger)maxBufferSize
            normalizeConstant:(Float32)normConstant
                progressBlock:(void(^)(double progress))progressHandler
              completionBlock:(void(^)(NSURL *fileURL, NSError *error))completionHandler
{
    OfflineAudioFileProcessor *processor = [[OfflineAudioFileProcessor alloc]initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
    [processor setProgressBlock:progressHandler];
    [processor setCompletionBlock:completionHandler];
    AudioProcessingBlock normalizeBlock = [processor normalizeProcessingBlockWithConstant:normConstant fadeInDuration:1.0 fadeOutDuration:1.0];
    processor.doNormalize = YES;
    [processor setProcessingBlock:normalizeBlock];
    return processor;
}

+ (instancetype)processFile:(NSString *)sourceFilePath
        withAudioBufferSize:(NSUInteger)maxBufferSize
                   compress:(BOOL)compress
                     reverb:(BOOL)reverb
            progressHandler:(void(^)(double progress))progressHandler
          completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler
{
    return [OfflineAudioFileProcessor processFile:sourceFilePath
                              withAudioBufferSize:maxBufferSize
                                         compress:compress
                                           reverb:reverb
                                      forceStereo:NO
                                  progressHandler:progressHandler
                                completionHandler:completionHandler];
}

+ (instancetype)processFile:(NSString *)sourceFilePath
        withAudioBufferSize:(NSUInteger)maxBufferSize
                   compress:(BOOL)compress
                     reverb:(BOOL)reverb
                forceStereo:(BOOL)forceStereo
            progressHandler:(void(^)(double progress))progressHandler
          completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler
{
    OfflineAudioFileProcessor *processor  = [[OfflineAudioFileProcessor alloc]initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize forceStereo:forceStereo];
    [processor setCompletionBlock:completionHandler];
    [processor setProgressBlock:progressHandler];
    processor.doReverb = reverb;
    processor.doCompression = compress;
    AudioProcessingBlock reverbBlock = nil;
    AudioProcessingBlock compressionBlock = nil;
    
    if (reverb) {
        reverbBlock = [processor mediumReverbProcessingBlock];
    }
    if (compress) {
        compressionBlock = [processor vectorCompressionProcessingBlock];
    }
    
    [processor setProcessingBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        
        OSStatus err = noErr;
        err = processor.doesReverb ? reverbBlock(buffer,bufferSize) :  err;
        err = processor.doesCompression ? compressionBlock(buffer,bufferSize) : err;
        
        return err;
    }];
    
    return processor;
}

- (void)setProgressBlock:(void(^)(double progress))progressBlock
{
    self.myProgressBlock = progressBlock;
}

- (void)setProcessingBlock:(OSStatus(^)(AudioBufferList *buffer, AVAudioFrameCount bufferSize))processingBlock
{
    self.myProcessingBlock = processingBlock;
}

- (void)setCompletionBlock:(void(^)(NSURL *resultFile, NSError *error))completionBlock
{
    self.myCompletionBlock = completionBlock;
}

- (instancetype)initWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize
{
    return [self initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize forceStereo:NO];
}

- (instancetype)initWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize forceStereo:(BOOL)forceStereo
{
    self = [super init];
    if (self) {
        _sourceFilePath = sourceFilePath;
        _maxBufferSize = maxBufferSize;
        _forceStereo = forceStereo;
        [self defaultInit];
    }
    
    return self;
}

- (void)defaultInit
{
    _ready = NO;
    _running = NO;
    _done = NO;
    _cancelled = NO;
    _resultAudioFile = nil;
    _tempResultAudioFile = nil;
    _progress = 0.0;
    _maxMeasuredOutputMagnitude = 0.0;
    _fileName = [_sourceFilePath lastPathComponent];
    NSError *err = nil;
    _ready = [self getReadyError:&err];
    _error = err;
}

- (BOOL)getReadyError:(NSError * __autoreleasing *)error
{
    NSParameterAssert(self.sourceFilePath);
    NSError *err = nil;
    
    self.sourceAudioFile = [self audioFileForReadingFromPath:self.sourceFilePath error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        
        return NO;
    }
    
    self.sourceFormat = self.sourceAudioFile.processingFormat;
    self.sourceLength = (AVAudioFrameCount)(self.sourceAudioFile.length);
    self.sourcePosition = 0;
    self.tempResultFilePath = [OfflineAudioFileProcessor tempFilePathForFile:self.fileName];
    
    AVAudioFormat *targetAudioFormat;
    
    if (self.forceStereo && self.sourceFormat.channelCount < 2) {
       targetAudioFormat = [[AVAudioFormat alloc]initWithCommonFormat:self.sourceFormat.commonFormat sampleRate:self.sourceFormat.sampleRate channels:2 interleaved:self.sourceFormat.isInterleaved];
    }else{
      targetAudioFormat = [[AVAudioFormat alloc]initWithCommonFormat:self.sourceFormat.commonFormat sampleRate:self.sourceFormat.sampleRate channels:self.sourceFormat.channelCount interleaved:self.sourceFormat.isInterleaved];
    }
    
    self.targetFormat = targetAudioFormat;
    self.tempResultAudioFile = [self audioFileForWritingToPath:self.tempResultFilePath processingFormat:targetAudioFormat error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        
        return NO;
    }
    
    return YES;
}

- (AVAudioFile *)audioFileForReadingFromPath:(NSString *)sourceFilePath error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    NSParameterAssert(sourceFilePath);
    NSURL *sourceFileURL = [NSURL fileURLWithPath:sourceFilePath];
    AVAudioFile *sourceAudioFile = [[AVAudioFile alloc]initForReading:sourceFileURL error:&err];
    if (err) {
        if (error) {
            *error = err;
        }
        
        return nil;
    }
    
    return sourceAudioFile;
}

- (AVAudioFile *)audioFileForWritingToPath:(NSString *)destinationFilePath processingFormat:(AVAudioFormat *)processingFormat error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(destinationFilePath);
    NSParameterAssert(processingFormat);
    
    NSURL *resultFileURL = [NSURL fileURLWithPath:destinationFilePath];
    NSMutableDictionary *resultFileSettings = [NSMutableDictionary dictionary];
    resultFileSettings[AVSampleRateKey] = @(processingFormat.sampleRate);
    resultFileSettings[AVNumberOfChannelsKey] = @(processingFormat.channelCount);
    NSError *err = nil;
    
    AVAudioFile *resultAudioFile = [[AVAudioFile alloc]initForWriting:resultFileURL
                                                             settings:resultFileSettings
                                                         commonFormat:processingFormat.commonFormat
                                                          interleaved:processingFormat.isInterleaved
                                                                error:&err];
    if (err) {
        if (error) {
            *error = err;
        }
        return nil;
    }
    
    return resultAudioFile;
}


- (void)start
{
    NSError *err = nil;

    if (!self.isReady) {
        
        self.ready = [self getReadyError:&err];
        
        if (err) {
            return [self finishWithError:err];
        }
    }
    
    self.running = [self startAudioSessionError:&err];
    
    if (err) {
        return [self finishWithError:err];
    }
    
    [self doMainProcessing];
}

- (void)pause
{
    if ( !self.isRunning || self.isCancelled || self.isPaused || self.isDone ) {
        return;
    }
    
    self.paused = YES;
    self.running = !([self stopAudioSessionError:nil]);
}

- (void)resume
{
    if ( !self.isPaused || self.isRunning || self.isCancelled || self.isDone || self.error ) {
        return;
    }
    
    self.paused = NO;
    NSError *err = nil;
    self.running = [self startAudioSessionError:&err];
    
    if (err) {
        return [self finishWithError:err];
    }
    
    [self doMainProcessing];
}

- (void)cancel
{
    if ( self.isCancelled || self.isDone ) {
        return;
    }
    
    self.cancelled = YES;
}

- (BOOL)startAudioSessionError:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    
    [[AVAudioSession sharedInstance]setActive:YES error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return NO;
    }
    
    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryAudioProcessing error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return NO;
    }
    
    [[AVAudioSession sharedInstance]setMode:AVAudioSessionModeDefault error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return NO;
    }
    
    return YES;
}

- (BOOL)stopAudioSessionError:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    [[AVAudioSession sharedInstance]setActive:NO error:&err];
    if (err) {
        if (error) {
            *error = err;
        }
        return NO;
    }
    
    return YES;
}

- (void)readFromFile:(AVAudioFile *)sourceFile
    processWithBlock:(AudioProcessingBlock)processingBlock
      andWriteToFile:(AVAudioFile *)targetFile
       progressBlock:(AudioProcessingProgressBlock)progressBlock
        maxMagnitude:(Float32 *)maxMagnitude
               error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    AVAudioFrameCount maxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFrameCount numFramesToWrite = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
    AVAudioFormat *sourceFormat = sourceFile.processingFormat;
    AVAudioFormat *targetFormat = targetFile.processingFormat;
    
    BOOL copyMonoBufferToStereo = (self.forceStereo && targetFormat.channelCount > sourceFormat.channelCount );
    
    while (numFramesToWrite && !self.isCancelled && !self.isPaused) {
        
        AVAudioFrameCount bufferSize = ( numFramesToWrite >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToWrite );
        AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:sourceBuffer frameCount:bufferSize error:&err];
        
        if (err) {
            break;
        }
        
        AudioBufferList *sourceBufferList = (AudioBufferList *)(sourceBuffer.mutableAudioBufferList);
        AudioBufferList *bufferListToProcess = NULL;
        AVAudioPCMBuffer *targetBuffer = nil;
        
        if (copyMonoBufferToStereo) {
            targetBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:targetFile.processingFormat frameCapacity:bufferSize];
            bufferListToProcess = (AudioBufferList *)(targetBuffer.audioBufferList);
            CopyMonoAudioBufferListToStereo(bufferListToProcess, sourceBufferList, bufferSize);
        }else{
            targetBuffer = sourceBuffer;
            bufferListToProcess = sourceBufferList;
        }
        
        OSStatus status = processingBlock(bufferListToProcess, bufferSize);
        
        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
            break;
        }
        
        if (maxMagnitude) {
            Float32 prevMax = *maxMagnitude;
            Float32 newMax = GetBufferMaximumMagnitude(bufferListToProcess, (UInt32)bufferSize);
            *maxMagnitude = ( newMax >= prevMax ) ? ( newMax ) : ( prevMax );
        }
        
        [targetFile writeFromBuffer:targetBuffer error:&err];
        
        if (err) {
            break;
        }
        
        numFramesToWrite = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
        
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

- (void)doMainProcessing
{
    if (self.isCancelled) {
        return [self cleanup];
    }
    
    NSError *err = nil;
    Float32 maxMagnitude = self.maxMeasuredOutputMagnitude;
    
    [self readFromFile:self.sourceAudioFile processWithBlock:self.myProcessingBlock andWriteToFile:self.tempResultAudioFile progressBlock:self.myProgressBlock maxMagnitude:&maxMagnitude error:&err];
    
    if (err) {
        return [self finishWithError:err];
    }
    
    self.maxMeasuredOutputMagnitude = maxMagnitude;
    
    if (self.isCancelled) {
        return [self cleanup];
    }
    
    if (self.isPaused) {
        return;
    }
    
    NSLog(@"MAX MAGNITUDE: %f",maxMagnitude);
    
    if (!self.doNormalize && self.maxMeasuredOutputMagnitude > 0.01) {
        
        self.maxAllowedPerChannelMagnitude = 0.99/(Float32)(self.targetFormat.channelCount);
        self.normalizeConstant = self.maxAllowedPerChannelMagnitude/self.maxMeasuredOutputMagnitude;
        NSLog(@"NORMALIZE CONSTANT: %f",self.normalizeConstant);
    }

    self.resultAudioFile = [[AVAudioFile alloc]initForReading:self.tempResultAudioFile.url error:&err];
    
    if (err) {
        return [self finishWithError:err];
    }
    
    return [self finishWithResult:self.resultAudioFile.url];
    
}

- (void)finishWithError:(NSError *)error
{
    self.error = error;
    self.cancelled = NO;
    self.paused = NO;
    self.running = NO;
    [self cleanup];
    self.myCompletionBlock(nil,error);
}

- (void)finishWithResult:(NSURL *)resultURL
{
    self.error = nil;
    self.cancelled = NO;
    self.paused = NO;
    self.running = NO;
    self.done = YES;
    [self cleanup];
    self.myCompletionBlock(resultURL, nil);
}

- (void)cleanup
{
    [self stopAudioSessionError:nil];

    [self cleanupFiles];

    if ( !self.isDone ) {
        [self deletePartialFiles];
    }
    
    if ( self.doesReverb ){
        [self freeverbBlockCleanup];
    }
    
}

- (void)deletePartialFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:self.tempResultFilePath]) {
        [fm removeItemAtPath:self.tempResultFilePath error:nil];
    }
}

- (void)cleanupFiles
{
    _sourceAudioFile = nil;
    _tempResultAudioFile = nil;
    _resultAudioFile = nil;
}


@end

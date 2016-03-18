//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"
#import "OfflineAudioFileProcessor+Functions.h"
#import "NSObject+AudioSessionManager.h"

@interface OfflineAudioFileProcessor () {
}

@property (nonatomic,strong,readwrite)                  NSString                           *fileName;
@property (nonatomic,strong)                            NSString                           *tempResultFilePath;

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
    OfflineAudioFileProcessor *processor = [OfflineAudioFileProcessor new];
    processor.normalizeConstant = normConstant;
    [processor configureToProcessFile:sourceFilePath
                  withAudioBufferSize:maxBufferSize
                             compress:NO
                               reverb:NO
                          postProcess:YES
                      progressHandler:progressHandler
                    completionHandler:completionHandler];
    
    return processor;
}

+ (instancetype)processFile:(NSString *)sourceFilePath
        withAudioBufferSize:(NSUInteger)maxBufferSize
                   compress:(BOOL)compress
                     reverb:(BOOL)reverb
            progressHandler:(void(^)(double progress))progressHandler
          completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler
{
    OfflineAudioFileProcessor *processor = [OfflineAudioFileProcessor new];
    [processor configureToProcessFile:sourceFilePath
                  withAudioBufferSize:maxBufferSize
                             compress:compress
                               reverb:reverb
                          postProcess:NO
                      progressHandler:progressHandler
                    completionHandler:completionHandler];
    return processor;
}

- (void)configureToProcessFile:(NSString *)sourceFilePath withAudioBufferSize:(NSUInteger)maxBufferSize compress:(BOOL)compress reverb:(BOOL)reverb postProcess:(BOOL)postProcess progressHandler:(void(^)(double progress))progressHandler completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler
{
    [self initializeProcessorWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
    
    [self setCompletionBlock:completionHandler];
    [self setProgressBlock:progressHandler];
    self.doReverb = reverb;
    self.doCompression = compress;
    self.doNormalize = postProcess;
    
    AudioProcessingBlock reverbBlock = nil;
    AudioProcessingBlock compressionBlock = nil;
    AudioProcessingBlock postProcessingBlock = nil;
    
    if (reverb) {
        reverbBlock = [self mediumReverbProcessingBlock];
    }
    if (compress) {
        compressionBlock = [self vectorCompressionProcessingBlock];
    }
    
    if (postProcess) {
        Float32 normConstant = self.normalizeConstant;
        postProcessingBlock = [self postProcessingBlockWithNormalizingConstant:normConstant fadeInRampTime:1.0 fadeOutRampTime:1.0];
    }
    self.maxMeasuredOutputMagnitude = 0.0;
    self.normalizeConstant = 0.0;
    __weak OfflineAudioFileProcessor *weakself = self;
    [self setProcessingBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        
        OSStatus err = noErr;
        err = weakself.doesReverb ? reverbBlock(buffer,bufferSize) :  err;
        err = weakself.doesCompression ? compressionBlock(buffer,bufferSize) : err;
        err = weakself.doesNormalize ? postProcessingBlock(buffer,bufferSize) : err;
        
        return err;
    }];

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
    return [self initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
}

- (void)initializeProcessorWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize
{
    self.sourceFilePath = sourceFilePath;
    self.maxBufferSize = maxBufferSize;
    [self defaultInit];
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
    self.targetFormat = self.sourceFormat;
    self.tempResultAudioFile = [self audioFileForWritingToPath:self.tempResultFilePath processingFormat:self.targetFormat error:&err];
    
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
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        [self doMainProcessing];
    }];
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
    [[NSOperationQueue new]addOperationWithBlock:^{
        [self doMainProcessing];
    }];
}

- (void)cancel
{
    if ( self.isCancelled || self.isDone ) {
        return;
    }
    
    BOOL wasPaused = self.isPaused;
    self.cancelled = YES;
    if (wasPaused) {
        [self resume];
    }
}

- (BOOL)startAudioSessionError:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    __weak OfflineAudioFileProcessor *weakself = self;
    [self startDefaultAudioSessionWithCategory:AVAudioSessionCategoryAudioProcessing
                                onInterruption:^(AVAudioSessionInterruptionType type, AVAudioSessionInterruptionOptions shouldResume) {
                                    if (type == AVAudioSessionInterruptionTypeBegan) {
                                        NSLog(@"Session Interruption");
                                        if (weakself.isRunning) {
                                            [weakself pause];
                                        }
                                    }else{
                                        NSLog(@"Session interruption ended");
                                        if (shouldResume) {
                                            NSLog(@"Resume Now");
                                            [weakself resume];
                                        }else{
                                            NSLog(@"Cancel pending");
                                            [weakself cancel];
                                        }
                                    }
                                }
                               onBackgrounding:^(BOOL isBackgrounded, BOOL wasBackgrounded) {
                                   if (isBackgrounded) {
                                       NSLog(@"ENTERED BACKGROUND");
                                   }else{
                                       NSLog(@"EXITING BACKGROUND");
                                   }
                               } error:&err];
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
    
    [self stopAudioSession:&err];
    
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
    
    while (numFramesToWrite && !self.isCancelled && !self.isPaused) {
        
        AVAudioFrameCount bufferSize = ( numFramesToWrite >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToWrite );
        AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:sourceBuffer frameCount:bufferSize error:&err];
        AudioBufferList *sourceBufferList = (AudioBufferList *)(sourceBuffer.mutableAudioBufferList);

        if (err) {
            break;
        }
        
        OSStatus status = processingBlock(sourceBufferList, bufferSize);
        
        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
            break;
        }
        
        if (maxMagnitude) {
            Float32 prevMax = *maxMagnitude;
            Float32 newMax = GetBufferMaximumMagnitude(sourceBufferList, (UInt32)bufferSize);
            *maxMagnitude = ( newMax >= prevMax ) ? ( newMax ) : ( prevMax );
        }
        
        [targetFile writeFromBuffer:sourceBuffer error:&err];
        
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
    NSLog(@"max magnitude: %f",self.maxMeasuredOutputMagnitude);
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
    NSLog(@"max magnitude: %f",self.maxMeasuredOutputMagnitude);
    self.myCompletionBlock(resultURL, nil);
}

- (void)cleanup
{
    [self stopAudioSessionError:nil];

    if ( self.doesReverb ){
        [self freeverbBlockCleanup];
    }
    
    [self cleanupFiles];

    if ( self.isCancelled ) {
        [self deletePartialFiles];
    }
}

- (void)deletePartialFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if (self.tempResultFilePath && [fm fileExistsAtPath:self.tempResultFilePath]) {
        [fm removeItemAtPath:self.tempResultFilePath error:nil];
    }

    if (self.resultFilePath && [fm fileExistsAtPath:self.resultFilePath]) {
        [fm removeItemAtPath:self.resultFilePath error:nil];
    }
}

- (void)cleanupFiles
{
    _sourceAudioFile = nil;
    _tempResultAudioFile = nil;
    _resultAudioFile = nil;
}

- (void)dealloc
{
    if (_fileName) {
        [OfflineAudioFileProcessor deleteTempFilesForFile:_fileName];
    }
}

@end

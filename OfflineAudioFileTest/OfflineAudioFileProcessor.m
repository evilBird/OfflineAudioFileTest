//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@interface OfflineAudioFileProcessor ()

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
@property (nonatomic,readwrite)                         AVAudioFrameCount                  numSourceFramesRemaining;
@property (nonatomic,readwrite)                         Float32                             measuredPeakOutputRMS;
@property (nonatomic,readwrite)                         Float32                             channelNormalizedMaxRMS;
@property (nonatomic,readwrite)                         Float32                             normalizeConstant;
@property (nonatomic,strong,readwrite)                  NSString                           *fileName;

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
    AudioProcessingBlock normalizeBlock = [processor normalizeProcessingBlockWithConstant:normConstant];
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
    
    OfflineAudioFileProcessor *processor  = [[OfflineAudioFileProcessor alloc]initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
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
    self = [super init];
    if (self) {
        _sourceFilePath = sourceFilePath;
        _fileName = [sourceFilePath lastPathComponent];
        _maxBufferSize = maxBufferSize;
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
    _measuredPeakOutputRMS = 0.0;
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
    self.sourceSampleRate = (NSUInteger)(self.sourceFormat.sampleRate);
    self.sourcePosition = 0;
    self.numSourceFramesRemaining = self.sourceLength;
    
    self.tempResultFilePath = [OfflineAudioFileProcessor tempFilePathForFile:self.fileName];
    self.tempResultAudioFile = [self audioFileForWritingToPath:self.tempResultFilePath fromSource:self.sourceAudioFile error:&err];
    
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

- (AVAudioFile *)audioFileForWritingToPath:(NSString *)destinationFilePath fromSource:(AVAudioFile *)sourceAudioFile error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(destinationFilePath);
    NSParameterAssert(sourceAudioFile);
    
    NSURL *resultFileURL = [NSURL fileURLWithPath:destinationFilePath];
    
    NSMutableDictionary *resultFileSettings = [NSMutableDictionary dictionary];
    resultFileSettings[AVSampleRateKey] = @(sourceAudioFile.processingFormat.sampleRate);
    resultFileSettings[AVNumberOfChannelsKey] = @(sourceAudioFile.processingFormat.channelCount);
    
    NSError *err = nil;
    
    AVAudioFile *resultAudioFile = [[AVAudioFile alloc]initForWriting:resultFileURL
                                                             settings:resultFileSettings
                                                         commonFormat:sourceAudioFile.processingFormat.commonFormat
                                                          interleaved:sourceAudioFile.processingFormat.isInterleaved
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

- (void)readFromFile:(AVAudioFile *)sourceFile processWithBlock:(AudioProcessingBlock)processingBlock andWriteToFile:(AVAudioFile *)targetFile progressBlock:(AudioProcessingProgressBlock)progressBlock maxRMS:(Float32 *)maxRMS error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    AVAudioFrameCount maxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFrameCount numFramesToWrite = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
    AVAudioFormat *sourceFormat = sourceFile.processingFormat;
    UInt32 sampleRate = (UInt32)(sourceFormat.sampleRate);
    Float32 windowLengthMs = 1.0;
    UInt32 samplesPerWindow = sourceFormat.sampleRate * windowLengthMs * 0.001;
    
    while (numFramesToWrite && !self.isCancelled && !self.isPaused) {
        AVAudioFrameCount bufferSize = ( numFramesToWrite >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToWrite );
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
        if (err) {
            break;
        }
        
        AudioBufferList *bufferList = (AudioBufferList *)(buffer.audioBufferList);
        OSStatus status = processingBlock(bufferList, bufferSize);
        
        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
            break;
        }
        
        [targetFile writeFromBuffer:buffer error:&err];
        
        if (err) {
            break;
        }
        
        if (maxRMS) {
            Float32 prevMax = *maxRMS;
            UInt32 windowSize = (UInt32)bufferSize/samplesPerWindow;
            Float32 newMax = GetPeakRMS(bufferList, sampleRate, (UInt32)bufferSize, windowSize);
            *maxRMS = ( newMax >= prevMax ) ? ( newMax ) : ( prevMax );
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
    Float32 maxRMSVal = self.measuredPeakOutputRMS;
    
    if (!self.doNormalize) {
        [self readFromFile:self.sourceAudioFile processWithBlock:self.myProcessingBlock andWriteToFile:self.tempResultAudioFile progressBlock:self.myProgressBlock maxRMS:&maxRMSVal error:&err];
    }else{
        [self readFromFile:self.sourceAudioFile processWithBlock:self.myProcessingBlock andWriteToFile:self.tempResultAudioFile progressBlock:self.myProgressBlock maxRMS:NULL error:&err];
    }
    
    if (err) {
        return [self finishWithError:err];
    }
    
    self.measuredPeakOutputRMS = maxRMSVal;
    
    if (self.isCancelled) {
        return [self cleanup];
    }
    
    if (self.isPaused) {
        return;
    }
    
    if (!self.doNormalize) {
        self.channelNormalizedMaxRMS = 0.95/(Float32)(self.sourceFormat.channelCount);
        NSLog(@"MAX RMS: %f",self.measuredPeakOutputRMS);
        self.normalizeConstant = self.channelNormalizedMaxRMS/self.measuredPeakOutputRMS;
        NSLog(@"Normalize constant: %f",self.normalizeConstant);
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

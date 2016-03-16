//
//  OfflineAudioFile.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@interface OfflineAudioFileProcessor ()

@property (nonatomic,strong,readwrite)               NSString                           *sourceFilePath;
@property (nonatomic,strong)                         NSString                           *tempResultFilePath;
@property (nonatomic,strong,readwrite)               NSString                           *resultFilePath;

@property (nonatomic,strong)                         AVAudioFile                        *sourceAudioFile;
@property (nonatomic,strong)                         AVAudioFile                        *resultAudioFile;

@property (nonatomic,readwrite)                      NSUInteger                         maxBufferSize;
@property (nonatomic,readwrite)                      NSUInteger                         sourceSampleRate;
@property (nonatomic,readwrite)                      AVAudioFrameCount                  sourceLength;
@property (nonatomic,readwrite)                      AVAudioFramePosition               sourcePosition;
@property (nonatomic,readwrite)                      AVAudioFormat                      *sourceFormat;
@property (nonatomic,readwrite)                      AVAudioFrameCount                  numSourceFramesRemaining;
@property (nonatomic,readwrite)                      Float32                            maxSampleValue;


@property (nonatomic,readwrite)                      double                             progress;
@property (nonatomic,readwrite)                      bool                               normalize;

@property (nonatomic,readwrite,getter=isReady)       bool                               ready;
@property (nonatomic,readwrite,getter=isRunning)     bool                               running;
@property (nonatomic,readwrite,getter=isPaused)      bool                               paused;
@property (nonatomic,readwrite,getter=isDone)        bool                               done;
@property (nonatomic,readwrite,getter=isCancelled)   bool                               cancelled;

@property (nonatomic,strong,readwrite)               NSError                            *error;

@property (nonatomic,copy)                          AudioProcessingProgressBlock        myProgressBlock;
@property (nonatomic,copy)                          AudioProcessingCompletionBlock      myCompletionBlock;
@property (nonatomic,copy)                          AudioProcessingBlock                myProcessingBlock;


@end

@implementation OfflineAudioFileProcessor

Float32 GetMaxSampleValueInBuffer(AudioBufferList *bufferList, UInt32 bufferSize)
{
    Float32 *tempBuffer = (Float32 *)(malloc(sizeof(Float32)*bufferSize));
    UInt32 numChannels = (UInt32)(bufferList->mNumberBuffers);
    Float32 maxVal = 0;
    Float32 myMaxVal = 0;
    for (UInt32 i = 0; i < numChannels; i ++ ) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vabs(samples, 1, tempBuffer, 1, bufferSize);
        vDSP_vsort(tempBuffer, bufferSize, -1);
        maxVal = tempBuffer[0];
        myMaxVal = ( maxVal >= myMaxVal ) ? ( maxVal ) : ( myMaxVal );
    }
    
    free(tempBuffer);
    return myMaxVal;
}

OSStatus NormalizeBufferList(AudioBufferList *bufferList, UInt32 bufferSize, Float32 constant)
{
    UInt32 numChannels = (UInt32)(bufferList->mNumberBuffers);
    for (UInt32 i = 0; i < numChannels; i ++) {
        Float32 *samples = (Float32 *)(bufferList->mBuffers[i].mData);
        vDSP_vsmul(samples, 1, &constant, samples, 1, bufferSize);
    }
    return noErr;
}

+ (instancetype)processorWithSource:(NSString *)sourceFilePath
                          maxBuffer:(NSUInteger)maxBufferSize
                    processingBlock:(AudioProcessingBlock)processingBlock
                      progressBlock:(AudioProcessingProgressBlock)progressBlock
                    completionBlock:(AudioProcessingCompletionBlock)completionBlock
{
    OfflineAudioFileProcessor *processor = [[OfflineAudioFileProcessor alloc]initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
    [processor setProcessingBlock:processingBlock];
    [processor setProgressBlock:progressBlock];
    [processor setCompletionBlock:completionBlock];
    return processor;
}

+ (instancetype)processFile:(NSString *)sourceFilePath
        withAudioBufferSize:(NSUInteger)maxBufferSize
                    onQueue:(dispatch_queue_t)processingQueue
                   compress:(BOOL)compress
                     reverb:(BOOL)reverb
                  normalize:(BOOL)normalize
            progressHandler:(void(^)(double progress))progressHandler
          completionHandler:(void(^)(NSURL *fileURL, NSError *error))completionHandler

{
    OfflineAudioFileProcessor *processor = [[OfflineAudioFileProcessor alloc]initWithSourceFile:sourceFilePath maxBufferSize:maxBufferSize];
    [processor setProgressBlock:progressHandler];
    [processor setCompletionBlock:completionHandler];
    processor.normalize = normalize;
    
    AudioProcessingBlock reverbBlock = nil;
    AudioProcessingBlock compressionBlock = nil;
    if (reverb) {
        reverbBlock = [processor mediumReverbProcessingBlock];
    }
    if (compress) {
        compressionBlock = [processor vectorCompressionProcessingBlock];
    }
    
    [processor setProcessingBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
        if (reverbBlock) {
            reverbBlock(buffer,bufferSize);
        }
        if (compressionBlock) {
            compressionBlock(buffer,bufferSize);
        }
        
        return noErr;
    }];
    
    dispatch_sync(processingQueue, ^{
        [processor start];
    });
    
    return processor;
}

- (void)defaultInit
{
    _running = NO;
    _done = NO;
    _cancelled = NO;
    _progress = 0.0;
    _sourcePosition = 0;
    _maxSampleValue = 0.0;
    _numSourceFramesRemaining = 0;
    _error = nil;
    _normalize = NO;
    _resultFilePath = nil;
    _tempResultFilePath = nil;
    self.ready = [self getReady];
}

- (BOOL)getReady;
{
    self.error = [self startAudioSession];
    
    if (self.error) {
        return NO;
    }
    
    self.error = [self setupFiles];
    if (self.error) {
        return NO;
    }
    
    return YES;
}

- (NSError *)startAudioSession
{
    NSError *err = nil;
    [[AVAudioSession sharedInstance]setActive:YES error:&err];
    if (err) {
        return err;
    }

    [[AVAudioSession sharedInstance]setCategory:AVAudioSessionCategoryAudioProcessing error:&err];
    
    if (err) {
        return err;
    }
    
    [[AVAudioSession sharedInstance]setMode:AVAudioSessionModeDefault error:&err];
    
    return err;
}

- (void)stopAudioSession
{
    [[AVAudioSession sharedInstance]setActive:NO error:nil];
}

- (AVAudioFile *)destinationAudioFileForSource:(NSString *)sourceFilePath
{
    NSError *err = nil;
    NSURL *sourceFileURL = [NSURL fileURLWithPath:sourceFilePath];
    AVAudioFile *sourceAudioFile = [[AVAudioFile alloc]initForReading:sourceFileURL error:&err];
    if (err) {
        self.error = err;
        return nil;
    }
    
    NSString *sourceFileName = [sourceFilePath lastPathComponent];
    NSString *tempFilePath = [OfflineAudioFileProcessor tempFilePathForFile:sourceFileName];
    AVAudioFormat *sourceFormat = sourceAudioFile.processingFormat;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:tempFilePath]) {
        [fm removeItemAtPath:tempFilePath error:nil];
    }
    
    NSMutableDictionary *resultFileSettings = [NSMutableDictionary dictionary];
    resultFileSettings[AVSampleRateKey] = @(sourceFormat.sampleRate);
    resultFileSettings[AVNumberOfChannelsKey] = @(sourceFormat.channelCount);
    NSURL *resultFileURL = [NSURL fileURLWithPath:tempFilePath];
    BOOL interleaved = sourceFormat.interleaved;
    AVAudioCommonFormat commonFormat = sourceFormat.commonFormat;
    
    AVAudioFile *resultAudioFile = [[AVAudioFile alloc]initForWriting:resultFileURL
                                                     settings:resultFileSettings
                                                 commonFormat:commonFormat
                                                  interleaved:interleaved
                                                        error:&err];
    if (err) {
        self.error = err;
        return nil;
    }
    
    return resultAudioFile;
    
}

- (NSError *)setupFiles
{
    NSError *err = nil;
    NSURL *sourceFileURL = [NSURL fileURLWithPath:self.sourceFilePath];
    self.sourceAudioFile = [[AVAudioFile alloc]initForReading:sourceFileURL error:&err];
    if (err) {
        return err;
    }
    NSString *sourceFileName = [self.sourceFilePath lastPathComponent];
    self.tempResultFilePath = [OfflineAudioFileProcessor tempFilePathForFile:sourceFileName];
    self.sourceFormat = self.sourceAudioFile.processingFormat;
    self.sourceSampleRate = (NSUInteger)(self.sourceFormat.sampleRate);
    self.sourceLength = (AVAudioFrameCount)(self.sourceAudioFile.length);
    self.numSourceFramesRemaining = self.sourceLength;
    NSFileManager *fm = [NSFileManager defaultManager];
    
    if ([fm fileExistsAtPath:self.tempResultFilePath]) {
        [fm removeItemAtPath:self.tempResultFilePath error:nil];
    }
    
    NSMutableDictionary *resultFileSettings = [NSMutableDictionary dictionary];
    resultFileSettings[AVSampleRateKey] = @(self.sourceFormat.sampleRate);
    resultFileSettings[AVNumberOfChannelsKey] = @(self.sourceFormat.channelCount);
    NSURL *resultFileURL = [NSURL fileURLWithPath:self.tempResultFilePath];
    BOOL interleaved = self.sourceFormat.interleaved;
    AVAudioCommonFormat commonFormat = self.sourceFormat.commonFormat;
    
    self.resultAudioFile = [[AVAudioFile alloc]initForWriting:resultFileURL
                                                     settings:resultFileSettings
                                                 commonFormat:commonFormat
                                                  interleaved:interleaved
                                                        error:&err];
    
    return err;
}

- (void)deletePartialFiles
{
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:self.tempResultFilePath]) {
        [fm removeItemAtPath:self.tempResultFilePath error:nil];
    }
}

- (void)teardownFiles
{
    self.sourceAudioFile = nil;
    self.resultAudioFile = nil;
}

- (instancetype)initWithSourceFile:(NSString *)sourceFilePath maxBufferSize:(NSUInteger)maxBufferSize
{
    self = [super init];
    if (self) {
        _sourceFilePath = sourceFilePath;
        _maxBufferSize = maxBufferSize;
        [self defaultInit];
    }
    
    return self;
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

- (void)start
{
    if (!self.isReady) {
        self.myCompletionBlock(nil,self.error);
        return;
    }
    
    [self doProcessing];
}

- (void)doProcessing
{
    if (self.isCancelled) {
        return;
    }
    
    self.running = YES;
    AVAudioFrameCount numSourceFramesRemaining = self.numSourceFramesRemaining;
    self.sourcePosition = self.sourceAudioFile.framePosition;
    AVAudioFrameCount myMaxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFormat *mySourceFormat = self.sourceFormat;
    NSError *err = nil;
    
    while (numSourceFramesRemaining && !self.isCancelled && !self.isPaused ) {
        
        AVAudioFrameCount bufferSize = ( numSourceFramesRemaining >= myMaxBufferSize ) ? ( myMaxBufferSize ) : ( numSourceFramesRemaining );
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:mySourceFormat frameCapacity:bufferSize];
        
        [self.sourceAudioFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
        if (err) {
            break;
        }
        
        AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
        OSStatus status = self.myProcessingBlock(bufferList, bufferSize);
        
        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
            break;
        }
        
        [self.resultAudioFile writeFromBuffer:buffer error:&err];
        
        if (err) {
            break;
        }
        
        numSourceFramesRemaining-=bufferSize;
        self.numSourceFramesRemaining = numSourceFramesRemaining;
        self.sourcePosition = self.sourceAudioFile.framePosition;
        self.progress = (double)(self.sourcePosition)/(double)(self.sourceLength);
        
    }
    
    if (err) {
        self.error = err;
    }
    
    if (!self.isCancelled && !self.isPaused) {
        if (self.normalize) {
            [self.resultAudioFile setFramePosition:0];
            AVAudioPCMBuffer *resultBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:self.sourceFormat
                                                                          frameCapacity:self.sourceLength];
            NSError *normError = nil;
            [self.resultAudioFile readIntoBuffer:resultBuffer error:&normError];
            if (normError) {
                self.running = NO;
                self.done = YES;
                [self cleanup];
                self.myCompletionBlock(nil,normError);
            }else{
                NSString *tempFileName = [self.tempResultFilePath lastPathComponent];
                NSString *tempFilePath = [OfflineAudioFileProcessor tempFilePathForFile:tempFileName];
                AVAudioFile *tempAudioFile = [self destinationAudioFileForSource:self.tempResultFilePath];
                if (self.error) {
                    self.running = NO;
                    self.done = YES;
                    [self cleanup];
                    self.myCompletionBlock(nil,normError);
                }else{
                    AudioBufferList *toNormalize = (AudioBufferList *)resultBuffer.audioBufferList;
                    UInt32 numChannels = toNormalize->mNumberBuffers;
                    Float32 maxAllowedSampleVal = 1.0/(Float32)numChannels;
                    Float32 maxSamp = self.maxSampleValue;
                    Float32 normConstant = maxAllowedSampleVal/maxSamp;
                    NormalizeBufferList(toNormalize, (UInt32)tempAudioFile.length, normConstant);
                    [tempAudioFile writeFromBuffer:resultBuffer error:&normError];
                    
                    if (normError) {
                        self.error = normError;
                        self.running = NO;
                        self.done = YES;
                        [self cleanup];
                        self.myCompletionBlock(nil,normError);
                    }else{
                        self.error = nil;
                        self.resultFilePath = tempFilePath;
                        self.running = NO;
                        self.done = YES;
                        [self cleanup];
                        [[NSFileManager defaultManager]removeItemAtPath:self.tempResultFilePath error:nil];
                        self.myCompletionBlock([NSURL fileURLWithPath:self.resultFilePath], nil);
                    }
                }
            }
        }else{
            self.resultFilePath = self.tempResultFilePath;
            self.running = NO;
            self.done = YES;
            [self cleanup];
            self.myCompletionBlock([NSURL fileURLWithPath:self.resultFilePath],err);
        }
    }else if (self.isCancelled){
        [self cleanup];
        self.running = NO;
    }else if (self.isPaused){
        self.running = NO;
    }
}

- (void)setReady:(bool)ready
{
    _ready = ready;
}

- (void)setProgress:(double)progress
{
    _progress = progress;
    if (self.myProgressBlock) {
        self.myProgressBlock(progress);
    }
}

- (void)pause
{
    if (!self.isRunning) {
        return;
    }
    self.paused = YES;
}

- (void)resume
{
    if (!self.isPaused) {
        return;
    }
    
    self.paused = NO;
    [self doProcessing];
}

- (void)cancel
{
    if (!self.isRunning && !self.isPaused) {
        return;
    }
    
    self.cancelled = YES;
    if (self.isPaused) {
        self.paused = NO;
        [self cleanup];
    }
}

- (void)cleanup
{
    if (self.isCancelled || self.error) {
        [self deletePartialFiles];
    }
    if (self.freeverbNeedsCleanup){
        [self freeverbBlockCleanup];
    }
    
    
    [self stopAudioSession];
    [self teardownFiles];
}

- (void)dealloc
{
    _myCompletionBlock = nil;
    _myProcessingBlock = nil;
    _myProgressBlock = nil;
}

@end

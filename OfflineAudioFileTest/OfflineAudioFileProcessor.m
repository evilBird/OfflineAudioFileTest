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

@property (nonatomic,readwrite)                      double                             progress;
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
        maxVal = tempBuffer[1];
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

- (void)defaultInit
{
    _running = NO;
    _done = NO;
    _cancelled = NO;
    _progress = 0.0;
    _sourcePosition = 0;
    _error = nil;
    _resultFilePath = nil;
    _tempResultFilePath = nil;
    [self getReadyToRun];
}

- (void)getReadyToRun
{
    self.error = [self startAudioSession];
    if (self.error) {
        return;
    }
    
    self.error = [self setupFiles];
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
    if (self.error) {
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
    
    __weak OfflineAudioFileProcessor *weakself = self;
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        
        weakself.running = YES;
        weakself.progress = 0.0;
        AVAudioFrameCount numSourceFrames = weakself.sourceLength;
        AVAudioFrameCount numSourceFramesRemaining = numSourceFrames;
        weakself.sourceAudioFile.framePosition = 0;
        weakself.sourcePosition = weakself.sourceAudioFile.framePosition;
        AVAudioFrameCount myMaxBufferSize = (AVAudioFrameCount)weakself.maxBufferSize;
        AVAudioFormat *mySourceFormat = weakself.sourceFormat;
        NSError *err = nil;
        
        while (numSourceFramesRemaining && !weakself.isCancelled && !weakself.isPaused ) {
            
            AVAudioFrameCount bufferSize = ( numSourceFramesRemaining >= myMaxBufferSize ) ? ( myMaxBufferSize ) : ( numSourceFramesRemaining );
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:mySourceFormat frameCapacity:bufferSize];
            
            [weakself.sourceAudioFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
            if (err) {
                break;
            }

            AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
            OSStatus status = weakself.myProcessingBlock(bufferList, bufferSize);
            
            if (status!=noErr) {
                err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
                break;
            }
            
            [weakself.resultAudioFile writeFromBuffer:buffer error:&err];
            
            if (err) {
                break;
            }
            
            numSourceFramesRemaining-=bufferSize;
            weakself.numSourceFramesRemaining = numSourceFramesRemaining;
            weakself.sourcePosition = weakself.sourceAudioFile.framePosition;
            weakself.progress = (double)(weakself.sourcePosition)/(double)(weakself.sourceLength);
            
        }
        
        NSURL *resultURL = nil;
        
        if (err) {
            weakself.error = err;
        }else{
            weakself.resultFilePath = weakself.tempResultFilePath;
            resultURL = [NSURL fileURLWithPath:weakself.resultFilePath];
        }
        
        if (!weakself.isCancelled && !weakself.isPaused) {
            weakself.running = NO;
            weakself.done = YES;
            [weakself cleanup];
            weakself.myCompletionBlock(resultURL,err);
        }else if (weakself.isCancelled){
            [weakself cleanup];
            weakself.running = NO;
        }else if (weakself.isPaused){
            weakself.running = NO;
        }
        
    }];
    
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
    [self resumeProcessing];
}

- (void)resumeProcessing
{
    if (self.isCancelled) {
        return;
    }
    
    __weak OfflineAudioFileProcessor *weakself = self;
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        
        weakself.running = YES;
        AVAudioFrameCount numSourceFrames = weakself.sourceLength;
        AVAudioFrameCount numSourceFramesRemaining = weakself.numSourceFramesRemaining;
        AVAudioFrameCount myMaxBufferSize = (AVAudioFrameCount)weakself.maxBufferSize;
        AVAudioFormat *mySourceFormat = weakself.sourceFormat;
        NSError *err = nil;
        
        while (numSourceFramesRemaining && !weakself.isCancelled && !weakself.isPaused ) {
            
            AVAudioFrameCount bufferSize = ( numSourceFramesRemaining >= myMaxBufferSize ) ? ( myMaxBufferSize ) : ( numSourceFramesRemaining );
            AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:mySourceFormat frameCapacity:bufferSize];
            
            [weakself.sourceAudioFile readIntoBuffer:buffer frameCount:bufferSize error:&err];
            if (err) {
                break;
            }
            
            AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
            OSStatus status = weakself.myProcessingBlock(bufferList, bufferSize);
            
            if (status!=noErr) {
                err = [NSError errorWithDomain:@"OfflineAudioFileProcessor" code:status userInfo:nil];
                break;
            }
            
            [weakself.resultAudioFile writeFromBuffer:buffer error:&err];
            
            if (err) {
                break;
            }
            
            numSourceFramesRemaining-=bufferSize;
            weakself.numSourceFramesRemaining = numSourceFramesRemaining;
            weakself.sourcePosition = weakself.sourceAudioFile.framePosition;
            weakself.progress = (double)(weakself.sourcePosition)/(double)(weakself.sourceLength);
            
        }
        
        NSURL *resultURL = nil;
        
        if (err) {
            weakself.error = err;
        }else{
            weakself.resultFilePath = weakself.tempResultFilePath;
            resultURL = [NSURL fileURLWithPath:weakself.resultFilePath];
        }
        
        if (!weakself.isCancelled && !weakself.isPaused) {
            weakself.running = NO;
            weakself.done = YES;
            [weakself cleanup];
            weakself.myCompletionBlock(resultURL,err);
        }else if (weakself.isCancelled){
            [weakself cleanup];
            weakself.running = NO;
        }else if (weakself.isPaused){
            weakself.running = NO;
        }
        
    }];
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

//
//  SNDoubleFilePlayer.m
//  sonacadenza-iOS
//
//  Created by Travis Henspeter on 11/5/15.
//  Copyright © 2015 Sonation Inc. All rights reserved.
//

#import "SonaAudioFileMixPlayer.h"
#import "NSObject+AudioSessionManager.h"

@interface SonaAudioFileMixPlayer ()

@property (nonatomic)   BOOL    filePlayer1DidFinishPlayback;
@property (nonatomic)   BOOL    filePlayer2DidFinishPlayback;

@end


@implementation SonaAudioFileMixPlayer


- (instancetype)initWithFile:(NSString *)filePath delegate:(id<SonaAudioFileMixPlayerDelegate>)delegate
{
    return [self initWithFile1:filePath file2:nil delegate:delegate];
}

- (instancetype)initWithFile1:(NSString *)file1Path file2:(NSString *)file2Path delegate:(id<SonaAudioFileMixPlayerDelegate>)delegate
{
    self = [super init];
    if (self) {
        _delegate = delegate;
        _filePlayer1DidFinishPlayback = NO;
        _filePlayer2DidFinishPlayback = NO;
        [self initWithPath1:file1Path path2:file2Path];
    }
    return self;
}

- (void)initWithPath1:(NSString *)filePath1 path2:(NSString *)filePath2
{
    __weak SonaAudioFileMixPlayer *weakself = self;
    [self setupEngineWithFile:filePath1 andFile:filePath2 completion:^(NSError *error) {
        if (nil == error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakself.delegate audioFileMixPlayerFinishedLoading:weakself];
            });
        }else{
            dispatch_async(dispatch_get_main_queue(), ^{
                [weakself.delegate audioFileMixPlayer:weakself didFailWithError:error];
            });
        }
    }];
}

- (void)startPlaybackAudioSessionError:(NSError *__autoreleasing *)error
{
    __weak SonaAudioFileMixPlayer *weakself = self;
    NSError *err = nil;
    
    [self startDefaultAudioSessionWithCategory:AVAudioSessionCategoryPlayback
                                onInterruption:^(AVAudioSessionInterruptionType type, AVAudioSessionInterruptionOptions shouldResume) {
                                    
                                    bool wasPlaying = weakself.isPlaying;
                                    if (type == AVAudioSessionInterruptionTypeBegan) {
                                        NSLog(@"Session Interruption");
                                        if (wasPlaying) {
                                            [weakself stop];
                                        }

                                    }else{
                                        NSLog(@"Session interruption ended");
                                        if (shouldResume && wasPlaying) {
                                            [weakself play];
                                        }
                                    }
                                }
                               onBackgrounding:^(BOOL isBackgrounded, BOOL wasBackgrounded){
                                   if (isBackgrounded) {
                                       NSLog(@"entering background");
                                   }else{
                                       NSLog(@"exiting background");
                                   }
                               }
                                         error:&err];
    if (err) {
        if (error) {
            *error = err;
        }
    }
}

- (void)stopAudioSession
{
    
    if (self.player1.isPlaying) {
        [self.player1 stop];
    }
    if (self.player2.isPlaying) {
        [self.player2 stop];
    }
    if (_playing) {
        _playing = NO;
    }
    if (self.engine.isRunning) {
        [self.engine pause];
    }
    
    [self.engine stop];
    
    AVAudioSession *session = [AVAudioSession sharedInstance];
    [session setActive:NO error:nil];
}


- (void)setupEngineWithFile:(NSString *)file1Path andFile:(NSString *)file2Path completion:(void(^)(NSError *error))completion
{
    NSError *err = nil;
    [self startPlaybackAudioSessionError:&err];
    if (err) {
        return completion(err);
    }
    
    self.engine = [[AVAudioEngine alloc]init];
    AVAudioMixerNode *mainMixer = [self.engine mainMixerNode];
    double file1Length = 0.0;
    double file2Length = 0.0;

    if (file1Path) {
        
        self.player1 = [[AVAudioPlayerNode alloc]init];
        [self.engine attachNode:self.player1];
        NSURL *file1URL = [NSURL fileURLWithPath:file1Path];
        self.audioFile1 = [[AVAudioFile alloc]initForReading:file1URL error:&err];
        
        if ( err ) {
            completion(err);
            return;
        }
        
        self.timePitch1 = [[AVAudioUnitTimePitch alloc]init];
        self.timePitch1.rate = 1.0;
        self.timePitch1.pitch = 0.0;
        [self.engine attachNode:self.timePitch1];
        
        [self.engine connect:self.player1
                          to:self.timePitch1
                      format:self.audioFile1.processingFormat];
        
        [self.engine connect:self.timePitch1 to:mainMixer fromBus:0 toBus:mainMixer.nextAvailableInputBus format:self.audioFile1.processingFormat];
        
        file1Length = self.audioFile1.length/(double)self.audioFile1.processingFormat.sampleRate;
    }

    if (file2Path) {
        
        self.player2 = [[AVAudioPlayerNode alloc]init];
        [self.engine attachNode:self.player2];
        
        
        NSURL *file2URL = [NSURL fileURLWithPath:file2Path];
        self.audioFile2 = [[AVAudioFile alloc]initForReading:file2URL error:&err];
        
        if ( nil != err ) {
            completion(err);
            return;
        }
        
        
        
        self.timePitch2 = [[AVAudioUnitTimePitch alloc]init];
        self.timePitch2.rate = 1.0;
        self.timePitch2.pitch = 0.0;
        [self.engine attachNode:self.timePitch2];
        
        
        [self.engine connect:self.player2
                          to:self.timePitch2
                      format:self.audioFile2.processingFormat];
        [self.engine connect:self.timePitch2 to:mainMixer fromBus:0 toBus:mainMixer.nextAvailableInputBus format:self.audioFile2.processingFormat];
        
        file2Length = self.audioFile2.length/(double)self.audioFile2.processingFormat.sampleRate;
    }
    
    self.duration = ( file1Length >= file2Length ) ? ( file1Length ) : ( file2Length );
    
    [self.engine prepare];
    [self.engine startAndReturnError:&err];
    completion(err);
}

- (void)play
{
    [self playFromTime:0.0];
}

- (void)playFromTime:(NSTimeInterval)time
{
    __weak SonaAudioFileMixPlayer *weakself = self;
    [self seekToTime:time completion:^(NSError *error) {
        if (error) {
            NSLog(@"ERROR: %@",error.debugDescription);
        }else{
            weakself.filePlayer1DidFinishPlayback = NO;
            weakself.filePlayer2DidFinishPlayback = NO;
            [weakself.player1 play];
            [weakself.player2 play];
            weakself.playing = YES;
        }
    }];
}

- (void)stop
{
    [self.player1 stop];
    [self.player2 stop];
    self.playing = NO;
}

- (void)adjustPitch:(double)cents
{
    self.timePitch1.pitch = cents;
    self.timePitch2.pitch = cents;
}

- (void)adjustTempo:(double)percent
{
    self.timePitch1.rate = percent;
    self.timePitch2.rate = percent;
}

- (void)seekToTime:(NSTimeInterval)time
{
    BOOL wasPlaying = NO;
    if (self.isPlaying) {
        wasPlaying = YES;
    }
    
    __weak SonaAudioFileMixPlayer *weakself = self;
    [self seekToTime:time completion:^(NSError *error) {
        if (error) {
            [weakself.delegate audioFileMixPlayer:weakself didFailWithError:error];
        }else{
            if (wasPlaying) {
                [weakself.player1 play];
                [weakself.player2 play];
                weakself.playing = YES;
            }
        }
    }];
}

- (void)seekToTime:(NSTimeInterval)time completion:(void(^)(NSError *error))completion
{

    __weak SonaAudioFileMixPlayer *weakself = self;
    NSError *err = nil;

    if (self.audioFile1) {
        
        AVAudioFrameCount totalFrames1 = (AVAudioFrameCount)self.audioFile1.length;
        AVAudioFramePosition offset1 = time*self.audioFile1.fileFormat.sampleRate;
        
        if (self.player1.isPlaying) {
            [self.player1 stop];
        }
        
        self.buffer1 = [[AVAudioPCMBuffer alloc]initWithPCMFormat:self.audioFile1.processingFormat frameCapacity:totalFrames1];
        
        self.audioFile1.framePosition = offset1;
        [self.audioFile1 readIntoBuffer:self.buffer1 error:&err];
        
        [self.player1 scheduleBuffer:self.buffer1 atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                weakself.filePlayer1DidFinishPlayback = YES;
                [weakself checkPlaybackIsFinished];
            });
        }];
        
    }
    
    
    if (self.audioFile2) {
        
        AVAudioFrameCount totalFrames2 = (AVAudioFrameCount)self.audioFile2.length;
        AVAudioFramePosition offset2 = time*self.audioFile2.fileFormat.sampleRate;
        
        if (self.player2.isPlaying) {
            [self.player2 stop];
        }
        self.buffer2 = [[AVAudioPCMBuffer alloc]initWithPCMFormat:self.audioFile2.processingFormat frameCapacity:totalFrames2];
        
        self.audioFile2.framePosition = offset2;
        [self.audioFile2 readIntoBuffer:self.buffer2 error:&err];
        
        
        [self.player2 scheduleBuffer:self.buffer2 atTime:nil options:AVAudioPlayerNodeBufferInterrupts completionHandler:^{
            dispatch_async(dispatch_get_main_queue(), ^{
                weakself.filePlayer2DidFinishPlayback = YES;
                [weakself checkPlaybackIsFinished];
            });
        }];
    }


    if ( self.engine.isRunning == NO ) {
        [self.engine prepare];
        [self.engine startAndReturnError:&err];
    }
    
    return completion(err);
}

- (void)checkPlaybackIsFinished
{
    if (nil!=self.player1 && nil==self.player2) {
        self.filePlayer2DidFinishPlayback = YES;
    }
    
    if ((self.filePlayer1DidFinishPlayback && self.filePlayer2DidFinishPlayback)) {
        if ( self.delegate ) {
            [self.delegate audioFileMixPlayerFinishedPlayback:self];
        }
    }
}

- (void)dealloc
{
    _delegate = nil;
    [self stopAudioSession];
    _buffer1 = nil;
    _buffer2 = nil;
    _player1 = nil;
    _player2 = nil;
    _timePitch1 = nil;
    _timePitch2 = nil;
    _audioFile1 = nil;
    _audioFile2 = nil;
    _engine = nil;
}

@end

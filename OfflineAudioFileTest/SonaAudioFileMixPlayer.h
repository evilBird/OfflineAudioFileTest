//
//  SNDoubleFilePlayer.h
//  sonacadenza-iOS
//
//  Created by Travis Henspeter on 11/5/15.
//  Copyright © 2015 Sonation Inc. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>

@protocol SonaAudioFileMixPlayerDelegate <NSObject>

- (void)audioFileMixPlayer:(id)sender didFailWithError:(NSError *)error;
- (void)audioFileMixPlayerFinishedLoading:(id)sender;

@optional

- (void)audioFileMixPlayerFinishedPlayback:(id)sender;

@end

@interface SonaAudioFileMixPlayer : NSObject


@property (nonatomic,weak)                  id<SonaAudioFileMixPlayerDelegate>          delegate;
@property (nonatomic,getter=isPlaying)      BOOL                                        playing;

@property (nonatomic)                       AVAudioFile                                 *audioFile1;
@property (nonatomic,strong)                AVAudioFile                                 *audioFile2;

@property (nonatomic,strong)                NSURL                                       *fileURL1;
@property (nonatomic,strong)                NSURL                                       *fileURL2;

@property (nonatomic,strong)                AVAudioUnitTimePitch                        *timePitch1;
@property (nonatomic,strong)                AVAudioUnitTimePitch                        *timePitch2;

@property (nonatomic,strong)                AVAudioPlayerNode                           *player1;
@property (nonatomic,strong)                AVAudioPlayerNode                           *player2;

@property (nonatomic,strong)                AVAudioPCMBuffer                            *buffer1;
@property (nonatomic,strong)                AVAudioPCMBuffer                            *buffer2;

@property (nonatomic)                       NSTimeInterval                              duration;
@property (nonatomic,strong)                AVAudioEngine                               *engine;


- (instancetype)initWithFile:(NSString *)filePath delegate:(id<SonaAudioFileMixPlayerDelegate>)delegate;
- (instancetype)initWithFile1:(NSString *)file1Path file2:(NSString *)file2Path delegate:(id<SonaAudioFileMixPlayerDelegate>)delegate;

- (void)play;
- (void)playFromTime:(NSTimeInterval)time;
- (void)stop;
- (void)adjustPitch:(double)cents;
- (void)adjustTempo:(double)percent;
- (void)seekToTime:(NSTimeInterval)time;

@end

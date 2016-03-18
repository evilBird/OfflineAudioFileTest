//
//  OfflineAudioFileProcessor+Functions.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/17/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor.h"

@interface OfflineAudioFileProcessor (Functions)

AudioBufferList* CreateAudioBufferList(AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize);
OSStatus ResizeAudioBufferList(AudioBufferList *bufferList, AVAudioFormat *audioFormat, AVAudioFrameCount maxBufferSize);
OSStatus CopyMonoAudioBufferListToStereo(AudioBufferList *stereoBufferList, AudioBufferList *monoBufferList, AVAudioFrameCount bufferSize);
void PrintAudioBufferList(AudioBufferList *bufferList, AVAudioFrameCount bufferSize, const char *tag);
void ClearAudioBufferList(AudioBufferList *bufferList);
void FreeAudioBufferList(AudioBufferList *bufferList);

@end

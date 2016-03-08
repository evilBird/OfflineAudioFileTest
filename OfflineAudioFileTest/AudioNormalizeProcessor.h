//
//  AudioNormalizeProcessor.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

@interface AudioNormalizeProcessor : NSObject

- (OSStatus)processBuffer:(AudioBufferList *)bufferList withSize:(NSUInteger)bufferSize;

@end

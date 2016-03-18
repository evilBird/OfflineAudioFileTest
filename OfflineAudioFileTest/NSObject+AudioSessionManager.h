//
//  NSObject+AudioSessionManager.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/18/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

typedef void (^AudioSessionNotificationHandler)(NSNotification *note);
typedef void (^AudioSessionInterruptionHandler)(AVAudioSessionInterruptionType type, AVAudioSessionInterruptionOptions shouldResume);
typedef void (^AudioSessionRouteChangeHandler)(AVAudioSessionRouteChangeReason reason, AVAudioSessionRouteDescription *currentRoute, AVAudioSessionSilenceSecondaryAudioHintType hintType);
typedef void (^AudioSessionServicesResetHandler)(AVAudioSession *session);
typedef NSError* (^AudioSessionConfigurationBlock)(AVAudioSession *session);
typedef void (^AudioSessionBackgroundingHandler)(BOOL isBackgrounded, BOOL wasBackgrounded);

@interface NSObject (AudioSessionManager)

- (void)startAudioSessionWithCategory:(NSString *)sessionCategory
                              options:(AVAudioSessionCategoryOptions)options
                                 mode:(NSString *)sessionMode
                   configureWithBlock:(AudioSessionConfigurationBlock)sessionConfigurationBlock
                       onInterruption:(AudioSessionInterruptionHandler)interruptionHandler
                        onRouteChange:(AudioSessionRouteChangeHandler)routeChangeHandler
                      onBackgrounding:(AudioSessionBackgroundingHandler)backgroundingHandler
                              onReset:(AudioSessionServicesResetHandler)resetHandler
                                error:(NSError *__autoreleasing *)error;

- (void)startDefaultAudioSessionWithCategory:(NSString *)sessionCategory
                              onInterruption:(AudioSessionInterruptionHandler)interruptionHandler
                             onBackgrounding:(AudioSessionBackgroundingHandler)backgroundingHandler
                                       error:(NSError *__autoreleasing *)error;

- (void)stopAudioSession:(NSError * __autoreleasing *)error;

@end

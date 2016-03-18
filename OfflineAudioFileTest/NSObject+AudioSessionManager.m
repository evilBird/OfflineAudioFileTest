//
//  NSObject+AudioSessionManager.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/18/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "NSObject+AudioSessionManager.h"

@implementation NSObject (AudioSessionManager)

- (void)startDefaultAudioSessionWithCategory:(NSString *)sessionCategory
                              onInterruption:(AudioSessionInterruptionHandler)interruptionHandler
                             onBackgrounding:(AudioSessionBackgroundingHandler)backgroundingHandler
                                       error:(NSError *__autoreleasing *)error
{
    return [self startAudioSessionWithCategory:sessionCategory options:0 mode:AVAudioSessionModeDefault configureWithBlock:nil onInterruption:interruptionHandler onRouteChange:nil onBackgrounding:backgroundingHandler onReset:nil error:error];
}

- (void)startAudioSessionWithCategory:(NSString *)sessionCategory
                              options:(AVAudioSessionCategoryOptions)options
                                 mode:(NSString *)sessionMode
                   configureWithBlock:(AudioSessionConfigurationBlock)sessionConfigurationBlock
                       onInterruption:(AudioSessionInterruptionHandler)interruptionHandler
                        onRouteChange:(AudioSessionRouteChangeHandler)routeChangeHandler
                      onBackgrounding:(AudioSessionBackgroundingHandler)backgroundingHandler
                              onReset:(AudioSessionServicesResetHandler)resetHandler
                                error:(NSError *__autoreleasing *)error
{
    NSError *err = nil;
    AVAudioSession *session = [AVAudioSession sharedInstance];
    
    [session setCategory:sessionCategory withOptions:options error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return;
    }
    
    [session setMode:sessionMode error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return;
    }
    
    
    if (sessionConfigurationBlock) {
        err = sessionConfigurationBlock(session);
        
        if (err) {
            if (error) {
                *error = err;
            }
            return;
        }
    }
    
    [session setActive:YES error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
    }
    
    if (interruptionHandler) {
        [self setNotificationHandler:[self notificationHandlerWithInterruptionHandler:[interruptionHandler copy]] forName:AVAudioSessionInterruptionNotification object:session];
    }
    
    if (routeChangeHandler) {
        [self setNotificationHandler:[self notificationHandlerWithRouteChangeHandler:[routeChangeHandler copy]] forName:AVAudioSessionRouteChangeNotification object:session];
    }
    
    if (backgroundingHandler) {
        [self setNotificationHandler:[self notificationHandlerWithBackgroundingHandler:[backgroundingHandler copy]] forName:UIApplicationDidEnterBackgroundNotification object:session];
        [self setNotificationHandler:[self notificationHandlerWithBackgroundingHandler:[backgroundingHandler copy]] forName:UIApplicationWillEnterForegroundNotification object:session];
    }
    
    if (resetHandler) {
        [self setNotificationHandler:[self notificationHandlerWithAudioSessionServicesResetHandler:[resetHandler copy]] forName:AVAudioSessionMediaServicesWereResetNotification object:session];
    }
}

- (void)setNotificationHandler:(void(^)(NSNotification *note))handler forName:(NSString *)notificationName object:(id)object
{
    NSNotificationCenter *notificationCenter = [NSNotificationCenter defaultCenter];
    [notificationCenter
     addObserverForName:notificationName
     object:object
     queue:[NSOperationQueue currentQueue]
     usingBlock:[handler copy]];
}

- (AudioSessionNotificationHandler)notificationHandlerWithInterruptionHandler:(AudioSessionInterruptionHandler)interruptionHandler
{
    AudioSessionNotificationHandler notificationHandler = ^(NSNotification *note){
        NSDictionary *info = note.userInfo;
        NSNumber *typeObject = info[AVAudioSessionInterruptionTypeKey];
        AVAudioSessionInterruptionType type = (AVAudioSessionInterruptionType)[typeObject unsignedIntegerValue];
        if (type == AVAudioSessionInterruptionTypeBegan) {
            interruptionHandler(type, 0);
        }
        
        NSNumber *optionObject = info[AVAudioSessionInterruptionOptionKey];
        AVAudioSessionInterruptionOptions resume = (AVAudioSessionInterruptionOptions)[optionObject unsignedIntegerValue];
        interruptionHandler(type, resume);
    };
    
    return [notificationHandler copy];
}

- (AudioSessionNotificationHandler)notificationHandlerWithRouteChangeHandler:(AudioSessionRouteChangeHandler)routeChangeHandler
{
    AudioSessionNotificationHandler notificationHandler = ^(NSNotification *note){
        NSDictionary *info = note.userInfo;
        NSNumber *reasonObject = info[AVAudioSessionRouteChangeReasonKey];
        AVAudioSessionRouteChangeReason reason = (AVAudioSessionRouteChangeReason)[reasonObject unsignedIntegerValue];
        NSNumber *hintObject = info[AVAudioSessionSilenceSecondaryAudioHintTypeKey];
        AVAudioSessionSilenceSecondaryAudioHintType hintType = (AVAudioSessionSilenceSecondaryAudioHintType)[hintObject unsignedIntegerValue];
        AVAudioSession *session = note.object;
        AVAudioSessionRouteDescription *currentRoute = session.currentRoute;
        routeChangeHandler(reason,currentRoute,hintType);
    };
    
    return [notificationHandler copy];
}

- (AudioSessionNotificationHandler)notificationHandlerWithAudioSessionServicesResetHandler:(AudioSessionServicesResetHandler)resetHandler
{
    AudioSessionNotificationHandler notificationHandler = ^(NSNotification *note){
        AVAudioSession *session = note.object;
        resetHandler(session);
    };
    
    return [notificationHandler copy];
}

- (AudioSessionNotificationHandler)notificationHandlerWithBackgroundingHandler:(AudioSessionBackgroundingHandler)backgroundingHandler
{
    AudioSessionNotificationHandler notificationHandler = ^(NSNotification *note){
        NSString *name = note.name;
        BOOL isBackgrounded,wasBackgrounded;
        if ([name isEqualToString:UIApplicationDidEnterBackgroundNotification]) {
            isBackgrounded = YES;
            wasBackgrounded = NO;
        }else if ([name isEqualToString:UIApplicationWillEnterForegroundNotification]){
            isBackgrounded = NO;
            wasBackgrounded = YES;
        }
        
        backgroundingHandler(isBackgrounded,wasBackgrounded);
    };
    
    return [notificationHandler copy];
}

- (void)stopAudioSession:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    
    [[NSNotificationCenter defaultCenter]removeObserver:self];
    
    [[AVAudioSession sharedInstance]setActive:NO error:&err];
    
    if (err) {
        if (error) {
            *error = err;
        }
        return;
    }
    
}

@end

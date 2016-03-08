//
//  ViewController.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "ViewController.h"
#import "OfflineAudioFileProcessor.h"
#import "AudioNormalizeProcessor.h"

@interface ViewController ()

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    
    AudioNormalizeProcessor *normalizer = [AudioNormalizeProcessor new];
    
    [OfflineAudioFileProcessor
     processFile:[OfflineAudioFileProcessor testSourceFilePath]
     withBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {

         Float32 *samples = buffer->mBuffers[0].mData;
         [normalizer processBuffer:buffer withSize:(NSUInteger)bufferSize];
         return noErr;
     }
     maxBufferSize:2048
     resultPath:[OfflineAudioFileProcessor testResultPath]
     completion:^(NSString *resultPath, NSError *error) {
         NSAssert(nil==error, @"ERROR: %@",error);
         NSLog(@"Finished writing audio file to path: %@",resultPath);
     }];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

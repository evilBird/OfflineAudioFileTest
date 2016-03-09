//
//  ViewController.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "ViewController.h"
#import "OfflineAudioFileProcessor.h"
#import "AudioSpectrumProcessor.h"

@interface ViewController (){
    NSUInteger kSampleRate;
    AVAudioFrameCount kBlockSize;
}

@end

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [self testStuff];
    // Do any additional setup after loading the view, typically from a nib.
}

- (void)testStuff
{
    NSString *testFilePath = [OfflineAudioFileProcessor testSourceFilePathForFile:[OfflineAudioFileProcessor testAccompFileName]];
    
    [OfflineAudioFileProcessor doDefaultProcessingWithSourceFile:testFilePath onProgress:^(double progress) {
        NSLog(@"Offline file processor made progress: %.3f",progress);
    } onSuccess:^(NSURL *resultFile) {
        NSLog(@"Offline file processor finished writing to path: %@",resultFile.path);
    } onFailure:^(NSError *error) {
        NSLog(@"Offline file processor failed with error: %@",error);
    }];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

@end

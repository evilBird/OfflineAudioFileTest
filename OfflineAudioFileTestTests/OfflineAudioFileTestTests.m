//
//  OfflineAudioFileTestTests.m
//  OfflineAudioFileTestTests
//
//  Created by Travis Henspeter on 3/7/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <XCTest/XCTest.h>
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>

@interface OfflineAudioFileTestTests : XCTestCase

@end

@implementation OfflineAudioFileTestTests

- (void)setUp {
    [super setUp];
    // Put setup code here. This method is called before the invocation of each test method in the class.
}

- (void)tearDown {
    // Put teardown code here. This method is called after the invocation of each test method in the class.
    [super tearDown];
}


- (void)testFunctions
{
    


    
    /*
    Float32 err1 = interval_duple_likelihood(101.0, 53.0);
    Float32 err2 = interval_duple_likelihood(102.0, 24.0);
    Float32 err3 = interval_duple_likelihood(99.0, 12.5);
    Float32 err4 = interval_duple_likelihood(50.0, 100.0);
    Float32 err5 = interval_duple_likelihood(25.0, 100.0);
    Float32 err6 = interval_duple_likelihood(14.5, 100.0);
    
    Float32 err7 = interval_triple_likelihood(100.0, 33.3);
    Float32 err8 = interval_triple_likelihood(33.3, 100.0);
    Float32 err9 = interval_triple_likelihood(66.6, 33.3);
    Float32 err10 = interval_triple_likelihood(103.0, 35.0);
    Float32 err11 = interval_triple_likelihood(32.0, 98.0);
     */
    
}


- (void)testExample {
    
    NSString *path = [[NSBundle bundleForClass:[self class]]pathForResource:@"faure_sicilienne_violin.48o" ofType:@"wav"];
    XCTAssert(nil!=path);
    NSURL *url = [NSURL fileURLWithPath:path];
    Float32 maxAmplitude = [self getMaxAmplitudeForFile:url];
    NSLog(@"max amplitude = %@",@(maxAmplitude));
    // This is an example of a functional test case.
    // Use XCTAssert and related functions to verify your tests produce the correct results.
}

- (Float32)getMaxAmplitudeForFile:(NSURL *)fileURL
{
    NSError *err = nil;
    AVAudioFile *file = [[AVAudioFile alloc]initForReading:fileURL error:&err];
    XCTAssert(nil==err);
    XCTAssert(nil!=file);
    AVAudioFrameCount numSourceFrames = (AVAudioFrameCount)file.length;
    XCTAssert(numSourceFrames>0);
    AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:file.processingFormat frameCapacity:numSourceFrames];
    XCTAssert(nil!=buffer);
    [file readIntoBuffer:buffer error:&err];
    XCTAssert(nil==err);
    AudioBufferList *bufferList = (AudioBufferList *)buffer.audioBufferList;
    Float32 *samples = (Float32 *)(bufferList->mBuffers[0].mData);
    Float32 *tempBuffer = (Float32 *)malloc(sizeof(Float32) * (UInt32)numSourceFrames);
    memset(tempBuffer, 0, sizeof(Float32) * (UInt32)numSourceFrames);
    vDSP_vabs(samples, 1, tempBuffer, 1, numSourceFrames);
    vDSP_vsort(tempBuffer, numSourceFrames, -1);
    Float32 maxSamp = tempBuffer[0];
    XCTAssert(maxSamp!=0.0);
    free(tempBuffer);
    return maxSamp;
}

- (void)testPerformanceExample {
    // This is an example of a performance test case.
    NSString *path = [[NSBundle bundleForClass:[self class]]pathForResource:@"faure_sicilienne_violin.48o" ofType:@"wav"];
    XCTAssert(nil!=path);
    NSURL *url = [NSURL fileURLWithPath:path];
    [self measureBlock:^{
        // Put the code you want to measure the time of here.
        Float32 maxAmplitude = [self getMaxAmplitudeForFile:url];
        NSLog(@"max amplitude = %@",@(maxAmplitude));
    }];
}

@end

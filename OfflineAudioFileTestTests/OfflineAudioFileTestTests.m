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
#import "OfflineAudioFileProcessor+Functions.h"
#import "OfflineAudioFileProcessor+Analysis.h"
#import "TempoDetectionTree.h"
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

- (void)testTempoDetection
{
    XCTestExpectation *expectation = [self expectationWithDescription:@"tempo will be detected"];
    NSString *filePath = [self doIWannaKnowFilePath];
    
    [OfflineAudioFileProcessor detectBPMOfFile:filePath allowedRange:NSRangeFromString(@"30, 180") onProgress:nil onSuccess:^(Float32 detectedTempo) {
        [expectation fulfill];
        NSLog(@"SUCCES: %f",detectedTempo);
    } onFailure:^(NSError *error) {
        [expectation fulfill];
        XCTFail(@"FAILED WITH ERROR: %@",error);
    }];
    
    [self waitForExpectationsWithTimeout:180.0 handler:^(NSError * _Nullable error) {
        if (error) {
            XCTFail(@"FAILED WITH ERROR: %@",error);
        }
    }];
}

- (NSString *)floriDadaFilePath
{
    NSString *fileName = @"FloriDada.wav";
    return [self bundlePathForFile:fileName];
}

- (NSString *)doIWannaKnowFilePath
{
    NSString *fileName = @"Do I Wanna Know.wav";
    return [self bundlePathForFile:fileName];
}

- (NSString *)americanSteelFilePath
{
    NSString *fileName = @"Got a Backbeat.wav";
    return [self bundlePathForFile:fileName];
}

- (NSString *)bundlePathForFile:(NSString *)fileName
{
    NSString *path = [[NSBundle mainBundle]pathForResource:fileName ofType:nil];
    NSParameterAssert(path);
    return path;
}

- (void)doComparisonBeat1:(Float32)beat1_length beat2:(Float32)beat2_length
{
    Float32 duple_ratio;
    Float32 duple_error = compare_beats_as_duples_get_error(beat1_length, beat2_length, &duple_ratio);
    Float32 tuple_ratio;
    Float32 tuple_error = compare_beats_as_tuples_get_error(beat1_length, beat2_length, &tuple_ratio);
    NSLog(@"\n\nComparison of Beat 1 ( %.3fs ) & Beat 2 ( %.3fs ): e(duple) = %.5f, r(duple) = %.3f, e(tuple) = %.5f, r(tuple) = %.3f\n\n",beat1_length,beat2_length,duple_error,duple_ratio,tuple_error,tuple_ratio);
}

- (void)compareBeat:(Float32)beat1_length toBeat:(Float32)beat2_length
{
    [self doComparisonBeat1:beat1_length beat2:beat2_length];
}

- (Float32 *)noteLengthsWithTempo:(Float32)tempo
{
    Float32 kTempo = tempo;
    Float32 kSecondsPerMinute = 60.0;
    Float32 kQuarternote = kSecondsPerMinute*1000.0/kTempo;
    
    Float32 kDottedQuarterNote = kQuarternote * 1.5;
    Float32 kHalfNote = kQuarternote*2.;
    Float32 kDottedHalfNote = kHalfNote*1.5;
    Float32 kWholeNote = kHalfNote*2.;
    Float32 kEighthNote = kQuarternote/2.;
    Float32 kDottedEighthNote = kEighthNote * 1.5;
    Float32 kSixteenthNote = kEighthNote/2.;
    Float32 kDottedSixteenthNote = kSixteenthNote * 1.5;
    Float32 kThirtySecondNote = kSixteenthNote/2.;
    Float32 kDottedThirtySecondNote = kThirtySecondNote * 1.5;
    Float32 kTriplet = kWholeNote/3.;
    Float32 kSixthNote = kHalfNote/3.;
    Float32 kTwelthNote = kQuarternote/3.;
    Float32 kTwentyFourthNote = kEighthNote/3.;
    
    Float32 *noteLengths = (Float32 *)malloc(sizeof(Float32) * 16);
    
    noteLengths[0] = kThirtySecondNote;
    noteLengths[1] = kDottedThirtySecondNote;
    noteLengths[2] = kTwentyFourthNote;
    noteLengths[3] = kSixteenthNote;
    noteLengths[4] = kDottedSixteenthNote;
    noteLengths[5] = kTwelthNote;
    noteLengths[6] = kEighthNote;
    noteLengths[7] = kDottedEighthNote;
    noteLengths[8] = kSixthNote;
    noteLengths[9] = kQuarternote;
    noteLengths[10] = kDottedQuarterNote;
    noteLengths[11] = kTriplet;
    noteLengths[12] = kHalfNote;
    noteLengths[13] = kDottedHalfNote;
    noteLengths[14] = kWholeNote;
    
    return noteLengths;
}

- (Float32 *)jitterBeats:(Float32 *)beats withTempo:(Float32)tempo amount:(Float32)amount count:(UInt32)count
{
    Float32 secsPerBeat = 60000.0/tempo;
    Float32 jitterMax = secsPerBeat*amount;
    Float32 jitterMin = -jitterMax;
    Float32 jitterRange = jitterMax-jitterMin;
    
    for (UInt32 i = 0; i < count; i ++) {
        Float32 norm = (Float32)arc4random_uniform(1000.0)*0.001;
        Float32 jitter = jitterMin + (norm * jitterRange);
        beats[i] += jitter;
    }
    
    return beats;
}

- (void)testBeatComparisons
{
    Float32 tolerance = 0.05;
    TempoDetectionNode *node1 = [TempoDetectionNode new];
    node1.tolerance = tolerance;
    TempoDetectionNode *node2 = [TempoDetectionNode new];
    node2.tolerance = tolerance;
    TempoDetectionNode *node3 = [TempoDetectionNode new];
    node3.tolerance = tolerance;
    TempoDetectionNode *node4 = [TempoDetectionNode new];
    node4.tolerance = tolerance;
    TempoDetectionNode *node5 = [TempoDetectionNode new];
    node5.tolerance = tolerance;
    TempoDetectionNode *node6 = [TempoDetectionNode new];
    node6.tolerance = tolerance;
    TempoDetectionNode *node7 = [TempoDetectionNode new];
    node7.tolerance = tolerance;
    
    node1.interval = 0.10;
    node2.interval = 0.025;
    node3.interval = 0.05;
    node4.interval = 0.033;
    node5.interval = 0.0166;
    node6.interval = 0.075;
    node7.interval = 0.0666;
    
    BOOL result = NO;
    
    result = [node7 isDoubleTupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node6 isDottedDupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node2 isDupleOfNode:node1];
    XCTAssert(result==NO);
    result = [node3 isDupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node2 canBeDupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node4 isDupleOfNode:node1];
    XCTAssert(result==NO);
    result = [node4 isTupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node5 isTupleOfNode:node1];
    XCTAssert(result==NO);
    result = [node5 canBeTupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node6 canBeDottedDupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node6 isDupleOfNode:node1];
    XCTAssert(result==NO);
    result = [node7 canBeTupleOfNode:node1];
    XCTAssert(result==YES);
    result = [node7 isTupleOfNode:node1];
    XCTAssert(result==NO);
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

//
//  TempoDetectionNode.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/25/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "TempoDetectionNode.h"

@implementation TempoDetectionNode

- (UInt32)descendantCounts
{
    UInt32 myCount = self.count;
    UInt32 duplesCount = ( nil != self.duples ) ? ( [self.duples descendantCounts] ) : ( 0 );
    UInt32 tuplesCount = ( nil != self.tuples ) ? ( [self.tuples descendantCounts] ) : ( 0 );
    UInt32 dottedDuplesCount = ( nil != self.dottedDuples ) ? ( [self.dottedDuples descendantCounts] ) : ( 0 );
    UInt32 doubleTuplesCount = ( nil != self.doubleTuples ) ? ( [self.doubleTuples descendantCounts] ) : ( 0 );
    return (myCount + duplesCount + tuplesCount + dottedDuplesCount + doubleTuplesCount );
}

- (BOOL)isEquivalentToNode:(TempoDetectionNode *)node
{
    Float32 delta = (fabsf(node.interval - self.interval));
    BOOL result = ( delta < 0.0025 );
    return result;
}

- (Float32)errorAsStrictSubdivision:(UInt32)subdivision ofNode:(TempoDetectionNode *)node
{
    Float32 sub = (Float32)subdivision;
    
    Float32 err = log2f(node.interval/self.interval) - log2f(sub);
    
    return err;
}

- (Float32)errorAsSubdivision:(UInt32)subdivision ofNode:(TempoDetectionNode *)node
{
    Float32 sub = (Float32)subdivision;
    
    Float32 err = log2f(node.interval/self.interval) - log2f(sub);// + 1.0;
    
    Float32 error = err-roundf(err);
    
    return error;
}

- (Float32)errorAsDottedSubdivision:(UInt32)subdivision ofNode:(TempoDetectionNode *)node
{
    Float32 sub = (Float32)subdivision;
    Float32 err = log2f(node.interval/self.interval) - log2f(sub) + log2f(sub*1.5);
    Float32 error = err-roundf(err);
    
    return error;
}

- (Float32)errorAsDoubleSubdivision:(UInt32)subdivision ofNode:(TempoDetectionNode *)node
{
    Float32 sub = (Float32)subdivision;
    Float32 logRat = log2f(node.interval/self.interval);
    Float32 logSub = log2f(sub);
    Float32 err = logRat - logSub;
    Float32 error = err-roundf(err);
    
    return error;
}

- (BOOL)canBeDottedDupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsDottedDuple = [self errorAsDottedSubdivision:2 ofNode:node];
    return ( fabsf(errorAsDottedDuple) < self.tolerance );
}

- (BOOL)canBeDupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsDuple = [self errorAsSubdivision:2 ofNode:node];
    return ( fabsf(errorAsDuple) < self.tolerance );
}


- (BOOL)canBeTupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsTuple = [self errorAsSubdivision:3 ofNode:node];
    return ( fabsf(errorAsTuple) < self.tolerance );
}

- (BOOL)isDupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsDuple = [self errorAsStrictSubdivision:2 ofNode:node];
    return ( fabsf(errorAsDuple) < self.tolerance );
}

- (BOOL)isTupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsTuple = [self errorAsStrictSubdivision:3 ofNode:node];
    return ( fabsf(errorAsTuple) < self.tolerance );
}

- (BOOL)isDottedDupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsDottedDuple = [self errorAsDottedSubdivision:2 ofNode:node];
    return ( fabsf(errorAsDottedDuple) < self.tolerance );
}

- (BOOL)isDoubleTupleOfNode:(TempoDetectionNode *)node
{
    if (node.interval <= self.interval) {
        return NO;
    }
    Float32 errorAsDoubleTuple = [self errorAsDoubleSubdivision:3 ofNode:node];
    return ( fabsf(errorAsDoubleTuple) < self.tolerance );
}

- (BOOL)insertNode:(TempoDetectionNode *)node
{
    if ([node isEquivalentToNode:self]) {
        [self addEquivalentNode:node];
        return YES;
    }
    
    if (!self.duples && [node isDupleOfNode:self]) {
        self.duples = node;
        node.parent = self;
        node.tree = self.tree;
        return YES;
    }
    
    if (self.duples && [self.duples insertNode:node]) {
        return YES;
    }
    
    
    if (!self.tuples && [node isTupleOfNode:self]) {
        self.tuples = node;
        node.parent = self;
        node.tree = self.tree;
        return YES;
    }
    
    if (self.tuples && [self.tuples insertNode:node]) {
        return YES;
    }
    
    if (!self.doubleTuples && [node isDoubleTupleOfNode:self]) {
        self.doubleTuples = node;
        node.parent = self;
        node.tree = self.tree;
        return YES;
    }
    
    if (self.doubleTuples && [self.doubleTuples insertNode:node]) {
        return YES;
    }
    
    if (!self.dottedDuples && [node isDottedDupleOfNode:self]) {
        self.dottedDuples = node;
        node.parent = self;
        node.tree = self.tree;
        return YES;
    }
    
    if (self.dottedDuples && [self.dottedDuples insertNode:node]) {
        return YES;
    }
    
    if (self.parent) {
        return NO;
    }
    
    if ([self isDupleOfNode:node] && [self.tree setRootNode:node asParentOfDupleNode:self]) {
        return YES;
    }
    
    if ([self isTupleOfNode:node] && [self.tree setRootNode:node asParentOfTupleNode:self]){
        return YES;
    }
    
    if ([self isDottedDupleOfNode:node] && [self.tree setRootNode:node asParentOfDottedDupleNode:self]) {
        return YES;
    }
    
    if ([self isDoubleTupleOfNode:node] && [self.tree setRootNode:node asParentOfDoubleTupleNode:self]) {
        return YES;
    }
    
    return NO;
}

- (void)addEquivalentNode:(TempoDetectionNode *)node
{
    UInt32 myCount = self.count;
    UInt32 theirCount = node.count;
    UInt32 ourCount = (myCount+theirCount);
    Float32 myWeight = (Float32)myCount/(Float32)ourCount;
    Float32 theirWeight = (Float32)theirCount/(Float32)ourCount;
    Float32 myWeightedInterval = self.interval * myWeight;
    Float32 theirWeightedInterval = node.interval * theirWeight;
    Float32 ourWeightedInterval = (myWeightedInterval + theirWeightedInterval);
    self.count = ourCount;
    self.interval = ourWeightedInterval;
    
}

- (NSUInteger)hash
{
    NSUInteger myCount = (NSUInteger)self.count;
    NSUInteger myInterval = (NSUInteger)self.interval * 1000000;
    NSString *myIdString = [NSString stringWithFormat:@"%lu-%lu",myInterval,myCount];
    return [myIdString hash];
}

- (BOOL)isEqual:(id)object
{
    return ([self hash] == [object hash]);
}

- (instancetype)copy
{
    TempoDetectionNode *node = [TempoDetectionNode new];
    node.interval = self.interval;
    node.count = self.count;
    node.tolerance = self.tolerance;
    return node;
}

- (void)print
{
    NSLog(@"\nNode Interval: %.3f, Count: %u",self.interval,self.count);
}

@end

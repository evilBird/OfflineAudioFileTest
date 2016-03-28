//
//  BeatInterval.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/24/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "BeatInterval.h"
#import "OfflineAudioFileProcessor+Functions.h"

@implementation BeatInterval

+ (NSArray *)mergeBeatIntervals:(NSArray *)intervals withSimilarity:(Float32)similarity
{
    NSLog(@"WILL MERGE %@ INTERVALS",@(intervals.count));
    NSMutableSet *intervalsSet = [NSMutableSet setWithArray:intervals];
    NSMutableArray *results = [NSMutableArray array];
    BOOL done = NO;
    NSUInteger numIterations = 0;
    NSUInteger maxIterations = intervals.count;
    while (!done) {
        BeatInterval *thisInterval = intervalsSet.allObjects.firstObject;
        NSRange range;
        range.location = 1;
        range.length = intervalsSet.allObjects.count-1;
        NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:range];
        NSArray *otherIntervals = [intervalsSet.allObjects objectsAtIndexes:indexSet];
        NSMutableSet *merged = [NSMutableSet setWithObject:thisInterval];
        
        for (BeatInterval *thatInterval in otherIntervals) {
            if ([thisInterval similarityToBeatInterval:thatInterval] > similarity) {
                [thisInterval mergeWithBeatInterval:thatInterval];
                [merged addObject:thatInterval];
            }
        }
        
        if (merged.allObjects.count > 1) {
            
            [intervalsSet minusSet:merged];
            [results addObject:thisInterval];
            
        }
        
        numIterations++;
        NSUInteger unmergedCount = intervalsSet.allObjects.count;
        done = ((unmergedCount == 0) || (numIterations >= maxIterations));
    }
    
    NSLog(@"DID MERGE INTERVALS: %@",@(results.count));
    return results;
}

+ (NSArray *)combineBeatIntervals:(NSArray *)intervals withMargin:(Float32)margin tolerance:(Float32)tolerance
{
    NSLog(@"WILL COMBINE %@ INTERVALS",@(intervals.count));
    NSMutableSet *intervalsSet = [NSMutableSet setWithArray:intervals];
    NSMutableArray *results = [NSMutableArray array];
    BOOL done = NO;
    NSUInteger numIterations = 0;
    NSUInteger maxIterations = intervals.count;
    
    while (!done) {
        NSMutableArray *intervalsSetObjects = intervalsSet.allObjects.mutableCopy;
        NSUInteger randIdx = arc4random_uniform((u_int32_t)intervalsSetObjects.count);
        BeatInterval *thisInterval = intervalsSet.allObjects[randIdx];
        [intervalsSetObjects removeObjectAtIndex:randIdx];
        intervalsSet = [NSMutableSet setWithArray:intervalsSetObjects];
        NSMutableSet *combined = [NSMutableSet setWithObject:thisInterval];
        
        for (BeatInterval *thatInterval in intervalsSetObjects) {
            Float32 combineError;
            Float32 aMargin = [thisInterval marginalImprovementIfCombinedWithBeatInterval:thatInterval error:&combineError];
            
            if (aMargin > 0.0 && combineError < tolerance) {
                [thisInterval combineWithBeatInterval:thatInterval];
                [combined addObject:thatInterval];
            }
        }
        
        if (combined.allObjects.count > 1) {
            
            [intervalsSet minusSet:combined];
            intervalsSet = [intervalsSet setByAddingObject:thisInterval].mutableCopy;
        }
        
        numIterations++;
        NSUInteger unmergedCount = intervalsSet.allObjects.count;
        done = ((unmergedCount == 1) || (numIterations >= maxIterations));
    }
    
    NSLog(@"DID COMBINE INTERVALS: %@",@(results.count));
    return results;
}

+ (instancetype)beatIntervalWithSeconds:(NSTimeInterval)seconds
{
    BeatInterval *beatInterval = [[BeatInterval alloc]init];
    [beatInterval.intervals addObject:@(seconds)];
    return beatInterval;
}

- (instancetype)init
{
    self = [super init];
    if (self) {
        _explained = [NSMutableSet set];
        _unexplained = [NSMutableSet set];
        _intervals = [NSMutableArray array];
        _combined = nil;
        _percentExplained = @(0.0);
    }
    
    return self;
}

- (void)addExplainedIndex:(NSUInteger)index
{
    [self.explained addObject:@(index)];
    [self updatePercentage];
}

- (void)addUnexplainedIndex:(NSUInteger)index
{
    [self.unexplained addObject:@(index)];
    [self updatePercentage];
}

- (void)updatePercentage
{
    NSUInteger total = self.explained.allObjects.count + self.unexplained.allObjects.count;
    if (!total) {
        self.percentExplained = @(0.0);
        return;
    }
    self.percentExplained = @((Float32)self.explained.allObjects.count/(Float32)total);
}

- (void)mergeWithBeatInterval:(BeatInterval *)beatInterval
{
    [self.intervals addObjectsFromArray:beatInterval.intervals];
    NSMutableSet *mergedExplained = [self.explained setByAddingObjectsFromSet:beatInterval.explained].mutableCopy;
    NSMutableSet *mergedUnexplained = [self.unexplained setByAddingObjectsFromSet:beatInterval.unexplained].mutableCopy;
    [mergedUnexplained minusSet:mergedExplained];
    self.explained = mergedExplained;
    self.unexplained = mergedUnexplained;
    [self updatePercentage];
}

- (void)combineWithBeatInterval:(BeatInterval *)beatInterval
{
    if (!self.combined) {
        self.combined = beatInterval;
        self.combineRelation = [self combineRatioForBeatInterval:beatInterval];
    }
    
    [self updateCombinedPercent];
}

- (void)updateCombinedPercent
{
    NSUInteger myTotal = self.explained.allObjects.count + self.unexplained.count;
    NSUInteger ourTotal = [self itemsExplainedByCombination].allObjects.count;
    self.percentExplainedByCombination = @((Float32)ourTotal/(Float32)myTotal);
}

- (NSSet *)itemsExplainedByCombination
{
    NSSet *myItems = [NSSet setWithSet:self.explained];

    if (!self.combined) {
        return myItems;
    }
    
    NSMutableSet *theirItems = [self.combined itemsExplainedByCombination].mutableCopy;
    return [theirItems setByAddingObjectsFromSet:myItems];
}

- (NSSet *)itemsInSet:(NSSet *)aSet notInSet:(NSSet *)otherSet
{
    NSMutableSet *aMutableSet = [NSMutableSet setWithSet:aSet];
    [aMutableSet minusSet:otherSet];
    return [NSSet setWithSet:aMutableSet];
}

- (Float32)similarityToBeatInterval:(BeatInterval *)beatInterval
{
    NSUInteger myTotal = self.explained.allObjects.count + self.unexplained.allObjects.count;
    NSUInteger myUniquesCount = [self itemsInSet:self.explained notInSet:beatInterval.explained].allObjects.count;
    Float32 myPercentUniques = (Float32)myUniquesCount/(Float32)myTotal;
    Float32 similariy = 1.0-myPercentUniques;
    return similariy;
}

- (Float32)combineRatioForBeatInterval:(BeatInterval *)beatInterval
{
    NSNumber *myAvgInterval = [self.intervals valueForKeyPath:@"@avg.self"];
    NSNumber *theirAvgInterval = [beatInterval.intervals valueForKeyPath:@"@avg.self"];
    Float32 dr;
    Float32 de = fabsf(compare_beats_as_duples_get_error(myAvgInterval.floatValue,theirAvgInterval.floatValue,&dr));
    Float32 tr;
    Float32 te = fabsf(compare_beats_as_tuples_get_error(myAvgInterval.floatValue,theirAvgInterval.floatValue,&tr));
    Float32 r = ( de < te ) ? ( dr ) : ( tr );
    return r;
}

- (Float32)marginalImprovementIfCombinedWithBeatInterval:(BeatInterval *)beatInterval error:(Float32 *)error
{
    NSUInteger myTotal = self.explained.allObjects.count + self.unexplained.allObjects.count;
    NSUInteger theirUniquesCount = [self itemsInSet:beatInterval.explained notInSet:self.explained].allObjects.count;
    Float32 theirContribution = (Float32)theirUniquesCount/(Float32)myTotal;
    Float32 myContribution = self.percentExplained.floatValue;
    Float32 ourContribution = theirContribution+myContribution;
    Float32 marginalImprovement = ourContribution/myContribution;
    NSNumber *myAvgInterval = [self.intervals valueForKeyPath:@"@avg.self"];
    NSNumber *theirAvgInterval = [beatInterval.intervals valueForKeyPath:@"@avg.self"];
    Float32 de = fabsf(compare_beats_as_duples_get_error(myAvgInterval.floatValue,theirAvgInterval.floatValue,NULL));
    Float32 te = fabsf(compare_beats_as_tuples_get_error(myAvgInterval.floatValue,theirAvgInterval.floatValue,NULL));
    Float32 e = ( de < te ) ? ( de ) : ( te );
    
    if (error) {
        *error = e;
    }
    
    return marginalImprovement;
}

- (void)print
{
    NSMutableString *toPrint = [NSMutableString new];
    [toPrint appendFormat:@"Beat explains %@ percent of peaks\n",self.percentExplained];
    [toPrint appendFormat:@"Intervals:"];
    for (NSNumber *interval in self.intervals) {
        [toPrint appendFormat:@"\t%@s",interval];
    }
    [toPrint appendFormat:@"\n"];
    
    NSLog(@"%@",toPrint);
}

@end

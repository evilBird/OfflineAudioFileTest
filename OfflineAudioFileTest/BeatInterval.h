//
//  BeatInterval.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/24/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface BeatInterval : NSObject

@property (nonatomic, strong)       NSMutableArray      *intervals;
@property (nonatomic, strong)       NSNumber            *percentExplained;
@property (nonatomic, strong)       NSNumber            *percentExplainedByCombination;
@property (nonatomic, strong)       NSMutableSet        *explained;
@property (nonatomic, strong)       NSMutableSet        *unexplained;
@property (nonatomic, strong)       NSMutableArray      *relatedIntervals;
@property (nonatomic, strong)       BeatInterval        *combined;
@property (nonatomic)               Float32             combineRelation;

+ (NSArray *)mergeBeatIntervals:(NSArray *)intervals withSimilarity:(Float32)similarity;
+ (NSArray *)combineBeatIntervals:(NSArray *)intervals withMargin:(Float32)margin tolerance:(Float32)tolerance;

+ (instancetype)beatIntervalWithSeconds:(NSTimeInterval)seconds;

- (void)addExplainedIndex:(NSUInteger)index;
- (void)addUnexplainedIndex:(NSUInteger)index;
- (Float32)similarityToBeatInterval:(BeatInterval *)beatInterval;
- (Float32)marginalImprovementIfCombinedWithBeatInterval:(BeatInterval *)beatInterval error:(Float32 *)error;

- (void)mergeWithBeatInterval:(BeatInterval *)beatInterval;
- (void)combineWithBeatInterval:(BeatInterval *)beatInterval;
- (NSSet *)itemsExplainedByCombination;
- (void)print;

@end

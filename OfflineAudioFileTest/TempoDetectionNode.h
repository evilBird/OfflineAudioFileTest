//
//  TempoDetectionNode.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/25/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>

@protocol TempoDetectionNodeTreeObject <NSObject>

- (BOOL)setRootNode:(id)root asParentOfDupleNode:(id)sender;
- (BOOL)setRootNode:(id)root asParentOfTupleNode:(id)sender;
- (BOOL)setRootNode:(id)root asParentOfDottedDupleNode:(id)sender;
- (BOOL)setRootNode:(id)root asParentOfDoubleTupleNode:(id)sender;

@end

@interface TempoDetectionNode : NSObject

@property (nonatomic)           Float32                                 interval;
@property (nonatomic)           UInt32                                  count;
@property (nonatomic,weak)      id<TempoDetectionNodeTreeObject>        tree;

@property (nonatomic,weak)      TempoDetectionNode                      *parent;
@property (nonatomic,strong)    TempoDetectionNode                      *duples;
@property (nonatomic,strong)    TempoDetectionNode                      *dottedDuples;
@property (nonatomic,strong)    TempoDetectionNode                      *tuples;
@property (nonatomic,strong)    TempoDetectionNode                      *doubleTuples;

@property (nonatomic)           Float32                                 tolerance;

- (UInt32)descendantCounts;

- (BOOL)isEquivalentToNode:(TempoDetectionNode *)node;
- (BOOL)isDupleOfNode:(TempoDetectionNode *)node;
- (BOOL)isTupleOfNode:(TempoDetectionNode *)node;
- (BOOL)isDottedDupleOfNode:(TempoDetectionNode *)node;
- (BOOL)isDoubleTupleOfNode:(TempoDetectionNode *)node;

- (BOOL)canBeDupleOfNode:(TempoDetectionNode *)node;
- (BOOL)canBeDottedDupleOfNode:(TempoDetectionNode *)node;
- (BOOL)canBeTupleOfNode:(TempoDetectionNode *)node;

- (BOOL)insertNode:(TempoDetectionNode *)node;
- (instancetype)copy;
- (void)print;

@end

//
//  TempoDetectionTree.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/25/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "TempoDetectionTree.h"

@interface TempoDetectionTree () <TempoDetectionNodeTreeObject>

- (BOOL)setRootNode:(id)root asParentOfDupleNode:(id)sender;
- (BOOL)setRootNode:(id)root asParentOfTupleNode:(id)sender;
- (BOOL)setRootNode:(id)root asParentOfDottedDupleNode:(id)sender;

@end

@implementation TempoDetectionTree

+ (instancetype)bestTreeForNodes:(NSArray *)nodes
{
    TempoDetectionTree *bestTree = nil;
    UInt32 totalNodes = (UInt32)nodes.count;
    UInt32 bestCount = 0;
    UInt32 numIterations = 0;
    
    for (NSUInteger i = 0; i < totalNodes; i++) {
        
        TempoDetectionNode *root = [nodes[i] copy];
        TempoDetectionTree *tree = [TempoDetectionTree new];
        
        [tree insertNode:root];


        NSMutableArray *mutableNodes = nodes.mutableCopy;
        [mutableNodes removeObjectAtIndex:i];

        for (TempoDetectionNode *aNode in mutableNodes) {
            TempoDetectionNode *aNodeCopy = [aNode copy];
            [tree insertNode:aNodeCopy];
        }
        
        UInt32 thisCount = [tree totalCount];
        
        if (thisCount > bestCount) {
            bestCount = thisCount;
            bestTree = tree;
        }
        
        numIterations++;
    }
    UInt32 maxCount = [[nodes valueForKeyPath:@"@sum.count"]unsignedIntValue];
    UInt32 tempo = (UInt32)((60.0/bestTree.root.interval)+0.5);
    NSLog(@"best tree explains %u of %u peak observations @ %u BPM",bestCount,maxCount,tempo);
    
    return bestTree;
}

- (UInt32)totalCount
{
    return [self.root descendantCounts];
}

- (BOOL)insertNode:(TempoDetectionNode *)node
{
    if (!self.root) {
        self.root = node;
        self.root.tree = self;
        return YES;
    }
    
    BOOL result = [self.root insertNode:node];
    return result;
}

- (BOOL)setRootNode:(id)root asParentOfDupleNode:(id)sender
{
    TempoDetectionNode *currentRoot = (TempoDetectionNode *)sender;
    if (currentRoot != self.root) {
        return NO;
    }
    
    TempoDetectionNode *newRoot = (TempoDetectionNode *)root;
    newRoot.duples = currentRoot;
    currentRoot.parent = newRoot;
    newRoot.tree = currentRoot.tree;
    self.root = newRoot;
    return YES;
}

- (BOOL)setRootNode:(id)root asParentOfTupleNode:(id)sender
{
    TempoDetectionNode *currentRoot = (TempoDetectionNode *)sender;
    if (currentRoot != self.root) {
        return NO;
    }
    
    TempoDetectionNode *newRoot = (TempoDetectionNode *)root;
    newRoot.tuples = currentRoot;
    newRoot.tree = currentRoot.tree;
    currentRoot.parent = newRoot;
    self.root = newRoot;
    return YES;
}

- (BOOL)setRootNode:(id)root asParentOfDottedDupleNode:(id)sender
{
    TempoDetectionNode *currentRoot = (TempoDetectionNode *)sender;
    if (currentRoot != self.root) {
        return NO;
    }
    
    TempoDetectionNode *newRoot = (TempoDetectionNode *)root;
    newRoot.dottedDuples = currentRoot;
    newRoot.tree = currentRoot.tree;
    currentRoot.parent = newRoot;
    self.root = newRoot;
    return YES;
}

- (BOOL)setRootNode:(id)root asParentOfDoubleTupleNode:(id)sender
{
    TempoDetectionNode *currentRoot = (TempoDetectionNode *)sender;
    if (currentRoot != self.root) {
        return NO;
    }
    
    TempoDetectionNode *newRoot = (TempoDetectionNode *)root;
    newRoot.doubleTuples = currentRoot;
    newRoot.tree = currentRoot.tree;
    currentRoot.parent = newRoot;
    self.root = newRoot;
    return YES;
}

@end

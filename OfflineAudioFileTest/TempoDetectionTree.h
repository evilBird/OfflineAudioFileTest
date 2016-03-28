//
//  TempoDetectionTree.h
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/25/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "TempoDetectionNode.h"

@interface TempoDetectionTree : NSObject

+ (instancetype)bestTreeForNodes:(NSArray *)nodes;

@property (nonatomic,strong)    TempoDetectionNode  *root;

- (BOOL)insertNode:(TempoDetectionNode *)node;
- (UInt32)totalCount;

@end

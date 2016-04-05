//
//  OfflineAudioFileProcessor+Analysis.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/19/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor+Analysis.h"
#import "OfflineAudioFileProcessor+Functions.h"
#import "BeatInterval.h"
#import "TempoDetectionTree.h"

static NSString *kObsIndex          =           @"obs_index";
static NSString *kStartTime         =           @"frame_start_time_s";
static NSString *kPeakRMS           =           @"peak_RMS";
static NSString *kLogNormalPeakRMS  =           @"log_norm_peak_RMS";
static NSString *kPeakTime          =           @"peak_time_s";
static NSString *kPeakInterval      =           @"peak_interval_s";
static NSString *kMSE_Du            =           @"mse_duple";
static NSString *kMSE_Tu            =           @"mse_tuple";
static NSString *kMSE               =           @"mse";
static NSString *kMSE_Bias           =          @"mse_bias";
static NSString *kTempoBPM          =           @"tempo_bpm";
static NSString *kTempoWt           =           @"tempo_weight";
static NSString *kLikelihood        =           @"likelihood";
static NSString *kObsCount          =           @"obs_ct";
static NSString *kFreqWt            =           @"freq_wt";

@interface OfflineAudioFileProcessor ()

@property (nonatomic,strong)    AudioProcessingBlock        myProcessingBlock;

@end


@implementation OfflineAudioFileProcessor (Analysis)

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
                 progressBlock:(AudioProcessingProgressBlock)progressBlock
                         error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    AVAudioFrameCount maxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFrameCount numFramesToRead = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
    
    while (numFramesToRead && !self.isCancelled && !self.isPaused) {
        
        AVAudioFrameCount bufferSize = ( numFramesToRead >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToRead );
        AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:sourceBuffer frameCount:bufferSize error:&err];
        AudioBufferList *sourceBufferList = (AudioBufferList *)(sourceBuffer.audioBufferList);
        
        if (err) {
            break;
        }
        
        OSStatus status = self.myProcessingBlock(sourceBufferList,bufferSize);

        if (status!=noErr) {
            err = [NSError errorWithDomain:@"OfflineAudioFileProcessor+Analysis.m" code:80 userInfo:nil];
            break;
        }
        
        if (err) {
            break;
        }
        
        numFramesToRead = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
        
        if (progressBlock) {
            double currentProgress = (double)(sourceFile.framePosition)/(double)(sourceFile.length);
            progressBlock(currentProgress);
        }
    }
    
    if (err) {
        if (error) {
            *error = err;
        }
        
        return;
    }
}

- (BOOL)writeAnalysisData:(id)dataObject toURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    BOOL result = NO;
    if ([dataObject respondsToSelector:@selector(writeToURL:atomically:encoding:error:)]){
        
        result = [dataObject writeToURL:targetURL atomically:NO encoding:1 error:&err];
        
    }else{
        err = [NSError errorWithDomain:@"OfflineAudioFileProcessor+Analysis.m" code:37 userInfo:nil];
    }
    
    if (err){
        if (error){
            *error = err;
        }
    }
    
    return result;
}

+ (NSArray *)logNormalizeObservations:(NSArray *)observations
{
    NSString *minRMSKeyPath = [NSString stringWithFormat:@"@min.%@",kPeakRMS];
    NSString *maxRMSKeyPath = [NSString stringWithFormat:@"@max.%@",kPeakRMS];
    
    NSNumber *minRMS = [observations valueForKeyPath:minRMSKeyPath];
    NSNumber *maxRMS = [observations valueForKeyPath:maxRMSKeyPath];
    
    Float32 e = 2.7182818;
    Float32 min, max, range, norm;
    min = minRMS.floatValue;
    max = maxRMS.floatValue;
    range = (max-min);
    norm = 1.0/range;
    
    NSMutableArray *normalizedObservations = [NSMutableArray array];
    [observations enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *anObs = (NSDictionary *)obj;
        NSMutableDictionary *myObs = anObs.mutableCopy;
        NSNumber *obsPeak = anObs[kPeakRMS];
        Float32 rawRMS = obsPeak.floatValue;
        Float32 normalizedRMS = (rawRMS - min) * norm;
        Float32 scaledRMS = (normalizedRMS * (e-1.0)) + 1.0;
        Float32 logNormRMS = logf(scaledRMS);
        myObs[kLogNormalPeakRMS] = @(logNormRMS);
        [normalizedObservations addObject:myObs];
    }];
    
    return [NSArray arrayWithArray:normalizedObservations];
}

+ (NSArray *)getPeaksForObservations:(NSArray *)observations minInterval:(Float32)minInterval peakThreshold:(Float32)threshold
{
    __block Float32 prevPeakTime = 0.0;
    __block NSMutableArray *peaks = [NSMutableArray array];
    
    [observations enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSDictionary *anObs = (NSDictionary *)obj;
        Float32 logNormPeakRMS = [anObs[kLogNormalPeakRMS] floatValue];
        Float32 peakTime = [anObs[kPeakTime] floatValue];
        
        if (logNormPeakRMS > threshold) {
            
            if (prevPeakTime == 0.0) {
                
                prevPeakTime = peakTime;
                
            }else{
                Float32 theInterval = (peakTime - prevPeakTime);
                if (theInterval > minInterval) {
                    NSMutableDictionary *myObs = anObs.mutableCopy;
                    Float32 peakInterval = round_float_to_sig_digs(theInterval, 3);
                    myObs[kPeakInterval] = @(peakInterval);
                    myObs[kObsIndex] = @(idx);
                    [peaks addObject:myObs];
                    prevPeakTime = peakTime;
                }
            }
        }
        
    }];
    
    return [NSArray arrayWithArray:peaks];
}

+ (NSDictionary *)peakFromPeakCluster:(NSArray *)peakCluster
{
    NSString *avgKey = [NSString stringWithFormat:@"@avg.%@",kPeakInterval];
    NSNumber *averageInterval = [peakCluster valueForKeyPath:avgKey];
    NSNumber *occurenceCt = @(peakCluster.count);
    NSDictionary *peak = @{kPeakInterval:averageInterval,
                           kObsCount:occurenceCt};
    return peak;
}

+ (NSArray *)sortedPeakLengths:(NSArray *)peaks ascending:(BOOL)ascending
{
    NSSortDescriptor *sortByLength = [NSSortDescriptor sortDescriptorWithKey:kPeakInterval ascending:ascending];
    NSArray *sortedPeaks = [peaks sortedArrayUsingDescriptors:@[sortByLength]];
    NSArray *peakLengths = [sortedPeaks valueForKey:kPeakInterval];
    
    return peakLengths;
}

static NSString *kRelatedKey = @"related";
static NSString *kUnrelatedKey = @"un-related";
static NSString *kRelatedEqualKey = @"related as equals";
static NSString *kRelatedDupleKey = @"related as duples";
static NSString *kRelatedTupleKey = @"related as tuples";
static NSString *kDebuggingKey = @"debugging";

+ (void)doSomethingWithSortedPeaksLengths:(NSArray *)sortedPeakLengths
{
    NSArray *intervals = [OfflineAudioFileProcessor getAllIntervalsForPeaks:sortedPeakLengths];
    NSArray *combinedIntervals = [BeatInterval combineBeatIntervals:intervals withMargin:0.01 tolerance:0.0125];
    NSArray *recombined = [BeatInterval combineBeatIntervals:combinedIntervals withMargin:0.01 tolerance:0.025];
    NSArray *sortedCombined = [recombined sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"percentExplainedByCombination" ascending:NO]]];
    
    
}

+ (NSArray *)getAllIntervalsForPeaks:(NSArray *)peaks
{
    NSMutableArray *mutablePeaks = peaks.mutableCopy;
    Float32 tolerance = 0.025;
    __block NSMutableArray *allIntervals = [NSMutableArray array];
    [mutablePeaks enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        __block NSUInteger thisIndex = idx;
        NSNumber *thisPeak = (NSNumber *)obj;
        __block BeatInterval *beatInterval = [BeatInterval beatIntervalWithSeconds:thisPeak.doubleValue];
        Float32 thisInterval = thisPeak.floatValue;
        [mutablePeaks enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            
            NSUInteger thatIndex = idx;
            if (thatIndex != thisIndex){
                NSNumber *thatPeak = (NSNumber *)obj;
                Float32 thatInterval = thatPeak.floatValue;
                if (fabsf(compare_beats_as_duples_get_error(thisInterval, thatInterval, NULL))<tolerance) {
                    [beatInterval addExplainedIndex:thatIndex];
                }else if (fabsf(compare_beats_as_tuples_get_error(thisInterval, thatInterval, NULL))<tolerance){
                    [beatInterval addExplainedIndex:thatIndex];
                }else{
                    [beatInterval addUnexplainedIndex:thatIndex];
                }
            }
        }];
        
        [allIntervals addObject:beatInterval];
    }];
    
    return allIntervals;
}

+ (NSDictionary *)getRelationshipsForPeakAtIndex:(NSUInteger)index inPeakLengthArray:(NSArray *)peakLengths debug:(BOOL)debug
{
    NSMutableArray *mutablePeakLengths = peakLengths.mutableCopy;
    NSNumber *shortestPeak = mutablePeakLengths[index];
    
    NSMutableDictionary *relationships = [NSMutableDictionary dictionary];
    relationships[kRelatedDupleKey] = [NSMutableDictionary dictionary];
    relationships[kRelatedTupleKey] = [NSMutableDictionary dictionary];
    relationships[kRelatedEqualKey] = [NSMutableArray array];
    relationships[kRelatedKey]  =   [NSMutableArray array];
    relationships[kUnrelatedKey] = [NSMutableArray array];
    NSMutableString *debuggingString = ( debug ) ? ( [NSMutableString new] ) : ( nil );
    Float32 baseLength = shortestPeak.floatValue;
    Float32 tolerance = 0.025;
    NSUInteger i = 0;
    
    for (NSNumber *aPeakLength in mutablePeakLengths) {
        
        if (i!=index) {
            Float32 aLength = aPeakLength.floatValue;
            Float32 dupleRatio;
            Float32 dupleErr = compare_beats_as_duples_get_error(aLength, baseLength, &dupleRatio);
            Float32 de = fabsf(dupleErr);
            
            Float32 tupleRatio;
            Float32 tupleErr = compare_beats_as_tuples_get_error(baseLength, aLength, &tupleRatio);
            Float32 te = fabsf(tupleErr);
            
            if ((de < tolerance && dupleRatio >=1.0) || (te < tolerance && tupleRatio>=1.0)){
                
                [relationships[kRelatedKey] addObject:aPeakLength];
                
                if (debuggingString) {
                    
                    if ((de < tolerance && dupleRatio == 1.0)||(te < tolerance && tupleRatio == 1.0))  {
                        
                        NSString *toAdd = [NSString stringWithFormat:@"\nEquals: %.3fs p(d)=%.3f p(t)=%.3f @1x",aLength,1.0-de,1.0-te];
                        [debuggingString appendString:toAdd];
                    }
                    
                    if (de < tolerance && dupleRatio >= 2.0) {
                        
                        NSString *toAdd = [NSString stringWithFormat:@"\nDuples: %.3fs p(d)=%.3f @ %.fx",aLength,1.0-de,dupleRatio];
                        [debuggingString appendString:toAdd];
                    }
                    
                    if (te < tolerance && tupleRatio >= 3.0) {
                        
                        NSString *toAdd = [NSString stringWithFormat:@"\nTuples: %.3fs p(t)=%.3f @%.fx",aLength,1.0-te,tupleRatio];
                        [debuggingString appendString:toAdd];
                    }
                }
            }else{
                if (fabsf(dupleErr) >= tolerance && fabsf(tupleErr) >= tolerance ) {
                    
                    [relationships[kUnrelatedKey] addObject:aPeakLength];
                    
                    if (debuggingString) {
                        NSString *toAdd = [NSString stringWithFormat:@"\nUnexplained: %.3fs p(d)=%.3f p(t)=%.3f",aLength,1.0-de,1.0-te];
                        [debuggingString appendString:toAdd];
                    }
                    
                }
            }
            
        }
    }
    
    if (debuggingString) {
        relationships[kDebuggingKey] = [NSString stringWithString:debuggingString];
    }
    
    return relationships;
    
}

+ (NSArray *)clusterPeaks:(NSArray *)peaks tolerance:(Float32)tolerance
{
    NSMutableArray *clusterPeaks = [NSMutableArray array];
    NSUInteger ct = peaks.count;
    
    while (ct > 1) {
        
        NSDictionary *thisPeak = (NSDictionary *)peaks.firstObject;
        Float32 thisInterval = [thisPeak[kPeakInterval] floatValue];
        Float32 thisTempo = 60.0/thisInterval;
        Float32 clusterMinInterval = thisInterval - thisInterval*tolerance;
        Float32 clusterMaxInterval = thisInterval + thisInterval*tolerance;
        
        Float32 clusterMinTempo = thisTempo-thisTempo*tolerance;
        Float32 clusterMaxTempo = thisTempo+thisTempo*tolerance;
        NSMutableArray *mutablePeaks = peaks.mutableCopy;
        
        NSMutableArray *thisCluster = [NSMutableArray arrayWithObject:thisPeak];
        
        for (UInt32 i = 1; i < mutablePeaks.count; i ++ ) {
            
            NSDictionary *thatPeak = mutablePeaks[i];
            Float32 thatInterval = [thatPeak[kPeakInterval] floatValue];
            Float32 thatTempo = 60.0/thatInterval;
            
            if (thatTempo >= clusterMinTempo && thatTempo <= clusterMaxTempo ) {
                [thisCluster addObject:thatPeak];
            }
        }
        
        if (thisCluster.count > 1) {
            NSDictionary *clusterPeak = [OfflineAudioFileProcessor peakFromPeakCluster:thisCluster.mutableCopy];
            [clusterPeaks addObject:clusterPeak];
        }
        
        NSSet *thisClusterSet = [NSSet setWithArray:thisCluster];
        NSMutableSet *remainingPeaksSet = [NSMutableSet setWithArray:mutablePeaks];
        [remainingPeaksSet minusSet:thisClusterSet];
        peaks = remainingPeaksSet.allObjects;
        ct = peaks.count;
    }
    
    return [NSArray arrayWithArray:clusterPeaks];
}

+ (NSArray *)calculateWeightedPeaks:(NSArray *)peaks minQuarterInterval:(Float32)minInterval maxQuarterInterval:(Float32)maxInterval
{
    Float32 kMinBPM = 60.0/maxInterval;
    Float32 kMaxBPM = 60.0/minInterval;
    
    __block NSMutableArray *results = [NSMutableArray array];
    NSString *kSumOfOccurencesKey = [NSString stringWithFormat:@"@sum.%@",kObsCount];
    NSNumber *sumOfOccurencesValue = [peaks valueForKeyPath:kSumOfOccurencesKey];
    UInt32 totalOccurences = sumOfOccurencesValue.unsignedIntValue;
    
    [peaks enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSDictionary *thisPeak = (NSDictionary *)obj;
        
        Float32 thisInterval = [thisPeak[kPeakInterval] floatValue];
        NSUInteger thisIndex = idx;
        UInt32 freq = [thisPeak[kObsCount]unsignedIntValue];
        
        __block Float32 sse_du = 0.0;
        __block Float32 sse_tu = 0.0;
        __block Float32 sse = 0.0;
        __block UInt32 sse_du_n = 0;
        __block UInt32 sse_tu_n = 0;
        __block UInt32 sse_n = 0;
        
        [peaks.mutableCopy enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            if ( idx != thisIndex ) {
                NSDictionary *thatPeak = (NSDictionary *)obj;
                Float32 thatInterval = [thatPeak[kPeakInterval] floatValue];
                
                Float32 r_du;
                Float32 e_du = compare_beats_as_duples_get_error(thisInterval, thatInterval, &r_du);
                Float32 se_du = (e_du * e_du);
                Float32 r_tu;
                Float32 e_tu = compare_beats_as_tuples_get_error(thisInterval, thatInterval, &r_tu);
                Float32 se_tu = (e_tu * e_tu);
                Float32 se;
                
                if (sse_du <= sse_tu) {
                    
                    sse_du += se_du;
                    sse_du_n ++;
                    se = se_du;
                    
                }else{
                    sse_tu += se_tu;
                    sse_tu_n ++;
                    se = se_tu;
                }
                sse += se;
                sse_n ++;
            }
        }];
        
        Float32 mse_du = sse_du/(Float32)sse_n;
        Float32 mse_tu = sse_tu/(Float32)sse_n;
        Float32 mse = sse/(Float32)sse_n;
        Float32 mse_bias = 0.0;
        Float32 mse_huge_bias = 100000000.0;
        Float32 freqWt = (Float32)freq/(Float32)totalOccurences;
        
        if (sse_du_n == 0 || sse_tu_n == 0 ) {
            
            mse_bias = mse_huge_bias;
            
        }else{
            
            Float32 err_bias = 0.0;
            Float32 ct_bias = 0.0;

            if ( mse_du >= mse_tu ) {
                
                err_bias = (mse_du/mse_tu)-1.0;
                ct_bias = (Float32)sse_n/(Float32)sse_tu_n;
                
            }else{
                
                err_bias = (mse_tu/mse_du)-1.0;
                ct_bias = (Float32)sse_n/(Float32)sse_du_n;
            }
            
            mse_bias = err_bias*(ct_bias);
        }
        
        Float32 bpm = 60.0/thisInterval;
        Float32 bpm_wt = weight_for_value_in_range(bpm, kMinBPM, kMaxBPM);
        Float32 ll = logf( mse/mse_bias * bpm_wt );

        NSMutableDictionary *newPeak = thisPeak.mutableCopy;
        newPeak[kMSE_Du] = @(mse_du);
        newPeak[kMSE_Tu] = @(mse_tu);
        newPeak[kMSE] = @(mse);
        newPeak[kMSE_Bias] = @(mse_bias);
        newPeak[kTempoBPM] = @(bpm);
        newPeak[kTempoWt] = @(bpm_wt);
        newPeak[kFreqWt] = @(freqWt);
        newPeak[kLikelihood] = @(ll);
        if (mse_bias < mse_huge_bias && bpm_wt > 0.0 ) {
            [results addObject:newPeak];
        }
    }];
    
    return [NSArray arrayWithArray:results];
}

+ (Float32)detectTempoInRange:(NSRange)tempoRange withData:(NSArray *)data
{
    Float32 kMinTempo = (Float32)tempoRange.location;
    Float32 kMaxTempo = (Float32)(tempoRange.length);
    Float32 kMinutesPerSec = 60.0;
    Float32 kMinQuarterInterval = (kMinutesPerSec/kMaxTempo);
    Float32 kMaxQuarterInterval = (kMinutesPerSec/kMinTempo);
    Float32 kMinSixteenthInterval = kMinQuarterInterval/4.0;

    
    NSArray *observations = [OfflineAudioFileProcessor logNormalizeObservations:data];
    NSArray *sortedObs = [observations sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:kPeakRMS ascending:YES]]];
    NSUInteger middleIndex = sortedObs.count/2;
    
    NSNumber *medianLogNormRMS = observations[middleIndex][kLogNormalPeakRMS];
    Float32 medRMS = medianLogNormRMS.floatValue;
    Float32 threshold = (2.0*(1.0 - medRMS)/4.0) + medRMS;
    
    NSArray *peaks = [OfflineAudioFileProcessor
                      getPeaksForObservations:observations
                      minInterval:kMinSixteenthInterval
                      peakThreshold:threshold];
    
    NSCountedSet *countedPeaksSet = [[NSCountedSet alloc]initWithArray:[peaks valueForKey:kPeakInterval]];
    __block NSMutableArray *nodes = [NSMutableArray array];
    [countedPeaksSet enumerateObjectsUsingBlock:^(id  _Nonnull obj, BOOL * _Nonnull stop) {
        TempoDetectionNode *aNode = [TempoDetectionNode new];
        aNode.interval = [(NSNumber *)obj floatValue];
        aNode.count = (UInt32)[countedPeaksSet countForObject:obj];
        aNode.tolerance = 0.05;
        [nodes addObject:aNode];
    }];
    
    TempoDetectionTree *bestTree = [TempoDetectionTree bestTreeForNodes:nodes];
    Float32 bestTempo = 60.0/bestTree.root.interval;
    return bestTempo;;
}

+ (OfflineAudioFileProcessor *)detectBPMOfFile:(NSString *)sourceFilePath allowedRange:(NSRange)tempoRange onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(Float32 detectedTempo))successHandler onFailure:(void(^)(NSError *error))failureHandler
{
    
    __block OfflineAudioFileProcessor *processor = [OfflineAudioFileProcessor new];
    
    [[NSOperationQueue new]addOperationWithBlock:^{
        
        [processor initializeProcessorWithSourceFile:sourceFilePath maxBufferSize:1024];
        [processor setProgressBlock:[progressHandler copy]];

        Float32 mySampleRate = processor.sourceFormat.sampleRate;
        UInt32 kWindowsPerBuffer = 8;
        __block NSMutableArray *vObservations = [NSMutableArray array];
        __block UInt32 vNumFramesRead = 0;
        
        [processor setProcessingBlock:^OSStatus(AudioBufferList *buffer, AVAudioFrameCount bufferSize) {
            OSStatus err = noErr;
            
            Float32 startingTime = (Float32)vNumFramesRead/mySampleRate;
            Float32 peakRMS;
            Float32 peakTime = startingTime + GetPeakRMSTime(buffer, (UInt32)mySampleRate, (UInt32)bufferSize, (UInt32)bufferSize/(UInt32)kWindowsPerBuffer, &peakRMS);
            
            [vObservations addObject:@{kStartTime:@(startingTime),
                                       kPeakRMS:@(peakRMS),
                                       kPeakTime:@(peakTime)
                                       }];
            
            vNumFramesRead += (UInt32)bufferSize;
            
            return err;
        }];
        
        [processor setCompletionBlock:^(NSURL *resultFile, NSError *error) {
            if (error) {
                return failureHandler(error);
            }
            
            Float32 myTempo = [OfflineAudioFileProcessor detectTempoInRange:tempoRange withData:vObservations];
            return successHandler(myTempo);
        }];
        
        [processor start];
    }];
    
    
    return processor;
}



@end

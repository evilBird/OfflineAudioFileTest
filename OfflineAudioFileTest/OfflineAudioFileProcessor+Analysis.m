//
//  OfflineAudioFileProcessor+Analysis.m
//  OfflineAudioFileTest
//
//  Created by Travis Henspeter on 3/19/16.
//  Copyright © 2016 birdSound. All rights reserved.
//

#import "OfflineAudioFileProcessor+Analysis.h"
#import "OfflineAudioFileProcessor+Functions.h"

static void *vUserInfo;
static AudioAnalysisBlock kAnalysisBlock;
/*
@interface OfflineAudioFileProcessor () {
    void *vUserInfo;
    AudioAnalysisBlock kAnalysisBlock;
}
@end
*/
@implementation OfflineAudioFileProcessor (Analysis)

+ (instancetype)analyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize analysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(NSURL *resultFile))successHandler onFailure:(void(^)(NSError *error))failureHandler
{
    __block OfflineAudioFileProcessor *analyzer = [OfflineAudioFileProcessor new];
    [[NSOperationQueue new]addOperationWithBlock:^{
        [analyzer configureToAnalyzeFile:sourceFilePath maxBlockSize:maxBlockSize usingAnalysisBlock:[analysisBlock copy] userInfo:userInfo onProgress:[progressHandler copy] onCompletion:^(NSURL *resultFile, NSError *error) {
            if (error) {
                return failureHandler(error);
            }
            
            return successHandler(resultFile);
        }];
        
        [analyzer start];
    }];
    
    return analyzer;
}

- (void)configureToAnalyzeFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize usingAnalysisBlock:(AudioAnalysisBlock)analysisBlock userInfo:(void *)userInfo onProgress:(AudioProcessingProgressBlock)progressHandler onCompletion:(AudioProcessingCompletionBlock) completionHandler
{
    vUserInfo = userInfo;
    kAnalysisBlock = [analysisBlock copy];
    [self initializeAnalyzerWithSourceFile:sourceFilePath maxBufferSize:maxBlockSize];
    [self setProgressBlock:[progressHandler copy]];
    __weak OfflineAudioFileProcessor *weakself = self;
    [self setCompletionBlock:^(NSURL *resultFile, NSError *error){
        
        NSError *err = nil;
        NSString *writeToPath = [OfflineAudioFileProcessor tempFilePathForFile:[sourceFilePath lastPathComponent] extension:@"txt"];
        NSURL *writeToURL = [NSURL fileURLWithPath:writeToPath];
        [weakself writeAnalysisDataToURL:writeToURL error:&err];
        
        if (err) {
            return completionHandler(nil,err);
        }
        
        return completionHandler(writeToURL, nil);
    }];
}

- (void)writeAnalysisDataToURL:(NSURL *)targetURL error:(NSError * __autoreleasing *)error
{
    id dataObject = (__bridge id)(vUserInfo);
    if ([dataObject isKindOfClass:[NSDictionary class]]) {
        NSDictionary *analysisDictionary = (NSDictionary *)dataObject;
        if (![analysisDictionary writeToURL:targetURL atomically:NO]) {
            NSError *e = [NSError errorWithDomain:@"OfflineAudioFileProcessor+Analysis.m" code:37 userInfo:nil];
            *error = e;
            return;
        }
    }
}

- (void)readFromAndAnalyzeFile:(AVAudioFile *)sourceFile
       progressBlock:(AudioProcessingProgressBlock)progressBlock
               error:(NSError * __autoreleasing *)error
{
    NSError *err = nil;
    AVAudioFrameCount maxBufferSize = (AVAudioFrameCount)self.maxBufferSize;
    AVAudioFrameCount numFramesToRead = (AVAudioFrameCount)(sourceFile.length - sourceFile.framePosition);
    AVAudioFrameCount numFramesRead = (AVAudioFrameCount)sourceFile.framePosition;
    
    while (numFramesToRead && !self.isCancelled && !self.isPaused) {
        
        AVAudioFrameCount bufferSize = ( numFramesToRead >= maxBufferSize ) ? ( maxBufferSize ) : ( numFramesToRead );
        AVAudioPCMBuffer *sourceBuffer = [[AVAudioPCMBuffer alloc]initWithPCMFormat:sourceFile.processingFormat frameCapacity:bufferSize];
        [sourceFile readIntoBuffer:sourceBuffer frameCount:bufferSize error:&err];
        AudioBufferList *sourceBufferList = (AudioBufferList *)(sourceBuffer.audioBufferList);
        
        if (err) {
            break;
        }
        UInt32 nfr = (UInt32)numFramesRead;
        UInt32 ntr = (UInt32)numFramesToRead;
        UInt32 sr = (UInt32)sourceFile.processingFormat.sampleRate;
        OSStatus status = kAnalysisBlock(sourceBufferList, bufferSize, nfr,ntr,sr,vUserInfo);
        
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
        myObs[kPeakRMS] = @(logNormRMS);
        [normalizedObservations addObject:myObs];
    }];
    
    return [NSArray arrayWithArray:normalizedObservations];
}

Float32 interval_triple_likelihood(Float32 value1, Float32 value2)
{
    Float32 num,den;
    num = ( value1 > value2 ) ? ( value1 ) : ( value2 );
    den = ( value1 > value2 ) ? ( value2 ) : ( value1 );
    Float32 logRatio = log2f(num/den);
    Float32 triple_error = fabsf(logRatio)-log2f(3.0);
    Float32 integral_error = fabsf(triple_error-roundf(triple_error));
    return (1.0 - integral_error);
}

Float32 interval_duple_likelihood(Float32 value1, Float32 value2)
{
    Float32 num,den;
    num = ( value1 > value2 ) ? ( value1 ) : ( value2 );
    den = ( value1 > value2 ) ? ( value2 ) : ( value1 );
    Float32 logRatio = log2f(num/den);
    Float32 duple_error = fabsf(logRatio)-log2f(2.0);
    Float32 integral_error = fabsf(duple_error-roundf(duple_error));
    return (1.0 - integral_error);
}

Float32 tempo_weight(Float32 tempo, Float32 min, Float32 max, Float32 bias)
{
    Float32 range = max-min;
    Float32 norm_interval = (tempo-min)/range;
    Float32 ci = norm_interval*M_PI+(M_PI*(0.5+bias));
    Float32 cv = cosf(ci);
    Float32 cv2 = ((cv * 0.5)+0.5);
    return (1.0-cv2);
}

+ (Float32)detectTempoWithData:(NSDictionary *)data bufferSize:(NSUInteger)bufferSize sampleRate:(NSUInteger)sampleRate
{
    NSArray *observations = [OfflineAudioFileProcessor logNormalizeObservations:data[kObservations]];
    NSArray *sortedObs = [observations sortedArrayUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:kPeakRMS ascending:YES]]];
    NSUInteger middleIndex = sortedObs.count/2;
    NSNumber *medianRMS = observations[middleIndex][kPeakRMS];
    
    NSString *minRMSKeyPath = [NSString stringWithFormat:@"@min.%@",kPeakRMS];
    NSString *maxRMSKeyPath = [NSString stringWithFormat:@"@max.%@",kPeakRMS];
    NSString *avgRMSKeyPath = [NSString stringWithFormat:@"@avg.%@",kPeakRMS];
    
    NSNumber *minRMS = [observations valueForKeyPath:minRMSKeyPath];
    NSNumber *maxRMS = [observations valueForKeyPath:maxRMSKeyPath];
    NSNumber *avgRMS = [observations valueForKeyPath:avgRMSKeyPath];
    
    NSLog(@"Summary:\nMin RMS: %@\nMax RMS: %@\nAvg RMS: %@\nMedian RMS: %@\n",minRMS,maxRMS,avgRMS,medianRMS);
    Float32 threshold = (maxRMS.floatValue - medianRMS.floatValue)/2.0 + medianRMS.floatValue;
    __block Float32 prevPeakTime = 0.0;
    Float32 kMinimumPeakInterval = ((Float32)bufferSize * 2.0)/(Float32)sampleRate;
    __block NSMutableArray *peaks = [NSMutableArray array];
    NSString *kIndex = @"index";
    
    [observations enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        
        NSDictionary *anObs = (NSDictionary *)obj;
        NSMutableDictionary *aMutableObs = anObs.mutableCopy;
        NSNumber *obsPeak = anObs[kPeakRMS];
        
        if (obsPeak.floatValue >= threshold) {
            Float32 peakTime = [anObs[kPeakRMSTime] floatValue];
            Float32 peakInterval = (peakTime - prevPeakTime);
            if (peakInterval > kMinimumPeakInterval) {
                aMutableObs[kIndex] = @(idx);
                aMutableObs[kInterval] = @(peakInterval);
                [peaks addObject:aMutableObs];
                prevPeakTime = peakInterval;
            }
        }
        
    }];
    
    Float32 kMinutesPerSec = 60.0;
    Float32 kMinTempo = 40.0;
    Float32 kMaxTempo = 180.0;
    Float32 kMinQuarterInterval = (kMinutesPerSec/kMaxTempo);
    Float32 kMaxQuarterInterval = (kMinutesPerSec/kMinTempo);
    
    NSPredicate *inRangeFilter = [NSPredicate predicateWithFormat:@"%K >= %@ AND %K <= %@",kInterval,@(kMinQuarterInterval),kInterval,@(kMaxQuarterInterval)];
    NSArray *inRangePeaks = [peaks filteredArrayUsingPredicate:inRangeFilter];
    __block NSMutableArray *weightedInRangePeaks = [NSMutableArray array];
    Float32 l_normConstant = 1.0/(Float32)(peaks.count * 1.0);
    NSString *kWeightedLikelihood = @"likelihood";
    NSString *kTempo = @"tempo";
    
    [inRangePeaks enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
        NSDictionary *aProcessedObs = (NSDictionary *)obj;
        Float32 thisInterval = [aProcessedObs[kInterval] floatValue];
        __block Float32 likelihood_running_average = 0.0;
        
        [peaks enumerateObjectsUsingBlock:^(id  _Nonnull obj, NSUInteger idx, BOOL * _Nonnull stop) {
            NSDictionary *aPeak = (NSDictionary *)obj;
            Float32 thatInterval = [aPeak[kInterval] floatValue];
            Float32 l_duple = interval_duple_likelihood(thisInterval, thatInterval);
            Float32 l_triple = interval_triple_likelihood(thisInterval, thatInterval);
            Float32 l = ( l_duple >= l_triple ) ? ( l_duple ) : ( l_triple );
            likelihood_running_average += (l * l_normConstant);
        }];
        
        NSMutableDictionary *aMutableTempoEstimate = [NSMutableDictionary dictionary];
        Float32 estTempo = (kMinutesPerSec/thisInterval);
        Float32 tempoWt = tempo_weight(estTempo, kMinTempo, kMaxTempo, 0.0);
        aMutableTempoEstimate[kWeightedLikelihood] = @(likelihood_running_average * tempoWt);
        aMutableTempoEstimate[kTempo] = @(kMinutesPerSec/thisInterval);
        [weightedInRangePeaks addObject:aMutableTempoEstimate];
    }];
    
    NSSortDescriptor *sortByLikelihood = [NSSortDescriptor sortDescriptorWithKey:kWeightedLikelihood ascending:NO];
    NSArray *sortedWeightedPeaks = [weightedInRangePeaks sortedArrayUsingDescriptors:@[sortByLikelihood]];
    NSLog(@"peaks by likelihood: %@",sortedWeightedPeaks);
    NSDictionary *mostLikely = sortedWeightedPeaks.firstObject;
    NSNumber *mostLikelyTempo = mostLikely[kTempo];
    return mostLikelyTempo.floatValue;
}


+ (void)detectBPMOfFile:(NSString *)sourceFilePath maxBlockSize:(NSUInteger)maxBlockSize onProgress:(AudioProcessingProgressBlock)progressHandler onSuccess:(void (^)(Float32 detectedTempo))successHandler onFailure:(void(^)(NSError *error))failureHandler
{
    [[NSOperationQueue new]addOperationWithBlock:^{
        __block NSMutableDictionary *vMyUserInfoDictionary = [NSMutableDictionary dictionary];
        vMyUserInfoDictionary[kObservations] = [NSMutableArray array];
        __block UInt32 vNumFramesRead = 0;
        __block Float32 mySampleRate = 0;
        [OfflineAudioFileProcessor analyzeFile:sourceFilePath maxBlockSize:maxBlockSize analysisBlock:^OSStatus(AudioBufferList *buffer, UInt32 bufferSize, UInt32 framesRead, UInt32 framesRemaining, UInt32 sampleRate, void *userInfo) {
            
            Float32 startingTime = (Float32)vNumFramesRead/(Float32)sampleRate;
            mySampleRate = (Float32)sampleRate;
            Float32 peakRMS;
            Float32 peakRMSTime = startingTime + GetPeakRMSTime(buffer, sampleRate, bufferSize, bufferSize/8, &peakRMS);
            [vMyUserInfoDictionary[kObservations] addObject:@{kStartTime:@(startingTime),
                                                              kPeakRMS:@(peakRMS),
                                                              kPeakRMSTime:@(peakRMSTime)
                                                              }];
            vNumFramesRead += bufferSize;
            
            return 0;
        } userInfo:NULL onProgress:progressHandler onSuccess:^(NSURL *resultFile) {
            NSDictionary *results = [NSDictionary dictionaryWithDictionary:vMyUserInfoDictionary];
            Float32 myTempo = [OfflineAudioFileProcessor detectTempoWithData:results bufferSize:maxBlockSize sampleRate:(NSUInteger)mySampleRate];
            return successHandler(myTempo);
        } onFailure:failureHandler];
    }];
    
}



@end

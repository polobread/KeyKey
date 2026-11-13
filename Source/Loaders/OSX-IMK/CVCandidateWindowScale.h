// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#ifndef CV_CANDIDATE_WINDOW_SCALE_H
#define CV_CANDIDATE_WINDOW_SCALE_H

#import <Foundation/Foundation.h>

static inline NSArray<NSString *> *CVCandidateWindowScalePercentages(void)
{
    return @[@"70", @"75", @"80", @"90", @"100", @"110", @"120", @"125",
             @"130", @"150", @"175", @"200", @"225", @"250", @"300"];
}

static inline NSString *CVNormalizedCandidateWindowScale(id value)
{
    if (![value isKindOfClass:[NSString class]])
        return @"system";
    // Map the former maximum to the largest available setting.
    if ([value isEqualToString:@"350"])
        return @"300";
    return [CVCandidateWindowScalePercentages() containsObject:value] ? value : @"system";
}

static inline float CVValidCandidateWindowScale(float scale)
{
    return (scale >= 0.70f && scale <= 3.0f) ? scale : 1.0f;
}

#endif

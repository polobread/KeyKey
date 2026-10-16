/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/

#import <Cocoa/Cocoa.h>

@class TakaoWordCount;

@interface TakaoAbout : NSViewController {
    TakaoWordCount *_wordCountController;
}
- (id)initWithModuleInfo:(NSArray *)modules;
- (void)refresh;
@end

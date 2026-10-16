// [AUTO_HEADER]

#import "CVKeyboardHelper.h"

@implementation CVKeyboardHelper

static CVKeyboardHelper *_sharedHelper = nil;

+ (CVKeyboardHelper *)sharedSendKey
{
	if (_sharedHelper == nil)
		_sharedHelper = [[CVKeyboardHelper alloc] init];
	return _sharedHelper;
}
- (id)init
{
	self = [super init];
	if (self != nil) {
		_validKeyboardLayouts = [[NSMutableArray alloc] init];
		[self loadValidKeyboardLayouts];
	}
	return self;
}
- (void)dealloc
{
	[_validKeyboardLayouts release];
	[super dealloc];
}
- (void)loadValidKeyboardLayouts
{
    [_validKeyboardLayouts removeAllObjects];
    NSDictionary *filter = [NSDictionary dictionaryWithObject:(id)kTISTypeKeyboardLayout
                                                       forKey:(id)kTISPropertyInputSourceType];
    CFArrayRef list = TISCreateInputSourceList((CFDictionaryRef)filter, true);
    if (!list) return;
    for (CFIndex i = 0; i < CFArrayGetCount(list); i++) {
        TISInputSourceRef source = (TISInputSourceRef)CFArrayGetValueAtIndex(list, i);
        CFStringRef sourceId = TISGetInputSourceProperty(source, kTISPropertyInputSourceID);
        if (sourceId && CFGetTypeID(sourceId) == CFStringGetTypeID())
            [_validKeyboardLayouts addObject:(NSString *)sourceId];
        // Get-rule properties are borrowed. The array retains the identifier.
    }
    CFRelease(list);
}
- (NSArray *)validKeyboardLayouts
{
	return _validKeyboardLayouts;
}
- (BOOL)validateKeyboardLayout:(NSString *)layout
{
	if (!_validKeyboardLayouts || ![_validKeyboardLayouts count]) 
		return NO;
	
	NSEnumerator *e = [_validKeyboardLayouts objectEnumerator];
	NSString *currentLayout;
	while (currentLayout = [e nextObject]) {
		if ([layout isEqualToString:currentLayout])
			return YES;
	}
	return NO;
}
@end

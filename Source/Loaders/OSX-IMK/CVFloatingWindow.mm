// [AUTO_HEADER]

#import "CVFloatingWindow.h"

@implementation CVFloatingWindow
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)aStyle backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{	
    if (self = [super initWithContentRect:contentRect styleMask:NSWindowStyleMaskBorderless backing:NSBackingStoreBuffered defer:NO]) {
		[self setBackgroundColor:[NSColor clearColor]];	
		[self setOpaque:NO];
		
		[self setLevel:NSStatusWindowLevel];
		[self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
			NSWindowCollectionBehaviorFullScreenAuxiliary];
		
        [self setHasShadow:YES];
    }
    return self;
}
- (BOOL)canBecomeKeyWindow
{
	return NO;
}
- (BOOL)canBecomeMainWindow
{
    return NO;
}
- (NSTimeInterval)animationResizeTime:(NSRect)newWindowFrame
{
	NSTimeInterval interval = 0.05;
	return interval;
}
@end

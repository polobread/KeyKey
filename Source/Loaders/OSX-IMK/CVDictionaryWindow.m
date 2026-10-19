// [AUTO_HEADER]

#import "CVDictionaryWindow.h"

@interface CVDictionaryWindow ()
- (void)configureSymbolPanel;
@end

@implementation CVDictionaryWindow
- (instancetype)initWithContentRect:(NSRect)contentRect styleMask:(NSWindowStyleMask)style backing:(NSBackingStoreType)bufferingType defer:(BOOL)flag
{
    self = [super initWithContentRect:contentRect
                           styleMask:style | NSWindowStyleMaskNonactivatingPanel
                             backing:bufferingType defer:flag];
    if (self)
        [self configureSymbolPanel];
    return self;
}

- (void)awakeFromNib
{
    [super awakeFromNib];
    // NIB decoding can restore NSPanel defaults after initialization.
    [self configureSymbolPanel];
}

- (void)configureSymbolPanel
{
    [self setFloatingPanel:YES];
    [self setWorksWhenModal:YES];
    [self setBecomesKeyOnlyIfNeeded:YES];
    [self setHidesOnDeactivate:NO];
    [self setLevel:NSStatusWindowLevel];
    [self setCollectionBehavior:NSWindowCollectionBehaviorCanJoinAllSpaces |
         NSWindowCollectionBehaviorFullScreenAuxiliary];
    [self setHasShadow:YES];
}
- (BOOL)canBecomeKeyWindow
{
    // Palette clicks must keep the editor's text input client as the target.
    return NO;
}
- (BOOL)canBecomeMainWindow
{
    return NO;
}
- (NSTimeInterval)animationResizeTime:(NSRect)newWindowFrame
{
	NSTimeInterval interval=0.05;
	return interval;
}
@end

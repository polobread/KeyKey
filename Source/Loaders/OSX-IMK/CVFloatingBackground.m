// [AUTO_HEADER]

#import "CVFloatingBackground.h"

@implementation CVFloatingBackground

- (void)dealloc
{
	[_backgroundFillColor release];
	[_borderColor release];	
	[super dealloc];
}
- (void)awakeFromNib
{
	_backgroundFillColor = [[NSColor blackColor] retain];
	_borderColor = [[NSColor whiteColor] retain];
}
- (NSFocusRingType)focusRingType
{
	return NSFocusRingTypeNone;
}
- (void)setBackgroundFillColor:(NSColor *)aColor
{
	NSColor *tmp = _backgroundFillColor;
	_backgroundFillColor = [aColor retain];
	[tmp release];
}

- (void)setBorderColor:(NSColor *)aColor
{
	NSColor *tmp = _borderColor;
	_borderColor = [aColor retain];
	[tmp release];	
}
- (void)drawRect:(NSRect)dirtyRect
{
	// Drawing coordinates follow bounds, even when the window is scaled.
	CGFloat lineWidth = 2.0;
	NSRect rect = NSInsetRect([self bounds], lineWidth / 2.0, lineWidth / 2.0);
	if (NSIsEmptyRect(rect))
		return;

	NSBezierPath *outline = [NSBezierPath bezierPathWithRoundedRect:rect xRadius:12 yRadius:12];
	[outline setFlatness:0.1];
	[outline setLineWidth:lineWidth];
	[_backgroundFillColor setFill];
	[outline fill];
	[_borderColor setStroke];
	[outline stroke];
}
@end

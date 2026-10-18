// [AUTO_HEADER]

#import "CVButtonViewController.h"
#import "OpenVanillaController.h"

@implementation CVButtonViewController

- (void) dealloc
{
	[_view release];
	[_buttonArray release];
	[super dealloc];
}
- (id)initWithDictionary:(NSDictionary *)d
{
	self = [super init];
	if (self != nil) {
		_buttonArray = [[NSMutableArray alloc] init];
		NSArray *buttons = [d valueForKey:@"Buttons"];
		BOOL emoji = [[d objectForKey:@"IsEmoji"] boolValue];
		CGFloat cell = emoji ? 34.0 : 25.0;
		NSUInteger rows = ([buttons count] + 9) / 10;
		NSView *grid = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 10 * cell, rows * cell)];
		NSUInteger i = 0;
		for (NSString *symbol in buttons) {
			CGFloat y = NSHeight([grid bounds]) - (1 + i / 10) * cell;
			CGFloat x = (i % 10) * cell;
			NSButton *button = [[[NSButton alloc] initWithFrame:NSMakeRect(x, y, cell - 2, cell - 2)] autorelease];
			[button setTarget:self];
			[button setAction:@selector(sendString:)];
			[button setButtonType:NSMomentaryLightButton];
			[button setBezelStyle:NSTexturedSquareBezelStyle];
			[button setTitle:symbol];
			if (emoji)
				[button setFont:[NSFont fontWithName:@"Apple Color Emoji" size:22.0] ?: [NSFont systemFontOfSize:22.0]];
			[_buttonArray addObject:button];
			[grid addSubview:button];
			i++;
		}
		if (emoji) {
			CGFloat scroller = [NSScroller scrollerWidthForControlSize:NSControlSizeRegular scrollerStyle:NSScrollerStyleLegacy];
			NSScrollView *scroll = [[NSScrollView alloc] initWithFrame:NSMakeRect(0, 0, 10 * cell + scroller, MIN(rows, (NSUInteger)8) * cell)];
			[scroll setBorderType:NSNoBorder];
			[scroll setScrollerStyle:NSScrollerStyleLegacy];
			[scroll setHasVerticalScroller:YES];
			[scroll setHasHorizontalScroller:NO];
			[scroll setDocumentView:grid];
			[[scroll contentView] scrollToPoint:NSMakePoint(0, MAX(0.0, NSHeight([grid bounds]) - NSHeight([[scroll contentView] bounds])))];
			[scroll reflectScrolledClipView:[scroll contentView]];
			_view = scroll;
			[grid release];
		}
		else {
			_view = grid;
		}
	}
	return self;
}
- (NSView *)view
{
	return _view;
}
- (IBAction)sendString:(id)sender
{
	NSButton *button = (NSButton *)sender;
	NSString *text = [button title];
	[OpenVanillaController sendComposedStringToCurrentlyActiveContext:text];
}

@end

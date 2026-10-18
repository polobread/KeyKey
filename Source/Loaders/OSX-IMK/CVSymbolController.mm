// [AUTO_HEADER]

#import "OpenVanillaController.h"
#import "CVSymbolController.h"
#import "CVSmileyViewController.h"
#import "CVButtonViewController.h"
#import <os/log.h>
#import "CVEmojiData.generated.h"
#import "CVCandidateWindowGeometry.h"

@implementation CVSymbolController

- (id)init
{
	self = [super init];
	if (self != nil) {
		_candidateWindowScale = 1.0;
		_viewArray = [NSMutableArray new];
		BOOL loaded = [NSBundle loadNibNamed:@"SymbolWindow" owner:self];
		NSAssert((loaded == YES), @"NIB did not load");
		// The loader may have posted its initial notification before this
		// lazily created controller existed. Read its current data as well.
		[self loadSymbolTable:nil];
	}
	return self;
}
- (void) dealloc
{
	[_viewArray release];
	[[NSNotificationCenter defaultCenter] removeObserver:self name:CVLoaderUpdateCannedMessagesNotification object:nil];
	[super dealloc];
}
- (void)loadSymbolTable:(NSNotification *)notification
{
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=window-load trigger=%{public}s",
	       notification ? "notification" : "snapshot");
	
	if ([_viewArray count])
		[_viewArray removeAllObjects];
	
	PVLoaderService *service = [OpenVanillaLoader sharedLoaderService];
	NSString *locale = service ? [NSString stringWithUTF8String:service->locale().c_str()] : @"en";
	NSArray *array = [[OpenVanillaLoader sharedInstance] mergedCannedMessagesArray];
	[_popUpButton removeAllItems];
	NSDictionary *d = nil;
	NSArray *categories = array;
	if ([array count]) {
		NSDictionary *emoji = @{@"Name": @"Emoji", @"IsSymbolButtonList": @"true",
		                         @"IsEmoji": @YES, @"Buttons": CVBuiltinEmojis()};
		categories = [array arrayByAddingObject:emoji];
	}
	NSEnumerator *enumerator = [categories objectEnumerator];
	
	while (d = [enumerator nextObject]) {
		if ([[d valueForKey:@"IsSymbolButtonList"] isEqualToString:@"true"]) {
			CVButtonViewController *controller = [[CVButtonViewController alloc] initWithDictionary:d];
			[controller autorelease];
			[_viewArray addObject:controller];		
		}
		else {
			CVSmileyViewController *controller = [[CVSmileyViewController alloc] initWithDictionary:d];	
			[controller autorelease];
			[_viewArray addObject:controller];		
		}
		NSString *name = [[d valueForKey:@"Name"] fallbackableLocalizedStringValueForLocale:locale];
		[_popUpButton addItemWithTitle:name];
	}
	NSView *view = [_viewArray count] ? [[_viewArray objectAtIndex:0] view] : nil;
	[self toggleActiveView:view];
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=window-loaded source_categories=%{public}lu menu_items=%{public}ld views=%{public}lu",
	       (unsigned long)[array count], (long)[_popUpButton numberOfItems], (unsigned long)[_viewArray count]);
}

- (void)awakeFromNib
{
	[[self window] setTitle:LFLSTR(@"Symbols")];	
	[[self window] setDelegate:self];

	[_popUpButton removeAllItems];
	[self toggleActiveView:nil];	
	
	NSRect screenRect = [[NSScreen mainScreen] visibleFrame];
	NSRect windowRect = [[self window] frame];
	int x = screenRect.origin.x + screenRect.size.width - windowRect.size.width - 10;
	int y = screenRect.origin.y + 200;

	[[self window] setFrame:NSMakeRect(x, y, windowRect.size.width, windowRect.size.height) display:YES];
	
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadSymbolTable:) name:CVLoaderUpdateCannedMessagesNotification object:nil];
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=observer-registered cached_categories=%{public}lu",
	       (unsigned long)[[[OpenVanillaLoader sharedInstance] mergedCannedMessagesArray] count]);
	
}

- (void)temporaryHide
{
	[[self window] orderOut:self];	
}
- (void)restoreWindowStatus
{
	if (_isVisible)
		[self showWindow:self];
}
- (BOOL)isVisible
{
	return _isVisible;
}
- (void)toggleActiveView:(NSView *)view
{
	for (NSView *previous in [[[_symbolContentView subviews] copy] autorelease])
		[previous removeFromSuperview];

	// Lay out in content coordinates. The old fixed frame-height allowance
	// included the title bar, leaving only two points below the popup control.
	const CGFloat bottom = 8.0, gap = 12.0, popupHeight = 26.0, top = 8.0;
	NSSize size = [view bounds].size;
	CGFloat width = MAX(250.0, size.width);
	NSRect contentRect = NSMakeRect(0, 0, width + 18.0,
	                               bottom + size.height + gap + popupHeight + top);
	NSWindow *window = [self window];
	NSRect windowRect = [window frame];
	CGFloat maxY = NSMaxY(windowRect);
	NSScreen *screen = [window screen] ?: [NSScreen mainScreen];
	NSRect visibleFrame = [screen visibleFrame];
	CGFloat titleHeight = NSHeight([window frame]) - NSHeight([[window contentView] frame]);
	NSRect available = visibleFrame;
	available.size.height = MAX(1.0, available.size.height - titleHeight);
	CGFloat scale = CVFitCandidateScale(contentRect.size, available, _candidateWindowScale);
	NSRect scaledContent = contentRect;
	scaledContent.size.width *= scale;
	scaledContent.size.height *= scale;
	windowRect.size = [window frameRectForContentRect:scaledContent].size;
	windowRect.origin.x = MIN(MAX(windowRect.origin.x, NSMinX(visibleFrame)), NSMaxX(visibleFrame) - NSWidth(windowRect));
	windowRect.origin.y = MIN(MAX(maxY - NSHeight(windowRect), NSMinY(visibleFrame)), NSMaxY(visibleFrame) - NSHeight(windowRect));

	// Match candidate-window scaling: resize physical content, retain logical
	// bounds, then lay out children. All fonts, controls and spacing scale once.
	NSRect unscaledFrame = windowRect;
	unscaledFrame.size = [window frameRectForContentRect:contentRect].size;
	[window setFrame:unscaledFrame display:NO];
	[[window contentView] setBoundsSize:contentRect.size];
	[window setFrame:windowRect display:NO];
	[[window contentView] setBoundsSize:contentRect.size];
	[_symbolContentView setFrame:NSMakeRect(9.0, bottom, width, size.height)];
	[_popUpButton setFrame:NSMakeRect(6.0, bottom + size.height + gap,
	                                contentRect.size.width - 12.0, popupHeight)];
	if (view) {
		[view setFrameOrigin:NSZeroPoint];
		[_symbolContentView addSubview:view];
	}
	// The expanded menu has its own window, so it does not inherit view scaling.
	[[_popUpButton menu] setFont:[NSFont menuFontOfSize:[[NSFont menuFontOfSize:0] pointSize] * scale]];
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=layout requested_scale=%{public}.2f applied_scale=%{public}.2f",
	       (double)_candidateWindowScale, (double)scale);
	[window display];
}

- (void)setCandidateWindowScale:(float)scale
{
	float value = (scale >= 0.75 && scale <= 3.5) ? scale : 1.0;
	if (_candidateWindowScale == value)
		return;
	_candidateWindowScale = value;
	NSInteger index = [_popUpButton indexOfSelectedItem];
	NSView *view = (index >= 0 && (NSUInteger)index < [_viewArray count]) ? [[_viewArray objectAtIndex:index] view] : nil;
	[self toggleActiveView:view];
}

#pragma mark Interface Builder actions

- (IBAction)toggleSymbol:(id)sender
{
	NSInteger selectedIndex = [_popUpButton indexOfSelectedItem];
	if (selectedIndex < 0 || (NSUInteger)selectedIndex >= [_viewArray count])
		return;
	id item = [_viewArray objectAtIndex:selectedIndex];
	NSView *view = [item view];
	[self toggleActiveView:view];
	
}
- (IBAction)showWindow:(id)sender
{
	// Retry if the window was created before the loader had any data.
	if (![_viewArray count]) {
		os_log(OS_LOG_DEFAULT, "KeyKey symbols event=empty-window-retry");
		[self loadSymbolTable:nil];
	}

	NSPoint point = [[self window] frame].origin;
	
	NSScreen *screen = nil;
	NSEnumerator *enumerator = [[NSScreen screens] objectEnumerator];
	BOOL found = NO;
	NSRect frame;
	while (screen = [enumerator nextObject]) {
		frame = [screen frame];
		if (point.x >= NSMinX(frame) && point.x <= NSMaxX(frame) && point.y >= NSMinY(frame) && point.y <= NSMaxY(frame)) {
			found = YES;
			break;
		}
	}
	if (!found)
		frame = [[NSScreen mainScreen] frame];
	
	NSRect windowRect = [[self window] frame];
	if (NSMaxX(windowRect) > NSMaxX(frame))
		windowRect.origin.x = NSMaxX(frame) - windowRect.size.width - 20;
	if (NSMinX(windowRect) < NSMinX(frame))
		windowRect.origin.x = NSMinX(frame) + 20;	
	if (NSMaxY(windowRect) > NSMaxY(frame))
		windowRect.origin.y = NSMaxY(frame) - windowRect.size.height - 20;
	if (NSMinY(windowRect) < NSMinY(frame))
		windowRect.origin.y = NSMinY(frame) + 20;
	[[self window] setFrameOrigin:windowRect.origin];
	[super showWindow:sender];
}
- (IBAction)hide:(id)sender
{
	[[self window] orderOut:self];
	_isVisible = NO;
}
- (IBAction)show:(id)sender
{
	[self showWindow:sender];
	_isVisible = YES;
}

#pragma mark NSWindow delegate methods

- (BOOL)windowShouldClose:(id)window
{
	[window orderOut:self];
	_isVisible = NO;
	return NO;
}

@end

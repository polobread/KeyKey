// [AUTO_HEADER]

#import "OpenVanillaController.h"
#import "CVSymbolController.h"
#import "CVSmileyViewController.h"
#import "CVButtonViewController.h"
#import <os/log.h>

@implementation CVSymbolController

- (id)init
{
	self = [super init];
	if (self != nil) {
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
	NSEnumerator *enumerator = [array objectEnumerator];
	
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
	if ([[_symbolContentView subviews] count]	) {
		NSView *lastView = [[_symbolContentView subviews] objectAtIndex:0];
		[lastView removeFromSuperview];
	}
	NSRect viewRect = [view bounds];
	NSRect symbolFrame = [_symbolContentView frame];
	symbolFrame.size = viewRect.size;
	NSRect windowRect = [[self window] frame];
	float currentMaxY = NSMaxY(windowRect);
	windowRect.size.height = symbolFrame.size.height + 65;
	windowRect.origin.y = currentMaxY - windowRect.size.height;
	[[self window] setFrame:windowRect display:YES animate:YES];
	
	[_symbolContentView setFrame:symbolFrame];	
	[_symbolContentView addSubview:view];
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
		if (point.x >= NSMinX(frame) && point.x <= NSMaxX(frame) && point.y >= NSMinY(frame) && point.y <= NSMaxX(frame)) {
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
		windowRect.origin.y = NSMinX(frame) + 20;
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

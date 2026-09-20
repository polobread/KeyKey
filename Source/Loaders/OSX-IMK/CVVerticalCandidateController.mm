// [AUTO_HEADER]

#import "CVVerticalCandidateController.h"
#import "CVCandidateWindowGeometry.h"
#import "NSColor+LFColorExtensions.h"

static void CVSetScaledCandidateWindowFrame(NSWindow *window, NSRect scaledFrame,
	NSSize unscaledSize)
{
	NSView *contentView = [window contentView];
	BOOL autoresizesSubviews = [contentView autoresizesSubviews];
	[contentView setAutoresizesSubviews:NO];
	[window setFrame:scaledFrame display:NO];
	[contentView setBoundsSize:unscaledSize];
	[contentView setAutoresizesSubviews:autoresizesSubviews];
}

static NSRect CVVisibleFrameForPoint(NSPoint point)
{
	for (NSScreen *screen in [NSScreen screens]) {
		if (NSPointInRect(point, [screen frame]))
			return [screen visibleFrame];
	}
	return [[NSScreen mainScreen] visibleFrame];
}

@implementation CVPageButton

- (BOOL)isFlipped
{
	return NO;
}
- (void)drawRect:(NSRect)aRect
{
	NSRect selfRect = [self frame];
	NSRect rect = NSMakeRect(0, 0, selfRect.size.width, selfRect.size.height);
	if ([self image]) {
		NSImage *i = nil;
		if ([[self cell] isHighlighted]) {
			if ([self alternateImage])
				i = [self alternateImage];
			else
				i = [self image];
		}
		else {
			i = [self image];
		}
		NSSize size = [i size];
		float x = (rect.size.width - size.width) / 2;
		float y = (rect.size.height - size.height) / 2;
		[i drawAtPoint:NSMakePoint(x, y)
              fromRect:NSZeroRect
             operation:NSCompositeSourceOver
              fraction:1.0];
	}
}
@end


@implementation CVVerticalCandidateController

- (void)dealloc
{
	[_candidateArray release];
	[_displayedCandidateTexts release];
	[_backgroundColor release];
	[_foregroundColor release];
	[_highlightTextColor release];
	[super dealloc];
}
- (id)init
{
	self = [super init];
	if (self != nil) {
		BOOL loaded = [NSBundle loadNibNamed:@"VerticalCandidateWindow" owner:self];
		NSAssert((loaded == YES), @"NIB did not load");
		
		_candidateTextHeight = 18.0;
		_candidateWindowScale = 1.0;
		_displayedPage = (size_t)-1;
		_displayedHighlightIndex = (size_t)-1;
	}
	return self;
}
- (NSImage *)imagePrev: (NSColor *)aColor
{
	NSImage *imagePrev;
	imagePrev = [[[NSImage alloc] initWithSize:NSMakeSize(6, 6)] autorelease];
	[imagePrev lockFocus];
	NSBezierPath *bezierPath = [NSBezierPath bezierPath];
	[bezierPath moveToPoint:NSMakePoint(0, 0)];
	[bezierPath lineToPoint:NSMakePoint(6, 0)];
	[bezierPath lineToPoint:NSMakePoint(3, 6)];
	[bezierPath closePath];
	[aColor setFill];
	[bezierPath fill];
	[imagePrev unlockFocus];
	return imagePrev;
}
- (NSImage *)imageNext: (NSColor *)aColor
{
	NSImage *imageNext;
	imageNext = [[[NSImage alloc] initWithSize:NSMakeSize(6, 6)] autorelease];
	[imageNext lockFocus];
	NSBezierPath *bezierPath = [NSBezierPath bezierPath];
	[bezierPath moveToPoint:NSMakePoint(0, 6)];
	[bezierPath lineToPoint:NSMakePoint(6, 6)];
	[bezierPath lineToPoint:NSMakePoint(3, 0)];
	[bezierPath closePath];
	[aColor setFill];
	[bezierPath fill];
	[imageNext unlockFocus];
	return imageNext;
}
- (void)awakeFromNib
{
	_backgroundColor = [[NSColor blackColor] retain];
	_foregroundColor = [[NSColor whiteColor] retain];
	_highlightTextColor = [[NSColor whiteColor] retain];

	[[[self window] contentView] setBackgroundFillColor:_backgroundColor];
	[[[self window] contentView] setBorderColor:_foregroundColor];
	[_tableView setTablebackgroundColor:_backgroundColor];

	_candidateArray = [[NSMutableArray alloc] init];
	[_scrollView setBorderType:NSNoBorder];
	[_tableView setDelegate:self];
	[_tableView setDataSource:self];

	[_pageIndicatorTextField setStringValue:@""];
	[_pageIndicatorTextField setTextColor:_foregroundColor];
	[_promptTextField setStringValue:@""];
	[_promptTextField setTextColor:_foregroundColor];

	[_tableView setBackgroundColor:[NSColor clearColor]];
	[_tableView setAction:@selector(sendKey:)];

	[_previousButton setHidden:YES];
	[_nextButton setHidden:YES];

	_sending = NO;
}
- (void)setFontHeight:(float)newHeight
{
	_fontHeight = newHeight;
	if (_fontHeight < 20)
		_fontHeight = 20;
}
- (void)updateDisplay:(PVVerticalCandidatePanel*)panel
              atPoint:(NSPoint)position
{
    // hide if it's invisible--before update
    if (!panel->isVisible()) {
		[self hide];
		return;
	}

	_sending = NO;

    NSPoint newPosition = position;
	NSPoint previousScrollPoint = [[_scrollView contentView] bounds].origin;

	if (_candidateArray)
		[_candidateArray removeAllObjects];
	else
		_candidateArray = [NSMutableArray new];

	[[[self window] contentView] setBackgroundFillColor:_backgroundColor];
	[[[self window] contentView] setBorderColor:_foregroundColor];
	[_tableView setTablebackgroundColor:_backgroundColor];

	NSColor *highlightColor = [NSColor highlightGradientFromColor];
	[_previousButton setImage:[self imagePrev:_foregroundColor]];
	[_previousButton setAlternateImage:[self imagePrev:highlightColor]];
	[_nextButton setImage:[self imageNext:_foregroundColor]];
	[_nextButton setAlternateImage:[self imageNext:highlightColor]];

    // update the content
    size_t fromIndex = panel->currentPage() * panel->candidatesPerPage();
    size_t index;
    size_t count = panel->currentPageCandidateCount();
    size_t highlightedIndex = panel->currentHightlightIndex();
	NSMutableArray *candidateTexts = [NSMutableArray arrayWithCapacity:count];
	size_t currentPage = panel->currentPage()  + 1;
	size_t pageCount = panel->pageCount();
	NSString *pageString = [NSString stringWithFormat:@"%d/%d", currentPage, pageCount];
	if ( pageCount > 1) {	 
		[_pageIndicatorTextField setStringValue:pageString];
		[_pageIndicatorTextField setHidden:NO];
		[_previousButton setHidden:NO];
		[_nextButton setHidden:NO];
	}
	else {
		[_pageIndicatorTextField setStringValue:@""];	 
		[_pageIndicatorTextField setHidden:YES];
		[_previousButton setHidden:YES];
		[_nextButton setHidden:YES];		 
	}

	_width = 0;

	NSString *prompt = [NSString stringWithUTF8String:panel->prompt().c_str()];
	[_promptTextField setStringValue:prompt];
	CGFloat promptWidth = ceil([[_promptTextField attributedStringValue] size].width);
	 
    OVCandidateList* list = panel->candidateList();
    
	float fontSize = _candidateTextHeight;
	
	NSFont *defaultFont = [NSFont systemFontOfSize:fontSize];	
	NSDictionary * attributes =  [NSDictionary dictionaryWithObject:defaultFont forKey:NSFontAttributeName];
	
	[_tableView setRowHeight:fontSize + 6.0];
    for (index = 0; index < count; index++) {
        string candidate = list->candidateAtIndex(fromIndex + index);        
        string keyString = panel->candidateKeyAtIndex(index).receivedString();
		NSString *candidateText = [NSString stringWithUTF8String:candidate.c_str()];
		[candidateTexts addObject:candidateText];

		NSAttributedString *c = [[NSAttributedString alloc] initWithString:candidateText attributes:attributes];
		NSString *k = [NSString stringWithUTF8String:keyString.c_str()];
		NSMutableDictionary *d = [NSMutableDictionary dictionary];
		[d setValue:c forKey:@"candidate"];
		NSImage *i = nil;
		if (index == highlightedIndex && panel->isInControl()){
			i = [CVTextDecoration imageWithACharacterInACircle:k foreground:_highlightTextColor background:_backgroundColor];
		}
		else {
			i = [CVTextDecoration imageWithACharacterInACircle:k foreground:_foregroundColor background:_backgroundColor];
		}
		[d setValue:i forKey:@"key"];

		float currentWidth = ceil([c size].width);
		if (currentWidth >= _width)
			_width = currentWidth;

		[_candidateArray addObject:d];
		[c release];
	}
	BOOL resetScroll = _panel != panel || _displayedPage != panel->currentPage() ||
		![_displayedCandidateTexts isEqualToArray:candidateTexts];
	BOOL revealHighlighted = resetScroll || !_displayedInControl ||
		_displayedHighlightIndex != highlightedIndex;
	[_displayedCandidateTexts release];
	_displayedCandidateTexts = [candidateTexts copy];
	_displayedPage = panel->currentPage();
	_displayedHighlightIndex = highlightedIndex;
	_displayedInControl = panel->isInControl();
	[_tableView reloadData];


	CGFloat tableHeight = ([_tableView rowHeight] + 2) * panel->candidatesPerPage();
	if (!tableHeight)
		tableHeight = 200;

	NSTableColumn *keyColumn = [_tableView tableColumnWithIdentifier:@"key"];
	NSTableColumn *candidateColumn = [_tableView tableColumnWithIdentifier:@"candidate"];
	CGFloat keyColumnWidth = 20.0;
	CGFloat columnSpacing = [_tableView intercellSpacing].width;
	CGFloat candidateColumnWidth = MAX(40.0, _width + 8.0);
	CGFloat windowWidth = keyColumnWidth + columnSpacing + candidateColumnWidth + 4.0;
	CGFloat promptLeading = pageCount > 1 ? 26.0 : 6.0;
	if ([prompt length])
		windowWidth = MAX(windowWidth, promptLeading + promptWidth + 10.0);

	NSRect visibleFrame = CVVisibleFrameForPoint(newPosition);
	CGFloat fullWindowHeight = tableHeight + 40.0;
	CGFloat minimumWindowHeight = MIN(fullWindowHeight, [_tableView rowHeight] + 42.0);
	CGFloat scale = CVFitCandidateScale(NSMakeSize(windowWidth, minimumWindowHeight),
		visibleFrame, _candidateWindowScale);
	CGFloat windowHeight = MIN(fullWindowHeight, visibleFrame.size.height / scale);
	BOOL needsScrolling = windowHeight + 0.5 < fullWindowHeight;
	if (needsScrolling) {
		// Reserve room for the scrollbar even when the user disables overlay scrollbars.
		windowWidth += 16.0;
		scale = CVFitCandidateScale(NSMakeSize(windowWidth, minimumWindowHeight),
			visibleFrame, _candidateWindowScale);
		windowHeight = MIN(fullWindowHeight, visibleFrame.size.height / scale);
	}

	CGFloat tableWidth = windowWidth - 4.0 - (needsScrolling ? 16.0 : 0.0);
	NSSize unscaledWindowSize = NSMakeSize(windowWidth, windowHeight);
	NSSize scaledSize = NSMakeSize(unscaledWindowSize.width * scale,
		unscaledWindowSize.height * scale);
	NSRect windowFrame = CVPlaceCandidateWindow(newPosition, scaledSize,
		visibleFrame, _fontHeight);

	// Finish resizing the window and its logical coordinate system before laying
	// out any children. Their XIB autoresizing masks must not inherit an
	// intermediate size from the previous candidate window.
	CVSetScaledCandidateWindowFrame([self window], windowFrame, unscaledWindowSize);

	[keyColumn setWidth:keyColumnWidth];
	[candidateColumn setWidth:tableWidth - keyColumnWidth - columnSpacing];
	[_scrollView setHasVerticalScroller:needsScrolling];
	[_scrollView setFrame:NSMakeRect(2.0, 20.0, windowWidth - 4.0,
		windowHeight - 40.0)];
	[_tableView setFrame:NSMakeRect(0.0, 0.0, tableWidth, tableHeight)];
	[_scrollView tile];

	NSRect promptFrame = [_promptTextField frame];
	promptFrame.origin = NSMakePoint(promptLeading, windowHeight - promptFrame.size.height - 6.0);
	promptFrame.size.width = windowWidth - promptLeading - 6.0;
	[_promptTextField setFrame:promptFrame];

	NSRect previousFrame = [_previousButton frame];
	previousFrame.origin = NSMakePoint(4.0, windowHeight - previousFrame.size.height);
	[_previousButton setFrame:previousFrame];
	NSRect nextFrame = [_nextButton frame];
	nextFrame.origin = NSMakePoint(4.0, -1.0);
	[_nextButton setFrame:nextFrame];
	NSRect pageFrame = [_pageIndicatorTextField frame];
	pageFrame.origin.x = 24.0;
	pageFrame.size.width = windowWidth - 30.0;
	[_pageIndicatorTextField setFrame:pageFrame];

	if (panel->isInControl()) {
		_allowClick = YES;
		[_tableView setAllowsEmptySelection:NO];
		if (highlightedIndex < count)
			[_tableView selectRowIndexes:[NSIndexSet indexSetWithIndex:(NSInteger)highlightedIndex] byExtendingSelection:NO];
		else
			[_tableView deselectAll:self];
	} 
	else {
		[_tableView setAllowsEmptySelection:YES];
		[_tableView deselectAll:self];
		_allowClick = NO;
	}

	// Preserve a manual scroll within the same page, but discard an offset from
	// different candidates. In either case constrain it after the new viewport
	// and document frames have both been laid out.
	NSClipView *clipView = [_scrollView contentView];
	NSPoint scrollPoint = resetScroll ? NSZeroPoint : previousScrollPoint;
	[clipView scrollToPoint:[clipView constrainScrollPoint:scrollPoint]];
	[_scrollView reflectScrolledClipView:clipView];
	if (needsScrolling && panel->isInControl() && highlightedIndex < count && revealHighlighted)
		[_tableView scrollRowToVisible:(NSInteger)highlightedIndex];
	[[self window] display];
    
    // show if it's visible--after update
	if (panel->isVisible())
		[[self window] orderFront:self];
}
- (void)hide
{
	[[self window] orderOut:self];
	[_displayedCandidateTexts release];
	_displayedCandidateTexts = nil;
	_displayedPage = (size_t)-1;
	_displayedHighlightIndex = (size_t)-1;
	_displayedInControl = NO;
}

#pragma mark Interface Builder actions

- (IBAction)sendKey:(id)sender
{
	if (_sending)
		return;
	int selectedItem = [_tableView selectedRow];
	string keyString = _panel->candidateKeyAtIndex(selectedItem).receivedString();
	[[CVSendKey sharedSendKey] typeString:[NSString stringWithUTF8String:keyString.c_str()]];
}

- (IBAction)updateSelectedCandidate:(id)sender
{
	int selectedItem = [_tableView selectedRow];
	_panel->setHighlightIndex((size_t)selectedItem);
	NSPoint p = [[self window] frame].origin;
	p.y = p.y + [[self window] frame].size.height;
	[self updateDisplay:_panel atPoint:p];
}

- (void)updateContent:(PVVerticalCandidatePanel*)panel
              atPoint:(NSPoint)position;
{
	[self updateDisplay:panel atPoint:position];
	_panel = panel;
}
- (IBAction)gotoNextPage:(id)sender
{
	_panel->goToNextPage();
	NSPoint p = [[self window] frame].origin;
	p.y = NSMaxY([[self window] frame]);
	[self updateDisplay:_panel atPoint:p];
}
- (IBAction)gotoPreviousPage:(id)sender
{
	_panel->goToPreviousPage();
	NSPoint p = [[self window] frame].origin;
	p.y = NSMaxY([[self window] frame]);
	[self updateDisplay:_panel atPoint:p];
}

- (void)setCandidateTextHeight:(float)inTextHeight
{
	_candidateTextHeight = inTextHeight;
}

- (void)setCandidateWindowScale:(float)scale
{
	_candidateWindowScale = (scale >= 0.75 && scale <= 3.5) ? scale : 1.0;
}

#pragma mark TableView delegate

- (BOOL)selectionShouldChangeInTableView:(NSTableView *)aTableView
{
	return _allowClick;
}
- (void)tableView:(NSTableView*)aTableView
  willDisplayCell:(id)aCell
   forTableColumn:(NSTableColumn*)aTableColumn
              row:(int)rowIndex
{
	int selectedRow = [_tableView selectedRow];
	if ([[aTableColumn identifier] isEqualToString:@"candidate"]) {
		if (rowIndex == selectedRow)
			[aCell setTextColor:_highlightTextColor];
		else 
			[aCell setTextColor:_foregroundColor];
	}
}
- (id)tableView:(NSTableView*)aTableView
objectValueForTableColumn:(NSTableColumn*)aTableColumn
            row:(int)rowIndex
{
    if ([[aTableColumn identifier] isEqualToString:@"key"])
		return [[_candidateArray objectAtIndex:rowIndex] objectForKey:@"key"];
	else if ([[aTableColumn identifier] isEqualToString:@"candidate"])
		return [[_candidateArray objectAtIndex:rowIndex] objectForKey:@"candidate"];
    return nil;
}
- (int)numberOfRowsInTableView:(NSTableView *)aTableView
{
    return [_candidateArray count];
}

@end

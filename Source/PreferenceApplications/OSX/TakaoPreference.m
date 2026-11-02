/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoPreference.h"
#import "TakaoWindow.h"
#import "TakaoGeneric.h"
#import "TakaoGlobal.h"
#import "TakaoAbout.h"

@implementation TakaoPreference

- (void)dealloc
{
    [_aboutController release];
    [_defaultApplicationImage release];
    [super dealloc];
}

- (void)awakeFromNib
{
	[NSApp setDelegate:self];
	
	_defaultApplicationImage = [[NSApp applicationIconImage] copy];

	NSArray *fetchedModules = nil;
	NSMutableArray *genericModules = [NSMutableArray array];
	NSArray *loadedModules = nil;
	
	id ovService;
	@try {
		ovService = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];	
		if (ovService) {
			[ovService setProtocolForProxy:@protocol(OpenVanillaService)];
			fetchedModules = [ovService identifiersAndLocalizedNamesWithPattern:@"Generic-*"];

			NSEnumerator *moduleEnumerator = [fetchedModules objectEnumerator];
			NSArray *itemArray = nil;
			while (itemArray = [moduleEnumerator nextObject]) {
				NSString *name = [itemArray objectAtIndex:0];
				if (![name isEqualToString:@"Generic-cj-cin"] && ![name isEqualToString:@"Generic-simplex-cin"])
					[genericModules addObject:itemArray];
			}
			
			NSArray *info = [ovService dynamicallyLoadedModulePackageInfo];
			loadedModules = [NSArray arrayWithArray:info];
		}
		
		if ([genericModules count]) {
			_hasGenericInputMethods = YES;
			[_takaoGenericController setModules:genericModules];
		}
		
		if ([loadedModules count]) {
			_hasLoadedModules = YES;
			[_takaoLoadedModuleController setModules:loadedModules];
		}
	}
	@catch(NSException *e) {
		// NSLog(@"Exceptions raise on retreiving version info");
		// return;
	}
	
    // NIB awake order is unspecified. Build the complete general pane before
    // measuring it, even when the optional IMK service is absent or throws.
    [_takaoGlobalController setInputMethods:genericModules];

    _aboutController = [[TakaoAbout alloc] initWithModuleInfo:loadedModules];
	id toolbar = [[[NSToolbar alloc] initWithIdentifier:@"preferences toolbar"] autorelease];
    [toolbar setAllowsUserCustomization:NO];
    [toolbar setAutosavesConfiguration:NO];
	[toolbar setSizeMode:NSToolbarSizeModeSmall];
	[toolbar setDisplayMode:NSToolbarDisplayModeIconAndLabel];
	[toolbar setDelegate:self];
	[toolbar setSelectedItemIdentifier:GeneralToolbarItemIdentifier];
#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5)
    // cancel unified look and feel?
	int newHeight = [_generalView frame].size.height - [_keyboardLayoutContentView frame].size.height + 10;
	[_generalView setFrame:NSMakeRect(0, 0, 480, newHeight)];
	[_keyboardLayoutContentView removeFromSuperview];
#else
	[_keyboardLayoutContentView addSubview:_keyboardLayoutView];	
#endif
	
	[window setLevel:NSFloatingWindowLevel];
	[window setToolbar:toolbar];
	[window setToolbarStyle:NSWindowToolbarStylePreference];
	[window center];
	[window setDelegate:self];
		
	[self setActiveView:_generalView animate:NO];
	[self setAppIcon:[NSImage imageNamed:@"general"]];	
	
	[window setTitle:LFLSTR(GeneralToolbarItemIdentifier)];
}

- (void)setActiveView:(NSView *)view animate:(BOOL)flag
{
	NSEvent *e = [NSApp currentEvent];
	if ([e modifierFlags] & NSShiftKeyMask) {
		[window useSlowMotion];
	} else {
		[window stopSlowMotion];
	}
	
    if (!view) return;
    NSSize paneSize = [view frame].size;
    NSRect oldWindowFrame = [window frame];
    // AppKit includes this window's actual titlebar and toolbar metrics.
    // A fixed chrome height clips the bottom rows on newer macOS versions.
    NSRect windowFrame = [window frameRectForContentRect:
        NSMakeRect(0.0, 0.0, paneSize.width, paneSize.height)];
    windowFrame.origin.x = oldWindowFrame.origin.x;
    windowFrame.origin.y = NSMaxY(oldWindowFrame) - NSHeight(windowFrame);

    NSView *contentView = [window contentView];
    for (NSView *currentView in [[[contentView subviews] copy] autorelease]) {
        if (currentView != view) [currentView removeFromSuperview];
    }
    // Keep each pane's measured size while AppKit resizes its content view.
    // In particular, never override the content view frame behind NSWindow.
    BOOL autoresizes = [contentView autoresizesSubviews];
    [contentView setAutoresizesSubviews:NO];
    [window setFrame:windowFrame display:YES animate:flag];
    [view setFrame:NSMakeRect(0.0, 0.0, paneSize.width, paneSize.height)];
    if ([view superview] != contentView) [contentView addSubview:view];
    [contentView setAutoresizesSubviews:autoresizes];
}

- (void)setAppIcon:(NSImage *)image
{
	NSImage *i = [[[NSImage alloc] initWithSize:NSMakeSize(512.0, 512.0)] autorelease];
	int height = [i size].height;
	int width = [i size].width;	
	NSRect fullRect = NSMakeRect(0, 0, width, height);				 
	NSRect newRect = NSMakeRect(width/2, 0, width/2, height/2);
	[i lockFocus];
	[_defaultApplicationImage drawInRect:fullRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[image drawInRect:newRect fromRect:NSZeroRect operation:NSCompositeSourceOver fraction:1.0];
	[i unlockFocus];
	[window setMiniwindowImage:i];
}

- (void)toggleActivePreferenceView:(id)sender
{
	NSView *view = nil;
	
	if ([[sender itemIdentifier] isEqualToString:GeneralToolbarItemIdentifier])
		view = _generalView;
	else if ([[sender itemIdentifier] isEqualToString:PhoneticToolbarItemIdentifier])
		view = _phoneticView;
	else if ([[sender itemIdentifier] isEqualToString:CangjieToolbarItemIdentifier])
		view = _cangjieView;
	else if ([[sender itemIdentifier] isEqualToString:SimplexToolbarItemIdentifier])
		view = _simpexView;
	else if ([[sender itemIdentifier] isEqualToString:PhraseToolbarItemIdentifier])
		view = _phraseView;
	else if ([[sender itemIdentifier] isEqualToString:GenericToolbarItemIdentifier])
		view = _genericSettingView;	
	else if ([[sender itemIdentifier] isEqualToString:PluginToolbarItemIdentifier])
		view = _pluginView;
	else if ([[sender itemIdentifier] isEqualToString:UpdateToolbarItemIdentifier])
		view = _updateView;
    else if ([[sender itemIdentifier] isEqualToString:AboutToolbarItemIdentifier]) {
        view = [_aboutController view];
        [_aboutController refresh];
    }

    if (!view) return;
	
	if (view != _generalView) {
		[[NSColorPanel sharedColorPanel] orderOut:self];
	}
	
	[self setActiveView:view animate:YES];
	[self setAppIcon:[sender image]];	
	[window setTitle:LFLSTR([sender itemIdentifier])];
}

- (IBAction)showAbout:(id)sender
{
    NSToolbar *toolbar = [window toolbar];
    for (NSToolbarItem *item in [toolbar items]) {
        if ([item.itemIdentifier isEqualToString:AboutToolbarItemIdentifier]) {
            [toolbar setSelectedItemIdentifier:AboutToolbarItemIdentifier];
            [self toggleActivePreferenceView:item];
            [window makeKeyAndOrderFront:sender];
            break;
        }
    }
}

#pragma mark NSWindow delegate methods

- (void)windowWillClose:(NSNotification *)notification
{
	[[NSApplication sharedApplication] terminate:self];
}

@end

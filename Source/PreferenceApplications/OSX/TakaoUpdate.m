/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoUpdate.h"

@implementation TakaoUpdate

- (id)updateService
{
	id service = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];
	[service setProtocolForProxy:@protocol(OpenVanillaService)];
	return service;
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_statusTimer invalidate]; [_statusTimer release];
	[super dealloc];
}
- (void)_getVersionInfo
{
	[_currentVersionTextField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""];
	[_latestVersionTextField setStringValue:@"—"];
	[_latestCheckTextField setStringValue:@"尚未檢查"];
	@try {
		id service = [self updateService];
		NSDictionary *status = [service desktopUpdateStatus];
		if (!status) [NSException raise:@"KeyKeyUpdateServiceUnavailable" format:@"No IMK update status"];
		[_statusTextField setStringValue:[status objectForKey:@"message"] ?: @"尚未設定更新服務；此建置不會連線。"];
		[_latestVersionTextField setStringValue:[[status objectForKey:@"latestVersion"] length] ? [status objectForKey:@"latestVersion"] : @"—"];
		[_checkButton setEnabled:[[status objectForKey:@"canCheck"] boolValue]];
		BOOL checking = [[status objectForKey:@"checking"] boolValue];
		[_checkProgressIndicator setHidden:!checking];
		if (checking) [_checkProgressIndicator startAnimation:self];
		else [_checkProgressIndicator stopAnimation:self];
		id date = [status objectForKey:@"lastCheck"];
		if ([date isKindOfClass:[NSDate class]])
			[_latestCheckTextField setStringValue:[NSDateFormatter localizedStringFromDate:date
				dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
	} @catch (NSException *exception) {
		[_checkButton setEnabled:NO];
		[_checkProgressIndicator stopAnimation:self];
		[_checkProgressIndicator setHidden:YES];
		[_statusTextField setStringValue:@"更新服務無法連接。第一次升級需手動安裝支援更新的版本。"];
	}
}

- (void)awakeFromNib
{
	[_checkProgressIndicator setHidden:YES];
	NSView *view = [_checkProgressIndicator superview];
	BOOL autoresizes = [view autoresizesSubviews];
	[view setAutoresizesSubviews:NO];
	NSArray *children = [[view subviews] copy];
	for (NSView *child in children) {
		NSRect frame = [child frame]; frame.origin.y += 64; [child setFrame:frame];
		if ([child isKindOfClass:[NSButton class]] && [(NSButton *)child action] == @selector(checkUpdateNow:))
			_checkButton = (NSButton *)child;
	}
	[children release];
	NSRect frame = [view frame]; frame.size.height += 64; [view setFrame:frame];
	[view setAutoresizesSubviews:autoresizes];
	_statusTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(24, 6, frame.size.width - 48, 54)] autorelease];
	[_statusTextField setEditable:NO]; [_statusTextField setSelectable:YES];
	[_statusTextField setBezeled:NO]; [_statusTextField setDrawsBackground:NO];
	[_statusTextField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[[_statusTextField cell] setWraps:YES];
	[view addSubview:_statusTextField];
	[self _getVersionInfo];
	_statusTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(_getVersionInfo) userInfo:nil repeats:YES] retain];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopStatusTimer:)
		name:NSWindowWillCloseNotification object:_window];
}

- (void)stopStatusTimer:(NSNotification *)notification
{
	[_statusTimer invalidate]; [_statusTimer release]; _statusTimer = nil;
}
#pragma mark Interface Builder actions

- (IBAction)checkUpdateNow:(id)sender
{
	@try {
		id service = [self updateService];
		if ([[[service desktopUpdateStatus] objectForKey:@"canCheck"] boolValue]) {
			[_checkButton setEnabled:NO];
			[_statusTextField setStringValue:@"正在檢查簽章更新…"];
			[service checkForDesktopUpdates];
			return;
		}
	} @catch (NSException *exception) { /* Show a local message without networking. */ }
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:@"此版本尚未設定更新服務"];
	[alert setInformativeText:@"需先安裝內含正式公開金鑰與更新網址的版本。此建置不會連線，也不會安裝未驗證的更新。"];
	[alert beginSheetModalForWindow:_window completionHandler:nil];
}

@end

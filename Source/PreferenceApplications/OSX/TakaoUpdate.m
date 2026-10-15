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
	// Set deadlines before rootProxy, which itself performs a synchronous RPC.
	NSConnection *connection = [NSConnection connectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];
	[connection setRequestTimeout:2];
	[connection setReplyTimeout:2];
	@try {
		id service = [connection rootProxy];
		[service setProtocolForProxy:@protocol(OpenVanillaService)];
		return service;
	} @catch (NSException *exception) {
		[connection invalidate];
		@throw;
	}
}

- (void)dealloc
{
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[_statusTimer invalidate]; [_statusTimer release];
	[_serviceQueue cancelAllOperations]; [_serviceQueue release];
	[super dealloc];
}
- (void)_getVersionInfo
{
	[self requestStatusWithAction:nil beta:NO];
}

- (void)renderStatus:(NSDictionary *)status
{
	[_currentVersionTextField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""];
	[_latestVersionTextField setStringValue:@"—"];
	[_latestCheckTextField setStringValue:@"尚未檢查"];
	if (status) {
		if ([[status objectForKey:@"currentVersion"] length]) [_currentVersionTextField setStringValue:[status objectForKey:@"currentVersion"]];
		[_statusTextField setStringValue:[status objectForKey:@"message"] ?: @"尚未設定更新服務；此建置不會連線。"];
		[_latestVersionTextField setStringValue:[[status objectForKey:@"latestVersion"] length] ? [status objectForKey:@"latestVersion"] : @"—"];
		[_checkButton setEnabled:[[status objectForKey:@"canCheck"] boolValue]];
		[_betaButton setState:[[status objectForKey:@"beta"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff];
		[_betaButton setEnabled:[[status objectForKey:@"canChangeBeta"] boolValue]];
		BOOL checking = [[status objectForKey:@"checking"] boolValue];
		[_checkProgressIndicator setHidden:!checking];
		if (checking) [_checkProgressIndicator startAnimation:self];
		else [_checkProgressIndicator stopAnimation:self];
		id date = [status objectForKey:@"lastCheck"];
		if ([date isKindOfClass:[NSDate class]])
			[_latestCheckTextField setStringValue:[NSDateFormatter localizedStringFromDate:date
				dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
	} else {
		[_checkButton setEnabled:NO];
		[_betaButton setEnabled:NO];
		[_checkProgressIndicator stopAnimation:self];
		[_checkProgressIndicator setHidden:YES];
		[_statusTextField setStringValue:@"更新服務無法連接。第一次升級需手動安裝支援更新的版本。"];
	}
}

- (void)requestStatusWithAction:(NSString *)action beta:(BOOL)beta
{
	if (_statusStopped || _statusRequestPending) return;
	if (!_serviceQueue) {
		_serviceQueue = [[NSOperationQueue alloc] init];
		[_serviceQueue setMaxConcurrentOperationCount:1];
	}
	_statusRequestPending = YES;
	NSUInteger generation = _statusGeneration;
	// Never wait for the IMK service on the AppKit thread. Also materialize the
	// remote dictionary here, so rendering cannot make further proxy calls.
	[_serviceQueue addOperationWithBlock:^{
		@autoreleasepool {
			NSDictionary *status = nil;
			id service = nil;
			@try {
				service = [self updateService];
				if ([action isEqualToString:@"check"]) [service checkForDesktopUpdates];
				else if ([action isEqualToString:@"beta"]) [service setBetaDesktopUpdates:beta];
				NSDictionary *remote = [service desktopUpdateStatus];
				if (remote) status = [[NSDictionary alloc] initWithDictionary:remote copyItems:YES];
			} @catch (NSException *exception) { /* Report service failure on the UI thread. */ }
			@finally {
				if ([service isProxy]) [[service connectionForProxy] invalidate];
			}
			[[NSOperationQueue mainQueue] addOperationWithBlock:^{
				if (!_statusStopped && generation == _statusGeneration) {
					_statusRequestPending = NO;
					[self renderStatus:status];
				}
			}];
			[status release];
		}
	}];
}

- (void)awakeFromNib
{
	[_checkProgressIndicator setHidden:YES];
	NSView *view = [_checkProgressIndicator superview];
	BOOL autoresizes = [view autoresizesSubviews];
	[view setAutoresizesSubviews:NO];
	NSArray *children = [[view subviews] copy];
	for (NSView *child in children) {
		NSRect frame = [child frame]; frame.origin.y += 88; [child setFrame:frame];
		if ([child isKindOfClass:[NSButton class]] && [(NSButton *)child action] == @selector(checkUpdateNow:))
			_checkButton = (NSButton *)child;
	}
	[children release];
	NSRect frame = [view frame]; frame.size.height += 88; [view setFrame:frame];
	[view setAutoresizesSubviews:autoresizes];
	_statusTextField = [[[NSTextField alloc] initWithFrame:NSMakeRect(24, 6, frame.size.width - 48, 54)] autorelease];
	[_statusTextField setEditable:NO]; [_statusTextField setSelectable:YES];
	[_statusTextField setBezeled:NO]; [_statusTextField setDrawsBackground:NO];
	[_statusTextField setFont:[NSFont systemFontOfSize:[NSFont smallSystemFontSize]]];
	[[_statusTextField cell] setWraps:YES];
	[view addSubview:_statusTextField];
	_betaButton = [[[NSButton alloc] initWithFrame:NSMakeRect(24, 70, frame.size.width - 48, 22)] autorelease];
	[_betaButton setButtonType:NSButtonTypeSwitch];
	[_betaButton setTitle:@"接收 beta 測試版更新（預設關閉）"];
	[_betaButton setTarget:self]; [_betaButton setAction:@selector(betaUpdatesChanged:)];
	[_betaButton setState:NSControlStateValueOff];
	[view addSubview:_betaButton];
	[self _getVersionInfo];
	_statusTimer = [[NSTimer scheduledTimerWithTimeInterval:1 target:self selector:@selector(_getVersionInfo) userInfo:nil repeats:YES] retain];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(stopStatusTimer:)
		name:NSWindowWillCloseNotification object:_window];
}

- (void)stopStatusTimer:(NSNotification *)notification
{
	[_statusTimer invalidate]; [_statusTimer release]; _statusTimer = nil;
	_statusStopped = YES; _statusGeneration++;
	[_serviceQueue cancelAllOperations];
}
#pragma mark Interface Builder actions

- (IBAction)betaUpdatesChanged:(id)sender
{
	if (_statusStopped || _statusRequestPending) return;
	[_checkButton setEnabled:NO]; [_betaButton setEnabled:NO];
	[self requestStatusWithAction:@"beta" beta:[sender state] == NSControlStateValueOn];
}

- (IBAction)checkUpdateNow:(id)sender
{
	if (_statusStopped || _statusRequestPending || ![_checkButton isEnabled]) return;
	[_checkButton setEnabled:NO]; [_betaButton setEnabled:NO];
	[_statusTextField setStringValue:@"正在檢查簽章更新…"];
	[self requestStatusWithAction:@"check" beta:NO];
}

@end

/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoUpdate.h"
#import "TakaoHelper.h"

@implementation TakaoUpdate

- (void)dealloc
{
	[super dealloc];
}
- (void)_getVersionInfo
{
	[_currentVersionTextField setStringValue:[[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"] ?: @""];
	[_latestVersionTextField setStringValue:@"由簽章更新服務檢查"];
	[_latestCheckTextField setStringValue:@"尚未檢查"];
	@try {
		id service = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];
		[service setProtocolForProxy:@protocol(OpenVanillaService)];
		NSDictionary *status = [service desktopUpdateStatus];
		if (![[status objectForKey:@"configured"] boolValue])
			[_latestVersionTextField setStringValue:@"尚未設定更新服務"];
		id date = [status objectForKey:@"lastCheck"];
		if ([date isKindOfClass:[NSDate class]])
			[_latestCheckTextField setStringValue:[NSDateFormatter localizedStringFromDate:date
				dateStyle:NSDateFormatterShortStyle timeStyle:NSDateFormatterShortStyle]];
	} @catch (NSException *exception) {
		[_latestVersionTextField setStringValue:@"請先手動安裝支援更新的版本"];
	}
}

- (void)awakeFromNib
{
	[_checkProgressIndicator setHidden:YES];
	[self _getVersionInfo];
}
#pragma mark Interface Builder actions

- (IBAction)checkUpdateNow:(id)sender
{
	@try {
		id service = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];
		[service setProtocolForProxy:@protocol(OpenVanillaService)];
		if ([[[service desktopUpdateStatus] objectForKey:@"configured"] boolValue]) {
			[service checkForDesktopUpdates];
			[self _getVersionInfo];
			return;
		}
	} @catch (NSException *exception) { /* Show a local message without networking. */ }
	NSAlert *alert = [[[NSAlert alloc] init] autorelease];
	[alert setMessageText:@"此版本尚未設定更新服務"];
	[alert setInformativeText:@"需先安裝內含正式公開金鑰與更新網址的版本。此建置不會連線，也不會安裝未驗證的更新。"];
	[alert beginSheetModalForWindow:_window completionHandler:nil];
}

@end

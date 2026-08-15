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
	id ovService;
	
    // @try {
		ovService = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];		
    // }
    // @catch(NSException *e) {
        // NSLog(@"Exceptions raise on retreiving version info");
        // [_currentVersionTextField setStringValue:@""];          
        // [_latestVersionTextField setStringValue:@""];        
        // [_latestCheckTextField setStringValue:@""];          
        // return;
    // }

	if (ovService) {
		[ovService setProtocolForProxy:@protocol(OpenVanillaService)];
		NSString *version = [ovService version];
		if (version) 
			[_currentVersionTextField setStringValue:version];
		else
			[_currentVersionTextField setStringValue:@""];	
			
		NSString *latestVersion = [ovService latestVersion];		
		if (latestVersion)
			[_latestVersionTextField setStringValue:latestVersion];
		else
			[_latestVersionTextField setStringValue:@""];
			
		NSString *latestCheck = [ovService latestCheck];
		if (latestCheck)
			[_latestCheckTextField setStringValue:latestCheck];
		else
			[_latestCheckTextField setStringValue:@""];	
	}
	else {
		[_currentVersionTextField setStringValue:@""];			
		[_latestVersionTextField setStringValue:@""];		
		[_latestCheckTextField setStringValue:@""];			
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
	NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"This build does not check for updates.") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"chichi77 KeyKey does not connect to the Internet.")];
	[alert beginSheetModalForWindow:_window modalDelegate:self didEndSelector:nil contextInfo:nil];
}

@end

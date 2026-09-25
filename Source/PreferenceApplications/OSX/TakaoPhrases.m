/*
Copyright (c) 2012, Yahoo! Inc.  All rights reserved.
Copyrights licensed under the New BSD License. See the accompanying LICENSE
file for terms.
*/
// [AUTO_HEADER]

#import "TakaoPhrases.h"

@implementation TakaoPhrases

- (void)awakeFromNib
{
	[_progressIndicator setIndeterminate:YES];
}

#pragma mark Import/Export

// Export database into a text file.
- (IBAction)exportDatabase:(id)sender
{
	id ovService;
	
	@try {
		ovService = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];		
	}
	@catch(NSException *e) {
		// NSLog(@"Exceptions raise on retreiving version info");	
		NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Unable to export database.") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Uknow errors happend.")];
		[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
		return;		
	}

	if (!ovService) {
		NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Unable to export database.") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"If you are not runnung chichi77 KeyKey, you are not able to export your database.")];
		[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
		return;
	}
	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setAllowedFileTypes:[NSArray arrayWithObjects:@"txt", nil]];
	[panel setExtensionHidden:NO];
	[panel setCanCreateDirectories:NO];
	[panel setNameFieldLabel:LFLSTR(@"Export As:")];
	[panel setRequiredFileType:@"txt"];
	[panel setTitle:LFLSTR(@"Export Database")];
	[panel setMessage:LFLSTR(@"Exporting your own customized phrases database.")];
	[panel setPrompt:LFLSTR(@"Export")];
	if ([panel runModal] == NSFileHandlingPanelOKButton) {
		NSString *path = [panel filename];
		if (ovService) {
			[ovService setProtocolForProxy:@protocol(OpenVanillaService)];
			bool rtn = [ovService exportUserPhraseDBToFile:path];
			if (rtn) {
				NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Done!") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Your phrases are successfully exported.")];
				[alert setAlertStyle:NSInformationalAlertStyle];
				[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
			}
			else {
				NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Error") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Unable to export database.")];
				[alert setAlertStyle:NSWarningAlertStyle];
				[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];				
			}
		}
	}
	else {
		// NSLog(@"Cancel");	
	}
}

// Import database from a text file.
- (IBAction)importDatabase:(id)sender
{
	id ovService;
	@try {
		ovService = [NSConnection rootProxyForConnectionWithRegisteredName:OPENVANILLA_DO_CONNECTION_NAME host:nil];		
	}
	@catch(NSException *e) {
		NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Unable to import database.") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Unknown errors happened.")];
		[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
		return;		
	}	
	if (!ovService) {
		NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Unable to import database.") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"If you are not runnung chichi77 KeyKey, you are not able to import your database.")];
		[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
		return;
	}	
	NSOpenPanel *panel = [NSOpenPanel openPanel];
	[panel setAllowedFileTypes:[NSArray arrayWithObjects:@"txt", nil]];
	[panel setExtensionHidden:NO];
	[panel setCanCreateDirectories:NO];	
	[panel setTitle:LFLSTR(@"Import Database")];
	[panel setMessage:LFLSTR(@"Import customized phrases to your own database.")];
	[panel setPrompt:LFLSTR(@"Choose")];
	if ([panel runModal] == NSFileHandlingPanelOKButton){
		NSString *path = [[panel filenames] objectAtIndex:0];
		if (ovService) {
			[ovService setProtocolForProxy:@protocol(OpenVanillaService)];
			bool rtn = [ovService importUserPhraseDBFromFile:path];
			if (rtn) {
				NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Done!") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Your phrases are successfully imported.")];
				[alert setAlertStyle:NSInformationalAlertStyle];				
				[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];				

			}
			else {
				NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Error") defaultButton:LFLSTR(@"OK") alternateButton:nil otherButton:nil informativeTextWithFormat:LFLSTR(@"Unable to import database.")];
				[alert setAlertStyle:NSWarningAlertStyle];
				[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
			}
		}
	}
	else {
		// NSLog(@"Cancel");
	}
}

- (IBAction)launchEditor:(id)sender
{
	// Preferences.app is installed beside PhraseEditor.app under the input
	// method's Contents/SharedSupport directory.
	NSString *sharedSupportPath = [[[NSBundle mainBundle] bundlePath] stringByDeletingLastPathComponent];
	NSString *phraseEditorPath = [sharedSupportPath stringByAppendingPathComponent:@"PhraseEditor.app"];
	BOOL launched = NO;

	if ([[NSFileManager defaultManager] fileExistsAtPath:phraseEditorPath]) {
		launched = [[NSWorkspace sharedWorkspace] openFile:phraseEditorPath];
	}

	if (!launched) {
		launched = [[NSWorkspace sharedWorkspace]
			launchAppWithBundleIdentifier:@"io.github.polobread.inputmethod.chichi77.PhraseEditor"
			options:NSWorkspaceLaunchDefault
			additionalEventParamDescriptor:nil
			launchIdentifier:nil];
	}

	if (!launched) {
		NSAlert *alert = [NSAlert alertWithMessageText:LFLSTR(@"Unable to launch user phrase editor.")
			defaultButton:LFLSTR(@"OK")
			alternateButton:nil
			otherButton:nil
			informativeTextWithFormat:LFLSTR(@"PhraseEditor.app is missing from the installed input method.")];
		[alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
	}
}

@end

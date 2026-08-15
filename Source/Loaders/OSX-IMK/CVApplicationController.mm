// [AUTO_HEADER]

#import "CVApplicationController.h"
#import "CVSendKey.h"
#import "CVNotifyController.h"
#import "OpenVanillaLoader.h"
#import "Minotaur.h"
//#import "Version.h"
#import "OpenVanillaController.h"

#if (MAC_OS_X_VERSION_MAX_ALLOWED < MAC_OS_X_VERSION_10_5)
#import <zlib.h>
#endif

using namespace CareService;
using namespace Minotaur;

// @todo in deployment, make this better
extern "C" {
extern char VendorMotcle[];
extern size_t VendorMotcleSize;
};

@implementation CVApplicationController

- (void)dealloc
{
	[_verticalCandidateController release];
	[_horizontalCandidateController release];
	[_plainTextCandidateController release];	
	[_searchController release];
	[_symbolController release];
	[_tooltipController release];
	[_aboutController release];
	[_inputMethodToggleWindowController release];
	[_versionInfo release];
	[super dealloc];
}
- (void)setLoader:(OpenVanillaLoader *)aLoader
{
    OpenVanillaLoader *tmp = _loader;
	
//	NSLog(@"if this instance's _loader is clean? %p", tmp);
//	
//	NSLog(@"loader instance: %p", aLoader);
//	NSLog(@"loader desc: %@", aLoader);
	
    _loader = [aLoader retain];
    if (tmp) {
        [tmp release];
    }
	
//	NSLog(@"finished retaining loader %@", _loader);
}
- (OpenVanillaLoader*)loader
{
    return _loader;
}

#pragma mark User Interface Controllers

- (CVVerticalCandidateController *)verticalCandidateController
{
    if (!_verticalCandidateController)
        _verticalCandidateController = [CVVerticalCandidateController new];

    return _verticalCandidateController;
}
- (CVHorizontalCandidateController *)horizontalCandidateController
{
    if (!_horizontalCandidateController)
        _horizontalCandidateController = [CVHorizontalCandidateController new];

    return _horizontalCandidateController;
}
- (CVPlainTextCandidateController *)plainTextCandidateController
{
    if (!_plainTextCandidateController)
        _plainTextCandidateController = [CVPlainTextCandidateController new];

    return _plainTextCandidateController;
}
- (CVSymbolController *)symbolController
{
    if (!_symbolController)
        _symbolController = [CVSymbolController new];

    return _symbolController;
}
- (CVToolTipController *)tooltipController
{
    if (!_tooltipController)
        _tooltipController = [CVToolTipController new];

    return _tooltipController;
}
- (CVSearchController *)searchController
{
    if (!_searchController)
        _searchController = [CVSearchController new];

    return _searchController;
}
- (CVAboutController *)aboutController
{
    if (!_aboutController)
        _aboutController = [CVAboutController new];

    return _aboutController;
}
- (CVInputMethodToggleWindowController *)inputMethodToggleWindowController
{
    if (!_inputMethodToggleWindowController)
        _inputMethodToggleWindowController = [CVInputMethodToggleWindowController new];

    return _inputMethodToggleWindowController;
}

#pragma mark To initialize the Application Controller

- (void)awakeFromNib
{
    _loader = nil;
	

    _serverPort = [[NSPort port] retain];
    _serverConnection  = [[NSConnection connectionWithReceivePort:_serverPort sendPort:_serverPort] retain];	
    
    // NSConnection *connection = [NSConnection defaultConnection];
    [_serverConnection setRootObject:self];
    
    if ([_serverConnection registerName:OPENVANILLA_DO_CONNECTION_NAME]) {
//	    NSLog(@"OpenVanilla DO service registered: %@", OPENVANILLA_DO_CONNECTION_NAME);
    }
    else {
        NSLog(@"Failed to register DO service");
    }
}

- (IBAction)showAboutWindow:(id)sender
{
	[[self aboutController] showWindow:sender];
}
- (NSDictionary *)_dictionaryWithIdentifier:(string)identifier localizedName:(NSString *)localizedName
{
	NSString *identifierString = [NSString stringWithUTF8String:identifier.c_str()];
	NSDictionary *d = [NSDictionary dictionaryWithObjectsAndKeys:identifierString, @"identifier", localizedName, @"localizedName", nil];
	return d;
}
- (NSArray *)inputMethodsArray
{
	NSMutableArray *a = [NSMutableArray array];
	
	NSMutableSet *excludeSet = [NSMutableSet set];
	
	PVPlistValue *configDict = [OpenVanillaLoader sharedLoader]->configRootDictionary();
	PVPlistValue *suppressSetting = configDict->valueForKey("ModulesSuppressedFromUI");
	if (suppressSetting) {
		if (suppressSetting->type() == PVPlistValue::Array) {
			size_t c = suppressSetting->arraySize();
			for (size_t i = 0 ; i < c ; i++) {
				[excludeSet addObject:[NSString stringWithUTF8String:suppressSetting->arrayElementAtIndex(i)->stringValue().c_str()]];
			}
		}
	}	
	
	if (![excludeSet containsObject:@"TraditionalMandarin"])
		[a addObject:[self _dictionaryWithIdentifier:("TraditionalMandarin") localizedName:LFLSTR(@"Traditional Phonetic")]];
	if (![excludeSet containsObject:@"Generic-cj-cin"])
		[a addObject:[self _dictionaryWithIdentifier:("Generic-cj-cin") localizedName:LFLSTR(@"Cangjie")]];
	if (![excludeSet containsObject:@"Generic-simplex-cin"])
		[a addObject:[self _dictionaryWithIdentifier:("Generic-simplex-cin") localizedName:LFLSTR(@"Simplex")]];	
	
	[excludeSet addObject:@"SmartMandarin"];
	[excludeSet addObject:@"TraditionalMandarin"];
	[excludeSet addObject:@"Generic-cj-cin"];
	[excludeSet addObject:@"Generic-simplex-cin"];

	vector<pair<string, string> >::iterator iter;    
    vector<pair<string, string> > idNamePairs = [OpenVanillaLoader sharedLoader]->allInputMethodIdentifiersAndNames();    

    for (iter = idNamePairs.begin(); iter != idNamePairs.end(); ++iter) {
        pair<string, string> idNamePair = *iter;        
        string identifier = idNamePair.first;
        string localizedName = idNamePair.second;
		
		if (![excludeSet containsObject:[NSString stringWithUTF8String:identifier.c_str()]]) {
			[a addObject:[self _dictionaryWithIdentifier:identifier localizedName:[NSString stringWithUTF8String:localizedName.c_str()]]];
		}
    }
	
	if (![a count]) {
		[a addObject:[self _dictionaryWithIdentifier:("TraditionalMandarin") localizedName:LFLSTR(@"Traditional Phonetic")]];
	}
	
	return a;
}

#pragma mark -
#pragma mark Distributed Object Methods

- (oneway void)reloadOpenVanilla
{
    NSLog(@"Reloading OpenVanilla");
    [[OpenVanillaLoader sharedInstance] reload];
    NSLog(@"Finished reloading OpenVanilla");
}
- (NSString *)primaryInputMethod
{
	NSString *primaryInputMethod = [NSString stringWithUTF8String:[OpenVanillaLoader sharedLoader]->primaryInputMethod().c_str()];
	return primaryInputMethod;
}
- (NSArray*)identifiersAndLocalizedNamesWithPattern:(NSString*)pattern
{
	//NSLog(@"calling remote stuff");
    return [_loader identifiersAndLocalizedNamesWithPattern:pattern];
}
- (bool)exportUserPhraseDBToFile:(NSString*)path
{
    return [_loader exportUserPhraseDBToFile:path];
}
- (bool)importUserPhraseDBFromFile:(NSString*)path
{
    return [_loader importUserPhraseDBFromFile:path];
}

- (NSString *)version
{
 return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleVersion"];
}

- (NSString *)latestVersion
{
 if (_versionInfo == nil) 
     [self _loadVersionInfo];
 NSString *latestVersion = [_versionInfo valueForKey:@"latestVersion"];
 if (latestVersion)
     return latestVersion;
 else
     return @"";
}
- (NSString *)latestCheck
{
 if (_versionInfo == nil) 
     [self _loadVersionInfo];
 NSDate *date = [_versionInfo valueForKey:@"latestCheck"];
 if (!date)
     return @"";
 NSDateFormatter *dateFormatter = [[[NSDateFormatter alloc] init]  autorelease];
 [dateFormatter setDateStyle:NSDateFormatterMediumStyle];
 [dateFormatter setTimeStyle:NSDateFormatterNoStyle];
 return [dateFormatter stringFromDate:date]; 
}

- (NSData *)_updateDataUsingBlockingFetch
{
    // The update service this used to poll is gone, and the loader no
    // longer carries an endpoint. Report no data rather than reach out.
    return nil;
}

- (NSDictionary *)shouldUpdate
{
    return [self shouldUpdateWithVersionInfoData:nil versionInfoSignatureData:nil];
}

- (NSDictionary *)shouldUpdateWithVersionInfoData:(NSData *)infoData versionInfoSignatureData:(NSData *)sigData
{
	// NSLog(@"%s, %p, %p", __PRETTY_FUNCTION__, infoData, sigData);
    NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];

    NSData *versionInfoData = infoData;
    if (!versionInfoData) {
        versionInfoData = [self _updateDataUsingBlockingFetch];
    }
    
    if (!versionInfoData) {
        [dictionary setValue:@"Error" forKey:@"Status"];
        [dictionary setValue:@"No version info data" forKey:@"Error"];
        return dictionary;
    }
 
    NSString *versionInfoFilePath = [self randomTemporaryFilenameWithFullpath];
    [versionInfoData writeToFile:versionInfoFilePath atomically:YES];
    
    NSData *versionInfoSignatureData = sigData;

    if (![versionInfoSignatureData length]) {
         [dictionary setValue:@"Error" forKey:@"Status"];
         [dictionary setValue:@"No signature data" forKey:@"Error"];
         return dictionary;
    }
    
    NSString *versionInfoSignatureFilePath = [self randomTemporaryFilenameWithFullpath]; 
    [versionInfoSignatureData writeToFile:versionInfoSignatureFilePath atomically:YES];
    if (![self validateFile:versionInfoFilePath againstSignature:versionInfoSignatureFilePath]) {
        [dictionary setValue:@"Error" forKey:@"Status"];
        [dictionary setValue:@"Bad signature" forKey:@"Error"];
        return dictionary;
    }
 
    // NSLog(@"checking component for update, name: %s", OPENVANILLA_LOADER_COMPONENT_NAME);
    NSDictionary *actionDictionary = [self shouldComponentNamed:[NSString stringWithUTF8String:OPENVANILLA_LOADER_COMPONENT_NAME] versionInfoXMLFile:versionInfoFilePath];
 
	NSDate *now = [NSDate date];
    NSString *latestVersion = [actionDictionary valueForKey:@"latestVersion"];
	
    NSString *action = [actionDictionary valueForKey:@"UpdateAction"];
    if (action == nil || ![action length]) {
		// NSLog(@"loader doesn't need update, now checking: %d", OPENVANILLA_DATABASE_COMPONENT_NAME);
		actionDictionary = [self shouldComponentNamed:[NSString stringWithUTF8String:OPENVANILLA_DATABASE_COMPONENT_NAME] versionInfoXMLFile:versionInfoFilePath];
	}
	
    if (_versionInfo)
        [_versionInfo release];
        
    _versionInfo = [[NSMutableDictionary dictionary] retain];
    [_versionInfo setValue:now forKey:@"latestCheck"];
    [_versionInfo setValue:latestVersion forKey:@"latestVersion"];
    [self _saveVersionInfo];
     
    if (![actionDictionary count]) {
        [dictionary setValue:@"No" forKey:@"Status"];
        return dictionary;  
    }
 
    action = [actionDictionary valueForKey:@"UpdateAction"];
    if (action == nil || ![action length]) {
         [dictionary setValue:@"No" forKey:@"Status"];
         return dictionary;
    }
    [dictionary setValue:@"Yes" forKey:@"Status"];
    [dictionary addEntriesFromDictionary:actionDictionary];
    return dictionary;
}

- (bool)validateFile:(NSString*)filename againstSignature:(NSString*)signatureFilename
{
    string upf = [filename UTF8String];
    string usf = [signatureFilename UTF8String];

    pair<char*, size_t> sigfile = OVFileHelper::SlurpFile(usf);
    
    if (!sigfile.first)
        return NO;

    bool valid = NO;
    
    if (Minos::ValidateFile(upf, sigfile, pair<char*, size_t>(VendorMotcle, VendorMotcleSize)))
        valid = YES;

    free(sigfile.first);
    return valid;
}
- (NSString*)randomTemporaryFilenameWithFullpath
{
    string tmpDir = OVPathHelper::PathCat(OVDirectoryHelper::TempDirectory(), "XXXXXXXXXX");
    char *tmp = (char*)calloc(1, tmpDir.size() + 1);
    strncpy(tmp, tmpDir.c_str(), tmpDir.size());
    mktemp(tmp);
    NSString *result = [NSString stringWithUTF8String:tmp];
    free(tmp);
    return result;
}

- (NSDictionary*)shouldComponentNamed:(NSString*)component versionInfoXMLFile:(NSString*)filename 
{
    [_loader versionChecker]->loadVersionInfoXMLFile([filename UTF8String]);

    if (![_loader versionChecker]->componentNeedsUpdating([component UTF8String])) {
     NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
     [dictionary setValue:[NSString stringWithUTF8String:[_loader versionChecker]->latestVersion().c_str()] forKey:@"latestVersion"];        
     return dictionary;
    }
    
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionary];
	[dictionary setValue:[NSString stringWithUTF8String:[_loader versionChecker]->updateAction().c_str()] forKey:@"UpdateAction"];
	[dictionary setValue:[NSString stringWithUTF8String:[_loader versionChecker]->actionURL().c_str()] forKey:@"ActionURL"];
	[dictionary setValue:[NSString stringWithUTF8String:[_loader versionChecker]->signatureURL().c_str()] forKey:@"SignatureURL"];  
	[dictionary setValue:[NSString stringWithUTF8String:[_loader versionChecker]->latestVersion().c_str()] forKey:@"latestVersion"];        
 
    string changeLogBaseURL = [_loader versionChecker]->changeLogBaseURL();
    string localeTag = [_loader versionChecker]->changeLogLocaleTagURL();
    string changeLogURL = OVStringHelper::StringByReplacingOccurrencesOfStringWithString(changeLogBaseURL, localeTag, [_loader loaderService]->locale());
 
	[dictionary setValue:[NSString stringWithUTF8String:changeLogURL.c_str()] forKey:@"ChangeLogURL"];
	return dictionary;
}
- (NSString*)userInformationForCareService
{
    stringstream sst;
    PVPlistValue* allPlists = [_loader loader]->loaderAndModulePropertyListsCombined();
    sst << *allPlists << endl;
    delete allPlists;
    return [NSString stringWithUTF8String:sst.str().c_str()];
}

- (oneway void)sendString:(NSString *)text
{
	[OpenVanillaController sendComposedStringToCurrentlyActiveContext:text];
}
- (oneway void)sendKey:(NSString *)key
{
	[[CVSendKey sharedSendKey] typeString:key];
}

- (BOOL)userPhraseDBCanProvideService
{
    return [_loader userPhraseDBCanProvideService];    
}
- (int)userPhraseDBNumberOfRow
{
    return [_loader userPhraseDBNumberOfRow];    
}
- (NSDictionary *)userPhraseDBDictionaryAtRow:(int)row
{
    return [_loader userPhraseDBDictionaryAtRow:row];        
}
- (NSArray *)userPhraseDBReadingsForPhrase:(NSString *)phrase
{
    return [_loader userPhraseDBReadingsForPhrase:phrase];            
}
- (void)userPhraseDBSave
{
    [_loader userPhraseDBSave];
}
- (void)userPhraseDBSetNewReading:(NSString *)reading forPhraseAtRow:(int)row
{
    [_loader userPhraseDBSetNewReading:reading forPhraseAtRow:row];
}
- (void)userPhraseDBDeleteRow:(int)row
{
    [_loader userPhraseDBDeleteRow:row];
}
- (void)userPhraseDBAddNewRow:(NSString *)phrase
{
    [_loader userPhraseDBAddNewRow:phrase];
}
- (void)userPhraseDBAddNewRows:(NSArray *)array
{
    [_loader userPhraseDBAddNewRows:array];
}

- (void)userPhraseDBSetPhrase:(NSString *)phrase atRow:(int)row
{
    [_loader userPhraseDBSetPhrase:phrase atRow:row];
}

- (NSString *)databaseVersion
{
	return [_loader databaseVersion];
}

- (NSArray *)dynamicallyLoadedModulePackageInfo
{
	return [_loader dynamicallyLoadedModulePackageInfo];
}

- (void)setBlackListOfPackageIdentifers:(NSArray *)inIdentifiers
{
	[_loader setBlackListOfPackageIdentifers:inIdentifiers];
}

@end

#pragma mark -

@implementation CVApplicationController(versionInfo)
- (NSString *)_plistFilepath: (NSString *)filename
{
	NSString *libPath = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory,NSUserDomainMask,YES) objectAtIndex:0];
	NSString *prefPath = [libPath stringByAppendingPathComponent:@"Preferences"];

	if (![[NSFileManager defaultManager] fileExistsAtPath:prefPath isDirectory:NULL]) {
		[[NSFileManager defaultManager] createDirectoryAtPath:prefPath attributes:nil];
	}
	return [prefPath stringByAppendingPathComponent:filename];	
}
- (NSString *)_versionInfoPath
{
	[self _plistFilepath:@"io.github.polobread.chichi77.UpdateCheck.plist"];
}
- (void)_saveVersionInfo
{
    NSString *errorString = nil;
    NSData *data = [NSPropertyListSerialization dataFromPropertyList:_versionInfo format:NSPropertyListXMLFormat_v1_0 errorDescription:&errorString];

    if (errorString)
        [errorString release];

    if (data)
        [data writeToFile:[self _versionInfoPath] atomically:YES];
}
- (void)_loadVersionInfo
{
	[_versionInfo release];
	_versionInfo = [[NSMutableDictionary dictionary] retain];
	NSData *data = [NSData dataWithContentsOfFile:[self _versionInfoPath] options:0 error:nil];
	if (data) {
		NSPropertyListFormat format;	
		NSString *errorString = nil;		
		NSMutableDictionary *d = [NSPropertyListSerialization propertyListFromData:data mutabilityOption:NSPropertyListImmutable format: &format errorDescription:&errorString];
		if (d) {
			[_versionInfo addEntriesFromDictionary:d];
		}
	} // end data
}

@end

@implementation CVApplicationController(AppDelegate)

- (NSString *)_validatedString:(NSString *)originalString
{
	NSString *string = [originalString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	
	if (!string && ![string length])
		return nil;
	int i;
	NSMutableString *validatedString = [NSMutableString string];
	for (i = 0; i < [string length]; i++) {
		unichar aChar = [originalString characterAtIndex:i];
		if (aChar >= 0x2E80 && aChar < 0xFF00) {
			[validatedString appendFormat:@"%C", aChar];
		}
	}
	return validatedString;
}


- (void)handleIncomingURL:(NSAppleEventDescriptor *)event withReplyEvent:(NSAppleEventDescriptor *)replyEvent
{
	NSString *url = [[[event paramDescriptorForKeyword:keyDirectObject] stringValue] stringByReplacingPercentEscapesUsingEncoding:NSUTF8StringEncoding];
	if ([url hasPrefix:@"ykeykey://"]) {
		NSString *string = [url substringWithRange:NSMakeRange(10, [url length] - 10)];	
		NSArray *a = [string componentsSeparatedByString:@"_"];
		if ([a count] < 2) {
			NSString *phrase = [self _validatedString:string];
			if (![phrase length]) {
				[CVNotifyController notify:LFLSTR(@"The phrase you want to add is invalid.")];
				return;
			}
			[self userPhraseDBAddNewRow:phrase];
			NSString *msg = [NSString stringWithFormat:@"%@%@", LFLSTR(@"Add new phrase: "), phrase];
			[CVNotifyController notify:msg];
		}
		else if ([a count] == 2) {
			NSString *phrase = [self _validatedString:[a objectAtIndex:0]];
			NSString *reading = [a objectAtIndex:1];
			if ([phrase length] != [[reading componentsSeparatedByString:@","] count]) {
				[CVNotifyController notify:LFLSTR(@"The phrase you want to add is invalid.")];
				return;
			}
			[self userPhraseDBAddNewRow:phrase];
			int lastRow = [self userPhraseDBNumberOfRow] - 1;
			[self userPhraseDBSetPhrase:phrase atRow:lastRow];
			[self userPhraseDBSetNewReading:reading forPhraseAtRow:lastRow];
			
			NSString *msg = [NSString stringWithFormat:@"%@%@", LFLSTR(@"Add new phrase: "), phrase];
			[CVNotifyController notify:msg];
		}
	}
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification
{
	[[NSAppleEventManager sharedAppleEventManager] setEventHandler:self andSelector:@selector(handleIncomingURL:withReplyEvent:) forEventClass:kInternetEventClass andEventID:kAEGetURL];
}

@end
// [AUTO_HEADER]

#import "OpenVanillaConfig.h"
#import "OpenVanillaLoader.h"
#import "OVOFFullWidthCharacterPackage.h"
#import "OVOFHanConvertPackage.h"
#import "OVAFBopomofoCorrectionPackage.h"
#import "OVAFEvalPackage.h"
#import "CVApplicationController.h"

#import "YKAFOneKeyPackage.h"
#import "YKSignedModuleLoadingSystem.h"

#import "GuanyinmaMacAdapter.h"
#import "OpenVanillaController.h"
#import "GuanyinmaMacUserData.h"
#import "GuanyinmaMacReadingCodec.h"
#import "LFCrossDevelopmentTools.h"

#import <zlib.h>
#import <os/log.h>

#include <sstream>
#include <set>
#include <memory>
#include <climits>

#import "LFUtilities.h"

NSString *CVLoaderUpdateCannedMessagesNotification = @"CVLoaderUpdateCannedMessagesNotification";

string FetchDatabaseVersionInfo(OVSQLiteConnection *connection, const string& dbAndTableName)
{
    string result;
    OVSQLiteStatement *statement = connection->prepare("SELECT value FROM %s WHERE KEY = %Q", dbAndTableName.c_str(), "version");
    
    if (statement) {
        if (statement->step() == SQLITE_ROW) {
            result = statement->textOfColumn(0);
            while (statement->step() == SQLITE_ROW) ;
        }
        
        delete statement;
    }
    
    return result;
}

class CVLoaderHookedServiceDelegate : public PVLoaderHookedServiceDelegate {
public:
	virtual void* loaderSpecificDataObjectForName(const string& name)
	{
		if (name == "OneKeyDataCopy") {
			void *copy = 0;
			
			@synchronized([OpenVanillaLoader sharedInstance]) {
				copy = [[OpenVanillaLoader sharedInstance] mergedOneKeyData]->copy();
			}
			
			return copy;
		}
		
		return 0;
	}
};

#ifdef OVLOADER_USE_SQLITE_CRYPTO
void InitSQLiteCrypto(sqlite3* db);
string FetchSQLiteCERODKey(const string& filename);
#endif

OpenVanillaLoader *OVLSharedInstance = nil;
NSLock *OVLSharedLock = nil;

using namespace OpenVanilla;

@interface OpenVanillaLoader (GuanyinmaAdministration)
- (string)_guanyinmaUserDatabasePath;
- (string)_qstringFromReading:(NSString*)reading;
@end

@implementation OpenVanillaLoader

#pragma mark Class methods

+ (OpenVanillaLoader*)sharedInstance
{
    if (!OVLSharedInstance) {
        OVLSharedInstance = [[OpenVanillaLoader alloc] init];
    }
    
    return OVLSharedInstance;
}
+ (PVLoader*)sharedLoader
{
    return [[OpenVanillaLoader sharedInstance] loader];
}
+ (PVLoaderService*)sharedLoaderService
{
    return [[OpenVanillaLoader sharedInstance] loaderService];
}
+ (VersionChecker*)sharedVersionChecker
{
    return [[OpenVanillaLoader sharedInstance] versionChecker];
}
+ (NSLock *)sharedLock
{
    if (!OVLSharedLock) {
        OVLSharedLock = [[NSLock alloc] init];
    }

    return OVLSharedLock;
}
+ (void)releaseSharedObjects
{
    [OVLSharedInstance release];
    [OVLSharedLock release];
}
+ (NSString*)locale
{
	// See here http://developer.apple.com/qa/qa2006/qa1391.html
    // We'll return canonical locale names, so zh-Hant and zh-Hans instead of zh_TW and zh_CN
    
    NSArray *languages = [[NSUserDefaults standardUserDefaults] objectForKey:@"AppleLanguages"];
    if ([languages count])
        return [languages objectAtIndex:0];
    
    return @"en";
}

#pragma mark Instance methods

- (id)init
{
	if (self = [super init]) {
		_loaderPolicy = 0;
		_encodingService = 0;
		_loaderService = 0;
		_bundleLoadingSystem = 0;
		_staticModuleLoadingSystem = 0;
		_signedModuleLoadingSystem = 0;
		_loader = 0;
		_CINDatabaseService = 0;
		_SQLiteDatabaseService = 0;
		_versionChecker = 0;
		
		_mergedCannedMessagesArray = [NSMutableArray new];
		_mergedOneKeyData = new PVPlistValue(PVPlistValue::Dictionary);
				
		_loaderServiceDelegate = new CVLoaderHookedServiceDelegate;
			
		_userOneKeyPlist = 0;
		_userCannedMessagePlist = 0;
		_userFreeCannedMessageFileTimestamp = new OVFileTimestamp;

		return self;
		
	}
	
	return self;
}
- (void)dealloc
{
    [self shutDown];

	[_mergedCannedMessagesArray release];
	delete _mergedOneKeyData;
	
	if (_userOneKeyPlist) {
		delete _userOneKeyPlist;
	}
	
	if (_userCannedMessagePlist) {
		delete _userCannedMessagePlist;
	}
	
    [super dealloc];
}
- (void)createDatabaseServices
{
	_userPersistence->setDefaultDatabaseConnection(0, "");
	
    if (_CINDatabaseService) {
        delete _CINDatabaseService;
        _CINDatabaseService = 0;
    }
        
    if (_SQLiteDatabaseService) {
        delete _SQLiteDatabaseService;
        _SQLiteDatabaseService = 0;
    }
        
    string resourcePath = [[[NSBundle mainBundle] resourcePath] UTF8String];
    string cinPath = OVPathHelper::PathCat(resourcePath, "DataTables");
    string dbPath = OVPathHelper::PathCat(resourcePath, "Databases");
    string userDataPath = OVDirectoryHelper::UserApplicationSupportDataDirectory(_loaderPolicy->loaderName());
    string userTablePath = OVPathHelper::PathCat(userDataPath, "DataTables");
	
	NSString *libAppSupportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask, YES) objectAtIndex:0];
	
	string libAppSupportLoaderPath = OVPathHelper::PathCat([libAppSupportPath UTF8String], _loaderPolicy->loaderName());
	string libAppSupportDBPath = OVPathHelper::PathCat(libAppSupportLoaderPath, "Databases");
	string supplementDBFile = OVPathHelper::PathCat(libAppSupportDBPath, "Supplement.db");
	
	cerr << supplementDBFile << endl;
	
	string supplementDBVersion;
    string mainDBVersion;

	#ifdef OPENVANILLA_CEROD_DATABASE_FILE
	string dbFile = OVPathHelper::PathCat(dbPath, [OPENVANILLA_CEROD_DATABASE_FILE UTF8String]);
	#else
    string dbFile = OVPathHelper::PathCat(dbPath, _loaderPolicy->defaultDatabaseFileName());
	#endif
    
    // NSLog(@"cin path = %s", cinPath.c_str());
    _CINDatabaseService = new OVCINDatabaseService(cinPath, "*.cin", "", 0);
    if (_CINDatabaseService) {
        if (OVDirectoryHelper::CheckDirectory(userTablePath)) {
            // NSLog(@"user cin path = %s", userTablePath.c_str());
            _CINDatabaseService->addDirectory(userTablePath, "*.cin", "", 0);
        }
        
        // NSLog(@"tables available = %d", _CINDatabaseService->tables().size());
    }
	
    // NSLog(@"db file = %s", dbFile.c_str());
    
    #ifndef OVLOADER_USE_SQLITE_CRYPTO
        _SQLiteDatabaseService = OVSQLiteDatabaseService::Create(dbFile);
    #else
		#ifdef OPENVANILLA_CEROD_DATABASE_FILE
			dbFile = FetchSQLiteCERODKey(dbFile);
			OVSQLiteConnection* dbc = OVSQLiteConnection::Open(dbFile);
	
			if (OVPathHelper::PathExists(supplementDBFile)) {
				NSLog(@"supplement database file = %s, exists: %d", supplementDBFile.c_str(), OVPathHelper::PathExists(supplementDBFile));

				supplementDBFile = FetchSQLiteCERODKey(supplementDBFile);				
				int attachResult = dbc->execute("ATTACH %Q AS supplement", supplementDBFile.c_str());
                // NSLog(@"attach result: %d", attachResult);

				if (attachResult == SQLITE_OK) {
					NSLog(@"fetching attached db version info");
					supplementDBVersion = FetchDatabaseVersionInfo(dbc, "supplement.cooked_information");                    
				}				
			}
		#else
			OVSQLiteConnection* dbc = OVSQLiteConnection::Open(dbFile);
			InitSQLiteCrypto(dbc->connection());
		#endif
	
        _SQLiteDatabaseService = OVSQLiteDatabaseService::ServiceWithExistingConnection(dbc, true);
        
        if (dbc->execute("PRAGMA synchronous = OFF") == SQLITE_OK) {
            // NSLog(@"pragma executed");
        }
        else {
            // NSLog(@"pragma execution failed");
        }

		mainDBVersion = FetchDatabaseVersionInfo(_SQLiteDatabaseService->connection(), "cooked_information");
	#endif
	
	if (supplementDBVersion.size()) {
		_versionChecker->registerComponentVersion(OPENVANILLA_DATABASE_COMPONENT_NAME, supplementDBVersion, true);            
		NSLog(@"Registered supplement DB '%s' version '%s'", OPENVANILLA_DATABASE_COMPONENT_NAME, supplementDBVersion.c_str());
		
		[_databaseVersion autorelease];
		_databaseVersion = [[NSString alloc] initWithUTF8String:supplementDBVersion.c_str()];
		
		// see if main DB's version is newer!
		if (mainDBVersion.size()) {
			if (VersionNumber(mainDBVersion) >= VersionNumber(supplementDBVersion)) {
				NSLog(@"Detaching supplement DB because it's older");
				_SQLiteDatabaseService->connection()->execute("DETACH supplement");
				_versionChecker->registerComponentVersion(OPENVANILLA_DATABASE_COMPONENT_NAME, mainDBVersion, true);                                
				[_databaseVersion autorelease];
				_databaseVersion = [[NSString alloc] initWithUTF8String:mainDBVersion.c_str()];
			}
		}            
	}
	else if (mainDBVersion.size()) {
		_versionChecker->registerComponentVersion(OPENVANILLA_DATABASE_COMPONENT_NAME, mainDBVersion, true);            
		NSLog(@"Registered main DB '%s' version '%s'", OPENVANILLA_DATABASE_COMPONENT_NAME, mainDBVersion.c_str());            

		[_databaseVersion autorelease];
		_databaseVersion = [[NSString alloc] initWithUTF8String:mainDBVersion.c_str()];
	}            	
    
    if (!_SQLiteDatabaseService) {
        NSLog(@"Cannot open database file %s, use in-memory SQLite database instead", dbFile.c_str());
        _SQLiteDatabaseService = OVSQLiteDatabaseService::Create();
    }
	_userPersistence->setDefaultDatabaseConnection(_SQLiteDatabaseService->connection(), "prepopulated_service_data");

	if (!_userCannedMessagePlist) {		
		_userCannedMessagePlist = new PVPropertyList(OVPathHelper::PathCat(userDataPath, "UserCannedMessages.plist"));    
	}
	
	if (!_userOneKeyPlist) {
		_userOneKeyPlist = new PVPropertyList(OVPathHelper::PathCat(userDataPath, "UserOneKey.plist"));
	}
	
}

- (void)_firstTimeUpdateUserData
{
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=initial-data-start");
	[self mergeOneKeyData];
	[self mergeCannedMessagesData];
	[[NSNotificationCenter defaultCenter] postNotificationName:CVLoaderUpdateCannedMessagesNotification object:self];	
}

- (void)_addInitializedStaticMoudlePackages
{
    OVModulePackage* pkg;
    OVPathInfo pathInfo = _loaderPolicy->modulePackagePathInfoFromPath("");
    
    const string modelPath = _SQLiteDatabaseService->filename();
    const string userPath = OVPathHelper::PathCat(pathInfo.writablePath, "GuanyinmaUserData.db");
    pkg = GuanyinmaCreateModulePackage(modelPath, userPath);
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("GuanyinmaPackage", pkg);

    pkg = new OVOFFullWidthCharacterPackage;
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("OVOFFullWidthCharacterPackage", pkg);
    
    pkg = new OVOFHanConvertPackage;    
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("OVOFHanConvertPackage", pkg);
    
    pkg = new OVAFBopomofoCorrectionPackage;    
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("OVAFBopomofoCorrectionPackage", pkg);
	
    pkg = new YKAFOneKeyPackage;
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("YKAFOneKeyPackage", pkg);	
    
    pkg = new OVAFEvalPackage;    
    pkg->initialize(&pathInfo, _loaderService);
    _staticModuleLoadingSystem->addInitializedPackage("OVAFEvalPackage", pkg);	    
}

- (void)reload
{
    [[OpenVanillaLoader sharedLock] lock];

    // finalize loader's inner workings
    _loaderService->logger("OpenVanilla") << "Preparing to reload OpenVanilla" << endl;
    _loader->prepareReload();
    
    // now loader's module package manager is dead, we now refresh the bundle loading system
    _staticModuleLoadingSystem->flushModules();
    _bundleLoadingSystem->unloadAllUnloadables();
	_bundleLoadingSystem->reset();
    _bundleLoadingSystem->rescan(_loaderPolicy);

	_signedModuleLoadingSystem->unloadAllUnloadables();
	_signedModuleLoadingSystem->reset();
	_signedModuleLoadingSystem->rescan(_signedModulesLoaderPolicy);
	
    // reload the databases
    [self createDatabaseServices];
    _loaderService->setCINDatabaseService(_CINDatabaseService);
    _loaderService->setSQLiteDatabaseService(_SQLiteDatabaseService);

    [self _addInitializedStaticMoudlePackages];
    
    _loader->reload();

	// NSLog(@"loaded: %@", [self dynamicallyLoadedModulePackageInfo]);

    [[OpenVanillaLoader sharedLock] unlock];
}

- (bool)start:(NSArray*)loadPaths
{
    NSAutoreleasePool *pool = [NSAutoreleasePool new];
    [[OpenVanillaLoader sharedLock] lock];

    if (_loader)
        return true;
        
    vector<string> cppLoadPaths;

	#ifndef OVLOADER_SUPPRESS_LOADPATHS
	NSEnumerator *loadPathsEnumerator = [loadPaths objectEnumerator];
	NSString *path;
	while (path = [loadPathsEnumerator nextObject]) {
//    for (NSString* path in loadPaths) {
        cppLoadPaths.push_back([path UTF8String]);
	}
	#endif

	NSBundle *bundle = [NSBundle mainBundle];
    NSDictionary *infoDictionary = [bundle infoDictionary];
    NSString *bundleVersion = [infoDictionary objectForKey:@"CFBundleVersion"];
	
    _versionChecker = new VersionChecker;    
    if (bundleVersion) {
        // NSLog(@"%s version %@", OPENVANILLA_LOADER_COMPONENT_NAME, bundleVersion);
        _versionChecker->registerComponentVersion(OPENVANILLA_LOADER_COMPONENT_NAME, [bundleVersion UTF8String]);
    }
	
    _loaderPolicy = new PVLoaderPolicy(cppLoadPaths);
	string loaderUserDataPath = OVDirectoryHelper::UserApplicationSupportDataDirectory(_loaderPolicy->loaderName());

	vector<string> signedModuleLoadPaths;
	do {
		NSString *libAppSupportPath = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSLocalDomainMask, YES) objectAtIndex:0];
		
		string libAppSupportLoaderPath = OVPathHelper::PathCat([libAppSupportPath UTF8String], _loaderPolicy->loaderName());
		string modulePath = OVPathHelper::PathCat(libAppSupportLoaderPath, "SignedModules");
		
//		if (OVPathHelper::PathExists(modulePath) && OVPathHelper::IsDirectory(modulePath)) {
//			NSLog(@"has signed module path: %s", modulePath.c_str());
			signedModuleLoadPaths.push_back(modulePath);
//		}
	} while(0);
	_signedModulesLoaderPolicy = new PVLoaderPolicy(signedModuleLoadPaths);
	_signedModuleLoadingSystem = new YKSignedModuleLoadingSystem(_signedModulesLoaderPolicy);
	
	// create user persistence
	string userPersistenceDBPath = OVPathHelper::PathCat(loaderUserDataPath, "UserData.db");
    _userPersistence = new OVLoaderUserPersistence(userPersistenceDBPath);    
    [self createDatabaseServices];

	
	// allows user modules...    
	string userModulePath = OVPathHelper::PathCat(loaderUserDataPath, "Modules");
    _loaderPolicy->addModulePackageLoadPath(userModulePath);
    
    _encodingService = new CVEncodingService;
    
    // since we don't know when Tiger has changed the locale tags, and it's a disaster...
    string naturalLocale = [[OpenVanillaLoader locale] UTF8String];
    
    if (OVWildcard::Match(naturalLocale, "zh?Hant*") || OVWildcard::Match(naturalLocale, "zh?TW*"))
        naturalLocale = "zh_TW";

    if (OVWildcard::Match(naturalLocale, "zh?Hans*") || OVWildcard::Match(naturalLocale, "zh?CN*"))
        naturalLocale = "zh_CN";
    
    _loaderService = new PVLoaderService(naturalLocale, _CINDatabaseService, _SQLiteDatabaseService, 0 /* uses default log emitter */, _encodingService);
	_loaderService->setHookedServiceDelegate(_loaderServiceDelegate);
    _bundleLoadingSystem = new PVBundleLoadingSystem(_loaderPolicy);

    OVPathInfo pathInfo = _loaderPolicy->modulePackagePathInfoFromPath("");
    
    // and we want _staticModuleLoadingSystem to own the packages we created, so that we don't have to worry about them
    _staticModuleLoadingSystem = new PVStaticModulePackageLoadingSystem(pathInfo, true);    
    [self _addInitializedStaticMoudlePackages];
    
    
    vector<PVModulePackageLoadingSystem*> loadingSystems;
    loadingSystems.push_back(_staticModuleLoadingSystem);
    loadingSystems.push_back(_bundleLoadingSystem);
	loadingSystems.push_back(_signedModuleLoadingSystem);

    _loader = new PVLoader(_loaderPolicy, _loaderService, loadingSystems);
    

    OVKeyValueMap kvm = _loader->configKeyValueMap();    
    bool writeConfig = false;

    string platformSummary = SystemInfo::PlatformSummary();
    string loaderVersion;
    loaderVersion = [bundleVersion UTF8String];
    
    if (kvm.stringValueForKey("PlatformSummary") != platformSummary) {
        kvm.setKeyStringValue("PlatformSummary", platformSummary);
        writeConfig = true;        
    }
    
    if (kvm.stringValueForKey("LoaderVersion") != loaderVersion) {
        kvm.setKeyStringValue("LoaderVersion", loaderVersion);
        writeConfig = true;                
    }
    
    if (!kvm.hasKey("DefaultInputMode")) {
        kvm.setKeyStringValue("DefaultInputMode", "Chinese");
        writeConfig = true;
    }

    if (!kvm.hasKey("ToggleInputModeWithShift")) {
        kvm.setKeyStringValue("ToggleInputModeWithShift", "true");
        writeConfig = true;
    }

    if (!kvm.hasKey("UUID")) {
        kvm.setKeyStringValue("UUID", UUIDHelper::CreateUUID());
        writeConfig = true;
    }

    if (!kvm.stringValueForKey("PrimaryInputMethod").length()) {
        kvm.setKeyStringValue("PrimaryInputMethod", "SmartMandarin");
        writeConfig = true;
    }
        
    if (writeConfig)
        _loader->syncLoaderConfig(true);
	
	if (!_loader->primaryInputMethod().size()) {
		_loader->setPrimaryInputMethod("SmartMandarin");
        _loader->syncSandwichConfig();
	}

	// NSLog(@"unlocking");
    [[OpenVanillaLoader sharedLock] unlock];
	
	// NSLog(@"scheduling");
	[self performSelectorOnMainThread:@selector(_firstTimeUpdateUserData) withObject:nil waitUntilDone:NO];
	
	sleep(1);

	// NSLog(@"loaded: %@", [self dynamicallyLoadedModulePackageInfo]);
	
    [pool drain];
    return true;
}
- (void)shutDown
{
    [[OpenVanillaLoader sharedLock] lock];

    if (_loader) {
        delete _loader;
        _loader = 0;
    }
        
    if (_staticModuleLoadingSystem) {
        delete _staticModuleLoadingSystem;
        _staticModuleLoadingSystem = 0;
    }
    
    if (_bundleLoadingSystem) {
        delete _bundleLoadingSystem;
        _bundleLoadingSystem = 0;
    }
	
	if (_signedModuleLoadingSystem) {
		delete _signedModuleLoadingSystem;
		_signedModuleLoadingSystem = 0;
	}
	
    if (_loaderService) {
        delete _loaderService;
        _loaderService = 0;
    }
    
    if (_CINDatabaseService) {
        delete _CINDatabaseService;
        _CINDatabaseService = 0;
    }
    
    if (_SQLiteDatabaseService) {
        delete _SQLiteDatabaseService;
        _SQLiteDatabaseService = 0;
    }
    
    if (_encodingService) {
        delete _encodingService;
        _encodingService = 0;
    }

	if (_signedModulesLoaderPolicy) {
		delete _signedModulesLoaderPolicy;
		_signedModulesLoaderPolicy = 0;
	}
	
    if (_loaderPolicy) {
        delete _loaderPolicy;
        _loaderPolicy = 0;
    }

    if (_versionChecker) {
        delete _versionChecker;
        _versionChecker = 0;
    }
    
    [[OpenVanillaLoader sharedLock] unlock];
}
- (PVLoader*)loader
{
    return _loader;
}
- (PVLoaderService*)loaderService
{
    return _loaderService;
}
- (NSArray*)identifiersAndLocalizedNamesWithPattern:(NSString*)pattern
{
    NSMutableArray *result = [NSMutableArray array];
    vector<pair<string, string> > rsp = _loader->allModuleIdentifiersAndNames();
    OVWildcard exp = OVWildcard(string([pattern UTF8String]));
    
    for (vector<pair<string, string> >::iterator ri = rsp.begin() ; ri != rsp.end() ; ++ri) {
        if (exp.match((*ri).first))
            [result addObject:[NSArray arrayWithObjects:[NSString stringWithUTF8String:(*ri).first.c_str()], [NSString stringWithUTF8String:(*ri).second.c_str()], nil]];
    }
    return result;
}
- (bool)exportUserPhraseDBToFile:(NSString*)path
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSError* error = nil;
    const bool success = store.exportArchive(path, &error);
    if (!success) NSLog(@"Guanyinma archive transfer failed: %@", [error localizedDescription]);
    return success;
}
- (bool)importUserPhraseDBFromFile:(NSString*)path
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSError* error = nil;
    const bool success = store.importArchive(path, &error);
    if (!success) NSLog(@"Guanyinma archive transfer failed: %@", [error localizedDescription]);
    return success;
}

- (VersionChecker*)versionChecker
{
    return _versionChecker;
}

- (NSString *)databaseVersion
{
	return _databaseVersion;
}

- (string)_guanyinmaUserDatabasePath
{
    OVPathInfo pathInfo = _loaderPolicy->modulePackagePathInfoFromPath("");
    return OVPathHelper::PathCat(pathInfo.writablePath, "GuanyinmaUserData.db");
}

- (NSDictionary *)userPhraseDBSnapshot
{
    if (![NSThread isMainThread]) {
        __block NSDictionary* reply = nil;
        dispatch_sync(dispatch_get_main_queue(), ^{
            reply = [[self userPhraseDBSnapshot] retain];
        });
        return [reply autorelease];
    }
    NSString* backend = [self userPhraseDBBackendIdentifier];
    NSMutableArray* rows = [NSMutableArray array];
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* phrases = store.phrases();
    if (!phrases) return nil;
    for (NSDictionary* phrase in phrases) {
        NSString* query = phrase[@"qstring"];
        NSString* reading = [NSString stringWithUTF8String:
            GuanyinmaMacDecodeReading([query UTF8String]).c_str()];
        [rows addObject:@{@"Text": phrase[@"current"], @"BPMF": reading}];
    }
    return @{@"backend": backend, @"rows": rows};
}

- (NSString *)userPhraseDBBackendIdentifier
{
    return @"guanyinma";
}

- (BOOL)applyUserPhraseEdit:(NSDictionary*)edit expectedBackend:(NSString*)backend
{
    if (![NSThread isMainThread]) {
        __block BOOL accepted = NO;
        dispatch_sync(dispatch_get_main_queue(), ^{
            accepted = [self applyUserPhraseEdit:edit expectedBackend:backend];
        });
        return accepted;
    }
    if (![backend isKindOfClass:[NSString class]] ||
        ![backend isEqualToString:[self userPhraseDBBackendIdentifier]] ||
        ![edit isKindOfClass:[NSDictionary class]])
        return NO;
    NSString* type = edit[@"type"];
    NSNumber* row = edit[@"row"];
    if (![type isKindOfClass:[NSString class]] || ![row isKindOfClass:[NSNumber class]] ||
        !([row doubleValue] >= 0 && [row doubleValue] <= INT_MAX &&
          [row doubleValue] == [row intValue]))
        return NO;
    if ([type isEqualToString:@"remove"] && [edit count] == 2) {
        [self userPhraseDBDeleteRow:[row intValue]];
        return YES;
    }
    NSString* value = edit[@"value"];
    if ([edit count] != 3 || ![value isKindOfClass:[NSString class]] || ![value length])
        return NO;
    if ([type isEqualToString:@"reading"]) {
        [self userPhraseDBSetNewReading:value forPhraseAtRow:[row intValue]];
        return YES;
    }
    if ([type isEqualToString:@"phrase"]) {
        [self userPhraseDBSetPhrase:value atRow:[row intValue]];
        return YES;
    }
    return NO;
}

- (BOOL)userPhraseDBCanProvideService
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    return store.valid() && store.phrases() != nil;
}
- (int)userPhraseDBNumberOfRow
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    return static_cast<int>([store.phrases() count]);
}
- (NSDictionary *)userPhraseDBDictionaryAtRow:(int)row
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* rows = store.phrases();
    if (row < 0 || static_cast<NSUInteger>(row) >= [rows count])
        return [NSDictionary dictionary];
    NSDictionary* entry = [rows objectAtIndex:row];
    const string qstring = [[entry objectForKey:@"qstring"] UTF8String];
    NSString* reading = [NSString stringWithUTF8String:GuanyinmaMacDecodeReading(qstring).c_str()];
    return @{@"Text": [entry objectForKey:@"current"], @"BPMF": reading};
}
- (NSArray *)userPhraseDBReadingsForPhrase:(NSString *)phrase
{
    NSMutableArray *results = [NSMutableArray array];
    if (![phrase length]) {
        return results;
    }

    vector<string> codepoints = OVUTF8Helper::SplitStringByCodePoint([phrase UTF8String]);    

    OVSQLiteDatabaseService *databaseService =
        dynamic_cast<OVSQLiteDatabaseService *>(_loaderService->SQLiteDatabaseService());
    if (!databaseService || !databaseService->connection()) {
        return results;
    }
    OVSQLiteStatement* select = databaseService->connection()->prepare(
        "SELECT qstring FROM unigrams WHERE current = ? ORDER BY probability DESC");
    
    OVKeyValueDataTableInterface* tbl = _loaderService->SQLiteDatabaseService()->createKeyValueDataTableInterface("Mandarin-bpmf-cin");
    if (!tbl) {
        delete select;
        return results;
    }

    vector<vector<string> > phraseBPMFs;
    phraseBPMFs.push_back(vector<string>());
    
	OVWildcard exp("*#");
    for (vector<string>::const_iterator cpi = codepoints.begin() ; cpi != codepoints.end() ; ++cpi) {
        vector<string> bpmfs;
        set<string> dedup;
        
        if (select) {
            select->bindTextToColumn(*cpi, 1);
            while (select->step() == SQLITE_ROW) {
                string b = select->textOfColumn(0);
				
				if (exp.match(b))
					continue;
				
                dedup.insert(b);
                bpmfs.push_back(b);
            }
            select->reset();
        }
        
        
        vector<string> extBpmfs = tbl->keysForValue(*cpi);
        for (vector<string>::iterator ebi = extBpmfs.begin() ; ebi != extBpmfs.end() ; ++ebi) {
            if (dedup.find(*ebi) == dedup.end()) {
                dedup.insert(*ebi);
                bpmfs.push_back(*ebi);
            }
        }
        
        
        if (!bpmfs.size()) {
            phraseBPMFs.clear();
            break;
        }

        vector<vector<string> > npb;
        for (vector<vector<string> >::const_iterator pbi = phraseBPMFs.begin() ; pbi != phraseBPMFs.end() ; ++pbi) {
            for (vector<string>::const_iterator bi = bpmfs.begin() ; bi != bpmfs.end() ; ++bi) {
                vector<string> newEntry = *pbi;
                newEntry.push_back(bi->size() == 2 ? GuanyinmaMacDecodeReading(*bi) : string());
                npb.push_back(newEntry);
                // A long polyphonic phrase can otherwise create millions of
                // combinations and freeze the editor. The highest-frequency
                // readings arrive first, so retain a practical ranked prefix.
                if (npb.size() >= 256)
                    break;
            }
            if (npb.size() >= 256)
                break;
        }
        phraseBPMFs = npb;
    }    
    
    for (vector<vector<string> >::const_iterator pbi = phraseBPMFs.begin() ; pbi != phraseBPMFs.end() ; ++pbi) {
        [results addObject:[NSString stringWithUTF8String:OVStringHelper::Join(*pbi, ",").c_str()]];
    }
    
	
	if (select) {
		delete select;
	}
	
    return results;
}
- (void)userPhraseDBSave
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    if (!store.apply(@{@"type": @"save_learning"}))
        NSLog(@"Guanyinma user-data checkpoint failed");
}
- (string)_qstringFromReading:(NSString *)reading
{
    string query;
    size_t count = 0;
    return GuanyinmaMacEncodeReading([reading UTF8String] ?: "", query, count) ? query : string();
}
- (void)userPhraseDBSetNewReading:(NSString *)reading forPhraseAtRow:(int)row
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* rows = store.phrases();
    if (row < 0 || ![reading length] || static_cast<NSUInteger>(row) >= [rows count])
        return;
    NSDictionary* entry = [rows objectAtIndex:row];
    NSString* qstring = [NSString stringWithUTF8String:[self _qstringFromReading:reading].c_str()];
    if (!store.apply(@{@"type": @"update_user_phrase",
        @"qstring": [entry objectForKey:@"qstring"], @"text": [entry objectForKey:@"current"],
        @"new_qstring": qstring, @"new_text": [entry objectForKey:@"current"]}))
        NSLog(@"Guanyinma user phrase reading update failed");
}

- (void)userPhraseDBDeleteRow:(int)row
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* rows = store.phrases();
    if (row < 0 || static_cast<NSUInteger>(row) >= [rows count])
        return;
    NSDictionary* entry = [rows objectAtIndex:row];
    if (!store.apply(@{@"type": @"remove_user_phrase",
        @"qstring": [entry objectForKey:@"qstring"], @"text": [entry objectForKey:@"current"]}))
        NSLog(@"Guanyinma user phrase removal failed");
}
- (void)userPhraseDBAddNewRow:(NSString *)phrase
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* readings = [self userPhraseDBReadingsForPhrase:phrase];
    if (![readings count])
        return;
    NSString* qstring = [NSString stringWithUTF8String:
        [self _qstringFromReading:[readings objectAtIndex:0]].c_str()];
    if (!store.apply(@{@"type": @"add_user_phrase", @"qstring": qstring, @"text": phrase}))
        NSLog(@"Guanyinma user phrase insertion failed");
}
- (void)userPhraseDBAddNewRows:(NSArray *)array
{
    for (NSString* phrase in array)
        [self userPhraseDBAddNewRow:phrase];
}

- (void)userPhraseDBSetPhrase:(NSString *)phrase atRow:(int)row
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    NSArray* rows = store.phrases();
    if (row < 0 || ![phrase length] || static_cast<NSUInteger>(row) >= [rows count])
        return;
    NSArray* readings = [self userPhraseDBReadingsForPhrase:phrase];
    if (![readings count])
        return;
    NSDictionary* entry = [rows objectAtIndex:row];
    NSString* qstring = [NSString stringWithUTF8String:
        [self _qstringFromReading:[readings objectAtIndex:0]].c_str()];
    if (!store.apply(@{@"type": @"update_user_phrase",
        @"qstring": [entry objectForKey:@"qstring"], @"text": [entry objectForKey:@"current"],
        @"new_qstring": qstring, @"new_text": phrase}))
        NSLog(@"Guanyinma user phrase update failed");
}

- (BOOL)resetSmartMandarinLearning
{
    GuanyinmaMacUserData store(_SQLiteDatabaseService->filename(), [self _guanyinmaUserDatabasePath]);
    return store.apply(@{@"type": @"reset_method_learning", @"method": @"smart"});
}

- (void)mergeCannedMessagesData
{
	NSUInteger sourceBytes = 0;
	NSUInteger categoryCount = 0;
	BOOL parsedPropertyList = NO;
	@synchronized(self) {	
		[_mergedCannedMessagesArray removeAllObjects];

		string cannedMsgs = _userPersistence->fetchLatestValueByKeyAndPopulateUserDB("canned_messages");
		sourceBytes = cannedMsgs.size();
		PVPlistValue *parsed = PVPropertyList::ParsePlistFromString(cannedMsgs.c_str());
	
	
		string localDT = OVDateTimeHelper::LocalDateTimeString();
		
		PVPlistValue msgArray(PVPlistValue::Array);    
		PVPlistValue* pvs[2];
		pvs[0] = parsed;
		pvs[1] = _userCannedMessagePlist->rootDictionary();
		
		for (size_t pi = 0 ; pi < 2 ; pi++) {
			PVPlistValue* msgs = pvs[pi]->valueForKey("CannedMessages");    
			if (msgs) {    
				for (size_t i = 0 ; i < msgs->arraySize() ; i++) {
					PVPlistValue* category = msgs->arrayElementAtIndex(i);
					
					string notBefore = category->stringValueForKey("NotBefore");
					if (notBefore.length() && localDT < notBefore) {
						continue;
					}
					
					string notAfter = category->stringValueForKey("NotAfter");
					if (notAfter.length() && localDT > notAfter) {
						continue;
					}
					
					msgArray.addArrayElement(category);
				}
			}
		}
		
		vector<string> userMessages;
		ifstream ifs;
		ifs.open([self userFreeCannedMessagePath].c_str(), ifstream::in);
		
		if (ifs.good()) {
			// ignore the first line
			string emptyLine;
			getline(ifs, emptyLine);
		}
		
		while (ifs.good()) {
			string line;
			getline(ifs, line);
			if (line.length()) {
				userMessages.push_back(line);
			}
		}
		ifs.close();
		
		if (userMessages.size()) {
			PVPlistValue userCategory(PVPlistValue::Dictionary);
			userCategory.setKeyValue("Name", [LFLSTR(@"User Defined") UTF8String]);
			PVPlistValue messages(PVPlistValue::Array);
			for (vector<string>::iterator umi = userMessages.begin() ; umi != userMessages.end() ; ++umi) {
				PVPlistValue msg(*umi);
				messages.addArrayElement(&msg);
			}
			userCategory.setKeyValue("Messages", &messages);
			msgArray.addArrayElement(&userCategory);
		}    
		
		PVPlistValue newData(PVPlistValue::Dictionary);
		newData.setKeyValue("CannedMessages", &msgArray);    
	
		stringstream sst;
		sst << newData;
		
		const string &s = sst.str();
		const char *ndc = s.c_str();
		
	
		NSData *cmData = [NSData dataWithBytesNoCopy:(void*)ndc length:s.length() freeWhenDone:NO];		
		id cmPlist = [NSPropertyListSerialization propertyListFromData:cmData mutabilityOption:NSPropertyListMutableContainersAndLeaves format:NULL errorDescription:NULL];
		parsedPropertyList = (cmPlist != nil);
		if (cmPlist) {
			NSArray *a = [cmPlist objectForKey:@"CannedMessages"];
			if (a) {
				if ([a isKindOfClass:[NSArray class]]) {
					[_mergedCannedMessagesArray addObjectsFromArray:a];
				}
			}
		}
		categoryCount = [_mergedCannedMessagesArray count];
	}

	// Counts and ordering only: never record symbols, custom phrases or typed text.
	os_log(OS_LOG_DEFAULT, "KeyKey symbols event=data-notification source_bytes=%{public}lu parsed=%{public}d categories=%{public}lu",
	       (unsigned long)sourceBytes, parsedPropertyList, (unsigned long)categoryCount);
	[[NSNotificationCenter defaultCenter] postNotificationName:CVLoaderUpdateCannedMessagesNotification object:self];
}

- (NSArray *)mergedCannedMessagesArray;
{
	@synchronized(self) {
		return _mergedCannedMessagesArray;
	}
}

- (void)syncUserCannedMessages
{
	string path = [self userFreeCannedMessagePath];
	
	if (!OVPathHelper::PathExists(path)) {
		// populate the file with UTF-8 BOM
		FILE* stream = OVFileHelper::OpenStream(path, "w");
		if (stream) {
			NSString *BOMLine = LFLSTR(@"BOM-LINE");
			NSString *exampleLine = LFLSTR(@"EXAMPLE-LINE");
			
			fputs([BOMLine UTF8String], stream);
			fputs("\n", stream);
			fputs([exampleLine UTF8String], stream);
			fputs("\n", stream);
			
			fclose(stream);
		}
	}
	
	bool shouldMerge = false;
	OVFileTimestamp newTS = OVPathHelper::TimestampForPath(path);

	if (newTS > *_userFreeCannedMessageFileTimestamp) {
		*_userFreeCannedMessageFileTimestamp = newTS;
		shouldMerge = true;
	}
	
	if (_userCannedMessagePlist->shouldReadSync()) {
		_userCannedMessagePlist->readSync();
		shouldMerge = true;
	}
	
	if (shouldMerge) {
		[self mergeCannedMessagesData];
	}
}

- (const string)userFreeCannedMessagePath
{
    string appDataDir = OVDirectoryHelper::UserApplicationSupportDataDirectory(_loaderPolicy->loaderName());
    OVDirectoryHelper::CheckDirectory(appDataDir);    
    return OVPathHelper::PathCat(appDataDir, "UserCannedMessages.txt");        
}

- (void)mergeOneKeyData
{
	@synchronized (self) {
		string oneKeyRawData = _userPersistence->fetchLatestValueByKeyAndPopulateUserDB("onekey_services");

		PVPlistValue *parsed = PVPropertyList::ParsePlistFromString(oneKeyRawData.c_str());
		vector<string> keys = parsed->dictionaryKeys();
		
		_mergedOneKeyData->removeAllKeysAndValues();
		for (vector<string>::iterator ki = keys.begin() ; ki != keys.end() ; ++ki) {
			_mergedOneKeyData->setKeyValue(*ki, parsed->valueForKey(*ki));
		}
		
		// ensure existence of features
		PVPlistValue farray(PVPlistValue::Array);
		PVPlistValue* features = _mergedOneKeyData->valueForKey("Features");
		if (!features) {
			_mergedOneKeyData->setKeyValue("Features", &farray);
		}
		else {
			if (features->type() != PVPlistValue::Array) {
				_mergedOneKeyData->setKeyValue("Features", &farray);
			}
		}

		// put vendor features in
		features = _mergedOneKeyData->valueForKey("Features");
		size_t fc = features->arraySize();
		for (size_t i = 0 ; i < fc ; i++) {
			PVPlistValue* vf = features->arrayElementAtIndex(i);
			if (vf) {
				vf->setKeyValue("IsVendorFeature", "true");
			}
		}

		
		PVPlistValue* userDict = _userOneKeyPlist->rootDictionary();	
		PVPlistValue* userFeatures = userDict->valueForKey("Features");
		if (userFeatures) {
			if (userFeatures->type() == PVPlistValue::Array) {
				size_t as = userFeatures->arraySize();
				for (size_t ai = 0 ; ai < as ; ai++) {
					features->addArrayElement(userFeatures->arrayElementAtIndex(ai));
				}
			}
		}
	}
}

- (PVPlistValue *)mergedOneKeyData
{
	return _mergedOneKeyData;
}

- (void)syncUserOneKeyData
{
    if (_userOneKeyPlist->shouldReadSync()) {
        _userOneKeyPlist->readSync();
		[self mergeOneKeyData];
    }
}

- (NSArray *)dynamicallyLoadedModulePackageInfo
{
	NSMutableArray *result = [NSMutableArray array];
	
	set<string> excluded;	
	vector<string> excludedList = _loader->excludedModulePackages();
	for (vector<string>::const_iterator ei = excludedList.begin() ; ei != excludedList.end() ; ++ei) {
		excluded.insert(*ei);
	}
	
	vector<string> pkgNames;
	
	pkgNames = _signedModuleLoadingSystem->availablePackages();
	for (vector<string>::const_iterator pi = pkgNames.begin() ; pi != pkgNames.end() ; ++pi) {
		string localizedName = (dynamic_cast<YKSignedModuleLoadingSystem *> (_signedModuleLoadingSystem))->localizedNameForPackage(*pi, _loaderService);
		OVPathInfo info = _signedModuleLoadingSystem->pathInfoForPackage(*pi, _loaderPolicy);
		
		[result addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						   [NSString stringWithUTF8String:(*pi).c_str()], OVServiceLoadedModulePackageIdentifierKey,
						   [NSString stringWithUTF8String:localizedName.c_str()], OVServiceLoadedModulePackageLocalizedNameKey,
						   [NSString stringWithUTF8String:info.loadedPath.c_str()], OVServiceLoadedModulePackageBundlePathKey,						  
						   ((excluded.find(*pi) == excluded.end()) ? (id)kCFBooleanTrue : (id)kCFBooleanFalse), OVServiceLoadedModulePackageEnabledKey,
						   nil]];							
	}

	pkgNames = _bundleLoadingSystem->availablePackages();
	for (vector<string>::const_iterator pi = pkgNames.begin() ; pi != pkgNames.end() ; ++pi) {
		string localizedName = *pi;
		OVPathInfo info = _bundleLoadingSystem->pathInfoForPackage(*pi, _loaderPolicy);
		
		[result addObject:[NSDictionary dictionaryWithObjectsAndKeys:
						   [NSString stringWithUTF8String:(*pi).c_str()], OVServiceLoadedModulePackageIdentifierKey,
						   [NSString stringWithUTF8String:localizedName.c_str()], OVServiceLoadedModulePackageLocalizedNameKey,
						   [NSString stringWithUTF8String:info.loadedPath.c_str()], OVServiceLoadedModulePackageBundlePathKey,
						   ((excluded.find(*pi) == excluded.end()) ? (id)kCFBooleanTrue : (id)kCFBooleanFalse), OVServiceLoadedModulePackageEnabledKey,
						   nil]];							
	}
	
	
	return result;
}

- (void)setBlackListOfPackageIdentifers:(NSArray *)inIdentifiers
{
	vector<string> list;
	NSEnumerator *ie = [inIdentifiers objectEnumerator];
	while (NSString *i = [ie nextObject]) {
		list.push_back([i UTF8String]);
	}
	
	_loader->setExcludedModulePackages(list);
}

@end

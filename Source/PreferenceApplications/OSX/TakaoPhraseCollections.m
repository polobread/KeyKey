// [AUTO_HEADER]

#import "TakaoPhraseCollections.h"
#import "TakaoSettings.h"
#import "TakaoHelper.h"
#import <sqlite3.h>

// The module writes its own preferences under this name; see
// OVAFASSOCIATEDPHRASE_IDENTIFIER in the project's preprocessor definitions.
#define PLIST_ASSOCIATED_PHRASE_FILENAME	@"io.github.polobread.chichi77.AssociatedPhrase.plist"
#define ENABLED_COLLECTIONS_KEY				@"EnabledCollections"

@implementation TakaoPhraseCollections

- (void)dealloc
{
	[_collections release];
	[_enabled release];
	[super dealloc];
}

- (NSString *)_databasePath
{
	// Preferences.app sits in the input method's SharedSupport, so the cooked
	// dictionary is two levels up in Resources.
	NSString *bundlePath = [[NSBundle mainBundle] bundlePath];
	NSString *inputMethod = [[bundlePath stringByDeletingLastPathComponent] stringByDeletingLastPathComponent];
	return [inputMethod stringByAppendingPathComponent:@"Resources/Databases/KeyKey.db"];
}

- (NSString *)_preferenceFilePath
{
	return [TakaoHelper plistFilePath:PLIST_ASSOCIATED_PHRASE_FILENAME];
}

- (void)_readCollections
{
	NSMutableArray *collections = [NSMutableArray array];

	sqlite3 *db = NULL;
	if (sqlite3_open_v2([[self _databasePath] UTF8String], &db, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
		// The counts are of head characters rather than phrases, which is what
		// the table is keyed on and so what the user actually gets.
		const char *sql =
			"SELECT n.source, n.display, count(a.headchar) "
			"FROM collection_names n LEFT JOIN associated_phrases a ON a.source = n.source "
			"GROUP BY n.source ORDER BY n.sortorder, n.display";

		sqlite3_stmt *statement = NULL;
		if (sqlite3_prepare_v2(db, sql, -1, &statement, NULL) == SQLITE_OK) {
			while (sqlite3_step(statement) == SQLITE_ROW) {
				const unsigned char *source = sqlite3_column_text(statement, 0);
				const unsigned char *display = sqlite3_column_text(statement, 1);
				if (!source || !display)
					continue;

				[collections addObject:[NSDictionary dictionaryWithObjectsAndKeys:
					[NSString stringWithUTF8String:(const char *)source], @"source",
					[NSString stringWithUTF8String:(const char *)display], @"display",
					[NSNumber numberWithInt:sqlite3_column_int(statement, 2)], @"count",
					nil]];
			}
			sqlite3_finalize(statement);
		}
		sqlite3_close(db);
	}

	[_collections release];
	_collections = [collections copy];
}

- (void)_readEnabled
{
	[_enabled release];
	_enabled = [NSMutableArray new];

	NSDictionary *preference = [NSDictionary dictionaryWithContentsOfFile:[self _preferenceFilePath]];
	NSString *value = [preference objectForKey:ENABLED_COLLECTIONS_KEY];

	if (!value) {
		// No key at all is a first run, and the module defaults to McBopomofo.
		// An empty string is the user having unticked everything, which is
		// left alone.
		[_enabled addObject:@"McBopomofo"];
		return;
	}

	NSEnumerator *enumerator = [[value componentsSeparatedByString:@","] objectEnumerator];
	NSString *name;
	while (name = [enumerator nextObject]) {
		name = [name stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
		if ([name length])
			[_enabled addObject:name];
	}
}

- (void)_writeEnabled
{
	// Written in the order the collections are listed, which is the order the
	// module contributes their candidates in.
	NSMutableArray *ordered = [NSMutableArray array];
	NSEnumerator *enumerator = [_collections objectEnumerator];
	NSDictionary *collection;
	while (collection = [enumerator nextObject]) {
		NSString *source = [collection objectForKey:@"source"];
		if ([_enabled containsObject:source])
			[ordered addObject:source];
	}

	NSDictionary *preference = [NSDictionary dictionaryWithObject:[ordered componentsJoinedByString:@","]
														  forKey:ENABLED_COLLECTIONS_KEY];

	NSError *error = nil;
	NSData *data = [NSPropertyListSerialization dataWithPropertyList:preference
															 format:NSPropertyListXMLFormat_v1_0
															options:0
															  error:&error];
	if (data)
		[data writeToFile:[self _preferenceFilePath] atomically:YES];
}

- (void)awakeFromNib
{
	[self reload];
}

- (void)reload
{
	[self _readCollections];
	[self _readEnabled];
	[_collectionTableView reloadData];
}

- (IBAction)toggleCollection:(id)sender
{
	[self _writeEnabled];
}

#pragma mark Table view data source

- (NSInteger)numberOfRowsInTableView:(NSTableView *)tableView
{
	return (NSInteger)[_collections count];
}

- (id)tableView:(NSTableView *)tableView objectValueForTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[_collections count])
		return nil;

	NSDictionary *collection = [_collections objectAtIndex:row];

	if ([[tableColumn identifier] isEqualToString:@"enabled"])
		return [NSNumber numberWithBool:[_enabled containsObject:[collection objectForKey:@"source"]]];

	if ([[tableColumn identifier] isEqualToString:@"count"])
		return [collection objectForKey:@"count"];

	return [collection objectForKey:@"display"];
}

- (void)tableView:(NSTableView *)tableView setObjectValue:(id)object forTableColumn:(NSTableColumn *)tableColumn row:(NSInteger)row
{
	if (row < 0 || row >= (NSInteger)[_collections count])
		return;

	if (![[tableColumn identifier] isEqualToString:@"enabled"])
		return;

	NSString *source = [[_collections objectAtIndex:row] objectForKey:@"source"];

	if ([object boolValue]) {
		if (![_enabled containsObject:source])
			[_enabled addObject:source];
	}
	else {
		[_enabled removeObject:source];
	}

	[self _writeEnabled];
}

@end

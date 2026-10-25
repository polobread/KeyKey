/* Isolated phrase-editor backend guards; no DO, profile or Contacts access. */
#import "../../../Utilities/PhraseEditor/OSX/PEController.h"
#include <assert.h>

@interface PEController (GuardTests)
- (void)reloadData;
- (void)windowDidBecomeKey:(NSNotification *)notification;
- (int)numberOfRowsInTableView:(NSTableView *)table;
- (id)tableView:(NSTableView *)table objectValueForTableColumn:(NSTableColumn *)column row:(int)row;
- (void)tableView:(NSTableView *)table setObjectValue:(id)value forTableColumn:(NSTableColumn *)column row:(int)row;
- (BOOL)tableView:(NSTableView *)table shouldEditTableColumn:(NSTableColumn *)column row:(NSInteger)row;
- (BOOL)validateToolbarItem:(NSToolbarItem *)item;
- (BOOL)validateMenuItem:(NSMenuItem *)item;
- (void)fixReadingForAddressBookImportFromIndex:(int)index;
@end

static NSUInteger checks;
static void require(BOOL condition, const char *message) {
    ++checks;
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); abort(); }
}
static NSMutableDictionary *row(NSString *text, NSString *reading) {
    return [NSMutableDictionary dictionaryWithDictionary:@{@"Text":text, @"BPMF":reading}];
}

@interface FakePhraseService : NSObject {
@public
    NSString *backend;
    NSMutableDictionary *stores;
    NSMutableArray *edits;
    NSUInteger effects, rejected, legacyEdits, snapshots, rowCounts, rowReads;
    BOOL oldService, changeDuringRead, snapshotFails;
}
@end
@implementation FakePhraseService
- (id)init {
    if ((self=[super init])) {
        backend=[@"manjusri" copy];
        stores=[@{
            @"manjusri":[NSMutableArray arrayWithObjects:row(@"舊詞",@"ㄐㄧㄡˋ,ㄘˊ"),
                row(@"舊字",@"ㄐㄧㄡˋ,ㄗˋ"),nil],
            @"guanyinma":[NSMutableArray arrayWithObjects:row(@"新詞",@"ㄒㄧㄣ,ㄘˊ"),
                row(@"新字",@"ㄒㄧㄣ,ㄗˋ"),nil]
        } mutableCopy];
        edits=[NSMutableArray new];
    }
    return self;
}
- (void)dealloc { [backend release]; [stores release]; [edits release]; [super dealloc]; }
- (void)select:(NSString *)value { [value retain]; [backend release]; backend=value; }
- (NSString *)userPhraseDBBackendIdentifier {
    if (oldService) [NSException raise:NSInvalidArgumentException format:@"Old service has no backend API"];
    return backend;
}
- (NSDictionary *)userPhraseDBSnapshot {
    ++snapshots;
    if (oldService) [NSException raise:NSInvalidArgumentException format:@"Old service has no snapshot API"];
    if (snapshotFails) return nil;
    NSMutableArray *rows=[NSMutableArray array];
    for (NSDictionary *entry in stores[backend])
        [rows addObject:[[[NSDictionary alloc] initWithDictionary:entry copyItems:YES] autorelease]];
    NSDictionary *snapshot=@{@"backend":backend,@"rows":rows};
    if (changeDuringRead) { changeDuringRead=NO; [self select:@"guanyinma"]; }
    return snapshot;
}
- (int)userPhraseDBNumberOfRow { ++rowCounts; return (int)[stores[backend] count]; }
- (NSDictionary *)userPhraseDBDictionaryAtRow:(int)index {
    ++rowReads;
    return index>=0 && (NSUInteger)index<[stores[backend] count] ? stores[backend][index] : nil;
}
- (NSArray *)userPhraseDBReadingsForPhrase:(NSString *)phrase { return @[@"ㄒㄧㄣ"]; }
- (BOOL)applyUserPhraseEdit:(NSDictionary *)edit expectedBackend:(NSString *)expected {
    [edits addObject:@{@"edit":edit,@"expected":expected ?: @""}];
    if (![backend isEqualToString:expected]) { ++rejected; return NO; }
    NSUInteger index=[edit[@"row"] unsignedIntegerValue];
    NSMutableArray *data=stores[backend];
    if (index>=[data count]) return NO;
    NSString *type=edit[@"type"];
    if ([type isEqualToString:@"remove"]) [data removeObjectAtIndex:index];
    else if ([type isEqualToString:@"reading"]) data[index][@"BPMF"]=edit[@"value"];
    else if ([type isEqualToString:@"phrase"]) {
        NSMutableDictionary *updated=[[data[index] mutableCopy] autorelease];
        updated[@"Text"]=edit[@"value"];
        [data removeObjectAtIndex:index]; [data addObject:updated];
    } else return NO;
    ++effects; return YES;
}
- (void)userPhraseDBDeleteRow:(int)index { ++legacyEdits; }
- (void)userPhraseDBSetNewReading:(NSString *)value forPhraseAtRow:(int)index { ++legacyEdits; }
- (void)userPhraseDBSetPhrase:(NSString *)value atRow:(int)index { ++legacyEdits; }
@end

@interface GuardTable : NSTableView { @public NSUInteger aborts,reloads; }
@end
@implementation GuardTable
- (BOOL)abortEditing { ++aborts; return [super abortEditing]; }
- (void)reloadData { ++reloads; [super reloadData]; }
@end
@interface GuardReadingTable : PESettingTableView
@end
@implementation GuardReadingTable
- (NSString *)currentReading { return @"ㄍㄥˋ,ㄘˊ"; }
@end

@interface GuardController : PEController { @public NSInteger readingTarget; }
- (id)initWithService:(FakePhraseService *)service;
- (GuardTable *)table;
- (void)captureReadingAtRow:(NSInteger)index;
@end
@implementation GuardController
- (id)initWithService:(FakePhraseService *)service {
    NSWindow *window=[[[NSWindow alloc] initWithContentRect:NSMakeRect(0,0,480,300)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:YES] autorelease];
    [window setReleasedWhenClosed:NO];
    if ((self=[super initWithWindow:window])) {
        _loader=[service retain];
        _tableView=[[[GuardTable alloc] initWithFrame:NSMakeRect(0,25,480,275)] autorelease];
        [_tableView addTableColumn:[[[NSTableColumn alloc] initWithIdentifier:@"phrase"] autorelease]];
        [_tableView addTableColumn:[[[NSTableColumn alloc] initWithIdentifier:@"reading"] autorelease]];
        [_tableView setAllowsMultipleSelection:YES];
        [_tableView setDataSource:(id)self]; [_tableView setDelegate:(id)self];
        _statusTextField=[[[NSTextField alloc] initWithFrame:NSMakeRect(0,0,480,25)] autorelease];
        _okButton=[[[NSButton alloc] initWithFrame:NSZeroRect] autorelease];
        _phraseTableView=[[[GuardReadingTable alloc] initWithFrame:NSZeroRect] autorelease];
        [[window contentView] addSubview:_tableView];
        [[window contentView] addSubview:_statusTextField];
        [[window contentView] addSubview:_okButton];
        [[window contentView] addSubview:_phraseTableView];
        readingTarget=-1;
        [self reloadData];
    }
    return self;
}
- (GuardTable *)table { return (GuardTable *)_tableView; }
- (void)captureReadingAtRow:(NSInteger)index {
    _editingRow=(int)index;
    [_editingBackend release]; _editingBackend=[_displayedBackend copy];
}
- (IBAction)editReading:(id)sender { readingTarget=[_tableView selectedRow]; }
@end

static GuardController *make(FakePhraseService **service) {
    *service=[[[FakePhraseService alloc] init] autorelease];
    return [[[GuardController alloc] initWithService:*service] autorelease];
}
static NSString *shown(GuardController *controller, NSInteger index) {
    return [controller tableView:[controller table]
        objectValueForTableColumn:[[controller table] tableColumnWithIdentifier:@"phrase"] row:(int)index];
}
static void selectRow(GuardController *controller, NSUInteger index) {
    [[controller table] selectRowIndexes:[NSIndexSet indexSetWithIndex:index] byExtendingSelection:NO];
}
static void tests(void) {
    FakePhraseService *service;
    GuardController *controller=make(&service);
    require([shown(controller,0) isEqualToString:@"舊詞"],"snapshot initially shows native core rows");
    require(service->snapshots==1 && service->rowCounts==0 && service->rowReads==0,
        "snapshot loading uses one bulk RPC and no legacy per-row getters");
    selectRow(controller,0);
    [service select:@"guanyinma"];
    require([shown(controller,0) isEqualToString:@"舊詞"],"paint preserves displayed backend snapshot");
    [controller delete:nil];
    require(service->rejected==1 && service->effects==0,"stale delete rejected atomically by backend guard");
    require([service->stores[@"guanyinma"] count]==2,"stale delete preserves other core row zero");
    require([shown(controller,0) isEqualToString:@"新詞"] && [[controller table] selectedRow]==-1,
        "rejected delete refreshes backend and clears selection");
    require(service->legacyEdits==0,"delete never falls back to unguarded legacy endpoint");

    controller=make(&service);
    [controller captureReadingAtRow:0];
    [service select:@"guanyinma"];
    [controller okAction:nil];
    require(service->rejected==1 && service->effects==0,"stale reading sheet retains its captured backend");
    require([service->stores[@"guanyinma"][0][@"BPMF"] isEqualToString:@"ㄒㄧㄣ,ㄘˊ"],
        "stale reading cannot change other core row");
    require([[controller valueForKey:@"_editingRow"] intValue]==-1,"rejected reading cancels old edit");
    require(service->legacyEdits==0,"reading never uses unguarded endpoint");

    controller=make(&service);
    [service select:@"guanyinma"];
    [controller tableView:[controller table] setObjectValue:@"更詞"
        forTableColumn:[[controller table] tableColumnWithIdentifier:@"phrase"] row:0];
    require(service->rejected==1 && service->effects==0,"stale inline phrase edit is rejected");
    require([service->stores[@"guanyinma"][0][@"Text"] isEqualToString:@"新詞"],
        "stale inline edit preserves other core text");
    require(service->legacyEdits==0,"inline phrase endpoint is always guarded");

    controller=make(&service);
    selectRow(controller,0);
    [controller captureReadingAtRow:0];
    NSUInteger aborts=[controller table]->aborts;
    [controller windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification
        object:[controller window]]];
    require([controller table]->aborts==aborts && [[controller table] selectedRow]==0,
        "same-backend window focus preserves selection and unfinished inline edit");
    require([[controller valueForKey:@"_editingRow"] intValue]==0 &&
        [[controller valueForKey:@"_editingBackend"] isEqualToString:@"manjusri"],
        "same-backend window focus preserves unfinished reading sheet identity");
    [service select:@"guanyinma"];
    [controller windowDidBecomeKey:[NSNotification notificationWithName:NSWindowDidBecomeKeyNotification
        object:[controller window]]];
    require([controller table]->aborts>aborts && [[controller table] selectedRow]==-1,
        "window reactivation aborts editing and clears old row selection");
    require([shown(controller,0) isEqualToString:@"新詞"],"window reactivation loads matching backend rows");
    [controller captureReadingAtRow:0]; [controller okAction:nil];
    require(service->effects==1,"current backend reading edit succeeds");
    require([service->stores[@"guanyinma"][0][@"BPMF"] isEqualToString:@"ㄍㄥˋ,ㄘˊ"],
        "guarded reading writes intended row");

    controller=make(&service);
    [controller tableView:[controller table] setObjectValue:@"更詞"
        forTableColumn:[[controller table] tableColumnWithIdentifier:@"phrase"] row:0];
    require(service->effects==1 && controller->readingTarget==1,
        "phrase rename locates moved identity before follow-up reading edit");
    require([service->stores[@"manjusri"][1][@"Text"] isEqualToString:@"更詞"],
        "renamed phrase may move without editing a different row");
    require(service->legacyEdits==0,"successful edit uses new endpoint only");

    controller=make(&service);
    [[controller table] selectRowIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0,2)]
        byExtendingSelection:NO];
    [controller delete:nil];
    require(service->effects==2 && [service->stores[@"manjusri"] count]==0,
        "multiple deletes keep one backend and descend by row");
    require([controller numberOfRowsInTableView:[controller table]]==0,"snapshot refreshed after deletion");
    NSMenuItem *add=[[[NSMenuItem alloc] initWithTitle:@"Add" action:@selector(add:) keyEquivalent:@""] autorelease];
    require([controller validateMenuItem:add],"valid empty backend can add its first word");

    controller=make(&service);
    service->oldService=YES; [controller reloadData];
    require([controller numberOfRowsInTableView:[controller table]]==0,"old service without snapshot remains unavailable");
    require(![controller tableView:[controller table] shouldEditTableColumn:
        [[controller table] tableColumnWithIdentifier:@"phrase"] row:0],"old service cannot begin row edit");
    [controller delete:nil];
    [controller tableView:[controller table] setObjectValue:@"更詞"
        forTableColumn:[[controller table] tableColumnWithIdentifier:@"phrase"] row:0];
    require([service->edits count]==0 && service->legacyEdits==0 && service->effects==0,
        "unavailable backend API never sends positional mutations");
    require(![controller validateMenuItem:add],"old service mutation controls are read-only");

    controller=make(&service);
    service->snapshotFails=YES; [controller reloadData];
    require([controller numberOfRowsInTableView:[controller table]]==0 &&
        ![[controller valueForKey:@"_displayedBackend"] length],"nil snapshot fails closed");
    require(service->rowCounts==0 && service->rowReads==0,"failed snapshot never falls back to per-row RPCs");

    controller=make(&service);
    service->changeDuringRead=YES; [controller reloadData];
    require([shown(controller,0) isEqualToString:@"舊詞"] &&
        [[controller valueForKey:@"_displayedBackend"] isEqualToString:@"manjusri"],
        "snapshot response binds rows to their original backend even if selection changes immediately");
    selectRow(controller,0); [controller delete:nil];
    require(service->rejected==1 && service->effects==0 &&
        [service->stores[@"guanyinma"] count]==2,"post-snapshot core change cannot mutate a different backend");

    controller=make(&service);
    [service select:@"guanyinma"];
    service->stores[@"guanyinma"][0][@"Text"]=@"沈名";
    [controller fixReadingForAddressBookImportFromIndex:0];
    require(service->rejected==1 && service->effects==0,"address-book reading correction also checks backend");
    require(service->legacyEdits==0,"address-book correction never bypasses row guard");
}
int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        tests();
        printf("PASS: %lu phrase-editor backend safety checks; no DO/profile/Contacts access\n",
            (unsigned long)checks);
    }
    return 0;
}

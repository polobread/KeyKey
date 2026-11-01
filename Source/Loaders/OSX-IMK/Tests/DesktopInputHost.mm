// Copyright (c) 2026 Chui-Ping Cheng. BSD-3-Clause; see ../../../../LICENSING.md.
// Controller methods are inserted verbatim from OpenVanillaController.mm at build time.
// The client and UI services are test doubles; PV, adapter and font service are real.
#import <Cocoa/Cocoa.h>
#import <AudioToolbox/AudioToolbox.h>
#include "PVContextSandwich.h"
#include "PVLoaderSystem.h"
#include "CVEncodingService.h"
#include "GuanyinmaMacAdapter.h"
#include "IMKInputMode.h"
#include "IMKShiftTap.h"
#include "OVOFFullWidthCharacter.h"
#include <memory>
#include <stdexcept>
using namespace OpenVanilla;

static PVLoader* testLoader;
static PVLoaderService* testService;
static IMKInputMode OVCInputMode;
#define LFLSTR(x) (x)
static void Require(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
static NSString* Native(const std::string& value) { return [NSString stringWithUTF8String:value.c_str()]; }
static NSUInteger Scalars(NSString* value) {
    return OVUTF8Helper::SplitStringByCodePoint([value UTF8String]).size();
}
@interface OpenVanillaLoader : NSObject
+ (PVLoader*)sharedLoader;
+ (PVLoaderService*)sharedLoaderService;
@end
@implementation OpenVanillaLoader
+ (PVLoader*)sharedLoader { return testLoader; }
+ (PVLoaderService*)sharedLoaderService { return testService; }
@end
@interface CVNotifyController : NSObject
+ (void)notify:(NSString*)message;
@end
@implementation CVNotifyController
+ (void)notify:(NSString*)message { NSLog(@"test notification: %@", message); }
@end
// Only declarations for UI messages in the unmodified controller methods.
// NSApp has no delegate, so these render-only calls have no receiver.
@interface NSObject (DesktopRenderingDeclarations)
- (id)inputMethodToggleWindowController;
- (id)searchController;
- (id)verticalCandidateController;
- (id)horizontalCandidateController;
- (id)plainTextCandidateController;
- (id)tooltipController;
- (void)useScreenOfPoint:(NSPoint)point;
- (void)moveToNextInputMethod;
- (void)setBufferHeight:(float)height;
- (float)bufferHeight;
- (NSPoint)cursorPosition;
- (void)showWithPrompt:(NSString*)prompt promptDescription:(NSString*)description buffer:(NSString*)buffer
    point:(NSPoint)point readingFrom:(int)start readingLength:(int)length cursorIndex:(size_t)cursor;
- (void)showWithPrompt:(NSString*)prompt promptDescription:(NSString*)description buffer:(NSString*)buffer
    readingFrom:(int)start readingLength:(int)length cursorIndex:(size_t)cursor;
- (void)setFontHeight:(float)height;
- (void)updateContent:(void*)panel atPoint:(NSPoint)point;
- (void)showToolTip:(NSString*)text atPoint:(NSPoint)point;
- (BOOL)hide;
@end
static void OVCLaunchApplication(const std::string&) { throw std::runtime_error("Unexpected application launch"); }
// CONTROLLER_FUNCTIONS

// In-memory native client: the production controller writes attributed marked
// text and UTF-16 selection/replacement ranges to these exact IMK selectors.
@interface DesktopClient : NSObject {
@public
    NSMutableString* document;
    NSMutableArray* transactions;
    NSRange marked, selection;
}
- (NSDictionary*)snapshot;
- (void)insertText:(id)value replacementRange:(NSRange)range;
- (void)setMarkedText:(id)value selectionRange:(NSRange)selected replacementRange:(NSRange)range;
- (NSDictionary*)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect*)rect;
@end
@implementation DesktopClient
- (id)init {
    if ((self = [super init])) {
        document = [NSMutableString new]; transactions = [NSMutableArray new];
        marked = NSMakeRange(NSNotFound, 0); selection = NSMakeRange(0, 0);
    }
    return self;
}
- (void)dealloc { [document release]; [transactions release]; [super dealloc]; }
- (NSDictionary*)snapshot {
    NSMutableString* text = [[document mutableCopy] autorelease];
    NSString* preedit = @"";
    if (marked.location != NSNotFound) {
        preedit = [document substringWithRange:marked]; [text deleteCharactersInRange:marked];
    }
    return @{@"text": text, @"preedit": preedit, @"document": [[document copy] autorelease],
        @"caret": @(Scalars([document substringToIndex:selection.location])),
        @"selection_utf16": @[@(selection.location), @(selection.length)],
        @"marked_utf16": marked.location == NSNotFound ? (id)[NSNull null] : @[@(marked.location), @(marked.length)]};
}
- (NSRange)replacement:(NSRange)range {
    if (range.location == NSNotFound) range = marked.location == NSNotFound ? selection : marked;
    Require(range.location <= document.length && range.length <= document.length - range.location,
        "Client replacement range exceeds UTF-16 document");
    return range;
}
- (void)insertText:(id)value replacementRange:(NSRange)range {
    NSString* text = [value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    range = [self replacement:range];
    [transactions addObject:@{@"operation": @"insertText", @"text": text,
        @"replacement_utf16": @[@(range.location), @(range.length)]}];
    [document replaceCharactersInRange:range withString:text];
    selection = NSMakeRange(range.location + text.length, 0); marked = NSMakeRange(NSNotFound, 0);
}
- (void)setMarkedText:(id)value selectionRange:(NSRange)selected replacementRange:(NSRange)range {
    NSString* text = [value isKindOfClass:NSAttributedString.class] ? [value string] : value;
    Require(selected.location <= text.length && selected.length <= text.length - selected.location,
        "Client marked selection exceeds UTF-16 text");
    range = [self replacement:range];
    [transactions addObject:@{@"operation": @"setMarkedText", @"text": text,
        @"selection_utf16": @[@(selected.location), @(selected.length)],
        @"replacement_utf16": @[@(range.location), @(range.length)]}];
    [document replaceCharactersInRange:range withString:text];
    marked = text.length ? NSMakeRange(range.location, text.length) : NSMakeRange(NSNotFound, 0);
    selection = NSMakeRange(range.location + selected.location, selected.length);
}
- (NSDictionary*)attributesForCharacterIndex:(NSUInteger)index lineHeightRectangle:(NSRect*)rect {
    *rect = NSMakeRect(0, 0, 1, 16); return @{};
}
@end

@interface DesktopController : NSObject {
@public
    IMKShiftTap _shiftTap;
    BOOL _shiftTapEnabled, _modeSwitchInProgress, _commitFromOurselves;
    BOOL _doNotClearContextStateEvenWithForcedCommit, _updateCommitStringBeforeCommit;
    PVLoaderContext* _context;
    NSMutableString* _composingBuffer;
    NSMutableIndexSet* _handledKeyCodes;
}
- (BOOL)handleEvent:(NSEvent*)event client:(id)sender;
- (void)commitComposition:(id)sender;
- (BOOL)_setEnglishMode:(BOOL)english client:(id)sender;
- (void)toggleOutputFilterAction:(id)sender;
- (BOOL)_syncEnglishModeToCore:(BOOL)english;
- (BOOL)_finishCompositionForModeSwitch:(id)sender;
- (void)_handleShiftTap:(NSEvent*)event client:(id)sender;
- (void)_resetUI;
- (void)_updateClient:(id)client cursorPosition:(int)position segmentPairs:(const PVCombinedUTF16TextBuffer::SegmentPairVector&)pairs;
- (BOOL)_fixCursorPosition:(NSPoint)point;
@end
@implementation DesktopController
- (id)init {
    if ((self = [super init])) {
        _context = testLoader->createContext(); _context->activate();
        _composingBuffer = [NSMutableString new]; _handledKeyCodes = [NSMutableIndexSet new];
        _shiftTapEnabled = YES;
    }
    return self;
}
- (void)dealloc {
    _context->deactivate(); delete _context;
    [_composingBuffer release]; [_handledKeyCodes release]; [super dealloc];
}
- (BOOL)_fixCursorPosition:(NSPoint)point { return NO; }
// CONTROLLER_METHODS
@end

class IsolatedPolicy : public PVLoaderPolicy {
    std::string root;
public:
    explicit IsolatedPolicy(const std::string& path) : PVLoaderPolicy({}), root(path) {}
    const std::string propertyListPathForLoader() override { return root + "/Loader.plist"; }
    const std::string propertyListPathFromIdentifier(const std::string& id) override { return root + "/" + id + ".plist"; }
};
class WidthPackage : public OVModulePackage {
public:
    size_t numberOfModules(OVLoaderService*) override { return 1; }
    OVModule* moduleAtIndex(size_t index, OVLoaderService*) override { return index ? nullptr : new OVOFFullWidthCharacter; }
};

static NSDictionary* Panel(DesktopController* controller) {
    auto* p = controller->_context->candidateService()->accessVerticalCandidatePanel();
    NSMutableArray* values = [NSMutableArray array];
    for (size_t i = 0; i < p->candidateList()->size(); ++i) [values addObject:Native(p->candidateList()->candidateAtIndex(i))];
    return @{@"visible": @(p->isVisible()), @"in_control": @(p->isInControl()),
        @"page": @(p->currentPage()), @"page_size": @(p->candidatesPerPage()), @"candidates": values};
}
static NSEvent* Key(NSString* token, NSEventType type, BOOL caps) {
    NSArray* parts = [token componentsSeparatedByString:@"+"];
    NSString* name = parts.lastObject;
    NSUInteger flags = caps ? NSAlphaShiftKeyMask : 0;
    if ([parts containsObject:@"shift"]) flags |= NSShiftKeyMask;
    if ([parts containsObject:@"ctrl"]) flags |= NSControlKeyMask;
    // ANSI US virtual keys, all on the main keyboard. No global layout/state changes.
    NSDictionary* codes = @{@"a": @0, @"s": @1, @"d": @2, @"f": @3, @"h": @4, @"g": @5,
        @"z": @6, @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"q": @12, @"w": @13,
        @"e": @14, @"r": @15, @"y": @16, @"t": @17, @"1": @18, @"2": @19, @"3": @20,
        @"4": @21, @"6": @22, @"5": @23, @"9": @25, @"7": @26, @"8": @28, @"0": @29,
        @"o": @31, @"u": @32, @"i": @34, @"p": @35, @"l": @37, @"j": @38, @"k": @40,
        @"n": @45, @"m": @46, @"Return": @36, @"space": @49, @"Escape": @53, @"BackSpace": @51,
        @"grave": @50, @"backslash": @42, @"question": @44, @"asterisk": @28,
        @"Home": @115, @"End": @119, @"Page_Up": @116, @"Page_Down": @121,
        @"Left": @123, @"Right": @124, @"Down": @125, @"Up": @126};
    Require(codes[name] != nil, "Unknown reference key; add its native ANSI mapping explicitly");
    if ([name isEqual:@"question"] || [name isEqual:@"asterisk"]) flags |= NSShiftKeyMask;
    NSDictionary* special = @{@"Return": @13, @"Escape": @27, @"space": @32, @"BackSpace": @127,
        @"Down": @(NSDownArrowFunctionKey), @"Up": @(NSUpArrowFunctionKey),
        @"Left": @(NSLeftArrowFunctionKey), @"Right": @(NSRightArrowFunctionKey),
        @"Home": @(NSHomeFunctionKey), @"End": @(NSEndFunctionKey),
        @"Page_Down": @(NSPageDownFunctionKey), @"Page_Up": @(NSPageUpFunctionKey),
        @"question": @63, @"asterisk": @42, @"grave": @96, @"backslash": @92};
    unichar ch = special[name] ? [special[name] unsignedShortValue] : [name characterAtIndex:0];
    if (flags & NSShiftKeyMask) {
        NSString* plain = @"1234567890-=[]\\;',./`";
        NSString* shifted = @"!@#$%^&*()_+{}|:\"<>?~";
        NSRange index = [plain rangeOfString:[NSString stringWithCharacters:&ch length:1]];
        if (index.location != NSNotFound) ch = [shifted characterAtIndex:index.location];
    }
    NSString* chars = [NSString stringWithCharacters:&ch length:1];
    if (!!(flags & NSShiftKeyMask) != !!(flags & NSAlphaShiftKeyMask)) {
        if (ch >= 'a' && ch <= 'z') chars = chars.uppercaseString;
    }
    return [NSEvent keyEventWithType:type location:NSZeroPoint modifierFlags:flags timestamp:NSProcessInfo.processInfo.systemUptime
        windowNumber:0 context:nil characters:chars charactersIgnoringModifiers:chars isARepeat:NO keyCode:[codes[name] unsignedShortValue]];
}
static void Send(DesktopController* controller, DesktopClient* client, NSString* token, BOOL& caps, BOOL control, NSMutableArray* trace) {
    if ([token isEqual:@"Caps_Lock"]) { caps = !caps; }
    else if (!control && [token isEqual:@"ctrl+backslash"]) {
        // macOS binding is the native menu/Shift mode action; Ctrl-backslash
        // belongs to the method chooser, not the Windows/Linux language toggle.
        Require([controller _setEnglishMode:!OVCInputMode.english client:client], "Native language action failed");
    } else if (!control && [token isEqual:@"shift+space"]) {
        // macOS uses an output-filter menu action for width, not Shift-space.
        NSMenuItem* item = [[[NSMenuItem alloc] initWithTitle:@"Full width" action:nil keyEquivalent:@""] autorelease];
        item.representedObject = @"OVOFFullWidthCharacter";
        [controller toggleOutputFilterAction:@{@"IMKCommandMenuItem": item}];
    } else {
        NSEvent* down = Key(token, NSKeyDown, caps);
        BOOL handled = control ? NO : [controller handleEvent:down client:client];
        if (!handled && down.characters.length == 1 && [down.characters characterAtIndex:0] >= 32 &&
            [down.characters characterAtIndex:0] < NSUpArrowFunctionKey && !(down.modifierFlags & NSControlKeyMask))
            [client insertText:down.characters replacementRange:NSMakeRange(NSNotFound, 0)];
        BOOL up = control ? NO : [controller handleEvent:Key(token, NSKeyUp, caps) client:client];
        [trace addObject:@{@"reference_key": token, @"event_characters": down.characters,
            @"modifier_flags": @(down.modifierFlags), @"key_code": @(down.keyCode),
            @"handled_down": @(handled), @"handled_up": @(up), @"timestamp": @(down.timestamp),
            @"caps": @(caps), @"english": @(OVCInputMode.english), @"state": [client snapshot], @"panel": Panel(controller)}];
        return;
    }
    [trace addObject:@{@"reference_key": token, @"caps": @(caps), @"english": @(OVCInputMode.english),
        @"binding": [token isEqual:@"Caps_Lock"] ? @"test-local modifier state" : @"native menu action",
        @"state": [client snapshot], @"panel": Panel(controller)}];
}

static NSString* TargetKey(DesktopController* controller, NSString* target, NSMutableArray* evidence) {
    auto* p = controller->_context->candidateService()->accessVerticalCandidatePanel();
    Require(p->isVisible() && p->isInControl(), "Target selection requires a live native panel");
    [evidence addObject:Panel(controller)];
    // Find by text in the real filtered native list, then navigate through the
    // same controller key path. The caller still checks the reviewed final text.
    for (size_t index = 0; index < p->candidateList()->size(); ++index) {
        if (p->candidateList()->candidateAtIndex(index) != [target UTF8String]) continue;
        return [NSString stringWithFormat:@"%zu:%u", index / p->candidatesPerPage(), p->candidateKeyAtIndex(index % p->candidatesPerPage()).keyCode()];
    }
    throw std::runtime_error("Requested candidate is absent from native filtered list");
}

int main(int argc, char** argv) { @autoreleasepool {
    NSMutableDictionary* report = [NSMutableDictionary dictionary];
    int result = 0;
    @try { try {
        Require(argc == 5, "usage: DesktopInputHost REQUEST OUTPUT MODEL PROFILE");
        [NSApplication sharedApplication];
        Require(NSApp.delegate == nil, "Isolated host must not have application UI services");
        NSError* error = nil;
        NSDictionary* request = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:@(argv[1])] options:0 error:&error];
        Require(request != nil, "Invalid request JSON");
        IsolatedPolicy policy(argv[4]);
        CVEncodingService fonts;
        PVLoaderService service("zh_TW", nullptr, nullptr, nullptr, &fonts); testService = &service;
        OVPathInfo info; info.writablePath = argv[4]; info.resourcePath = argv[4]; info.loadedPath = argv[4];
        PVStaticModulePackageLoadingSystem packages(info, true);
        auto* package = GuanyinmaCreateModulePackage(argv[3], std::string(argv[4]) + "/GuanyinmaUserData.db");
        Require(package->initialize(&info, &service), "Rust package initialization failed");
        packages.addInitializedPackage("Guanyinma", package);
        auto* width = new WidthPackage; Require(width->initialize(&info, &service), "Width filter initialization failed");
        packages.addInitializedPackage("Width", width);
        PVLoader loader(&policy, &service, {&packages}); testLoader = &loader;
        Require(loader.primaryInputMethod() == [request[@"method"] UTF8String], "Native primary method readback differs");
        [report setObject:Native(loader.primaryInputMethod()) forKey:@"method_readback"];
        OVCInputMode.initialize(loader.configKeyValueMap().stringValueForKey("DefaultInputMode") == "English");
        DesktopController* controller = [[DesktopController alloc] init];
        DesktopClient* client = [[DesktopClient alloc] init];
        NSMutableArray* trace = [NSMutableArray array]; report[@"events"] = trace;
        NSMutableArray* checkpoints = [NSMutableArray array]; report[@"checkpoints"] = checkpoints;
        report[@"client_transactions"] = client->transactions;
        BOOL caps = NO, control = [request[@"control"] boolValue];
        @try {
            // Read the active module's native PV dictionary, not only a plist
            // roundtrip. This also detects an unintended module/default fallback.
            std::string method = [request[@"method"] UTF8String];
            auto* dictionary = loader.configDictionaryForModule(method);
            Require(dictionary != nullptr, "Active module has no native preference dictionary");
            OVKeyValueMap values = dictionary->readOnlyKeyValueMap();
            NSDictionary* requested = [NSDictionary dictionaryWithContentsOfFile:
                [@(argv[4]) stringByAppendingPathComponent:[request[@"method"] stringByAppendingString:@".plist"]]];
            NSMutableDictionary* native = [NSMutableDictionary dictionary];
            for (NSString* key in requested) {
                NSString* actual = Native(values.stringValueForKey([key UTF8String]));
                Require([actual isEqual:requested[key]], "Native module preference readback differs");
                native[key] = actual;
            }
            report[@"module_config_readback"] = native;
            if ([request[@"scenario"] isEqual:@"focus"]) {
                for (NSString* key in @[@"s", @"u", @"3", @"c", @"l", @"3"]) Send(controller, client, key, caps, control, trace);
                [checkpoints addObject:[client snapshot]];
                [controller commitComposition:client]; controller->_context->deactivate();
                [checkpoints addObject:[client snapshot]];
                DesktopController* other = [[DesktopController alloc] init]; DesktopClient* otherClient = [[DesktopClient alloc] init];
                for (NSString* key in @[@"s", @"u", @"3", @"Return"]) Send(other, otherClient, key, caps, control, trace);
                [checkpoints addObject:[otherClient snapshot]];
                report[@"other_client_transactions"] = otherClient->transactions;
                [other release]; [otherClient release]; controller->_context->activate();
                [checkpoints addObject:[client snapshot]];
            } else {
                for (NSDictionary* step in request[@"steps"]) {
                    NSUInteger index = 0;
                    for (NSString* reference in step[@"keys"]) {
                        NSString* target = step[@"candidate_targets"][[NSString stringWithFormat:@"%lu", (unsigned long)index]];
                        NSString* actual = reference;
                        if (target) {
                            NSMutableArray* pages = [NSMutableArray array];
                            NSArray* parsed = [TargetKey(controller, target, pages) componentsSeparatedByString:@":"];
                            auto* panel = controller->_context->candidateService()->accessVerticalCandidatePanel();
                            size_t page = [parsed[0] integerValue];
                            size_t budget = panel->pageCount() + 1;
                            while (panel->currentPage() != page && budget--) {
                                Send(controller, client, @"Page_Down", caps, control, trace); [pages addObject:Panel(controller)];
                            }
                            Require(panel->currentPage() == page, "Native target page was not reached");
                            unichar key = [parsed[1] intValue]; actual = [NSString stringWithCharacters:&key length:1];
                            [trace addObject:@{@"candidate_target": target, @"reference_key": reference, @"actual_key": actual, @"pages": pages}];
                        }
                        Send(controller, client, actual, caps, control, trace); ++index;
                    }
                    [checkpoints addObject:[client snapshot]];
                }
            }
        } @finally { [controller release]; [client release]; }
    } catch (const std::exception& exception) { report[@"error"] = Native(exception.what()); result = 1; }
    } @catch (NSException* exception) { report[@"error"] = exception.description; result = 1; }
    if (argc >= 3) {
        NSData* data = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:nil];
        if (!data || ![data writeToFile:@(argv[2]) atomically:YES]) return 2;
    }
    return result;
} }

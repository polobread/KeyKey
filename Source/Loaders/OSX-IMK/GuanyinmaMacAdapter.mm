/*
 * macOS OpenVanilla frontend bridge for the Guanyinma shared core.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 *
 * Native buffer/candidate integration follows the OpenVanilla module API.
 * The existing PV sandwich retains associated-phrase UI, keys and output filters.
 */
#include "GuanyinmaMacAdapter.h"

bool GuanyinmaSupportsInputMethod(const std::string& identifier)
{
    return identifier == "TraditionalMandarin" || identifier == "SmartMandarin" ||
        identifier == "OVIMTraditionalMandarin" ||
        identifier == "OVIMSmartMandarin" ||
        identifier == "Generic-cj-cin" ||
        identifier == "Generic-simplex-cin";
}

#if KEYKEY_ENABLE_GUANYINMA
#import <Foundation/Foundation.h>
#include <PlainVanilla/PVCandidate.h>
#include "../../ModulePackages/OVIMMandarin/OVAFAssociatedPhrase.h"
#include "../../Guanyinma/include/guanyinma.h"
#include <algorithm>
#include <climits>
#include <memory>
#include <map>
#include <set>

using namespace OpenVanilla;

namespace {

static NSString* NativeString(const std::string& value)
{
    return [[[NSString alloc] initWithBytes:value.data() length:value.size()
        encoding:NSUTF8StringEncoding] autorelease];
}

static std::string UTF8String(NSString* value)
{
    if (![value isKindOfClass:[NSString class]]) return std::string();
    NSData* data = [value dataUsingEncoding:NSUTF8StringEncoding];
    return data ? std::string(static_cast<const char*>([data bytes]), [data length]) : std::string();
}

static NSNumber* Boolean(bool value) { return [NSNumber numberWithBool:value]; }

static bool ConfigBool(OVKeyValueMap* config, const char* key, bool fallback)
{
    return config && config->hasKey(key) ? config->isKeyTrue(key) : fallback;
}

static std::string ConfigString(OVKeyValueMap* config, const char* key)
{
    return config && config->hasKey(key) ? config->stringValueForKey(key) : std::string();
}

static bool Reject(std::string* error, const std::string& message)
{
    if (error) *error = message;
    return false;
}

static bool IsSmart(const std::string& identifier) { return identifier == "OVIMSmartMandarin" || identifier == "SmartMandarin"; }
static bool IsTable(const std::string& identifier)
{
    return identifier == "Generic-cj-cin" || identifier == "Generic-simplex-cin";
}

static NSString* MethodName(const std::string& identifier)
{
    if (IsSmart(identifier)) return @"smart";
    if (identifier == "Generic-cj-cin") return @"cangjie";
    if (identifier == "Generic-simplex-cin") return @"simplex";
    return @"traditional";
}

static std::string NativeEncoding(OVKeyValueMap* config)
{
    const std::string encoding = ConfigString(config, "UseCharactersSupportedByEncoding");
    // Native modules normalize unknown or historic boolean strings to the
    // system-font policy before using the encoding service.
    return encoding == "UTF-8" || encoding == "BIG-5" ? encoding : std::string();
}

static NSString* LayoutName(OVKeyValueMap* config)
{
    const std::string layout = ConfigString(config, "KeyboardLayout");
    // Keep Formosa's case-insensitive persisted names and historical aliases.
    // In particular, the macOS preference UI saves "Hanyu Pinyin" with a space.
    if (OVWildcard::Match(layout, "hsu") ||
        OVWildcard::Match(layout, "bpmfdtnlgkhjvcjvcrzasexuyhgeiawomnklldfjs")) return @"hsu";
    if (OVWildcard::Match(layout, "eten")) return @"eten";
    if (OVWildcard::Match(layout, "eten26") ||
        OVWildcard::Match(layout, "bpmfdtnlvkhgvcgycjqwsexuaorwiqzpmntlhfjkd")) return @"eten26";
    if (OVWildcard::Match(layout, "hanyupinyin") ||
        OVWildcard::Match(layout, "hanyu pinyin") ||
        OVWildcard::Match(layout, "hanyu-pinyin") ||
        OVWildcard::Match(layout, "pinyin")) return @"hanyu_pinyin";
    // Manjusri/OpenVanilla use Standard when a saved layout name is unknown.
    return @"standard";
}

static bool ValidateConfiguration(const std::string& identifier, OVKeyValueMap* config,
    std::string* error)
{
    if (error) error->clear();
    if (!GuanyinmaSupportsInputMethod(identifier))
        return Reject(error, "input method is not supported by Guanyinma");
    if (IsSmart(identifier)) {
        if (config && config->hasKey("ComposingTextBufferSize")) {
            int size = config->intValueForKey("ComposingTextBufferSize");
            if (size < 10 || size > 20)
                return Reject(error, "Guanyinma composition size must be between 10 and 20");
        }
    }
    if (!IsTable(identifier)) {
        std::string keys = ConfigString(config, "CandidateSelectionKeys");
        std::set<unsigned char> unique;
        for (size_t i = 0; i < keys.size(); ++i) {
            unsigned char key = static_cast<unsigned char>(keys[i]);
            if (key < 0x21 || key > 0x7e || !unique.insert(key).second)
                return Reject(error, "candidate selection keys must be unique printable ASCII");
        }
        if (keys.size() > 32)
            return Reject(error, "candidate selection keys must contain at most 32 keys");
    }
    if (IsTable(identifier)) {
        if (config && config->hasKey("MaximumRadicalLength")) {
            const int maximum = config->intValueForKey("MaximumRadicalLength");
            if (maximum < 0 || maximum > 128)
                return Reject(error, "radical length must be zero (default) or within 1..128");
        }
        for (const char* name : {"MatchOneChar", "MatchZeroOrMoreChar"}) {
            const std::string value = ConfigString(config, name);
            if (!value.empty() && (static_cast<unsigned char>(value[0]) < 0x21 ||
                                  static_cast<unsigned char>(value[0]) > 0x7e))
                return Reject(error, "wildcard keys must start with printable ASCII");
        }
        std::string punctuation = ConfigString(config, "UseOverrideTable");
        if (!punctuation.empty() && punctuation != "Punctuations-punctuations-cin" &&
            punctuation != "Punctuations-cj-mixedwidth-cin" &&
            punctuation != "Punctuations-cj-halfwidth-cin")
            return Reject(error, "the selected punctuation override requires the legacy core");
    }
    return true;
}

static NSDictionary* Configuration(const std::string& identifier,
    const std::string& userDatabasePath, OVKeyValueMap* config, std::string* error)
{
    if (!ValidateConfiguration(identifier, config, error)) return nil;
    const bool smart = IsSmart(identifier);
    const bool table = IsTable(identifier);
    const bool cangjie = identifier == "Generic-cj-cin";
    const bool learnTable = table && ConfigBool(config, "UseDynamicFrequency", cangjie);
    NSMutableDictionary* result = [NSMutableDictionary dictionaryWithObjectsAndKeys:
        MethodName(identifier), @"method", @"desktop", @"profile",
        LayoutName(config), @"layout",
        [NSDictionary dictionaryWithObjectsAndKeys:Boolean(false), @"ignore_caps_lock_in_chinese",
            Boolean(true), @"literal_keypad", nil], @"behaviors",
        [NSDictionary dictionaryWithObjectsAndKeys:Boolean(true), @"user_phrases",
            Boolean(smart), @"candidate_overrides", Boolean(smart), @"bigrams",
            Boolean(learnTable), @"table_learning", nil], @"learning", nil];
    if (!userDatabasePath.empty()) {
        NSString* userPath = NativeString(userDatabasePath);
        if (!userPath) {
            Reject(error, "Guanyinma user database path must be valid UTF-8");
            return nil;
        }
        [result setObject:userPath forKey:@"user_database"];
    }
    std::string keys = ConfigString(config, "CandidateSelectionKeys");
    if (smart) {
        int limit = config && config->hasKey("ComposingTextBufferSize") ?
            config->intValueForKey("ComposingTextBufferSize") : 10;
        NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            Boolean(true), @"use_bigrams",
            Boolean(ConfigBool(config, "ShowCandidateListWithSpace", true)), @"space_opens_candidates",
            Boolean(ConfigBool(config, "CandidateCursorAtEndOfTargetBlock", false)), @"candidate_cursor_at_end",
            Boolean(ConfigBool(config, "ClearComposingTextWithEsc", false)), @"clear_composing_with_escape",
            Boolean(ConfigBool(config, "ShiftKeyAlwaysCommitUppercaseCharacters", false)), @"shift_always_uppercase",
            [NSNumber numberWithInt:limit], @"max_completed_syllables",
            Boolean(false), @"shift_at_limit", Boolean(false), @"selection_returns_to_end", nil];
        if (!keys.empty()) [options setObject:NativeString(keys) forKey:@"candidate_selection_keys"];
        [result setObject:options forKey:@"smart"];
    }
    else if (!table && !keys.empty())
        [result setObject:NativeString(keys) forKey:@"traditional_selection_keys"];
    if (table) {
        std::string overrideTable = ConfigString(config, "UseOverrideTable");
        NSString* punctuation = overrideTable == "Punctuations-cj-halfwidth-cin" ? @"half" :
            (overrideTable == "Punctuations-cj-mixedwidth-cin" ? @"mixed" : @"original");
        NSMutableDictionary* options = [NSMutableDictionary dictionaryWithObjectsAndKeys:
            Boolean(ConfigBool(config, "ComposeWhileTyping", false)), @"realtime",
            Boolean(cangjie && ConfigBool(config, "PrefixCandidates", false)), @"prefix",
            Boolean(ConfigBool(config, "ClearReadingBufferAtCompositionError", true)), @"clear_on_error",
            Boolean(ConfigBool(config, "ShouldCommitAtMaximumRadicalLength", !cangjie)), @"query_at_maximum",
            Boolean(ConfigBool(config, "UseSpaceAsFirstCandidateSelectionKey", false)), @"space_as_first_selection_key",
            Boolean(ConfigBool(config, "SendFirstCandidateWithSpaceWithOnePageList", cangjie)), @"space_commits_first_on_single_page",
            Boolean(learnTable), @"learn_selection", punctuation, @"punctuation", nil];
        const int maximum = config && config->hasKey("MaximumRadicalLength") ?
            config->intValueForKey("MaximumRadicalLength") : 0;
        if (maximum > 0) [options setObject:[NSNumber numberWithInt:maximum] forKey:@"maximum_radical_length"];
        if (config && (config->hasKey("MatchOneChar") || config->hasKey("MatchZeroOrMoreChar"))) {
            std::string one = config->hasKey("MatchOneChar") ? ConfigString(config, "MatchOneChar") : (cangjie ? "?" : "");
            std::string many = config->hasKey("MatchZeroOrMoreChar") ? ConfigString(config, "MatchZeroOrMoreChar") : (cangjie ? "*" : "");
            [options setObject:[NSDictionary dictionaryWithObjectsAndKeys:
                one.empty() ? (id)[NSNull null] : NativeString(one.substr(0, 1)), @"one",
                many.empty() ? (id)[NSNull null] : NativeString(many.substr(0, 1)), @"many", nil]
                forKey:@"wildcards"];
        }
        [result setObject:options forKey:MethodName(identifier)];
    }
    return result;
}

static std::string MarkedPhraseToolTip(const std::string& text, OVLoaderService* service)
{
    const std::string locale = service ? service->locale() : std::string();
    if (locale == "zh_TW" || locale == "zh-Hant")
        return "正在選取字詞組：" + text + "，請按ENTER鍵加入資料庫";
    if (locale == "zh_CN" || locale == "zh-Hans")
        return "正在选取字词组：" + text + "，请按ENTER键加入数据库";
    return "Currently marked: \"" + text + "\", press ENTER to add into the database.";
}

static std::string PhraseFeedbackToolTip(const std::string& text, bool added, OVLoaderService* service)
{
    const std::string locale = service ? service->locale() : std::string();
    if (locale == "zh_TW" || locale == "zh-Hant")
        return added ? "加入新詞：「" + text + "」" :
            "「" + text + "」無法加入，該詞已經存在於資料庫中";
    if (locale == "zh_CN" || locale == "zh-Hans")
        return added ? "加入新词：“" + text + "”" :
            "“" + text + "”无法加入，该词已经存在于数据库中";
    return added ? "New phrase \"" + text + "\" added." :
        "Cannot add \"" + text + "\". It may already exist in the database.";
}

static std::string LastError()
{
    size_t required = 0;
    if (guanyinma_last_error(NULL, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL || !required)
        return "Guanyinma operation failed";
    std::vector<uint8_t> bytes(required);
    if (guanyinma_last_error(&bytes[0], bytes.size(), &required) != GUANYINMA_OK)
        return "Guanyinma operation failed";
    return std::string(reinterpret_cast<const char*>(&bytes[0]), required - 1);
}

static NSDictionary* ReadResult(GuanyinmaResult* result, std::string* error)
{
    size_t required = 0;
    int32_t status = guanyinma_result_json(result, NULL, 0, &required);
    if (status != GUANYINMA_BUFFER_TOO_SMALL || !required) {
        if (error) *error = LastError();
        guanyinma_result_close(&result);
        return nil;
    }
    std::vector<uint8_t> bytes(required);
    status = guanyinma_result_json(result, &bytes[0], bytes.size(), &required);
    if (status != GUANYINMA_OK) {
        if (error) *error = LastError();
        guanyinma_result_close(&result);
        return nil;
    }
    guanyinma_result_close(&result);
    NSError* jsonError = nil;
    id parsed = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithBytes:&bytes[0] length:required - 1]
        options:0 error:&jsonError];
    if (![parsed isKindOfClass:[NSDictionary class]]) {
        if (error) *error = jsonError ? UTF8String([jsonError localizedDescription]) :
            "Guanyinma returned an invalid JSON snapshot";
        return nil;
    }
    return parsed;
}

static std::string SelectionKeys(const std::string& identifier, NSDictionary* configuration,
    const std::string& modelPath, std::string* error)
{
    if (!IsTable(identifier)) {
        NSDictionary* smartOptions = [configuration objectForKey:@"smart"];
        NSString* explicitKeys = IsSmart(identifier) ?
            [smartOptions objectForKey:@"candidate_selection_keys"] :
            [configuration objectForKey:@"traditional_selection_keys"];
        if (explicitKeys) return UTF8String(explicitKeys);
        NSString* layout = [configuration objectForKey:@"layout"];
        if ([layout isEqualToString:@"hsu"]) return "asdfzxcv";
        if ([layout isEqualToString:@"eten26"]) return "asdfjkl;";
        return IsSmart(identifier) ? "12345678" : "123456789";
    }
    GuanyinmaDatabase* database = NULL;
    if (guanyinma_database_open(reinterpret_cast<const uint8_t*>(modelPath.data()),
        modelPath.size(), &database) != GUANYINMA_OK) {
        if (error) *error = LastError();
        return std::string();
    }
    const std::string property("__property_selkey");
    GuanyinmaResult* result = NULL;
    int32_t status = guanyinma_database_query(database,
        identifier == "Generic-cj-cin" ? GUANYINMA_QUERY_CANGJIE : GUANYINMA_QUERY_SIMPLEX,
        reinterpret_cast<const uint8_t*>(property.data()), property.size(), &result);
    if (status != GUANYINMA_OK) {
        if (error) *error = LastError();
        guanyinma_database_close(&database);
        return std::string();
    }
    NSDictionary* value = ReadResult(result, error);
    guanyinma_database_close(&database);
    if (!value) return std::string();
    NSArray* rows = [value objectForKey:@"rows"];
    std::string keys = [rows count] ? UTF8String([rows objectAtIndex:0]) : std::string();
    if (keys.empty()) keys = "123456789";
    NSDictionary* tableOptions = [configuration objectForKey:MethodName(identifier)];
    if ([[tableOptions objectForKey:@"space_as_first_selection_key"] boolValue]) keys.insert(0, 1, ' ');
    return keys;
}

// The frontend owns its font/encoding service. The policy lives at least as
// long as its Rust session, including the old session during preference refresh.
// Only the serialized native event thread invokes it; the core stores no OS data.
struct NativeCandidateFilter {
    OVEncodingService* service;
    const std::string encoding;
    NativeCandidateFilter(const std::string& value, OVEncodingService* nativeService = NULL)
        : service(nativeService), encoding(value) {}
};

static int32_t GUANYINMA_CALL CandidateAccepted(void* opaque, const uint8_t* bytes, size_t length)
{
    NativeCandidateFilter* filter = static_cast<NativeCandidateFilter*>(opaque);
    if (!filter || !filter->service) return 0;
    // Neither C++ nor Objective-C exceptions may cross the C callback boundary.
    @try {
        try {
            const std::string text(reinterpret_cast<const char*>(bytes), length);
            return filter->encoding.empty() ? filter->service->stringSupportedBySystem(text) :
                filter->service->stringSupportedByEncoding(text, filter->encoding);
        }
        catch (...) { return 0; }
    }
    @catch (NSException*) { return 0; }
}

static bool OpenSession(const std::string& path, NSDictionary* configuration,
    const std::shared_ptr<NativeCandidateFilter>& filter,
    GuanyinmaSession** session, std::string* error)
{
    NSError* jsonError = nil;
    NSData* config = [NSJSONSerialization dataWithJSONObject:configuration options:0 error:&jsonError];
    if (!config) return Reject(error, UTF8String([jsonError localizedDescription]));
    if (guanyinma_abi_version() != 1)
        return Reject(error, "unsupported Guanyinma ABI version");
    if (guanyinma_session_open_with_candidate_filter(
        reinterpret_cast<const uint8_t*>(path.data()), path.size(),
        static_cast<const uint8_t*>([config bytes]), [config length],
        CandidateAccepted, filter.get(), session) != GUANYINMA_OK)
        return Reject(error, LastError());
    return true;
}

// A PV plist key-value map is a borrowed dictionary view even after copy().
// Capture known native settings by value so plist reload/destruction cannot
// leave a session holding the previous root dictionary.
class ConfigurationMap : public OVKeyValueMapImpl {
public:
    ConfigurationMap(OVKeyValueMap* source)
    {
        static const char* const keys[] = {
            "KeyboardLayout", "CandidateSelectionKeys", "UseCharactersSupportedByEncoding",
            "CandidateCursorAtEndOfTargetBlock", "ShowCandidateListWithSpace",
            "ClearComposingTextWithEsc", "ClearComposingTextWithEscUserChoice",
            "ComposingTextBufferSize", "ShiftKeyAlwaysCommitUppercaseCharacters",
            "MaximumRadicalLength", "ShouldCommitAtMaximumRadicalLength",
            "ClearReadingBufferAtCompositionError", "MatchOneChar", "MatchZeroOrMoreChar",
            "UseDynamicFrequency", "UseSpaceAsFirstCandidateSelectionKey",
            "ComposeWhileTyping", "PrefixCandidates", "SendFirstCandidateWithSpaceWithOnePageList",
            "UseOverrideTable"
        };
        if (source) {
            for (size_t i = 0; i < sizeof(keys) / sizeof(keys[0]); ++i)
                if (source->hasKey(keys[i])) m_values[keys[i]] = source->stringValueForKey(keys[i]);
        }
    }
    virtual bool shouldDelete() { return true; }
    virtual OVKeyValueMapImpl* copy() { return new ConfigurationMap(*this); }
    virtual bool isReadOnly() { return true; }
    virtual bool setKeyStringValue(const std::string&, const std::string&) { return false; }
    virtual bool hasKey(const std::string& key) { return m_values.find(key) != m_values.end(); }
    virtual const std::string stringValueForKey(const std::string& key)
    {
        std::map<std::string, std::string>::const_iterator found = m_values.find(key);
        return found == m_values.end() ? std::string() : found->second;
    }
private:
    std::map<std::string, std::string> m_values;
};

struct ModuleConfiguration {
    OVKeyValueMap config;
    size_t generation;
    ModuleConfiguration(OVKeyValueMap* value) : config(new ConfigurationMap(value)), generation(1) {}
    void capture(OVKeyValueMap* value) { config = OVKeyValueMap(new ConfigurationMap(value)); }
};

class GuanyinmaContext;
// macOS factories, event handling and lifecycle calls use the existing
// serialized FE event thread/loader lock. This registry is not a cross-thread
// API and never dereferences a candidate service during context destruction.
static std::vector<GuanyinmaContext*> s_contexts;

class GuanyinmaContext : public OVEventHandlingContext {
public:
    GuanyinmaContext(const std::string& identifier, const std::string& modelPath,
        const std::string& userDatabasePath, std::shared_ptr<ModuleConfiguration> sharedConfig,
        GuanyinmaSession* session, NSDictionary* configuration, const std::string& selectionKeys,
        std::shared_ptr<NativeCandidateFilter> filter)
        : m_identifier(identifier), m_modelPath(modelPath), m_userDatabasePath(userDatabasePath),
          m_sharedConfig(sharedConfig), m_generation(sharedConfig->generation),
          m_candidateFilter(std::move(filter)), m_session(session),
          m_configuration([configuration retain]), m_snapshot(nil), m_selectionKeys(selectionKeys),
          m_candidateService(NULL), m_candidatePanel(NULL), m_ownerCandidateService(NULL), m_active(false)
    {
        s_contexts.push_back(this);
    }

    virtual ~GuanyinmaContext()
    {
        s_contexts.erase(std::remove(s_contexts.begin(), s_contexts.end(), this), s_contexts.end());
        guanyinma_session_close(&m_session);
        [m_configuration release];
        [m_snapshot release];
    }

    bool initialSnapshot(std::string* error)
    {
        GuanyinmaResult* result = NULL;
        if (guanyinma_session_snapshot(m_session, &result) != GUANYINMA_OK)
            return Reject(error, LastError());
        NSDictionary* snapshot = ReadResult(result, error);
        if (!snapshot) return false;
        replaceSnapshot(snapshot);
        return true;
    }

    virtual void startSession(OVLoaderService* service)
    {
        m_active = true;
        // Bind before any input operation; opening/snapshotting has no queries
        // that need candidate acceptance. Repeated activation preserves input.
        bindCandidateService(service);
        refreshConfiguration(service);
    }

    virtual void stopSession(OVLoaderService* service)
    {
        m_active = false;
        m_candidateService = NULL;
        m_candidatePanel = NULL;
        // Learning is already transactional per operation; this is an explicit
        // flush only, with no commit/replay of visible text.
        if (!apply([NSDictionary dictionaryWithObject:@"save_learning" forKey:@"type"]))
            reportError(service);
    }

    virtual void clear(OVLoaderService* service)
    {
        bindCandidateService(service);
        m_candidateService = NULL;
        m_candidatePanel = NULL;
        if (!apply([NSDictionary dictionaryWithObject:@"reset" forKey:@"type"])) {
            // The native loader has explicitly preserved/discarded its old
            // buffers before clear(). Do not keep an unreset graph that could
            // reappear on the next key after a temporary user-store failure.
            guanyinma_session_close(&m_session);
            [m_snapshot release];
            m_snapshot = nil;
            if (!OpenSession(m_modelPath, m_configuration, m_candidateFilter, &m_session, &m_error) ||
                !initialSnapshot(&m_error)) {
                guanyinma_session_close(&m_session);
                reportError(service);
            }
        }
        refreshConfiguration(service);
    }

    virtual bool handleKey(OVKey* key, OVTextBuffer* reading, OVTextBuffer* composing,
        OVCandidateService* candidates, OVLoaderService* service)
    {
        if (!key) return false;
        bindCandidateService(service);
        refreshConfiguration(service);
        // Manjusri's macOS Caps Lock policy excludes Ctrl punctuation chords.
        // This is native event classification; the shared core receives only
        // shortcuts that the FE has classified as input-method operations.
        if (IsSmart(m_identifier) && key->isCapsLockOn() && key->isCombinedFunctionKey()) {
            const bool occupied = [[m_snapshot objectForKey:@"visible_text"] length] ||
                [[m_snapshot objectForKey:@"candidates"] count];
            if (occupied) service->beep();
            return occupied;
        }
        if (!IsSmart(m_identifier) && key->isCapsLockOn() && !key->isCombinedFunctionKey() &&
            !key->isNumLockOn() && !key->isPrintable() &&
            [[m_snapshot objectForKey:@"visible_text"] length]) {
            if (!apply([NSDictionary dictionaryWithObject:@"reset" forKey:@"type"])) {
                render(reading, composing, candidates, service, false);
                reportError(service);
                return true;
            }
            render(reading, composing, candidates, service);
            if (!IsTable(m_identifier)) {
                // Legacy Traditional commits the original key-code byte even
                // for a nonprintable Caps key. Preserve that macOS compatibility
                // at the FE boundary; never admit it as a common DirectText or
                // phonetic Character operation.
                composing->commitAsTextSegment(std::string(1, static_cast<char>(key->keyCode())));
                composing->updateDisplay();
            }
            return true;
        }
        if (!IsSmart(m_identifier) && key->keyCode() == OVKeyCode::Space &&
            key->isCapsLockOn() && !key->isCombinedFunctionKey() && !key->isNumLockOn())
            return handleDirectText(" ", reading, composing, candidates, service);
        if (key->isDirectTextKey() || (!key->keyCode() &&
            OVUTF8Helper::SplitStringByCodePoint(key->receivedString()).size() > 1))
            return handleDirectText(key->receivedString(), reading, composing, candidates, service);
        NSDictionary* operation = operationForKey(key);
        if (!operation) return false;
        if (!apply(operation)) {
            // Once a session exists, replaying an event through the old engine
            // could duplicate or discard composition. Keep its last good view,
            // including a panel temporarily released by the keypad pre-hook.
            render(reading, composing, candidates, service, false);
            reportError(service);
            return true;
        }
        return render(reading, composing, candidates, service);
    }

    virtual bool handleDirectText(const std::string& text, OVTextBuffer* reading,
        OVTextBuffer* composing, OVCandidateService* candidates, OVLoaderService* service)
    {
        if (text.empty()) return false;
        NSString* value = NativeString(text);
        if (!value) { service->beep(); return true; }
        if (!apply([NSDictionary dictionaryWithObjectsAndKeys:
            @"direct_text", @"type", value, @"text", nil])) {
            render(reading, composing, candidates, service, false);
            reportError(service);
            return true;
        }
        return render(reading, composing, candidates, service);
    }

    virtual void candidateCanceled(OVCandidateService* candidates, OVTextBuffer* reading,
        OVTextBuffer* composing, OVLoaderService* service)
    {
        NSDictionary* operation = IsSmart(m_identifier) ?
            [NSDictionary dictionaryWithObject:@"close_candidates" forKey:@"type"] :
            [NSDictionary dictionaryWithObjectsAndKeys:@"key", @"type", @"escape", @"key", nil];
        if (!apply(operation)) reportError(service);
        else render(reading, composing, candidates, service);
    }

    virtual bool candidateSelected(OVCandidateService* candidates, const std::string& text,
        size_t index, OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service)
    {
        NSArray* values = [m_snapshot objectForKey:@"candidates"];
        // Validate both identity and absolute index before translating the
        // native panel's chosen index into the core's page-local operation.
        if (index >= [values count] || UTF8String([values objectAtIndex:index]) != text) {
            service->beep();
            return true;
        }
        size_t pageSize = [[m_snapshot objectForKey:@"page_size"] unsignedIntegerValue];
        if (!pageSize || !syncCandidatePosition(index, false)) {
            render(reading, composing, candidates, service, false);
            reportError(service);
            return true;
        }
        if (!apply([NSDictionary dictionaryWithObjectsAndKeys:@"select", @"type",
            [NSNumber numberWithUnsignedLongLong:index % pageSize], @"index", nil])) {
            reportError(service);
            return true;
        }
        render(reading, composing, candidates, service);
        return true;
    }

    virtual bool candidateNonPanelKeyReceived(OVCandidateService* candidates, const OVKey* key,
        OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service)
    {
        if (!key || IsSmart(m_identifier) || key->isDirectTextKey()) return false;
        const bool table = IsTable(m_identifier);
        // Native Traditional rejects modified chords; Generic's continuation
        // callback classifies roots independently of the ordinary literal path.
        if (!table && key->isCombinedFunctionKey()) return false;
        OVOneDimensionalCandidatePanel* panel = candidates->useOneDimensionalCandidatePanel();
        if (!syncCandidatePosition(panel->currentHightlightIndexInCandidateList(), true)) {
            render(reading, composing, candidates, service, false);
            reportError(service);
            return true;
        }
        NSDictionary* operation = nil;
        if (key->keyCode() == OVKeyCode::Backspace) {
            operation = [NSDictionary dictionaryWithObjectsAndKeys:
                @"key", @"type", @"backspace", @"key", nil];
        }
        else if (key->keyCode() == OVKeyCode::Space) {
            NSDictionary* options = [m_configuration objectForKey:MethodName(m_identifier)];
            if (!table || ![[options objectForKey:@"space_commits_first_on_single_page"] boolValue])
                return false;
            // A Space that escaped PV's candidate/page bindings follows
            // Generic's callback: choose the first item of the complete list.
            if (!syncCandidatePosition(0, false)) {
                reportError(service);
                return true;
            }
            operation = [NSDictionary dictionaryWithObjectsAndKeys:
                @"select", @"type", @0, @"index", nil];
        }
        else if (key->isKeyCodePrintable() && key->keyCode() >= 0x21 && key->keyCode() <= 0x7e) {
            char code = static_cast<char>(key->keyCode());
            if (!table && [[m_configuration objectForKey:@"layout"] isEqualToString:@"hanyu_pinyin"] &&
                code >= 'A' && code <= 'Z') code += 'a' - 'A';
            // A candidate continuation is already classified by the native
            // callback. Do not run Caps/Shift literal translation a second time.
            operation = [NSDictionary dictionaryWithObjectsAndKeys:
                @"character", @"type", NativeString(std::string(1, code)), @"text", nil];
        }
        else return false;
        if (!apply(operation)) {
            render(reading, composing, candidates, service, false);
            reportError(service);
            return true;
        }
        return render(reading, composing, candidates, service);
    }

    bool ownsActiveService(OVCandidateService* service) const
    {
        return m_active && service && service == m_ownerCandidateService;
    }

    bool setEnglishMode(bool enabled, std::string* error)
    {
        // A repeated FE assertion must not query/write the user store or
        // disturb an in-progress reading that is already in this mode.
        if ([[m_snapshot objectForKey:@"english"] boolValue] == enabled) return true;
        if ([[m_snapshot objectForKey:@"visible_text"] length] ||
            [[m_snapshot objectForKey:@"candidates"] count])
            return Reject(error, "finish visible input before changing the core input mode");
        if (!apply([NSDictionary dictionaryWithObjectsAndKeys:
                @"set_english", @"type", Boolean(enabled), @"enabled", nil]))
            return Reject(error, m_error);
        // The empty-session precondition makes SetEnglish idempotent and avoids
        // returning host text a second time after the FE's preserve transaction.
        return true;
    }

    bool prepareKeypadEvent(const OVKey* key, OVCandidateService* candidateService)
    {
        if (!candidateService || candidateService != m_candidateService || !key || !key->isNumLockOn() ||
            key->isCombinedFunctionKey() || key->isDirectTextKey() ||
            !key->isKeyCodePrintable()) return false;
        NSArray* values = [m_snapshot objectForKey:@"candidates"];
        if (![values count]) return false;
        PVCandidateService* nativeService = dynamic_cast<PVCandidateService*>(candidateService);
        if (!nativeService || !m_candidatePanel ||
            nativeService->lastUsedPanel() != m_candidatePanel) return false;
        OVOneDimensionalCandidatePanel* panel = m_candidatePanel;
        if (!panel->isVisible() || panel->candidateList()->size() != [values count]) return false;
        // Around filters share the service. Never release another owner's
        // panel merely because this input context previously used the service.
        for (size_t i = 0; i < [values count]; ++i)
            if (panel->candidateList()->candidateAtIndex(i) != UTF8String([values objectAtIndex:i]))
                return false;
        panel->hide();
        panel->cancelEventHandler();
        return true;
    }

private:
    void bindCandidateService(OVLoaderService* service)
    {
        m_candidateFilter->service = service ? service->encodingService() : NULL;
    }

    void replaceSnapshot(NSDictionary* snapshot)
    {
        [snapshot retain];
        [m_snapshot release];
        m_snapshot = snapshot;
    }

    bool apply(NSDictionary* operation)
    {
        NSError* jsonError = nil;
        NSData* json = [NSJSONSerialization dataWithJSONObject:operation options:0 error:&jsonError];
        if (!json) { m_error = UTF8String([jsonError localizedDescription]); return false; }
        GuanyinmaResult* result = NULL;
        if (guanyinma_session_apply(m_session, static_cast<const uint8_t*>([json bytes]),
            [json length], &result) != GUANYINMA_OK) {
            m_error = LastError();
            return false;
        }
        NSDictionary* snapshot = ReadResult(result, &m_error);
        if (!snapshot) return false;
        replaceSnapshot(snapshot);
        return true;
    }

    void reportError(OVLoaderService* service)
    {
        if (!service) return;
        service->beep();
        service->logger("Guanyinma") << m_error << std::endl;
    }

    void refreshConfiguration(OVLoaderService* service)
    {
        if (m_generation == m_sharedConfig->generation) return;
        // Defer changed preferences while a visible session still belongs to
        // the old configuration. The controller preserves it before clear().
        if ([[m_snapshot objectForKey:@"visible_text"] length] ||
            [[m_snapshot objectForKey:@"candidates"] count]) return;
        NSDictionary* configuration = Configuration(m_identifier, m_userDatabasePath,
            &m_sharedConfig->config, &m_error);
        if (!configuration) {
            // Existing sessions retain their last supported configuration. A
            // newly created context may select legacy before accepting input.
            // A saved unsupported preference is not a per-keystroke error.
            m_generation = m_sharedConfig->generation;
            reportError(service);
            return;
        }
        std::shared_ptr<NativeCandidateFilter> replacementFilter(new NativeCandidateFilter(
            NativeEncoding(&m_sharedConfig->config),
            service ? service->encodingService() : NULL));
        GuanyinmaSession* replacement = NULL;
        if (!OpenSession(m_modelPath, configuration, replacementFilter, &replacement, &m_error)) {
            reportError(service);
            return;
        }
        std::string keys = SelectionKeys(m_identifier, configuration, m_modelPath, &m_error);
        if (keys.empty()) {
            guanyinma_session_close(&replacement);
            reportError(service);
            return;
        }
        GuanyinmaSession* oldSession = m_session;
        m_session = replacement;
        if (!initialSnapshot(&m_error)) {
            guanyinma_session_close(&m_session);
            m_session = oldSession;
            reportError(service);
            return;
        }
        guanyinma_session_close(&oldSession);
        m_candidateFilter = std::move(replacementFilter);
        [configuration retain];
        [m_configuration release];
        m_configuration = configuration;
        m_selectionKeys = keys;
        m_generation = m_sharedConfig->generation;
    }

    NSDictionary* operationForKey(const OVKey* key)
    {
        NSString* name = nil;
        switch (key->keyCode()) {
            case OVKeyCode::Return: case OVKeyCode::MacEnter: name = @"return"; break;
            case OVKeyCode::Space: name = @"space"; break;
            case OVKeyCode::Backspace: name = @"backspace"; break;
            case OVKeyCode::Delete: name = @"delete"; break;
            case OVKeyCode::Esc: name = @"escape"; break;
            case OVKeyCode::Tab: name = @"tab"; break;
            case OVKeyCode::Left: name = @"left"; break;
            case OVKeyCode::Right: name = @"right"; break;
            case OVKeyCode::Up: name = @"up"; break;
            case OVKeyCode::Down: name = @"down"; break;
            case OVKeyCode::Home: name = @"home"; break;
            case OVKeyCode::End: name = @"end"; break;
            case OVKeyCode::PageUp: name = @"page_up"; break;
            case OVKeyCode::PageDown: name = @"page_down"; break;
            default: break;
        }
        // On macOS OpenVanillaController sets NumLock only for actual keypad
        // virtual keys. It deliberately ignores the global NumericPad mask.
        NSDictionary* modifiers = [NSDictionary dictionaryWithObjectsAndKeys:
            Boolean(key->isShiftPressed()), @"shift", Boolean(key->isCtrlPressed()), @"control",
            Boolean(key->isAltPressed() || key->isOptPressed()), @"alt",
            Boolean(key->isCommandPressed()), @"command", Boolean(key->isCapsLockOn()), @"caps_lock",
            Boolean(false), @"num_lock", Boolean(key->isNumLockOn()), @"keypad", nil];
        if (name) return [NSDictionary dictionaryWithObjectsAndKeys:
            @"key", @"type", name, @"key", modifiers, @"modifiers", nil];
        std::string text = key->receivedString();
        if (text.empty() && key->isKeyCodePrintable()) text.assign(1, static_cast<char>(key->keyCode()));
        if (OVUTF8Helper::SplitStringByCodePoint(text).size() != 1) return nil;
        if (text.size() == 1 && key->keyCode() >= 0x20 && key->keyCode() <= 0x7e &&
            !key->isCombinedFunctionKey() && !key->isNumLockOn() &&
            (key->isCapsLockOn() || (key->isShiftPressed() && key->isKeyCodeAlpha()))) {
            char native = static_cast<char>(key->keyCode());
            if (native >= 'A' && native <= 'Z') native += 'a' - 'A';
            else if (native >= 'a' && native <= 'z') native -= 'a' - 'A';
            if (key->isCapsLockOn() && key->isShiftPressed() && native >= 'a' && native <= 'z')
                native -= 'a' - 'A';
            text.assign(1, native);
        }
        NSString* character = NativeString(text);
        if (!character || ([character length] == 1 && [character characterAtIndex:0] < 0x20))
            return nil;
        return [NSDictionary dictionaryWithObjectsAndKeys:
            @"character", @"type", character, @"text", modifiers, @"modifiers", nil];
    }

    bool syncCandidatePosition(size_t absoluteIndex, bool syncHighlight)
    {
        NSArray* originalCandidates = [[[m_snapshot objectForKey:@"candidates"] copy] autorelease];
        NSArray* originalSpans = [[[m_snapshot objectForKey:@"candidate_spans"] copy] autorelease];
        size_t size = [[m_snapshot objectForKey:@"page_size"] unsignedIntegerValue];
        size_t count = [originalCandidates count];
        if (!size || absoluteIndex >= count) { m_error = "native candidate position is out of range"; return false; }
        size_t currentPage = [[m_snapshot objectForKey:@"page"] unsignedIntegerValue];
        size_t targetPage = absoluteIndex / size;
        if (targetPage != currentPage) {
            long long delta = static_cast<long long>(targetPage) - static_cast<long long>(currentPage);
            if (delta < INT_MIN || delta > INT_MAX) return false;
            if (!apply([NSDictionary dictionaryWithObjectsAndKeys:@"page", @"type",
                [NSNumber numberWithInt:static_cast<int>(delta)], @"delta", nil])) return false;
            if (![originalCandidates isEqual:[m_snapshot objectForKey:@"candidates"]] ||
                ![originalSpans isEqual:[m_snapshot objectForKey:@"candidate_spans"]]) {
                m_error = "candidate view changed; native event was canceled";
                return false;
            }
        }
        if (syncHighlight) {
            size_t currentHighlight = [[m_snapshot objectForKey:@"highlight"] unsignedIntegerValue];
            size_t targetHighlight = absoluteIndex % size;
            if (targetHighlight != currentHighlight &&
                !apply([NSDictionary dictionaryWithObjectsAndKeys:@"move_highlight", @"type",
                    [NSNumber numberWithLongLong:static_cast<long long>(targetHighlight) -
                        static_cast<long long>(currentHighlight)], @"delta", nil])) return false;
            if (![originalCandidates isEqual:[m_snapshot objectForKey:@"candidates"]] ||
                ![originalSpans isEqual:[m_snapshot objectForKey:@"candidate_spans"]]) {
                m_error = "candidate view changed; native event was canceled";
                return false;
            }
        }
        return true;
    }

    bool render(OVTextBuffer* reading, OVTextBuffer* composing, OVCandidateService* candidates,
        OVLoaderService* service, bool emitEffects = true)
    {
        m_ownerCandidateService = candidates;
        NSDictionary* effects = [m_snapshot objectForKey:@"effects"];
        std::string commit = UTF8String([effects objectForKey:@"commit"]);
        // Existing OV output filters and associated phrases see each commit
        // through the same native text-buffer pipeline as Manjusri.
        if (emitEffects && !commit.empty()) composing->commitAsTextSegment(commit);
        std::string readingText = UTF8String([m_snapshot objectForKey:@"reading"]);
        std::string composition = IsSmart(m_identifier) ?
            UTF8String([m_snapshot objectForKey:@"composition"]) : std::string();
        reading->setText(readingText);
        composing->setText(composition);
        size_t cursor = [[m_snapshot objectForKey:@"cursor"] unsignedIntegerValue];
        size_t readingCount = OVUTF8Helper::SplitStringByCodePoint(readingText).size();
        size_t compositionCount = OVUTF8Helper::SplitStringByCodePoint(composition).size();
        composing->setCursorPosition(std::min(compositionCount, cursor >= readingCount ? cursor - readingCount : 0));
        composing->setHighlightMark(OVTextBuffer::RangePair(0, 0));
        composing->clearToolTip();
        id marked = [m_snapshot objectForKey:@"marked_phrase"];
        if (IsSmart(m_identifier) && [marked isKindOfClass:[NSDictionary class]]) {
            size_t start = [[marked objectForKey:@"text_start"] unsignedIntegerValue];
            size_t length = [[marked objectForKey:@"text_length"] unsignedIntegerValue];
            if (start <= compositionCount && length <= compositionCount - start) {
                composing->setHighlightMark(OVTextBuffer::RangePair(start, length));
                composing->showToolTip(MarkedPhraseToolTip(UTF8String([marked objectForKey:@"text"]), service));
            }
        }
        id phraseFeedback = [effects objectForKey:@"phrase_feedback"];
        if (emitEffects && [phraseFeedback isKindOfClass:[NSDictionary class]])
            composing->showToolTip(PhraseFeedbackToolTip(
                UTF8String([phraseFeedback objectForKey:@"text"]),
                [[phraseFeedback objectForKey:@"added"] boolValue], service));
        std::vector<OVTextBuffer::RangePair> segments;
        if (IsSmart(m_identifier)) {
            size_t offset = 0;
            for (NSDictionary* segment in [m_snapshot objectForKey:@"segments"]) {
                size_t length = OVUTF8Helper::SplitStringByCodePoint(UTF8String([segment objectForKey:@"text"])).size();
                if (length) segments.push_back(OVTextBuffer::RangePair(offset, length));
                offset += length;
            }
        }
        composing->setWordSegments(segments);
        reading->updateDisplay();
        composing->updateDisplay();

        OVOneDimensionalCandidatePanel* panel = candidates->useOneDimensionalCandidatePanel();
        NSArray* candidateValues = [m_snapshot objectForKey:@"candidates"];
        m_candidateService = [candidateValues count] ? candidates : NULL;
        m_candidatePanel = [candidateValues count] ? panel : NULL;
        if ([candidateValues count]) {
            std::vector<std::string> values;
            for (NSString* value in candidateValues) values.push_back(UTF8String(value));
            panel->cancelEventHandler();
            panel->candidateList()->setCandidates(values);
            panel->setCandidateKeys(IsTable(m_identifier) ?
                m_selectionKeys.substr(0, [[m_snapshot objectForKey:@"page_size"] unsignedIntegerValue]) :
                m_selectionKeys, service);
            panel->setCandidatesPerPage([[m_snapshot objectForKey:@"page_size"] unsignedIntegerValue]);
            OVKeyVector nextKeys = panel->defaultNextPageKeys();
            OVKeyVector previousKeys = panel->defaultPreviousPageKeys();
            nextKeys.push_back(service->makeOVKey('>', false, false, false, true));
            previousKeys.push_back(service->makeOVKey('<', false, false, false, true));
            // Native table options can reserve Space for first-candidate
            // selection rather than paging a one-page list.
            NSDictionary* tableOptions = [m_configuration objectForKey:MethodName(m_identifier)];
            if (IsTable(m_identifier) &&
                ([[tableOptions objectForKey:@"space_as_first_selection_key"] boolValue] ||
                 [[tableOptions objectForKey:@"space_commits_first_on_single_page"] boolValue]) &&
                [[m_snapshot objectForKey:@"page_count"] unsignedIntegerValue] <= 1) {
                OVKey space = service->makeOVKey(OVKeyCode::Space);
                nextKeys.erase(std::remove(nextKeys.begin(), nextKeys.end(), space), nextKeys.end());
            }
            panel->setNextPageKeys(nextKeys);
            panel->setPreviousPageKeys(previousKeys);
            panel->show();
            panel->yieldToCandidateEventHandler();
            panel->goToPage([[m_snapshot objectForKey:@"page"] unsignedIntegerValue]);
            id highlight = [m_snapshot objectForKey:@"highlight"];
            panel->setHighlightIndex([highlight isKindOfClass:[NSNumber class]] ?
                [highlight unsignedIntegerValue] : 0);
            panel->updateDisplay();
        }
        else {
            panel->hide();
            panel->cancelEventHandler();
            panel->candidateList()->clear();
            panel->updateDisplay();
        }
        if (emitEffects && [[effects objectForKey:@"beep"] boolValue]) service->beep();
        return [[effects objectForKey:@"handled"] boolValue];
    }

    std::string m_identifier;
    std::string m_modelPath;
    std::string m_userDatabasePath;
    std::shared_ptr<ModuleConfiguration> m_sharedConfig;
    size_t m_generation;
    std::shared_ptr<NativeCandidateFilter> m_candidateFilter;
    GuanyinmaSession* m_session;
    NSDictionary* m_configuration;
    NSDictionary* m_snapshot;
    std::string m_selectionKeys;
    std::string m_error;
    OVCandidateService* m_candidateService;
    OVOneDimensionalCandidatePanel* m_candidatePanel;
    OVCandidateService* m_ownerCandidateService;
    bool m_active;
};

static OVEventHandlingContext* CreateContext(const std::string& identifier,
    const std::string& modelPath, const std::string& userDatabasePath,
    std::shared_ptr<ModuleConfiguration> sharedConfig, std::string* error)
{
    if (error) error->clear();
    NSDictionary* configuration = Configuration(identifier, userDatabasePath, &sharedConfig->config, error);
    if (!configuration) return NULL;
    std::string keys = SelectionKeys(identifier, configuration, modelPath, error);
    if (keys.empty()) return NULL;
    std::shared_ptr<NativeCandidateFilter> filter(new NativeCandidateFilter(
        NativeEncoding(&sharedConfig->config)));
    GuanyinmaSession* session = NULL;
    if (!OpenSession(modelPath, configuration, filter, &session, error)) return NULL;
    GuanyinmaContext* context = new GuanyinmaContext(identifier, modelPath, userDatabasePath,
        sharedConfig, session, configuration, keys, std::move(filter));
    if (!context->initialSnapshot(error)) { delete context; return NULL; }
    return context;
}

// Resolve the actual active input context, rather than a saved preference:
// an existing native context may still be finishing input after a core change.
class GuanyinmaAssociatedPhraseQuery : public OVAFAssociatedPhraseQuery {
public:
    explicit GuanyinmaAssociatedPhraseQuery(const std::string& path)
        : m_path(path), m_database(NULL) {}
    virtual ~GuanyinmaAssociatedPhraseQuery() { guanyinma_database_close(&m_database); }
    virtual bool isActive(OVCandidateService* service) const
    {
        for (size_t i = s_contexts.size(); i > 0; --i)
            if (s_contexts[i - 1]->ownsActiveService(service)) return true;
        return false;
    }
    virtual bool lookup(const std::string& head, const std::vector<std::string>& collections,
        std::vector<std::string>& candidates, std::string& error)
    {
        candidates.clear();
        @try {
            if (!m_database && guanyinma_database_open(
                reinterpret_cast<const uint8_t*>(m_path.data()), m_path.size(), &m_database) != GUANYINMA_OK)
                return Reject(&error, LastError());
            NSMutableArray* names = [NSMutableArray arrayWithCapacity:collections.size()];
            for (size_t i = 0; i < collections.size(); ++i) {
                NSString* name = NativeString(collections[i]);
                if (!name) return Reject(&error, "invalid UTF-8 collection name");
                [names addObject:name];
            }
            NSString* key = NativeString(head);
            if (!key) return Reject(&error, "invalid UTF-8 associated phrase head");
            NSDictionary* request = [NSDictionary dictionaryWithObjectsAndKeys:
                key, @"head", names, @"collections", nil];
            NSError* jsonError = nil;
            NSData* bytes = [NSJSONSerialization dataWithJSONObject:request options:0 error:&jsonError];
            if (!bytes) return Reject(&error, UTF8String([jsonError localizedDescription]));
            GuanyinmaResult* result = NULL;
            if (guanyinma_database_associated_phrases(m_database,
                static_cast<const uint8_t*>([bytes bytes]), [bytes length], &result) != GUANYINMA_OK)
                return Reject(&error, LastError());
            NSDictionary* value = ReadResult(result, &error);
            if (!value) return false;
            id rows = [value objectForKey:@"rows"];
            if (![[value objectForKey:@"schema_version"] isEqual:@1] ||
                ![[value objectForKey:@"kind"] isEqual:@"associated_phrases"] ||
                ![[value objectForKey:@"key"] isEqual:key] || ![rows isKindOfClass:[NSArray class]])
                return Reject(&error, "invalid associated phrase result");
            std::vector<std::string> next;
            for (id row in rows) {
                if (![row isKindOfClass:[NSString class]])
                    return Reject(&error, "invalid associated phrase row");
                next.push_back(UTF8String(row));
            }
            candidates.swap(next);
            return true;
        }
        @catch (NSException* exception) { return Reject(&error, UTF8String([exception reason])); }
    }
private:
    const std::string m_path;
    GuanyinmaDatabase* m_database;
};

class GuanyinmaModule : public OVModule {
public:
    GuanyinmaModule(OVModule* legacy, const std::string& modelPath, const std::string& userPath,
        std::shared_ptr<GuanyinmaCoreSelection> selection = {})
        : m_legacy(legacy), m_modelPath(modelPath), m_userPath(userPath),
          m_config(new ModuleConfiguration(NULL)), m_service(NULL), m_usesCore(false),
          m_selection(std::move(selection)), m_legacyConfigGeneration(0) {}
    virtual ~GuanyinmaModule() { delete m_legacy; }
    virtual const std::string identifier() const { return m_legacy->identifier(); }
    virtual const std::string localizedName(const std::string& locale) { return m_legacy->localizedName(locale); }
    virtual bool isPreprocessor() const { return m_legacy->isPreprocessor(); }
    virtual bool isInputMethod() const { return m_legacy->isInputMethod(); }
    virtual bool isOutputFilter() const { return m_legacy->isOutputFilter(); }
    virtual bool isAroundFilter() const { return m_legacy->isAroundFilter(); }
    virtual int suggestedOrder() const { return m_legacy->suggestedOrder(); }
    virtual AroundFilterDisplayOption aroundFilterPreferredDisplayOption()
        { return m_legacy->aroundFilterPreferredDisplayOption(); }
    virtual bool initialize(OVPathInfo* path, OVLoaderService* service)
    {
        m_path = *path;
        m_service = service;
        // Do not initialize the legacy Smart module here: it opens native user
        // databases. Its initialized package already supplied readonly metadata.
        return true;
    }
    virtual void finalize()
    {
        if (m_legacy->isInitialized()) m_legacy->finalize();
    }
    virtual void loadConfig(OVKeyValueMap* config, OVLoaderService* service)
    {
        m_config->capture(config);
        ++m_config->generation;
        bool needsLegacy = m_selection ?
            GuanyinmaCoreSelectionStatus(m_selection, identifier()).nativeCount > 0 :
            (!m_usesCore && !ValidateConfiguration(identifier(), config, NULL));
        if (needsLegacy && m_legacy->isInitialized() && m_legacy->isUsable()) {
            m_legacy->loadConfig(config, service);
            m_legacyConfigGeneration = m_config->generation;
        }
    }
    virtual void saveConfig(OVKeyValueMap* config, OVLoaderService* service)
    {
        // Guanyinma reads the native preferences without rewriting them or
        // opening any legacy learning store. Legacy fallback keeps its API.
        bool needsLegacy = m_selection ?
            GuanyinmaCoreSelectionStatus(m_selection, identifier()).nativeCount > 0 : !m_usesCore;
        if (needsLegacy && m_legacy->isInitialized() && m_legacy->isUsable())
            m_legacy->saveConfig(config, service);
    }
    virtual OVEventHandlingContext* createContext()
    {
        if (m_selection) {
            return GuanyinmaCreateSwitchingContext(identifier(), m_selection,
                [this](bool requested) { return createDelegate(requested); },
                [this]() { return static_cast<std::uint64_t>(m_config->generation); });
        }
        GuanyinmaCoreDelegate result = createDelegate(true);
        return result.context ? result.context : new OVEventHandlingContext;
    }

    GuanyinmaCoreDelegate createDelegate(bool requested)
    {
        std::string error;
        if (requested) {
            OVEventHandlingContext* context = CreateContext(identifier(), m_modelPath,
                m_userPath, m_config, &error);
            if (context) {
                m_usesCore = true;
                return {context, true, {}};
            }
            if (m_service)
                m_service->logger("Guanyinma") << identifier() << ": " << error
                    << "; using legacy core before session creation" << std::endl;
        }
        if (!m_legacy->isInitialized()) {
            if (!m_service || !m_legacy->moduleInitialize(&m_path, m_service))
                return {NULL, false, error.empty() ? "The legacy core could not be initialized" : error};
        }
        if (!m_legacy->isUsable())
            return {NULL, false, error.empty() ? "The legacy core is unavailable" : error};
        // This delegate has selected the original core. Its own configuration
        // and user store retain the existing native initialization behavior.
        // Reusing the original core after a failed Rust request must not flush
        // its in-memory learned choices before the current session saves them.
        if (m_legacyConfigGeneration != m_config->generation) {
            m_legacy->loadConfig(&m_config->config, m_service);
            m_legacyConfigGeneration = m_config->generation;
        }
        OVEventHandlingContext* context = m_legacy->createContext();
        if (context) m_usesCore = false;
        return {context, false, context ? error : "The legacy input context is unavailable"};
    }
    bool usesCore() const { return m_usesCore; }

private:
    OVModule* m_legacy;
    std::string m_modelPath;
    std::string m_userPath;
    std::shared_ptr<ModuleConfiguration> m_config;
    OVPathInfo m_path;
    OVLoaderService* m_service;
    bool m_usesCore;
    std::shared_ptr<GuanyinmaCoreSelection> m_selection;
    std::size_t m_legacyConfigGeneration;
};

class GuanyinmaPackage : public OVModulePackage {
public:
    GuanyinmaPackage(OVModulePackage* legacy, const std::string& modelPath,
        const std::string& userPath, std::shared_ptr<GuanyinmaCoreSelection> selection = {})
        : m_legacy(legacy), m_modelPath(modelPath), m_userPath(userPath),
          m_selection(std::move(selection)) {}
    virtual ~GuanyinmaPackage() { delete m_legacy; }
    virtual size_t numberOfModules(OVLoaderService* service)
        { return m_legacy ? m_legacy->numberOfModules(service) : 0; }
    virtual OVModule* moduleAtIndex(size_t index, OVLoaderService* service)
    {
        if (!m_legacy) return NULL;
        OVModule* module = m_legacy->moduleAtIndex(index, service);
        OVAFAssociatedPhrase* associated = dynamic_cast<OVAFAssociatedPhrase*>(module);
        if (associated) {
            associated->setQueryProvider(std::shared_ptr<OVAFAssociatedPhraseQuery>(
                new GuanyinmaAssociatedPhraseQuery(m_modelPath)));
            return module;
        }
        if (!module || !GuanyinmaSupportsInputMethod(module->identifier())) return module;
        return new GuanyinmaModule(module, m_modelPath, m_userPath, m_selection);
    }
    virtual void finalize()
    {
        if (!m_legacy) return;
        m_legacy->finalize();
        delete m_legacy;
        m_legacy = NULL;
    }
private:
    OVModulePackage* m_legacy;
    std::string m_modelPath;
    std::string m_userPath;
    std::shared_ptr<GuanyinmaCoreSelection> m_selection;
};

} // namespace

bool GuanyinmaCanUseInputMethod(const std::string& identifier, OVKeyValueMap* config,
    std::string* error)
{
    return ValidateConfiguration(identifier, config, error);
}

bool GuanyinmaModuleUsesCore(const OVModule* module)
{
    const GuanyinmaModule* wrapped = dynamic_cast<const GuanyinmaModule*>(module);
    return wrapped && wrapped->usesCore();
}

OVEventHandlingContext* GuanyinmaCreateInputContext(const std::string& identifier,
    const std::string& modelPath, const std::string& userDatabasePath,
    OVKeyValueMap* moduleConfig, std::string* error)
{
    return CreateContext(identifier, modelPath, userDatabasePath,
        std::shared_ptr<ModuleConfiguration>(new ModuleConfiguration(moduleConfig)), error);
}

bool GuanyinmaPrepareCandidatePanelForKey(const OVKey* key, OVCandidateService* candidateService)
{
    for (size_t i = 0; i < s_contexts.size(); ++i)
        if (s_contexts[i]->prepareKeypadEvent(key, candidateService)) return true;
    return false;
}

bool GuanyinmaSetEnglishModeForService(OVCandidateService* candidateService,
    bool enabled, std::string* error)
{
    if (error) error->clear();
    for (size_t i = s_contexts.size(); i > 0; --i)
        if (s_contexts[i - 1]->ownsActiveService(candidateService))
            return s_contexts[i - 1]->setEnglishMode(enabled, error);
    return true;
}

OVModulePackage* GuanyinmaWrapModulePackage(OVModulePackage* initializedPackage,
    const std::string& modelPath, const std::string& userDatabasePath, bool enabled)
{
    return enabled && initializedPackage ?
        new GuanyinmaPackage(initializedPackage, modelPath, userDatabasePath) : initializedPackage;
}

OVModulePackage* GuanyinmaWrapModulePackage(OVModulePackage* initializedPackage,
    const std::string& modelPath, const std::string& userDatabasePath,
    const std::shared_ptr<GuanyinmaCoreSelection>& selection)
{
    return initializedPackage && selection ?
        new GuanyinmaPackage(initializedPackage, modelPath, userDatabasePath, selection) : initializedPackage;
}

#else

bool GuanyinmaCanUseInputMethod(const std::string&, OpenVanilla::OVKeyValueMap*,
    std::string* error)
{
    if (error) *error = "Guanyinma is not enabled in this build";
    return false;
}

bool GuanyinmaModuleUsesCore(const OpenVanilla::OVModule*) { return false; }

OpenVanilla::OVEventHandlingContext* GuanyinmaCreateInputContext(const std::string&,
    const std::string&, const std::string&, OpenVanilla::OVKeyValueMap*, std::string* error)
{
    if (error) *error = "Guanyinma is not enabled in this build";
    return NULL;
}

bool GuanyinmaPrepareCandidatePanelForKey(const OpenVanilla::OVKey*,
    OpenVanilla::OVCandidateService*)
{
    return false;
}

bool GuanyinmaSetEnglishModeForService(OpenVanilla::OVCandidateService*,
    bool, std::string* error)
{
    if (error) error->clear();
    return true;
}

OpenVanilla::OVModulePackage* GuanyinmaWrapModulePackage(
    OpenVanilla::OVModulePackage* initializedPackage, const std::string&,
    const std::string&, bool)
{
    return initializedPackage;
}

OpenVanilla::OVModulePackage* GuanyinmaWrapModulePackage(
    OpenVanilla::OVModulePackage* initializedPackage, const std::string&,
    const std::string&, const std::shared_ptr<GuanyinmaCoreSelection>&)
{
    return initializedPackage;
}

#endif

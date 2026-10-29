#include "FrontendSettings.h"

#include <ShlObj.h>
#include <ShellScalingApi.h>
#include <algorithm>

#include <cstdlib>
#include <fstream>
#include <iterator>
#include <filesystem>
#include <sstream>
#include <memory>
#include <chrono>
#include <charconv>
#include <map>
#include <vector>
#include "PVPropertyList.h"
#include "InputMethods.h"
#include "SharedFileAccess.h"

namespace KeyKey::WindowsTsf {
namespace {

std::string ReadFile(const std::wstring& path) {
    std::string result; ReadSharedSettingsFile(path,result); return result;
}

std::string PlistString(const std::string& xml, const std::string& key,
                        const std::string& defaultValue) {
    const std::string keyTag = "<key>" + key + "</key>";
    size_t position = xml.find(keyTag);
    if (position == std::string::npos) return defaultValue;
    position = xml.find("<string>", position + keyTag.size());
    if (position == std::string::npos) return defaultValue;
    position += 8;
    const size_t end = xml.find("</string>", position);
    return end == std::string::npos ? defaultValue
                                    : xml.substr(position, end - position);
}

bool PlistBool(const std::string& xml, const std::string& key,
               bool defaultValue) {
    const std::string value =
        PlistString(xml, key, defaultValue ? "true" : "false");
    return value == "true" || value == "1" || value == "YES";
}

int CandidateScalePercent(const std::string& value) {
    char* end = nullptr;
    const long parsed = std::strtol(value.c_str(), &end, 10);
    if (!end || end == value.c_str() || *end != '\0') return 0;
    constexpr int allowed[] = {75, 90, 100, 125, 150, 175,
                               200, 225, 250, 300, 350};
    for (const int percent : allowed) {
        if (parsed == percent) return percent;
    }
    return 0;
}

std::wstring Utf8ToWide(const std::string& text) {
    if (text.empty()) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS,
                                            text.data(),
                                            static_cast<int>(text.size()),
                                            nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                        static_cast<int>(text.size()), result.data(), length);
    return result;
}

bool UsableProfileDirectory(const std::wstring& directory) {
    if (directory.empty()) return false;
    if (!CreateDirectoryW(directory.c_str(), nullptr) && GetLastError() != ERROR_ALREADY_EXISTS)
        return false;
    // AppContainer may see a Roaming directory's attributes while being
    // unable to list or write its files. Probe directory access without
    // creating a disposable file or broadening any ACL.
    HANDLE handle = CreateFileW(directory.c_str(), FILE_LIST_DIRECTORY | FILE_ADD_FILE,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
        OPEN_EXISTING, FILE_FLAG_BACKUP_SEMANTICS, nullptr);
    if (handle == INVALID_HANDLE_VALUE) return false;
    CloseHandle(handle);
    return true;
}

std::wstring ProductionSettingsDirectory() {
    wchar_t roaming[MAX_PATH]{};
    if (SUCCEEDED(SHGetFolderPathW(nullptr, CSIDL_APPDATA | CSIDL_FLAG_CREATE,
                                  nullptr, SHGFP_TYPE_CURRENT, roaming))) {
        const std::wstring directory = std::wstring(roaming) + L"\\chichi77 KeyKey";
        if (UsableProfileDirectory(directory)) return directory;
    }
    // Search/Store processes have their own writable, sandboxed Temp path.
    // Keep their preferences and learning there when Roaming is unavailable.
    wchar_t temporary[32768]{};
    const DWORD length = GetTempPathW(static_cast<DWORD>(std::size(temporary)), temporary);
    if (!length || length >= std::size(temporary)) return {};
    const std::wstring directory = std::wstring(temporary) + L"chichi77 KeyKey";
    return UsableProfileDirectory(directory) ? directory : std::wstring();
}

}  // namespace

std::wstring SettingsDirectory() {
    std::wstring testDirectory(32768, L'\0');
    const DWORD length = GetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",
        testDirectory.data(), static_cast<DWORD>(testDirectory.size()));
    if (length && length < testDirectory.size()) {
        testDirectory.resize(length);
        CreateDirectoryW(testDirectory.c_str(), nullptr);
        return testDirectory;
    }
    static const std::wstring directory = ProductionSettingsDirectory();
    return directory;
}
std::string LoadInputMethodPreference(const std::string& fallback) {
    return PlistString(ReadFile(SettingsDirectory()+L"\\com.polobread.chichi77-keykey.windows.plist"),
                       "PrimaryInputMethod",fallback);
}

void MigrateLegacyPreferences() {
    const std::wstring directory = SettingsDirectory();
    if (directory.empty()) return;
    constexpr const wchar_t* suffixes[] = {
        L"", L".TraditionalMandarin", L".SmartMandarin",
        L".AssociatedPhrase", L".Generic-cj-cin", L".Generic-simplex-cin"};
    for (const wchar_t* suffix : suffixes) {
        const std::wstring current = directory +
            L"\\com.polobread.chichi77-keykey.windows" + suffix + L".plist";
        const std::wstring legacy = directory +
            L"\\org.openvanilla.chichi77-keykey.windows" + suffix + L".plist";
        // Keep the old file for text hosts still using the previous DLL.
        SettingsFileLock guard(current);
        if (!guard || GetFileAttributesW(current.c_str())!=INVALID_FILE_ATTRIBUTES) continue;
        std::string source;
        if (!ReadSharedSettingsFile(legacy,source)) continue;
        std::unique_ptr<OpenVanilla::PVPlistValue> parsed(OpenVanilla::PVPropertyList::ParsePlistFromString(source.c_str()));
        if (parsed && parsed->type()==OpenVanilla::PVPlistValue::Dictionary) WriteSharedSettingsFile(current,source);
    }
}

std::wstring LoaderPreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\com.polobread.chichi77-keykey.windows.plist";
}

std::wstring TraditionalMandarinPreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\com.polobread.chichi77-keykey.windows."
                     L"TraditionalMandarin.plist";
}

std::wstring SmartMandarinPreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\com.polobread.chichi77-keykey.windows."
                     L"SmartMandarin.plist";
}

std::wstring AssociatedPhrasePreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\com.polobread.chichi77-keykey.windows."
                     L"AssociatedPhrase.plist";
}

FrontendSettings LoadFrontendSettings() {
    FrontendSettings settings;
    const std::string xml = ReadFile(LoaderPreferencesPath());
    settings.candidateLayout =
        PlistString(xml, "OneDimensionalCandidatePanelStyle", "vertical") ==
                "horizontal"
            ? CandidateLayout::Horizontal
            : CandidateLayout::Vertical;
    settings.candidateScalePercent = CandidateScalePercent(
        PlistString(xml, "CandidateWindowScalePercent", "system"));
    settings.highlightColor =
        Utf8ToWide(PlistString(xml, "HighlightColor", "Default"));
    settings.toggleWithControlBackslash = PlistBool(
        xml, "ToggleInputMethodWithControlBackslash", true);
    settings.symbolPanelShortcutEnabled = PlistBool(xml, "SymbolPanelShortcutEnabled", true);
    settings.ignoreCapsLockInChinese = PlistBool(xml, "IgnoreCapsLockInChinese", true);
    settings.playSoundOnTypingError =
        PlistBool(xml, "ShouldPlaySoundOnTypingError", true);
    settings.simplifiedChineseOutput = PlistBool(xml, "SimplifiedChineseOutput", false);
    // Only an explicit English preference changes the backward-compatible default.
    settings.defaultChineseMode = PlistString(xml, "DefaultInputMode", "Chinese") != "English";
    return settings;
}

UINT ContentDpiForScale(UINT hostDpi, HMONITOR monitor, int scalePercent) {
    if (scalePercent <= 0) return hostDpi;
    DEVICE_SCALE_FACTOR monitorScale = SCALE_100_PERCENT;
    if (FAILED(GetScaleFactorForMonitor(monitor, &monitorScale)) || monitorScale <= 0)
        monitorScale = SCALE_100_PERCENT;
    return static_cast<UINT>(std::max(1, MulDiv(static_cast<int>(hostDpi), scalePercent,
        static_cast<int>(monitorScale))));
}

bool DiagnosticSession::activeAt(std::int64_t now) const {
    constexpr std::int64_t duration = 3 * 24 * 60 * 60;
    return startedAt > 0 && expiresAt > startedAt &&
           expiresAt - startedAt == duration && now >= startedAt && now < expiresAt;
}

std::wstring DiagnosticSettingsPath() {
    const auto directory = SettingsDirectory();
    return directory.empty() ? std::wstring() : directory + L"\\diagnostics.plist";
}

DiagnosticSession LoadDiagnosticSession() {
    // Separate from loader preferences so module config saves cannot renew or
    // overwrite the diagnostic deadline. Missing/invalid settings stay off.
    const auto path = DiagnosticSettingsPath();
    std::error_code error;
    if (path.empty() || std::filesystem::file_size(path, error) > 16384 || error) return {};
    const auto xml = ReadFile(path);
    std::unique_ptr<OpenVanilla::PVPlistValue> dictionary(
        OpenVanilla::PVPropertyList::ParsePlistFromString(xml.c_str()));
    if (!dictionary || dictionary->type() != OpenVanilla::PVPlistValue::Dictionary) return {};
    const auto number = [&](const char* key) {
        const auto text = dictionary->stringValueForKey(key);
        std::int64_t value = 0;
        const auto parsed = std::from_chars(text.data(), text.data() + text.size(), value);
        return parsed.ec == std::errc() && parsed.ptr == text.data() + text.size() ? value : 0;
    };
    return {number("StartedAtUtc"), number("ExpiresAtUtc")};
}

std::string SmartMandarinSettingsSignature() {
    const auto xml = ReadFile(SmartMandarinPreferencesPath());
    std::string signature;
    for (const auto* key : {"KeyboardLayout", "CandidateSelectionKeys",
            "CandidateCursorAtEndOfTargetBlock", "ShowCandidateListWithSpace",
            "ComposingTextBufferSize", "ClearComposingTextWithEsc",
            "ClearComposingTextWithEscUserChoice", "UseCharactersSupportedByEncoding"}) {
        signature += std::string(key) + "=" + PlistString(xml, key, "") + "\n";
    }
    return signature;
}

bool SaveSimplifiedOutputPreference(bool enabled) {
    const auto path = LoaderPreferencesPath();
    if (path.empty()) return false;
    SettingsFileLock guard(path);
    if (!guard) return false;
    std::error_code error;
    const bool existing = std::filesystem::exists(path, error);
    if (error) return false;
    const auto source = ReadFile(path);
    if (existing && source.empty()) return false;
    std::unique_ptr<OpenVanilla::PVPlistValue> dictionary(source.empty()
        ? new OpenVanilla::PVPlistValue(OpenVanilla::PVPlistValue::Dictionary)
        : OpenVanilla::PVPropertyList::ParsePlistFromString(source.c_str()));
    if (!dictionary || dictionary->type() != OpenVanilla::PVPlistValue::Dictionary) return false;
    dictionary->setKeyValue("SimplifiedChineseOutput", enabled ? "true" : "false");
    std::ostringstream serialized;
    serialized << "<plist version=\"1.0\">" << *dictionary << "</plist>";
    const auto xml = serialized.str();
    return WriteSharedSettingsFile(path,xml);
}

bool IsInputMethodVisible(const char* identifier) {
    const std::string xml = ReadFile(LoaderPreferencesPath());
    constexpr char key[] = "<key>ModulesSuppressedFromUI</key>";
    const size_t keyStart = xml.find(key);
    if (keyStart == std::string::npos) return true;
    const size_t nextTag = xml.find('<', keyStart + sizeof(key) - 1);
    if (nextTag == std::string::npos || xml.compare(nextTag, 7, "<array>") != 0)
        return true;
    const size_t end = xml.find("</array>", nextTag);
    if (end == std::string::npos) return true;
    const std::string entry = std::string("<string>") + identifier + "</string>";
    const size_t found = xml.find(entry, nextTag + 7);
    return found == std::string::npos || found >= end;
}

namespace {
std::wstring TablePreferencesPath(bool simplex) {
    const auto directory = SettingsDirectory();
    return directory.empty() ? std::wstring() : directory +
        (simplex ? L"\\com.polobread.chichi77-keykey.windows.Generic-simplex-cin.plist" :
                   L"\\com.polobread.chichi77-keykey.windows.Generic-cj-cin.plist");
}

bool PrivateTableProfile() {
    // Test profiles model the private settings directory of a restricted host.
    if (GetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", nullptr, 0)) return true;
    static const bool privateProfile = [] {
        wchar_t roaming[MAX_PATH]{};
        if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA | CSIDL_FLAG_CREATE,
                nullptr, SHGFP_TYPE_CURRENT, roaming))) return true;
        const auto sharedDirectory = std::wstring(roaming) + L"\\chichi77 KeyKey";
        return _wcsicmp(SettingsDirectory().c_str(), sharedDirectory.c_str()) != 0;
    }();
    return privateProfile;
}
}

TablePreviewSettings LoadTablePreviewSettings(bool simplex) {
    const auto xml = ReadFile(TablePreferencesPath(simplex));
    TablePreviewSettings settings;
    settings.composeWhileTyping = PlistBool(xml, "ComposeWhileTyping", false);
    if (!PlistBool(xml, "ComposeWhenTypingMigrated", false) &&
        xml.find("<key>ComposeWhenTyping</key>") != std::string::npos)
        settings.composeWhileTyping = PlistBool(xml, "ComposeWhenTyping", false);
    settings.prefixCandidates = !simplex && PlistBool(xml, "PrefixCandidates", false);
    settings.clearOnError = !settings.composeWhileTyping &&
        PlistBool(xml, "ClearReadingBufferAtCompositionError", true);
    return settings;
}

bool SyncTablePreviewSettings(SharedTableSettings& shared, TfClientId client, bool immersive, bool simplex) {
    const auto local = LoadTablePreviewSettings(simplex);
    const auto published = shared.read();
    // Some immersive hosts can use the actual desktop profile. Its saved file
    // remains authoritative, including the interval between WPF save/publish.
    if (!immersive || !PrivateTableProfile()) {
        return (published && published->encoded() == local.encoded()) ||
            SUCCEEDED(shared.write(client, local));
    }
    // Until a desktop host/settings app has published, retain the private
    // profile. Restricted hosts must never publish stale defaults back.
    if (!published || published->encoded() == local.encoded()) return true;
    const auto path = TablePreferencesPath(simplex);
    if (path.empty()) return false;
    SettingsFileLock guard(path);
    if (!guard) return false;
    std::error_code error;
    const bool existing = std::filesystem::exists(path, error);
    if (error) return false;
    const auto source = ReadFile(path);
    if (existing && source.empty()) return false;
    std::unique_ptr<OpenVanilla::PVPlistValue> dictionary(source.empty()
        ? new OpenVanilla::PVPlistValue(OpenVanilla::PVPlistValue::Dictionary)
        : OpenVanilla::PVPropertyList::ParsePlistFromString(source.c_str()));
    if (!dictionary || dictionary->type() != OpenVanilla::PVPlistValue::Dictionary) return false;
    dictionary->setKeyValue("ComposeWhileTyping", published->composeWhileTyping ? "true" : "false");
    if (!simplex)
        dictionary->setKeyValue("PrefixCandidates", published->prefixCandidates ? "true" : "false");
    dictionary->setKeyValue("ClearReadingBufferAtCompositionError", published->clearOnError ? "true" : "false");
    dictionary->setKeyValue("ComposeWhenTypingMigrated", "true");
    std::ostringstream serialized;
    serialized << "<plist version=\"1.0\">" << *dictionary << "</plist>";
    // The existing engine settings signature detects this change and applies
    // it through the ordered composition-commit boundary.
    return WriteSharedSettingsFile(path, serialized.str());
}

namespace {
using Plist = OpenVanilla::PVPlistValue;
struct SharedPreference {
    const char* module;
    const char* key;
    const char* fallback;
    bool boolean = false;
    unsigned version = 1;
    std::string id() const { return std::string(module) + "." + key; }
};
// Only settings exposed by the Windows input UI. Live method/output/startup
// modes and table preview flags use their existing dedicated compartments.
const SharedPreference sharedPreferences[] = {
    {"Loader", "OneDimensionalCandidatePanelStyle", "vertical"},
    {"Loader", "CandidateWindowScalePercent", "system"},
    {"Loader", "HighlightColor", "Default"},
    {"Loader", "ToggleInputMethodWithControlBackslash", "true", true},
    {"Loader", "SymbolPanelShortcutEnabled", "true", true},
    {"Loader", "ShouldPlaySoundOnTypingError", "true", true},
    {"TraditionalMandarin", "KeyboardLayout", "Standard"},
    {"TraditionalMandarin", "UseCharactersSupportedByEncoding", ""},
    {"SmartMandarin", "KeyboardLayout", "Standard"},
    {"SmartMandarin", "UseCharactersSupportedByEncoding", ""},
    {"SmartMandarin", "ShowCandidateListWithSpace", "false", true},
    {"SmartMandarin", "CandidateCursorAtEndOfTargetBlock", "false", true},
    {"SmartMandarin", "CandidateSelectionKeys", ""},
    {"SmartMandarin", "ComposingTextBufferSize", "10"},
    {"SmartMandarin", "ClearComposingTextWithEscUserChoice", "false", true},
    {"SmartMandarin", "ClearComposingTextWithEsc", "false", true},
    {"Generic-cj-cin", "ShouldCommitAtMaximumRadicalLength", "false", true},
    {"Generic-cj-cin", "UseDynamicFrequency", "false", true},
    {"Generic-cj-cin", "UseCharactersSupportedByEncoding", ""},
    {"Generic-cj-cin", "UseOverrideTable", ""},
    {"Generic-simplex-cin", "ShouldCommitAtMaximumRadicalLength", "true", true},
    {"Generic-simplex-cin", "UseCharactersSupportedByEncoding", ""},
    {"AssociatedPhrase", "EnabledCollections", "McBopomofo"},
    {"Loader", "IgnoreCapsLockInChinese", "true", true, 2},
};

std::wstring PreferenceFile(const std::string& module) {
    const auto directory = SettingsDirectory();
    if (directory.empty()) return {};
    const auto suffix = module == "Loader" ? std::string() : "." + module;
    return directory + L"\\com.polobread.chichi77-keykey.windows" +
        Utf8ToWide(suffix) + L".plist";
}

std::unique_ptr<Plist> ReadPreferenceDictionary(const std::wstring& path) {
    std::error_code error;
    const bool existing = std::filesystem::exists(path, error);
    if (error) return {};
    std::string source;
    if (existing && !ReadSharedSettingsFile(path, source)) return {};
    std::unique_ptr<Plist> value(existing
        ? OpenVanilla::PVPropertyList::ParsePlistFromString(source.c_str())
        : new Plist(Plist::Dictionary));
    if (!value || value->type() != Plist::Dictionary) return {};
    return value;
}

std::string SerializePreferences(Plist& value) {
    std::ostringstream stream;
    stream << "<plist version=\"1.0\">" << value << "</plist>";
    return stream.str();
}

std::unique_ptr<Plist> ParseRuntimeSnapshot(const std::wstring& source) {
    if (source.empty() || source.size() > SharedRuntimePreferences::maximumLength ||
        source.find(L'\0') != std::wstring::npos) return {};
    const auto utf8 = OpenVanilla::OVUTF8::FromUTF16(source);
    const unsigned version = utf8.compare(0, 3, "v3;") == 0 ? 3 : utf8.compare(0, 3, "v2;") == 0 ? 2
        : utf8.compare(0, 3, "v1;") == 0 ? 1 : 0;
    if (!version) return {};
    size_t offset = 3;
    auto snapshot = std::make_unique<Plist>(Plist::Dictionary);
    const auto readValue = [&](const std::string& key) {
        const auto colon = utf8.find(':', offset);
        if (colon == std::string::npos || colon == offset || colon - offset > 4) return false;
        size_t size = 0;
        const auto parsed = std::from_chars(utf8.data() + offset, utf8.data() + colon, size);
        if (parsed.ec != std::errc() || parsed.ptr != utf8.data() + colon || size > 4096 ||
            size > utf8.size() - colon - 1) return false;
        snapshot->setKeyValue(key, utf8.substr(colon + 1, size));
        offset = colon + 1 + size;
        return true;
    };
    for (const auto& setting : sharedPreferences) {
        // Older publishers have no Caps Lock preference; adopt the Windows
        // default without shifting the positional fields in their v1 snapshot.
        if (setting.version > version) {
            snapshot->setKeyValue(setting.id(), setting.fallback);
            continue;
        }
        if (!readValue(setting.id())) return {};
        auto* value = snapshot->valueForKey(setting.id());
        if (!value || value->type() != Plist::String || value->stringValue().size() > 4096) return {};
        if (setting.boolean && value->stringValue() != "true" && value->stringValue() != "false") return {};
    }
    // v3 publishers inserted a core selector before visibility. Consume it for
    // wire compatibility, but it cannot affect this Guanyinma-only frontend.
    if (version == 3 && !readValue("Retired.InputCore")) return {};
    bool anyVisible = false;
    for (const auto& method : kInputMethods) {
        const auto key = std::string("Visible.") + method.identifier;
        if (!readValue(key)) return {};
        auto* value = snapshot->valueForKey(key);
        if (!value || value->type() != Plist::String ||
            (value->stringValue() != "true" && value->stringValue() != "false")) return {};
        anyVisible |= value->stringValue() == "true";
    }
    if (offset != utf8.size() || !anyVisible) return {};
    return snapshot;
}

std::wstring EncodeRuntimeSnapshot(Plist& snapshot) {
    std::string result = "v2;";
    const auto append = [&](const std::string& key) {
        const auto value = snapshot.stringValueForKey(key);
        result += std::to_string(value.size()) + ":" + value;
    };
    for (const auto& setting : sharedPreferences) append(setting.id());
    for (const auto& method : kInputMethods) append(std::string("Visible.") + method.identifier);
    return Utf8ToWide(result);
}
}

std::wstring RuntimePreferencesSnapshot() {
    std::map<std::string, std::unique_ptr<Plist>> files;
    Plist snapshot(Plist::Dictionary);
    snapshot.setKeyValue("Version", "1");
    for (const auto& setting : sharedPreferences) {
        auto& file = files[setting.module];
        if (!file) file = ReadPreferenceDictionary(PreferenceFile(setting.module));
        if (!file) return {};
        auto* stored = file->valueForKey(setting.key);
        std::string value = stored && stored->type() == Plist::String
            ? stored->stringValue() : setting.fallback;
        if (setting.boolean) value = (value == "true" || value == "1" || value == "YES") ? "true" : "false";
        snapshot.setKeyValue(setting.id(), value);
    }
    for (const auto& method : kInputMethods)
        snapshot.setKeyValue(std::string("Visible.") + method.identifier,
            IsInputMethodVisible(method.identifier) ? "true" : "false");
    const auto result = EncodeRuntimeSnapshot(snapshot);
    return ParseRuntimeSnapshot(result) ? result : std::wstring();
}

bool SyncRuntimePreferences(SharedRuntimePreferences& shared, TfClientId client, bool immersive) {
    const auto remote = shared.read();
    if (!immersive || !PrivateTableProfile()) {
        const auto local = RuntimePreferencesSnapshot();
        return !local.empty() && ((remote && *remote == local) || SUCCEEDED(shared.write(client, local)));
    }
    if (!remote || shared.alreadyApplied(*remote)) return true;
    auto snapshot = ParseRuntimeSnapshot(*remote);
    if (!snapshot) return false;
    std::map<std::string, std::unique_ptr<Plist>> files;
    std::vector<std::unique_ptr<SettingsFileLock>> locks;
    for (const auto& setting : sharedPreferences) {
        auto& file = files[setting.module];
        if (!file) {
            const auto path = PreferenceFile(setting.module);
            locks.push_back(std::make_unique<SettingsFileLock>(path));
            if (!*locks.back()) return false;
            file = ReadPreferenceDictionary(path);
            if (!file) return false;
        }
        file->setKeyValue(setting.key, snapshot->stringValueForKey(setting.id()));
    }
    auto* loader = files["Loader"].get();
    Plist suppressed(Plist::Array);
    // Preserve suppression entries belonging to modules outside our four modes.
    auto* previous = loader->valueForKey("ModulesSuppressedFromUI");
    if (previous && previous->type() == Plist::Array) {
        for (size_t i = 0; i < previous->arraySize(); ++i) {
            auto* value = previous->arrayElementAtIndex(i);
            if (value && value->type() == Plist::String && !FindInputMethod(value->stringValue().c_str()))
                suppressed.addArrayElement(value);
        }
    }
    for (const auto& method : kInputMethods) {
        if (snapshot->stringValueForKey(std::string("Visible.") + method.identifier) == "false") {
            Plist value(method.identifier);
            suppressed.addArrayElement(&value);
        }
    }
    loader->setKeyValue("ModulesSuppressedFromUI", &suppressed);
    for (const auto& file : files) {
        const auto path = PreferenceFile(file.first);
        const auto xml = SerializePreferences(*file.second);
        if (ReadFile(path) != xml && !WriteSharedSettingsFile(path, xml)) return false;
    }
    shared.applied(*remote);
    return true;
}

COLORREF HighlightColorValue(const std::wstring& name) {
    if (name == L"Green") return RGB(59, 173, 31);
    if (name == L"Yellow") return RGB(235, 181, 0);
    if (name == L"Red") return RGB(191, 0, 41);
    return RGB(128, 0, 128);
}

}  // namespace KeyKey::WindowsTsf

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
#include "PVPropertyList.h"
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

COLORREF HighlightColorValue(const std::wstring& name) {
    if (name == L"Green") return RGB(59, 173, 31);
    if (name == L"Yellow") return RGB(235, 181, 0);
    if (name == L"Red") return RGB(191, 0, 41);
    return RGB(128, 0, 128);
}

}  // namespace KeyKey::WindowsTsf

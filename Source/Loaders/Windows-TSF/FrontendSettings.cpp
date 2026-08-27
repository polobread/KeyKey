#include "FrontendSettings.h"

#include <ShlObj.h>

#include <cstdlib>
#include <fstream>
#include <iterator>

namespace KeyKey::WindowsTsf {
namespace {

std::string ReadFile(const std::wstring& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) return {};
    return std::string(std::istreambuf_iterator<char>(input),
                       std::istreambuf_iterator<char>());
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

}  // namespace

std::wstring SettingsDirectory() {
    wchar_t roaming[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA | CSIDL_FLAG_CREATE,
                                nullptr, SHGFP_TYPE_CURRENT, roaming))) {
        return {};
    }
    std::wstring directory = std::wstring(roaming) + L"\\chichi77 KeyKey";
    CreateDirectoryW(directory.c_str(), nullptr);
    return directory;
}

std::wstring LoaderPreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\org.openvanilla.chichi77-keykey.windows.plist";
}

std::wstring TraditionalMandarinPreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\org.openvanilla.chichi77-keykey.windows."
                     L"TraditionalMandarin.plist";
}

std::wstring AssociatedPhrasePreferencesPath() {
    const std::wstring directory = SettingsDirectory();
    return directory.empty()
               ? std::wstring()
               : directory +
                     L"\\org.openvanilla.chichi77-keykey.windows."
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
    return settings;
}

COLORREF HighlightColorValue(const std::wstring& name) {
    if (name == L"Green") return RGB(59, 173, 31);
    if (name == L"Yellow") return RGB(235, 181, 0);
    if (name == L"Red") return RGB(191, 0, 41);
    return RGB(128, 0, 128);
}

}  // namespace KeyKey::WindowsTsf

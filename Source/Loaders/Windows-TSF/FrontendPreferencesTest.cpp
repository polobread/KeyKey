#include "FrontendSettings.h"
#include "PVPropertyList.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <chrono>
#include <stdexcept>

using namespace KeyKey::WindowsTsf;
static void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
static std::string Read(const std::wstring& path) {
    std::ifstream input(path, std::ios::binary);
    return {std::istreambuf_iterator<char>(input), std::istreambuf_iterator<char>()};
}
int main() {
    wchar_t temp[MAX_PATH]{};
    GetTempPathW(MAX_PATH, temp);
    const auto directory = std::wstring(temp) + L"keykey-preferences-" + std::to_wstring(GetCurrentProcessId());
    std::filesystem::create_directories(directory);
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", directory.c_str());
    int result = 0;
    try {
        const auto loader = LoaderPreferencesPath();
        const auto smart = SmartMandarinPreferencesPath();
        Check(LoadFrontendSettings().defaultChineseMode, "Missing startup preference must default to Chinese");
        for (const auto* value : {"English", "Chinese", "invalid", ""}) {
            { std::ofstream out(loader); out << "<plist><dict><key>DefaultInputMode</key><string>"
                << value << "</string></dict></plist>"; }
            Check(LoadFrontendSettings().defaultChineseMode == (std::string(value) != "English"),
                  "Startup mode must accept English and fall back to Chinese");
        }
        { std::ofstream out(loader); out << "<plist version=\"1.0\"><dict>"
            "<key>HighlightColor</key><string>Green</string>"
            "<key>ModulesSuppressedFromUI</key><array><string>TraditionalMandarin</string></array>"
            "<key>RetainedText</key><string>A&amp;B&lt;C</string>"
            "</dict></plist>"; }
        const std::string smartXml = "<plist version=\"1.0\"><dict><key>CandidateSelectionKeys</key>"
            "<string>1234567&amp;</string></dict></plist>";
        { std::ofstream out(smart); out << smartXml; }
        const auto future = std::filesystem::file_time_type::clock::now() + std::chrono::hours(24);
        std::filesystem::last_write_time(loader, future);
        Check(SaveSimplifiedOutputPreference(true), "First output preference save failed");
        const auto firstTime = std::filesystem::last_write_time(loader);
        Check(firstTime >= future + std::chrono::seconds(1), "Future timestamp did not advance");
        Check(LoadFrontendSettings().simplifiedChineseOutput, "Enabled output preference not read");
        Check(SaveSimplifiedOutputPreference(false), "Quick output preference save failed");
        Check(std::filesystem::last_write_time(loader) >= firstTime + std::chrono::seconds(1), "Quick toggle timestamp did not advance");
        Check(!LoadFrontendSettings().simplifiedChineseOutput, "Disabled output preference not read");
        Check(LoadFrontendSettings().highlightColor == L"Green" && !IsInputMethodVisible("TraditionalMandarin"),
            "Other loader preferences not preserved");
        std::unique_ptr<OpenVanilla::PVPlistValue> parsed(OpenVanilla::PVPropertyList::ParsePlistFromString(Read(loader).c_str()));
        Check(parsed && parsed->type() == OpenVanilla::PVPlistValue::Dictionary, "Saved loader XML invalid");
        Check(parsed->stringValueForKey("RetainedText") == "A&B<C", "XML entity value not preserved");
        Check(Read(smart) == smartXml && Read(loader).find("CandidateSelectionKeys") == std::string::npos,
            "Candidate keys changed or contaminated loader preferences");
        std::cout << "Frontend preference persistence and timestamps passed\n";
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; result = 1; }
    std::filesystem::remove_all(directory);
    return result;
}

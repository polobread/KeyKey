#include "KeyKeyEngine.h"
#include "FrontendSettings.h"
#include "OutputConversion.h"
#include "ModuleState.h"
#include "Mandarin.h"
#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}
using namespace KeyKey::WindowsTsf;
using namespace Formosa::Mandarin;
void Check(bool yes, const char* message) { if (!yes) throw std::runtime_error(message); }
EngineResult Key(KeyKeyEngineSession& engine, UINT vk, wchar_t character = 0) {
    KeyEvent event; event.virtualKey = vk; event.numLock = true;
    if (character) event.text = std::wstring(1, character);
    return engine.handleKey(event);
}
EngineResult Character(KeyKeyEngineSession& engine, wchar_t c) {
    const UINT vk = c == L';' ? VK_OEM_1 : c == L'/' ? VK_OEM_2 : c == L'.' ? VK_OEM_PERIOD
        : c >= L'a' && c <= L'z' ? c - L'a' + 'A' : c;
    return Key(engine, vk, c);
}
EngineResult Type(KeyKeyEngineSession& engine, const std::string& keys) {
    EngineResult result;
    for (auto c : keys) { result = Character(engine, c); Check(result.handled, "Reading key rejected"); }
    return result;
}
void WriteSettings(const std::string& layout, const std::string& keys, int size) {
    std::ofstream plist(SmartMandarinPreferencesPath(), std::ios::binary);
    plist << "<plist><dict><key>KeyboardLayout</key><string>" << layout
        << "</string><key>CandidateSelectionKeys</key><string>" << keys
        << "</string><key>ComposingTextBufferSize</key><string>" << size
        << "</string><key>ShowCandidateListWithSpace</key><string>true</string></dict></plist>";
    plist.close();
    std::filesystem::last_write_time(SmartMandarinPreferencesPath(),
        std::filesystem::file_time_type::clock::now() + std::chrono::seconds(3));
}
int main(int argc, char** argv) {
    try {
        g_module = GetModuleHandleW(nullptr);
        const std::string mode = argc > 1 ? argv[1] : "custom";
        const auto profile = std::filesystem::temp_directory_path() /
            (L"keykey-advanced-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
        std::filesystem::create_directories(profile);
        Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str()), "Profile isolation");
        const std::string layout = mode == "hsu" ? "Hsu" : mode == "eten26" ? "ETen26" : "Standard";
        const std::string keys = mode == "custom" ? "asdfjkl;" : mode == "invalid" ? "11223344" : "";
        const int size = mode == "custom" ? 12 : mode == "invalid" ? -1 : 10;
        WriteSettings(layout, keys, size);
        Check(SelectInputMethod("SmartMandarin"), "Smart unavailable");
        auto engine = KeyKeyEngineSession::Create();
        Check(engine && engine->ready(), "Engine unavailable");
        if (mode == "four-output") {
            for (const auto* method : {"SmartMandarin", "TraditionalMandarin", "Generic-cj-cin", "Generic-simplex-cin"}) {
                Check(SelectInputMethod(method), "Output test method unavailable");
                engine = KeyKeyEngineSession::Create();
                auto output = Type(*engine, std::string(method).find("Generic") == 0
                    ? std::string(method) == "Generic-cj-cin" ? "jwj" : "jj" : "tk ");
                std::wstring commit = output.committedText;
                output.committedText.clear();
                if (commit.empty() && std::string(method).find("Generic") == 0) {
                    output = Key(*engine, VK_SPACE, L' ');
                    commit += output.committedText;
                    output.committedText.clear();
                }
                if (commit.empty() && output.candidatesVisible) {
                    bool found = false;
                    std::set<std::wstring> pages;
                    while (output.candidatesVisible && !found) {
                        std::wstring page;
                        for (const auto& candidate : output.candidates) {
                            page += candidate.text + L"\n";
                            if (candidate.text == L"車") { output = Character(*engine, candidate.selectionKey[0]); found = true; break; }
                        }
                        if (found || !pages.insert(page).second) break;
                        output = Key(*engine, VK_NEXT);
                    }
                    Check(found, (std::string(method) + " could not select traditional 車").c_str());
                }
                commit += output.committedText;
                if (commit.empty()) { output = Key(*engine, VK_RETURN,L'\r'); commit += output.committedText; }
                Check(commit == L"車" && ConvertOutput(commit,false) == L"車" && ConvertOutput(commit,true) == L"车",
                    "Four input methods must retain traditional engine text and share simplified output");
            }
            std::cout << "Four input methods output passed\n"; return 0;
        }
        const auto* keyboard = BopomofoKeyboardLayout::LayoutForName(layout);
        const auto reading = BopomofoSyllable::FromComposedString("ㄋㄧˇ");
        auto result = Type(*engine, keyboard->keySequenceFromSyllable(reading));
        result = Key(*engine, VK_SPACE, L' ');
        Check(result.candidatesVisible && result.candidates.size() == 8, "Space did not open eight choices");
        const std::wstring expected = mode == "custom" || mode == "eten26" ? L"asdfjkl;"
            : mode == "hsu" ? L"asdfzxcv" : L"12345678";
        for (size_t i = 0; i < 8; ++i) Check(result.candidates[i].selectionKey == expected.substr(i, 1), "Layout or custom selection keys changed");
        const auto chosen = result.candidates[1].text;
        result = Character(*engine, expected[1]);
        Check(!result.candidatesVisible && result.compositionText == chosen, "Non-digit candidate selection failed");
        if (mode == "custom") {
            engine->reset();
            const char* syllables[] = {"fu/3","ru84","ul4","fm4","s83","xu3","j06","sk7","fm4","c93","1u0","up","jo4","s84","xu3","u.3","1u3","ru","su6"};
            std::wstring committed;
            for (size_t i = 0; i < std::size(syllables); ++i) {
                result = Type(*engine, syllables[i]); committed += result.committedText;
                if (i == 6) {
                    result = Key(*engine, VK_DOWN);
                    std::set<std::wstring> pages;
                    bool found = false;
                    while (result.candidatesVisible && !found) {
                        std::wstring page;
                        for (const auto& candidate : result.candidates) {
                            page += candidate.text + L"\n";
                            if (candidate.text == L"玩") { result = Character(*engine, candidate.selectionKey[0]); found = true; break; }
                        }
                        if (found || !pages.insert(page).second) break;
                        result = Key(*engine, VK_NEXT);
                    }
                    Check(found, "Fixture homophone selection");
                }
                if (i == 10 || i == 11 || i == 17) { result = Key(*engine, VK_SPACE,L' '); committed += result.committedText; }
                if (i == 11) Check(committed.empty() && result.compositionText == L"請假要去哪裡玩呢去海邊因", "Custom twelve-syllable boundary");
                if (i == 12) Check(committed == L"請假", "Custom boundary must evict a complete leading word");
            }
            Check(committed + result.compositionText == L"請假要去哪裡玩呢去海邊因為那裡有比基尼", "Custom length lost or duplicated text");
            Check(ConvertOutput(committed + result.compositionText,true) == L"请假要去哪里玩呢去海边因为那里有比基尼", "Long output conversion");
            const auto previous = result.compositionText;
            WriteSettings("Standard", "12345678", 20);
            result = Character(*engine, L'1');
            Check(result.committedText == previous && result.compositionText == L"ㄅ", "Settings change lost pending sentence");
        }
        std::cout << "Advanced engine " << mode << " passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}

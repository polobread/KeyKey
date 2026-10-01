#include "KeyKeyEngine.h"
#include "InputMethods.h"

#include <atomic>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>

#include "ModuleState.h"
#include "sqlite3.h"

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}

namespace {
using namespace KeyKey::WindowsTsf;

void Check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

KeyEvent Key(UINT code, bool shift = false) {
    KeyEvent event;
    event.virtualKey = code;
    event.shift = shift;
    event.numLock = true;  // Global Num Lock must not disable normal letter keys.
    // Match the text TSF receives from ToUnicodeEx, including \b, \r and Esc.
    // Empty synthetic text on editing keys hides errors in the OVKey adapter.
    BYTE state[256]{};
    state[code] = 0x80;
    state[VK_SHIFT] = shift ? 0x80 : 0;
    state[VK_NUMLOCK] = 1;
    wchar_t text[8]{};
    const HKL layout = GetKeyboardLayout(0);
    const int length = ToUnicodeEx(code, MapVirtualKeyExW(code, MAPVK_VK_TO_VSC, layout),
                                  state, text, static_cast<int>(std::size(text)), 4, layout);
    if (length > 0) event.text.assign(text, text + length);
    return event;
}

EngineResult Press(KeyKeyEngineSession& session, char c) {
    return session.handleKey(Key(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c));
}

EngineResult Type(KeyKeyEngineSession& session, const char* text) {
    EngineResult result;
    for (; *text; ++text) {
        result = Press(session, *text);
        Check(result.handled, "Table engine passed through a radical.");
    }
    return result;
}

bool HasCandidate(const EngineResult& result, const wchar_t* text) {
    for (const auto& candidate : result.candidates)
        if (candidate.text == text) return true;
    return false;
}

std::filesystem::path Prepare(const std::string& mode) {
    const auto profile = std::filesystem::temp_directory_path() /
        (L"keykey-table-test-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
         std::to_wstring(GetTickCount64()));
    std::filesystem::create_directories(profile);
    Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str()),
          "Could not isolate the test profile.");
    std::ofstream loader(profile / L"com.polobread.chichi77-keykey.windows.plist");
    loader << "<plist version=\"1.0\"><dict><key>PrimaryInputMethod</key>"
              "<string>Generic-cj-cin</string><key>ActivatedAroundFilters</key>"
              "<array/></dict></plist>";
    for (const auto* suffix : {L"Generic-cj-cin", L"Generic-simplex-cin"}) {
        std::ofstream config(profile / (std::wstring(L"com.polobread.chichi77-keykey.windows.") +
                                      suffix + L".plist"));
        config << "<plist version=\"1.0\"><dict>"
                  "<key>UseDynamicFrequency</key><string>"
               << (mode == "dynamic" ? "true" : "false") << "</string>"
                  "<key>ComposeWhileTyping</key><string>"
               << (mode == "compose" ? "true" : "false") << "</string>";
        if (mode == "alias")
            config << "<key>ComposeWhenTyping</key><string>true</string>";
        config << "</dict></plist>";
        Check(config.good(), "Could not write table preferences.");
    }
    return profile;
}

void TestBasics() {
    Check(CurrentInputMethod() == "Generic-cj-cin", "Existing Cangjie selection was lost.");
    for (const auto& method : kInputMethods)
        Check(IsInputMethodAvailable(method.identifier), "An input method was not loaded.");
    Check(!SelectInputMethod("Generic-unknown-cin"), "Unknown table was accepted.");
    auto session = KeyKeyEngineSession::Create();
    Check(session && session->ready(), "Table session did not initialize.");
    Check(Key(VK_BACK).text == L"\b", "Windows Backspace translation was not exercised.");
    Check(Key(VK_RETURN).text == L"\r", "Windows Enter translation was not exercised.");
    for (const auto* method : {"Generic-cj-cin", "Generic-simplex-cin"}) {
        Check(SelectInputMethod(method), "Could not select table for editing-key tests.");
        Type(*session, "ab");
        auto edited = session->handleKey(Key(VK_BACK));
        Check(edited.handled && edited.compositionText == L"日" &&
              edited.committedText.empty() && !edited.beep && !edited.candidatesVisible,
              "Translated Backspace failed to shorten radicals or dismiss candidates.");
        edited = session->handleKey(Key(VK_BACK));
        Check(edited.handled && edited.compositionText.empty() &&
              edited.committedText.empty() && !edited.beep && !edited.candidatesVisible,
              "Translated Backspace failed to remove the final radical.");
        edited = session->handleKey(Key(VK_BACK));
        Check(!edited.handled && edited.committedText.empty(),
              "Backspace on empty input committed a control character.");
        Type(*session, "a");
        edited = session->handleKey(Key(VK_ESCAPE));
        Check(edited.handled && edited.compositionText.empty() &&
              edited.committedText.empty() && !edited.beep && !edited.candidatesVisible,
              "Translated Esc failed to cancel unfinished radicals.");
        Type(*session, "a");
        edited = session->handleKey(Key(VK_RETURN));
        Check(edited.handled && !edited.beep &&
              (edited.candidatesVisible || !edited.committedText.empty()),
              "Translated Enter failed to convert unfinished radicals.");
        session->reset();
        Type(*session, "ab");
        session->handleKey(Key(VK_SPACE));
        edited = session->handleKey(Key(VK_ESCAPE));
        Check(edited.handled && edited.compositionText.empty() &&
              edited.committedText.empty() && !edited.candidatesVisible,
              "Translated Esc failed to cancel the candidate panel.");
        session->reset();
    }
    Check(SelectInputMethod("Generic-cj-cin"), "Could not restore Cangjie.");
    auto result = Type(*session, "ab");
    Check(result.compositionText == L"日月" && result.compositionCursor == 2 &&
          !result.candidatesVisible, "Cangjie radical display was incorrect.");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.candidatesVisible && HasCandidate(result, L"明"), "Cangjie ab did not find 明.");
    result = Press(*session, '1');
    Check(result.committedText == L"明" && result.compositionText.empty(), "Cangjie selection failed.");

    session->reset();
    Type(*session, "ab");
    result = session->handleKey(Key(VK_BACK));
    Check(result.compositionText == L"日", "Backspace did not remove one radical.");
    result = session->handleKey(Key(VK_ESCAPE));
    Check(result.compositionText.empty() && result.committedText.empty(), "Esc committed cancelled radicals.");

    Type(*session, "zzzzz");
    result = Press(*session, 'a');
    Check(result.beep && result.compositionText.size() == 5, "Sixth Cangjie radical was accepted.");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.beep && result.compositionText.empty(), "Invalid code was not cleared.");

    session->reset();
    Type(*session, "a");
    result = session->handleKey(Key(VK_OEM_2, true));  // a?
    Check(result.compositionText == L"日？" && result.committedText.empty(),
          "Wildcard committed punctuation instead of retaining the query.");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.candidatesVisible && HasCandidate(result, L"明"), "Cangjie wildcard lookup failed.");
    Check(result.candidates.size() == 9, "Small prior query reduced later candidate page size.");
    const auto first = result.candidates.front().text;
    result = session->handleKey(Key(VK_NEXT));
    Check(result.candidatesVisible && result.candidates.front().text != first, "Candidate next page failed.");
    result = session->handleKey(Key(VK_PRIOR));
    Check(result.candidates.front().text == first, "Candidate previous page failed.");
    result = session->handleKey(Key(VK_ESCAPE));
    Check(!result.candidatesVisible && result.compositionText.empty(), "Candidate cancellation left radicals.");

    KeyEvent shortcut = Key(VK_OEM_COMMA);
    shortcut.control = true;
    Check(!IsInputMethodControlKey(shortcut) && !session->wantsKey(shortcut), "Cangjie swallowed a host Ctrl shortcut.");
    result = session->handleKey(Key(VK_OEM_COMMA));
    Check(result.committedText == L"，", "Cangjie punctuation failed.");
    session->reset();
    Check(SelectInputMethod("Generic-simplex-cin"), "Could not switch to Simplex.");
    result = Type(*session, "ab");
    Check(result.candidatesVisible && result.candidates.size() == 9 && HasCandidate(result, L"明"),
          "Simplex two-code automatic query failed.");
    const auto selected = result.candidates[1].text;
    result = Press(*session, '2');
    Check(result.committedText == selected, "Simplex numeric selection failed.");
    session->reset();
    Type(*session, "ab");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.candidatesVisible && !HasCandidate(result, L"明"), "Simplex space did not page.");
    session->reset();
    Check(SelectInputMethod("TraditionalMandarin"), "Could not switch back to Mandarin.");
    Check(IsInputMethodControlKey(shortcut), "Mandarin punctuation shortcut stopped working.");
    result = Type(*session, "1u3");
    Check(result.candidatesVisible && !result.candidates.empty(), "Mandarin regression after table switch.");
    session->reset();
    Check(SelectInputMethod("Generic-cj-cin"), "Cangjie selection failed.");
    Type(*session, "ab");
    Check(SelectInputMethod("Generic-simplex-cin"), "Simplex selection failed.");
    result = Press(*session, 'a');
    Check(result.committedText == L"日月" && result.compositionText == L"日",
          "Changing input mode mixed or discarded the old radicals.");
    Check(SelectInputMethod("Generic-cj-cin"), "Cangjie selection failed.");
    result = session->handleKey(Key(VK_LEFT));
    Check(!result.handled && result.committedText == L"日" && result.compositionText.empty(),
          "Mode change swallowed a host navigation key or lost the prior reading.");
}

void TestCompose() {
    auto session = KeyKeyEngineSession::Create();
    for (const auto* method : {"Generic-cj-cin", "Generic-simplex-cin"}) {
        Check(SelectInputMethod(method), "Table input method was unavailable.");
        auto result = Type(*session, "a");
        Check(result.candidatesVisible && HasCandidate(result, L"日"), "ComposeWhileTyping or legacy alias was ignored.");
        result = session->handleKey(Key(VK_BACK));
        Check(result.handled && result.committedText.empty() && !result.beep &&
              result.compositionText.empty() && !result.candidatesVisible,
              "Translated Backspace left a stale candidate panel.");
        session->reset();
        Type(*session, "a");
        result = Press(*session, 'b');
        Check(result.candidatesVisible && HasCandidate(result, L"明"), "Live lookup could not extend radicals.");
        result = session->handleKey(Key(VK_BACK));
        Check(result.handled && result.compositionText == L"日" && result.candidatesVisible &&
              HasCandidate(result, L"日") && !result.beep && result.committedText.empty(),
              "Live Backspace did not refresh candidates for the shorter code.");
        result = session->handleKey(Key(VK_ESCAPE));
        Check(result.handled && result.compositionText.empty() &&
              result.committedText.empty() && !result.candidatesVisible,
              "Live Esc left a stale candidate panel.");
        session->reset();
    }
}

void TestLearning(const std::filesystem::path& profile) {
    auto session = KeyKeyEngineSession::Create();
    Type(*session, "ab");
    auto result = session->handleKey(Key(VK_SPACE));
    Check(result.candidates.size() == 2, "Unexpected initial Cangjie candidates.");
    const auto learned = result.candidates[1].text;
    result = Press(*session, '2');
    Check(result.committedText == learned, "Learning selection did not commit.");
    // An independent connection must obtain a write lock while the IME is active.
    sqlite3* database = nullptr;
    const auto path = profile / L"Generic-cj-cin-DynamicCandidateOrder.sqlite3";
    Check(sqlite3_open16(path.c_str(), &database) == SQLITE_OK, "Learning DB missing.");
    struct Close { sqlite3* db; ~Close() { sqlite3_close(db); } } close{database};
    Check(sqlite3_exec(database, "BEGIN IMMEDIATE", nullptr, nullptr, nullptr) == SQLITE_OK,
          "IME held a write transaction across input events.");
    Type(*session, "ab");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.candidates.front().text == learned, "Learned ordering was not visible to the active session.");
    const auto blockedSelection = result.candidates[1].text;
    result = Press(*session, '2');
    Check(result.committedText == blockedSelection, "A locked learning DB prevented input.");
    sqlite3_exec(database, "ROLLBACK", nullptr, nullptr, nullptr);
    auto second = KeyKeyEngineSession::Create();
    Type(*second, "ab");
    result = second->handleKey(Key(VK_SPACE));
    Check(result.candidates.front().text == learned, "A new context could not see committed learning.");
    second->reset();
    session->reset();
    const auto preferences = profile / L"com.polobread.chichi77-keykey.windows.Generic-cj-cin.plist";
    {
        std::ofstream config(preferences);
        config << "<plist version=\"1.0\"><dict>"
                  "<key>UseDynamicFrequency</key><string>true</string>"
                  "<key>UseCharactersSupportedByEncoding</key><string>BIG-5</string>"
                  "</dict></plist>";
    }
    std::filesystem::last_write_time(preferences,
        std::filesystem::file_time_type::clock::now() + std::chrono::seconds(2));
    Type(*session, "ab");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.committedText == L"明",
          "Learning resurrected a candidate excluded by Big-5 filtering.");
}

void TestSettings(const std::filesystem::path& profile) {
    auto session = KeyKeyEngineSession::Create();
    Type(*session, "afhhh");
    auto result = session->handleKey(Key(VK_SPACE));
    Check(result.committedText == L"影", "Five-code Cangjie conversion failed.");
    session->reset();
    Type(*session, "idbbr");
    result = session->handleKey(Key(VK_SPACE));
    Check(result.committedText == L"\U0002A3A9" && result.committedText.size() == 2,
          "Supplementary-plane output was corrupted.");
    session->reset();
    const auto preferences = profile / L"com.polobread.chichi77-keykey.windows.Generic-cj-cin.plist";
    {
        std::ofstream config(preferences);
        config << "<plist version=\"1.0\"><dict>"
                  "<key>ShouldCommitAtMaximumRadicalLength</key><string>true</string>"
                  "<key>UseOverrideTable</key><string>Punctuations-cj-halfwidth-cin</string>"
                  "<key>UseCharactersSupportedByEncoding</key><string>BIG-5</string>"
                  "</dict></plist>";
    }
    std::filesystem::last_write_time(preferences,
        std::filesystem::file_time_type::clock::now() + std::chrono::seconds(2));
    result = Type(*session, "afhhh");
    Check(result.committedText == L"影", "Maximum-code setting did not reload.");
    session->reset();
    result = session->handleKey(Key(VK_OEM_COMMA));
    Check(result.committedText == L",", "Halfwidth punctuation override did not reload.");
    session->reset();
    result = Type(*session, "idbbr");
    Check(result.beep && result.committedText.empty() && result.compositionText.empty(),
          "Big-5 restriction did not exclude a supplementary-plane character.");
}
}  // namespace

int main(int argc, char** argv) {
    try {
        const std::string mode = argc > 1 ? argv[1] : "basic";
        const auto profile = Prepare(mode);
        if (mode == "basic") TestBasics();
        else if (mode == "compose" || mode == "alias") TestCompose();
        else if (mode == "dynamic") TestLearning(profile);
        else if (mode == "settings") TestSettings(profile);
        else throw std::runtime_error("Unknown test mode.");
        std::cout << "Windows table input test passed: " << mode << '\n';
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

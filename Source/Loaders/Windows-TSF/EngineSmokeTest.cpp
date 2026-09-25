#include "KeyKeyEngine.h"

#include <Windows.h>

#include <atomic>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>

#include "ModuleState.h"
#include "sqlite3.h"

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}  // namespace KeyKey::WindowsTsf

namespace {

KeyKey::WindowsTsf::EngineResult Press(
    KeyKey::WindowsTsf::KeyKeyEngineSession& session, wchar_t character,
    wchar_t translatedCharacter = 0) {
    using namespace KeyKey::WindowsTsf;
    KeyEvent event;
    event.virtualKey = static_cast<UINT>(character >= L'a' && character <= L'z'
                                             ? character - L'a' + 'A'
                                             : character);
    // Num Lock is normally enabled on Windows desktops. It must not turn main
    // keyboard keys into numpad keys for the OpenVanilla core.
    event.numLock = true;
    // Exercise both an empty ToUnicodeEx result and a misleading translated
    // character. The Standard Bopomofo layout is based on virtual-key position.
    if (translatedCharacter) event.text.assign(1, translatedCharacter);

    return session.handleKey(event);
}

bool LooksLikePassThrough(const KeyKey::WindowsTsf::EngineResult& result,
                          wchar_t key) {
    return result.committedText == std::wstring(1, key) ||
           result.compositionText == std::wstring(1, key);
}

KeyKey::WindowsTsf::EngineResult PressKey(
    KeyKey::WindowsTsf::KeyKeyEngineSession& session, UINT virtualKey) {
    KeyKey::WindowsTsf::KeyEvent event;
    event.virtualKey = virtualKey;
    return session.handleKey(event);
}

bool PrepareTestProfile(const std::string& mode) {
    std::wstring executable(32768, L'\0');
    const DWORD length = GetModuleFileNameW(
        nullptr, executable.data(), static_cast<DWORD>(executable.size()));
    if (!length || length >= executable.size()) return false;
    executable.resize(length);
    const auto root = std::filesystem::path(executable).parent_path() / L"EscTestProfiles";
    const auto profile = root / std::filesystem::path(mode);
    std::error_code error;
    std::filesystem::remove_all(profile, error);
    if (error) return false;
    std::filesystem::create_directories(profile, error);
    if (error || !SetEnvironmentVariableW(
                     L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str())) return false;

    std::ofstream plist(profile /
        L"com.polobread.chichi77-keykey.windows.SmartMandarin.plist",
        std::ios::binary);
    if (!plist) return false;
    plist << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"
             "<plist version=\"1.0\"><dict>\n"
             "<key>ClearComposingTextWithEsc</key><string>"
          << (mode == "keep" ? "false" : "true") << "</string>\n";
    if (mode != "legacy") {
        plist << "<key>ClearComposingTextWithEscUserChoice</key>"
                 "<string>true</string>\n";
    }
    plist << "</dict></plist>\n";
    return plist.good();
}

bool TypeHello(KeyKey::WindowsTsf::KeyKeyEngineSession& session) {
    for (const wchar_t key : L"su3cl3") {
        if (!key) break;
        const auto result = Press(session, key);
        if (!result.handled) return false;
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    using namespace KeyKey::WindowsTsf;
    const std::string mode = argc > 1 ? argv[1] : "legacy";
    if (mode != "legacy" && mode != "keep" && mode != "clear") return 12;
    if (!PrepareTestProfile(mode)) {
        std::cerr << "Unable to prepare isolated Esc test profile.\n";
        return 13;
    }
    const bool clearSentenceWithEsc = mode == "clear";
    const std::string originalMethod = CurrentInputMethod();
    struct RestoreInputMethod {
        const std::string& method;
        ~RestoreInputMethod() {
            if (!method.empty()) SelectInputMethod(method.c_str());
        }
    } restore{originalMethod};
    if (!SelectInputMethod("SmartMandarin")) {
        std::cerr << "Smart Mandarin is not available.\n";
        return 10;
    }

    auto session = KeyKeyEngineSession::Create();
    if (!session || !session->ready()) {
        std::cerr << "Engine did not initialize; check Databases/KeyKey.db.\n";
        return 11;
    }
    const auto initial = Press(*session, L'1');  // Standard layout: Bopomofo B.
    if (!initial.handled || initial.compositionText.empty() ||
        LooksLikePassThrough(initial, L'1')) {
        std::cerr << "First Bopomofo key was not handled as a reading.\n";
        return 1;
    }

    const auto medial = Press(*session, L'j', L'J');  // Bopomofo U.
    if (!medial.handled || medial.compositionText.empty() ||
        LooksLikePassThrough(medial, L'j')) {
        std::cerr << "Second Bopomofo key was not handled as a reading.\n";
        return 2;
    }

    const auto tone = Press(*session, L'4');  // ㄅㄨˋ should compose 不.
    if (!tone.handled || tone.compositionText.find(L'不') == std::wstring::npos) {
        std::cerr << "Smart Mandarin did not convert ㄅㄨˋ to 不.\n";
        return 3;
    }

    session->reset();
    if (!TypeHello(*session)) {
        std::cerr << "Smart Mandarin did not accept the 你好 reading.\n";
        return 4;
    }
    const auto completed = PressKey(*session, VK_ESCAPE);
    if (!completed.handled || !completed.committedText.empty() ||
        (!clearSentenceWithEsc && completed.compositionText != L"你好") ||
        (clearSentenceWithEsc && !completed.compositionText.empty())) {
        std::cerr << "Esc did not respect the completed-sentence preference.\n";
        return 5;
    }

    session->reset();
    if (!TypeHello(*session)) return 6;
    const auto candidates = PressKey(*session, VK_DOWN);
    if (!candidates.handled || !candidates.candidatesVisible ||
        candidates.compositionText != L"你好") {
        std::cerr << "Could not open Smart Mandarin candidates.\n";
        return 7;
    }
    const auto closedCandidates = PressKey(*session, VK_ESCAPE);
    if (!closedCandidates.handled || closedCandidates.candidatesVisible ||
        closedCandidates.compositionText != L"你好" ||
        !closedCandidates.committedText.empty()) {
        std::cerr << "Esc in candidates changed the completed sentence.\n";
        return 8;
    }

    session->reset();
    if (!TypeHello(*session)) return 9;
    const auto reading = Press(*session, L'1');
    if (!reading.handled || reading.compositionText == L"你好") {
        std::cerr << "Could not start an unfinished reading.\n";
        return 14;
    }
    const auto canceledReading = PressKey(*session, VK_ESCAPE);
    if (!canceledReading.handled || canceledReading.compositionText != L"你好" ||
        !canceledReading.committedText.empty()) {
        std::cerr << "Esc removed the sentence instead of only its reading.\n";
        return 15;
    }
    const auto secondEscape = PressKey(*session, VK_ESCAPE);
    if (!secondEscape.handled ||
        (!clearSentenceWithEsc && secondEscape.compositionText != L"你好") ||
        (clearSentenceWithEsc && !secondEscape.compositionText.empty())) {
        std::cerr << "Second Esc did not respect the sentence preference.\n";
        return 16;
    }

    std::cout << "Bopomofo and Esc " << mode << " test passed with WinSQLite "
              << sqlite3_libversion() << ".\n";
    return 0;
}

#include "KeyKeyEngine.h"

#include <Windows.h>

#include <atomic>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <set>

#include "ModuleState.h"
#include "InputMethods.h"
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
    event.virtualKey = character == L'/' ? VK_OEM_2
        : character == L'.' ? VK_OEM_PERIOD
        : static_cast<UINT>(character >= L'a' && character <= L'z'
                                ? character - L'a' + 'A' : character);
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
    if (virtualKey == VK_BACK) event.text = L"\b";
    if (virtualKey == VK_RETURN) event.text = L"\r";
    if (virtualKey == VK_ESCAPE) event.text = L"\x1b";
    return session.handleKey(event);
}

bool SelectTrailingCandidate(KeyKey::WindowsTsf::KeyKeyEngineSession& session,
                             const std::wstring& text,
                             KeyKey::WindowsTsf::EngineResult& result) {
    result = PressKey(session, VK_DOWN);
    std::set<std::wstring> visitedPages;
    while (result.handled && result.candidatesVisible) {
        std::wstring page;
        for (const auto& candidate : result.candidates) {
            if (candidate.text == text && candidate.selectionKey.size() == 1) {
                result = Press(session, candidate.selectionKey.front());
                return result.handled && !result.candidatesVisible &&
                       result.committedText.empty();
            }
            page += candidate.text + L"\n";
        }
        if (!visitedPages.insert(page).second) break;
        result = PressKey(session, VK_NEXT);
    }
    return false;
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

bool TestNumpad() {
    using namespace KeyKey::WindowsTsf;
    for (const auto& method : kInputMethods) {
        if (!SelectInputMethod(method.identifier)) return false;
        auto session = KeyKeyEngineSession::Create();
        if (!session || !session->ready()) return false;
        auto number = [&](UINT vk, wchar_t expected, const std::wstring& prefix = L"") {
            KeyEvent event; event.virtualKey = vk; event.numLock = true;
            if (!session->wantsKey(event)) return false;
            const auto result = session->handleKey(event);
            return result.handled && !result.beep && result.committedText == prefix + expected &&
                   result.compositionText.empty() && !result.candidatesVisible && !session->hasComposition();
        };
        for (UINT digit = 0; digit < 10; ++digit)
            if (!number(VK_NUMPAD0 + digit, static_cast<wchar_t>(L'0' + digit))) return false;
        for (auto pair : {std::pair<UINT,wchar_t>{VK_DECIMAL,L'.'}, {VK_ADD,L'+'},
                          {VK_SUBTRACT,L'-'}, {VK_MULTIPLY,L'*'}, {VK_DIVIDE,L'/'}})
            if (!number(pair.first, pair.second)) return false;
        KeyEvent shortcut; shortcut.virtualKey = VK_NUMPAD1; shortcut.numLock = true;
        shortcut.control = true;
        if (session->wantsKey(shortcut)) return false;
        shortcut.control = false; shortcut.alt = true;
        if (session->wantsKey(shortcut)) return false;
        KeyEvent navigation; navigation.virtualKey = VK_END;
        if (session->wantsKey(navigation)) return false;
        const auto reading = Press(*session, IsTableInputMethod(method.identifier) ? L'a' : L'1');
        if (!reading.handled || reading.compositionText.empty() ||
            !number(VK_NUMPAD2, L'2', reading.compositionText)) return false;
        // A fresh main-keyboard reading must still work after the numpad commit.
        const auto next = Press(*session, IsTableInputMethod(method.identifier) ? L'a' : L'1');
        if (!next.handled || next.compositionText.empty()) return false;
        session->reset();
        if (!IsTableInputMethod(method.identifier)) {
            Press(*session, L'1'); Press(*session, L'j');
            auto composed = Press(*session, L'4');
            if (std::string(method.identifier) == "SmartMandarin") composed = PressKey(*session, VK_DOWN);
            if (!composed.candidatesVisible || composed.compositionText.empty() ||
                !number(VK_NUMPAD8, L'8', composed.compositionText)) return false;
        }
    }
    return true;
}

}  // namespace

int main(int argc, char** argv) {
    using namespace KeyKey::WindowsTsf;
    const std::string mode = argc > 1 ? argv[1] : "legacy";
    if (mode != "legacy" && mode != "keep" && mode != "clear" && mode != "numpad") return 12;
    if (!PrepareTestProfile(mode)) {
        std::cerr << "Unable to prepare isolated Esc test profile.\n";
        return 13;
    }
    if (mode == "numpad") {
        if (!TestNumpad()) { std::cerr << "Numpad input/preservation failed.\n"; return 20; }
        std::cout << "Numpad digits, operators, composition and candidate preservation passed.\n";
        return 0;
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

    session->reset();
    const wchar_t* syllables[] = {L"fu/3", L"ru84", L"ul4", L"fm4", L"s83",
                                  L"xu3", L"j06", L"sk7", L"fm4", L"c93", L"1u0",
                                  L"up", L"jo4", L"s84", L"xu3", L"u.3", L"1u3",
                                  L"ru", L"su6"};
    std::wstring committed;
    EngineResult result;
    for (size_t index = 0; index < std::size(syllables); ++index) {
        for (const wchar_t* key = syllables[index]; *key; ++key) {
            result = Press(*session, *key);
            if (!result.handled) {
                std::cerr << "Long Smart Mandarin reading was not handled.\n";
                return 17;
            }
            committed += result.committedText;
        }
        // This fixture checks editing boundaries and text preservation. Select
        // the intended homophone explicitly; model updates may prefer 完.
        if (index == 6 && !SelectTrailingCandidate(*session, L"玩", result)) {
            std::cerr << "Could not select 玩 for the desktop-limit fixture.\n";
            return 22;
        }
        if (index == 9 &&
            (!committed.empty() || result.compositionText != L"請假要去哪裡玩呢去海")) {
            std::cerr << "Smart Mandarin changed the sentence before its desktop limit.\n";
            return 18;
        }
        if (index == 10 || index == 11 || index == 17) {
            result = PressKey(*session, VK_SPACE);
            committed += result.committedText;
            if (!result.handled) {
                std::cerr << "Smart Mandarin first-tone reading was not completed.\n";
                return 19;
            }
        }
        if (index == 10) {
            if (committed != L"請假" ||
                result.compositionText != L"要去哪裡玩呢去海邊") {
                std::cerr << "Smart Mandarin did not evict the whole leading word at eleven readings.\n";
                return 20;
            }
        }
    }
    if (committed + result.compositionText !=
        L"請假要去哪裡玩呢去海邊因為那裡有比基尼") {
        std::cerr << "Smart Mandarin lost text while shifting the full sentence.\n";
        return 21;
    }

    std::cout << "Bopomofo and Esc " << mode << " test passed with WinSQLite "
              << sqlite3_libversion() << ".\n";
    return 0;
}

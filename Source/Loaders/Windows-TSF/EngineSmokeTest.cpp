#include "KeyKeyEngine.h"

#include <Windows.h>

#include <atomic>
#include <cstdlib>
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

}  // namespace

int main() {
    using namespace KeyKey::WindowsTsf;
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

    std::cout << "Bopomofo engine smoke test passed with WinSQLite "
              << sqlite3_libversion() << ".\n";
    return 0;
}

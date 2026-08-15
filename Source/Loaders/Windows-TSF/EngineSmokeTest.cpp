#include "KeyKeyEngine.h"

#include <Windows.h>

#include <atomic>
#include <cstdlib>
#include <iostream>

#include "ModuleState.h"

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}  // namespace KeyKey::WindowsTsf

namespace {

KeyKey::WindowsTsf::EngineResult Press(wchar_t character,
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

    static std::unique_ptr<KeyKeyEngineSession> session = KeyKeyEngineSession::Create();
    if (!session || !session->ready()) {
        std::cerr << "Engine did not initialize; check Databases/KeyKey.db.\n";
        std::exit(10);
    }
    return session->handleKey(event);
}

bool LooksLikePassThrough(const KeyKey::WindowsTsf::EngineResult& result,
                          wchar_t key) {
    return result.committedText == std::wstring(1, key) ||
           result.compositionText == std::wstring(1, key);
}

}  // namespace

int main() {
    const auto initial = Press(L'1');  // Standard layout: Bopomofo B.
    if (!initial.handled || initial.compositionText.empty() ||
        LooksLikePassThrough(initial, L'1')) {
        std::cerr << "First Bopomofo key was not handled as a reading.\n";
        return 1;
    }

    const auto medial = Press(L'u', L'U');  // Standard layout: Bopomofo I.
    if (!medial.handled || medial.compositionText.empty() ||
        LooksLikePassThrough(medial, L'u')) {
        std::cerr << "Second Bopomofo key was not handled as a reading.\n";
        return 2;
    }

    const auto tone = Press(L'3');  // Standard layout: third tone.
    if (!tone.handled ||
        (tone.committedText.empty() && tone.compositionText.empty() &&
         !tone.candidatesVisible)) {
        std::cerr << "Tone key produced neither text nor candidates.\n";
        return 3;
    }

    std::cout << "Traditional Bopomofo engine smoke test passed.\n";
    return 0;
}

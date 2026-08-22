#include "KeyKeyEngine.h"

#include <Windows.h>

#include <atomic>
#include <cstdlib>
#include <iostream>
#include <string>
#include <vector>

#include "ModuleState.h"
#include "PVCandidate.h"
#include "PVLoaderService.h"

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}  // namespace KeyKey::WindowsTsf

namespace {

using KeyKey::WindowsTsf::EngineResult;
using KeyKey::WindowsTsf::IsInputMethodControlKey;
using KeyKey::WindowsTsf::KeyEvent;
using KeyKey::WindowsTsf::KeyKeyEngineSession;
using namespace OpenVanilla;

bool Expect(bool condition, const char* message) {
    if (condition) return true;
    std::cerr << message << '\n';
    return false;
}

KeyEvent VirtualKey(UINT virtualKey) {
    KeyEvent event;
    event.virtualKey = virtualKey;
    event.numLock = true;
    return event;
}

KeyEvent Character(wchar_t character) {
    KeyEvent event = VirtualKey(static_cast<UINT>(
        character >= L'a' && character <= L'z' ? character - L'a' + 'A'
                                                : character));
    return event;
}

KeyEvent ControlKey(UINT virtualKey, bool alt = false, bool shift = false) {
    KeyEvent event = VirtualKey(virtualKey);
    event.control = true;
    event.alt = alt;
    event.shift = shift;
    return event;
}

bool TestPlainVanillaHomeAndEnd() {
    PVLoaderService loader;
    PVVerticalCandidatePanel panel(&loader);
    static_cast<OVOneDimensionalCandidatePanel&>(panel).setCandidateKeys(
        "123456789", &loader);
    panel.candidateList()->setCandidates(
        {"0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "11"});
    panel.show();
    if (!Expect(panel.yieldToCandidateEventHandler(),
                "Candidate panel did not enter keyboard control.")) {
        return false;
    }

    const auto endState = panel.handleKeyEvent(
        loader.makeOVKey(OVKeyCode::End), &loader);
    if (!Expect(endState == PVCandidateState::UpdateCandidateHighlight,
                "End was not handled as candidate navigation.") ||
        !Expect(panel.currentPage() == panel.pageCount() - 1,
                "End did not move to the final candidate page.") ||
        !Expect(panel.currentHightlightIndex() ==
                    panel.currentPageCandidateCount() - 1,
                "End did not highlight the final candidate.")) {
        return false;
    }

    const auto homeState = panel.handleKeyEvent(
        loader.makeOVKey(OVKeyCode::Home), &loader);
    return Expect(homeState == PVCandidateState::UpdateCandidateHighlight,
                  "Home was not handled as candidate navigation.") &&
           Expect(panel.currentPage() == 0,
                  "Home did not move to the first candidate page.") &&
           Expect(panel.currentHightlightIndex() == 0,
                  "Home did not highlight the first candidate.");
}

bool TestWindowsEngineCandidateKeys() {
    std::unique_ptr<KeyKeyEngineSession> session = KeyKeyEngineSession::Create();
    if (!Expect(session && session->ready(),
                "Engine did not initialize; check Databases/KeyKey.db.")) {
        return false;
    }

    session->handleKey(Character(L'1'));  // Standard layout: Bopomofo B.
    session->handleKey(Character(L'u'));  // Standard layout: Bopomofo I.
    EngineResult candidates = session->handleKey(Character(L'3'));  // Third tone.
    if (!Expect(candidates.handled && candidates.candidatesVisible &&
                    !candidates.candidates.empty(),
                "Bopomofo sequence did not open a candidate list.")) {
        return false;
    }

    KeyEvent copyShortcut = Character(L'c');
    copyShortcut.control = true;
    if (!Expect(!session->wantsKey(copyShortcut),
                "Ctrl+C was captured while candidates were visible.")) {
        return false;
    }

    KeyEvent altShortcut = Character(L'f');
    altShortcut.alt = true;
    if (!Expect(!session->wantsKey(altShortcut),
                "Alt+F was captured while candidates were visible.")) {
        return false;
    }

    KeyEvent modifiedNavigation = VirtualKey(VK_LEFT);
    modifiedNavigation.control = true;
    if (!Expect(!session->wantsKey(modifiedNavigation),
                "Ctrl+Left was captured while candidates were visible.")) {
        return false;
    }

    EngineResult last = session->handleKey(VirtualKey(VK_END));
    if (!Expect(last.handled && last.candidatesVisible && !last.candidates.empty(),
                "End closed or failed to update the candidate list.") ||
        !Expect(last.highlightedCandidate == last.candidates.size() - 1,
                "End did not expose the final candidate as highlighted.")) {
        return false;
    }

    EngineResult first = session->handleKey(VirtualKey(VK_HOME));
    return Expect(first.handled && first.candidatesVisible,
                  "Home closed or failed to update the candidate list.") &&
           Expect(first.highlightedCandidate == 0,
                  "Home did not expose the first candidate as highlighted.");
}

bool TestInputMethodControlKeyClassification() {
    for (UINT key = 'A'; key <= 'Z'; ++key) {
        if (!Expect(!IsInputMethodControlKey(ControlKey(key)),
                    "A general Ctrl+letter shortcut was captured.") ||
            !Expect(IsInputMethodControlKey(ControlKey(key, true)),
                    "A table-backed Ctrl+Alt+letter symbol was rejected.")) {
            return false;
        }
    }

    for (UINT key = '0'; key <= '9'; ++key) {
        const bool expected = key == '0' || key == '1';
        if (!Expect(IsInputMethodControlKey(ControlKey(key)) == expected,
                    "Ctrl+digit classification did not match the punctuation table.") ||
            !Expect(!IsInputMethodControlKey(ControlKey(key, true)),
                    "An undefined Ctrl+Alt+digit shortcut was captured.")) {
            return false;
        }
    }

    const UINT ctrlPunctuation[] = {
        VK_OEM_COMMA, VK_OEM_PERIOD, VK_OEM_1, VK_OEM_7, VK_OEM_4, VK_OEM_6,
    };
    for (UINT key : ctrlPunctuation) {
        if (!Expect(IsInputMethodControlKey(ControlKey(key)),
                    "A table-backed Ctrl+punctuation key was rejected.")) {
            return false;
        }
    }
    const UINT shiftedCtrlPunctuation[] = {
        VK_OEM_COMMA, VK_OEM_PERIOD, VK_OEM_2, VK_OEM_1, VK_OEM_7,
    };
    for (UINT key : shiftedCtrlPunctuation) {
        if (!Expect(IsInputMethodControlKey(ControlKey(key, false, true)),
                    "A Windows-only shifted Ctrl+punctuation key was rejected.")) {
            return false;
        }
    }

    const UINT ctrlAltPunctuation[] = {
        VK_OEM_1, VK_OEM_7, VK_OEM_COMMA, VK_OEM_PERIOD, VK_OEM_2,
    };
    for (UINT key : ctrlAltPunctuation) {
        if (!Expect(IsInputMethodControlKey(ControlKey(key, true)),
                    "A table-backed Ctrl+Alt+punctuation key was rejected.") ||
            !Expect(!IsInputMethodControlKey(ControlKey(key, true, true)),
                    "An undefined shifted Ctrl+Alt+punctuation key was captured.")) {
            return false;
        }
    }

    return Expect(!IsInputMethodControlKey(ControlKey('C')),
                  "Ctrl+C must remain an application shortcut.") &&
           Expect(!IsInputMethodControlKey(ControlKey(VK_LEFT)),
                  "Ctrl+Left must remain an application shortcut.") &&
           Expect(!IsInputMethodControlKey(VirtualKey(VK_MENU)),
                  "Alt without Ctrl must remain an application modifier.");
}

bool TestInputMethodControlKeyResults() {
    auto punctuationList = KeyKeyEngineSession::Create();
    if (!Expect(punctuationList && punctuationList->ready(),
                "Engine did not initialize for Ctrl symbol tests.")) {
        return false;
    }
    EngineResult list = punctuationList->handleKey(ControlKey('0'));
    if (!Expect(list.handled && list.candidatesVisible &&
                    list.candidates.size() > 1,
                "Ctrl+0 did not open the punctuation list.")) {
        return false;
    }

    auto punctuationListAlias = KeyKeyEngineSession::Create();
    EngineResult alias = punctuationListAlias->handleKey(ControlKey('1'));
    if (!Expect(alias.handled && alias.candidatesVisible,
                "Ctrl+1 did not open the punctuation list.")) {
        return false;
    }

    auto punctuation = KeyKeyEngineSession::Create();
    EngineResult semicolon = punctuation->handleKey(ControlKey(VK_OEM_1));
    if (!Expect(semicolon.handled && semicolon.committedText == L"\uFF1B",
                "Ctrl+semicolon did not commit the table-backed full-width symbol.")) {
        return false;
    }

    auto shiftedPunctuation = KeyKeyEngineSession::Create();
    EngineResult colon = shiftedPunctuation->handleKey(
        ControlKey(VK_OEM_1, false, true));
    if (!Expect(colon.handled && colon.committedText == L"\uFF1A",
                "Ctrl+Shift+semicolon did not commit the Windows colon entry.")) {
        return false;
    }

    auto ctrlAltSymbol = KeyKeyEngineSession::Create();
    EngineResult corner = ctrlAltSymbol->handleKey(ControlKey('Q', true));
    return Expect(corner.handled && corner.committedText == L"\u250C",
                  "Ctrl+Alt+Q did not commit the table-backed box symbol.");
}

}  // namespace

int main() {
    if (!TestPlainVanillaHomeAndEnd()) return 1;
    if (!TestWindowsEngineCandidateKeys()) return 2;
    if (!TestInputMethodControlKeyClassification()) return 3;
    if (!TestInputMethodControlKeyResults()) return 4;
    std::cout << "Candidate key state-machine test passed.\n";
    return 0;
}

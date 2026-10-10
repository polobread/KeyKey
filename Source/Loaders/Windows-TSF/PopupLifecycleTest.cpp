#include "CandidateWindow.h"
#include "ModuleState.h"
#include "SymbolPanel.h"

#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <algorithm>

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
struct PopupLifecycleTestAccess {
    static HWND window(const CandidateWindow& popup) { return popup.window_; }
    static void create(CandidateWindow& popup, HWND owner) { popup.ensureWindow(owner); }
    static HFONT font(const CandidateWindow& popup) { return popup.font_; }
    static bool empty(const CandidateWindow& popup) {
        return popup.candidates_.empty() && popup.cellWidths_.empty();
    }
};
struct SymbolPanelTestAccess {
    static HWND window(const SymbolPanel& popup) { return popup.window_; }
    static HWND item(const SymbolPanel& popup) { return GetDlgItem(popup.content_,100); }
    static void rememberPosition(SymbolPanel& popup) {
        RECT bounds{}; GetWindowRect(popup.window_, &bounds);
        popup.position_ = {bounds.left, bounds.top}; popup.hasPosition_ = true;
    }
    static std::vector<HFONT> fonts(const SymbolPanel& popup) {
        return {popup.font_, popup.symbolFont_, popup.emojiFont_};
    }
    static UINT dpi(const SymbolPanel& popup) { return popup.dpi_; }
};
}  // namespace KeyKey::WindowsTsf

namespace {
using namespace KeyKey::WindowsTsf;
constexpr RECT kAnchor{40, 40, 80, 70};
const std::vector<EngineCandidate> kCandidates{{L"1", L"candidate"}, {L"2", L"second"}};

void Check(bool condition, const char* message) {
    if (!condition) throw std::runtime_error(message);
}

std::vector<std::pair<DWORD,HWND>> imeEvents;
void CALLBACK RecordImeEvent(HWINEVENTHOOK,DWORD event,HWND window,LONG,LONG,DWORD,DWORD) {
    imeEvents.emplace_back(event,window);
}
void PumpMessages() {
    MSG message{};
    while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) { TranslateMessage(&message); DispatchMessageW(&message); }
}
int EventCount(DWORD event,HWND window) {
    PumpMessages();
    return static_cast<int>(std::count(imeEvents.begin(),imeEvents.end(),std::make_pair(event,window)));
}

struct Host {
    HWND window = CreateWindowExW(0, L"STATIC", L"KeyKey popup lifecycle test",
        WS_OVERLAPPEDWINDOW, 20, 20, 500, 250, nullptr, nullptr, g_module, nullptr);
    HWND edit = nullptr;
    Host() {
        Check(window != nullptr, "Cannot create native owner");
        edit = CreateWindowExW(0, L"EDIT", L"", WS_CHILD | WS_VISIBLE,
            10, 10, 200, 40, window, nullptr, g_module, nullptr);
        Check(edit != nullptr, "Cannot create native edit");
        ShowWindow(window, SW_SHOWNOACTIVATE);
        SetActiveWindow(window);
        SetFocus(edit);
    }
    ~Host() { if (window) DestroyWindow(window); }
    void destroy() { DestroyWindow(window); window = edit = nullptr; }
};

void CheckNoActivation(HWND active, HWND focused, HWND popup) {
    Check(GetActiveWindow() == active && GetFocus() == focused,
        "Popup stole owner activation or edit focus");
    Check(SendMessageW(popup, WM_MOUSEACTIVATE, 0, 0) == MA_NOACTIVATE,
        "Popup click must not activate its window");
}

void CandidateLifecycle() {
    CandidateWindow popup;
    popup.hide();
    popup.hide();
    Check(!PopupLifecycleTestAccess::window(popup), "Initial hide created a popup");
    Host host;
    PopupLifecycleTestAccess::create(popup, host.window);
    HWND window = PopupLifecycleTestAccess::window(popup);
    Check(window && !IsWindowVisible(window), "New popup must be initially hidden");
    popup.hide();
    Check(!IsWindow(window) && !PopupLifecycleTestAccess::window(popup),
        "Unused candidate HWND was not retired");
    Check(ShowOwnedPopups(host.window, TRUE) != FALSE, "Owner restore failed");
    Check(!IsWindowVisible(window), "Initially hidden popup appeared on owner restore");

    popup.show(host.window, kAnchor, kCandidates, 0);
    window = PopupLifecycleTestAccess::window(popup);
    const HFONT font = PopupLifecycleTestAccess::font(popup);
    Check(font && GetObjectType(font) == OBJ_FONT, "Candidate font missing");
    popup.hide();
    Check(!PopupLifecycleTestAccess::window(popup) && !IsWindow(window) &&
          PopupLifecycleTestAccess::empty(popup), "Normal cancel retained an empty candidate HWND");
    Check(PopupLifecycleTestAccess::font(popup) == font && GetObjectType(font) == OBJ_FONT,
        "Normal cancel discarded the reusable candidate font");
    Check(!SetWindowPos(window, HWND_TOPMOST, 0, 0, 0, 0,
                       SWP_NOACTIVATE | SWP_NOMOVE | SWP_NOSIZE | SWP_SHOWWINDOW),
        "A canceled candidate HWND can still be shown topmost");
    popup.show(host.window, kAnchor, kCandidates, 0);
    window = PopupLifecycleTestAccess::window(popup);
    Check(ShowOwnedPopups(host.window, FALSE) != FALSE &&
          ShowOwnedPopups(host.window, TRUE) != FALSE && IsWindowVisible(window) &&
          !PopupLifecycleTestAccess::empty(popup),
        "Temporary owner hide must restore live candidate content");

    // A host restoration message already queued before cancellation cannot
    // act on the empty old popup. No new HWND is created until a new result.
    Check(PostMessageW(window, WM_SHOWWINDOW, TRUE, SW_PARENTOPENING) != FALSE,
        "Cannot queue owner restore for candidate");
    popup.hide();
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) DispatchMessageW(&message);
    Check(!IsWindow(window) && !PopupLifecycleTestAccess::window(popup),
        "Queued owner restore retained a canceled candidate");

    for (int cycle = 0; cycle < 5; ++cycle) {
        const HWND active = GetActiveWindow(), focused = GetFocus();
        popup.show(host.window, kAnchor, kCandidates, 0);
        window = PopupLifecycleTestAccess::window(popup);
        Check(IsWindowVisible(window), "Candidate did not show");
        Check(GetWindow(window, GW_OWNER) == host.window, "Candidate has wrong owner");
        CheckNoActivation(active, focused, window);
        Check(ShowOwnedPopups(host.window, FALSE) != FALSE, "Owner popup hide failed");
        Check(!IsWindowVisible(window), "Owner did not temporarily hide candidate");
        popup.hide();
        popup.hide();
        Check(!IsWindow(window), "Suppressed candidate HWND was not retired");
        Check(PopupLifecycleTestAccess::empty(popup), "Hide retained candidate content");
        Check(ShowOwnedPopups(host.window, TRUE) != FALSE, "Owner popup restore failed");
        Check(!PopupLifecycleTestAccess::window(popup) ||
              !IsWindowVisible(PopupLifecycleTestAccess::window(popup)),
            "Owner restore reopened an empty candidate popup");
    }
    popup.show(host.window, kAnchor, kCandidates, 1);
    host.destroy();
    Check(!PopupLifecycleTestAccess::window(popup), "Destroyed owner retained candidate HWND");
    popup.hide();
    Host replacement;
    popup.show(replacement.window, kAnchor, kCandidates, 0);
    window = PopupLifecycleTestAccess::window(popup);
    Check(window && IsWindowVisible(window) && GetWindow(window, GW_OWNER) == replacement.window,
        "Candidate did not recreate for replacement owner");
    CheckNoActivation(replacement.window, replacement.edit, window);
    Check(ShowOwnedPopups(replacement.window, FALSE) != FALSE, "Replacement owner hide failed");
    popup.show(replacement.window, kAnchor, {}, 0);
    Check(ShowOwnedPopups(replacement.window, TRUE) != FALSE, "Replacement owner restore failed");
    Check(!PopupLifecycleTestAccess::window(popup) ||
          !IsWindowVisible(PopupLifecycleTestAccess::window(popup)),
        "Empty candidate update returned on owner restore");
    popup.hide();

    // A busy host can delay painting after the first candidate is shown.
    // Cancel without pumping WM_PAINT: the pending blank surface must retire,
    // and the next result must still have a valid region that can be painted.
    popup.show(replacement.window, kAnchor, kCandidates, 0);
    window = PopupLifecycleTestAccess::window(popup);
    Check(GetUpdateRect(window, nullptr, FALSE) != FALSE,
        "First candidate paint was not pending for delayed-paint check");
    popup.hide();
    Check(!IsWindow(window) && !PopupLifecycleTestAccess::window(popup),
        "Cancel before painting retained a candidate HWND");
    popup.show(replacement.window, kAnchor, kCandidates, 1);
    window = PopupLifecycleTestAccess::window(popup);
    Check(UpdateWindow(window) != FALSE &&
          !GetUpdateRect(window, nullptr, FALSE) && IsWindowVisible(window),
        "Candidate did not paint after a delayed-paint cancellation");
    CheckNoActivation(replacement.window, replacement.edit, window);
    popup.hide();
}

void SymbolLifecycle() {
    SymbolPanel popup;
    popup.hide();
    Host host;
    int selections = 0;
    const auto select = [&](const std::wstring&) { ++selections; };
    const HWND active = GetActiveWindow(), focused = GetFocus();
    Check(popup.show(host.window, kAnchor, select), "Symbol panel did not show");
    HWND window = SymbolPanelTestAccess::window(popup);
    HWND firstItem = SymbolPanelTestAccess::item(popup);
    Check(firstItem && IsWindowEnabled(firstItem), "Symbol item missing for stale command check");
    CheckNoActivation(active, focused, window);
    popup.hide();
    Check(!SymbolPanelTestAccess::window(popup) && !IsWindow(window),
        "Normal symbol cancellation retained its native surface");
    Check(!SetWindowPos(window,HWND_TOPMOST,0,0,0,0,
        SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE|SWP_SHOWWINDOW),
        "Canceled symbol HWND can still be shown topmost");
    SendMessageW(window, WM_COMMAND, MAKEWPARAM(100, BN_CLICKED),
        reinterpret_cast<LPARAM>(firstItem));
    Check(selections == 0, "Normally hidden symbol panel dispatched stale selection");
    Check(popup.show(host.window, kAnchor, select), "Symbol panel did not reopen for suppression");
    window = SymbolPanelTestAccess::window(popup);
    firstItem = SymbolPanelTestAccess::item(popup);
    Check(firstItem && IsWindowEnabled(firstItem), "Reopened symbol item missing");
    Check(ShowOwnedPopups(host.window, FALSE) != FALSE &&
          ShowOwnedPopups(host.window, TRUE) != FALSE && popup.visible(),
        "Temporary owner hide must restore live symbols");
    // Record a real displayed position, as the completed drag handler does.
    SymbolPanelTestAccess::rememberPosition(popup);
    RECT before{}; GetWindowRect(window, &before);
    const auto fonts = SymbolPanelTestAccess::fonts(popup);
    const auto dpi = SymbolPanelTestAccess::dpi(popup);
    Check(ShowOwnedPopups(host.window, FALSE) != FALSE, "Owner symbol hide failed");
    Check(!popup.visible(), "Owner did not temporarily hide symbols");
    popup.hide();
    popup.hide();
    Check(!IsWindow(window), "Suppressed symbol HWND was not retired");
    Check(SymbolPanelTestAccess::fonts(popup) == fonts,
        "Retiring suppressed symbols discarded font resources");
    for (HFONT font : fonts) Check(GetObjectType(font) == OBJ_FONT, "Retired symbols deleted a live font");
    Check(ShowOwnedPopups(host.window, TRUE) != FALSE, "Owner symbol restore failed");
    Check(!popup.visible(), "Explicitly hidden symbols returned on owner restore");
    Check(selections == 0, "Suppressed symbol panel dispatched stale selection");
    Check(popup.show(host.window, kAnchor, select), "Symbol panel did not reopen");
    window = SymbolPanelTestAccess::window(popup);
    RECT reopened{}; GetWindowRect(window, &reopened);
    Check(reopened.left == before.left && reopened.top == before.top &&
          SymbolPanelTestAccess::dpi(popup) == dpi,
        "Recreated symbols lost remembered position or DPI");
    CheckNoActivation(active, focused, window);
    firstItem = SymbolPanelTestAccess::item(popup);
    Check(firstItem && IsWindowEnabled(firstItem), "Recreated symbol item missing");
    SendMessageW(window, WM_COMMAND, MAKEWPARAM(100, BN_CLICKED),
        reinterpret_cast<LPARAM>(firstItem));
    Check(selections == 1 && !popup.visible(), "Recreated symbol callback did not select and close");
    Check(popup.show(host.window, kAnchor, select), "Symbol panel did not reopen before owner destruction");
    host.destroy();
    Check(!SymbolPanelTestAccess::window(popup), "Destroyed owner retained symbol HWND");
    Host replacement;
    Check(popup.show(replacement.window, kAnchor, select), "Symbols did not recreate for replacement owner");
    CheckNoActivation(replacement.window, replacement.edit, SymbolPanelTestAccess::window(popup));
    popup.hide();
    // Cancel before painting and with an owner-restore message already queued.
    Check(popup.show(replacement.window,kAnchor,select),"Delayed symbol panel show");
    window=SymbolPanelTestAccess::window(popup);
    Check(PostMessageW(window,WM_SHOWWINDOW,TRUE,SW_PARENTOPENING)!=FALSE,
        "Cannot queue owner restore for symbols");
    popup.hide(); PumpMessages();
    Check(!IsWindow(window) && !SymbolPanelTestAccess::window(popup) && selections==1,
        "Queued owner restore retained canceled symbols or selected stale text");
    Check(popup.show(replacement.window,kAnchor,select),"Reopen canceled symbols");
    window=SymbolPanelTestAccess::window(popup);
    Check(UpdateWindow(window)!=FALSE && IsWindowVisible(window),"Recreated symbols did not paint");
    popup.hide();
}

void LightDismissEvents() {
    const auto hook=SetWinEventHook(EVENT_OBJECT_IME_SHOW,EVENT_OBJECT_IME_CHANGE,nullptr,
        RecordImeEvent,GetCurrentProcessId(),GetCurrentThreadId(),WINEVENT_OUTOFCONTEXT);
    Check(hook!=nullptr,"Cannot observe IME light-dismiss notifications");
    Host host;
    {
        CandidateWindow popup; popup.show(host.window,kAnchor,kCandidates,0);
        const HWND window=PopupLifecycleTestAccess::window(popup);
        Check(EventCount(EVENT_OBJECT_IME_SHOW,window)==1,"Candidate missing SHOW event");
        RECT moved=kAnchor; moved.left+=20; moved.right+=20;
        popup.show(host.window,moved,kCandidates,1);
        Check(EventCount(EVENT_OBJECT_IME_SHOW,window)==1,"Candidate update repeated SHOW event");
        Check(EventCount(EVENT_OBJECT_IME_CHANGE,window)>=1,"Candidate move missing CHANGE event");
        ShowOwnedPopups(host.window,FALSE);
        Check(EventCount(EVENT_OBJECT_IME_HIDE,window)==1,"Owner-hidden candidate missing HIDE event");
        ShowOwnedPopups(host.window,TRUE);
        Check(EventCount(EVENT_OBJECT_IME_SHOW,window)==2,"Owner-restored candidate missing SHOW event");
        popup.hide();
        Check(EventCount(EVENT_OBJECT_IME_HIDE,window)==2,"Canceled candidate missing HIDE event");
    }
    imeEvents.clear();
    {
        SymbolPanel popup;
        Check(popup.show(host.window,kAnchor,[](const std::wstring&){}),"Symbol event panel show");
        const HWND window=SymbolPanelTestAccess::window(popup);
        Check(EventCount(EVENT_OBJECT_IME_SHOW,window)==1,"Symbols missing SHOW event");
        RECT bounds{}; GetWindowRect(window,&bounds);
        SetWindowPos(window,nullptr,bounds.left+10,bounds.top+10,0,0,SWP_NOACTIVATE|SWP_NOSIZE|SWP_NOZORDER);
        Check(EventCount(EVENT_OBJECT_IME_CHANGE,window)>=1,"Symbol move missing CHANGE event");
        ShowOwnedPopups(host.window,FALSE);
        Check(EventCount(EVENT_OBJECT_IME_HIDE,window)==1,"Owner-hidden symbols missing HIDE event");
        ShowOwnedPopups(host.window,TRUE);
        Check(EventCount(EVENT_OBJECT_IME_SHOW,window)==2,"Owner-restored symbols missing SHOW event");
        popup.hide();
        Check(EventCount(EVENT_OBJECT_IME_HIDE,window)==2,"Canceled symbols missing HIDE event");
    }
    UnhookWinEvent(hook);
}
}  // namespace

int main() {
    try {
        KeyKey::WindowsTsf::g_module = GetModuleHandleW(nullptr);
        // Keep popup preferences and panel positions outside the user's profile.
        const auto directory = std::filesystem::current_path() /
            (L"popup-lifecycle-test-profile-" + std::to_wstring(GetCurrentProcessId()));
        std::filesystem::create_directories(directory);
        Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", directory.c_str()) != FALSE,
            "Cannot isolate popup test preferences");
        CandidateLifecycle();
        SymbolLifecycle();
        LightDismissEvents();
        std::cout << "Candidate and symbol popup native lifecycle checks passed\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

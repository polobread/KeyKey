#include "SymbolPanel.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include <iostream>
#include <stdexcept>
namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}
using namespace KeyKey::WindowsTsf;
void Check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
int main() {
    try {
        g_module = GetModuleHandleW(nullptr);
        const auto& categories = BuiltinSymbolCategories();
        Check(categories.size() == 17, "All plist categories must be embedded");
        size_t count = 0;
        bool longMessage = false;
        for (const auto& category : categories) {
            Check(!category.name.empty() && !category.items.empty(), "Empty category");
            for (const auto& item : category.items) {
                Check(!item.label.empty() && !item.text.empty(), "Empty item");
                ++count;
                if (item.text == L"v(\xFFE3\xFE36\xFFE3)y \x5F97\x610F\x3001YA~") longMessage = true;
            }
        }
        Check(count == 807, "All 733 Buttons and 74 Messages must be embedded");
        Check(longMessage, "Full message text must survive generation");
        HWND host = CreateWindowExW(0, L"EDIT", L"", WS_POPUP, 0,0,100,100,
                                    nullptr, nullptr, g_module, nullptr);
        Check(host != nullptr, "Host creation");
        SetFocus(host);
        HWND focus = GetFocus();
        SymbolPanel panel;
        RECT anchor{20,20,30,40};
        int calls = 0; std::wstring chosen;
        Check(panel.show(host, anchor, [&](const std::wstring& text) { ++calls; chosen = text; }), "Panel creation");
        HWND hwnd = FindWindowW(L"chichi77.KeyKey.TSF.SymbolPanel", nullptr);
        Check(hwnd && panel.visible(), "Panel visible");
        Check(GetWindowLongPtrW(hwnd, GWL_EXSTYLE) & WS_EX_NOACTIVATE, "Noactivate style");
        Check(GetFocus() == focus, "Showing panel keeps host focus");
        HWND item = GetDlgItem(hwnd, 100);
        SendMessageW(item, WM_LBUTTONDOWN, MK_LBUTTON, MAKELPARAM(5,5));
        Check(GetFocus() == focus, "Press keeps host focus");
        SendMessageW(item, WM_LBUTTONUP, 0, MAKELPARAM(5,5));
        Check(calls == 1 && chosen == categories[0].items[0].text && !panel.visible(), "Click inserts once and closes");
        SendMessageW(hwnd, WM_COMMAND, MAKEWPARAM(100, BN_CLICKED), reinterpret_cast<LPARAM>(item));
        Check(calls == 1, "Stale click ignored");
        Check(panel.show(host, anchor, [&](const std::wstring&) { ++calls; }), "Reopen");
        SendMessageW(hwnd, WM_COMMAND, MAKEWPARAM(5, BN_CLICKED), 0);
        item = GetDlgItem(hwnd, 100);
        int length = GetWindowTextLengthW(item);
        std::wstring next(static_cast<size_t>(length)+1,L'\0');
        GetWindowTextW(item,next.data(),length+1); next.resize(length);
        Check(next == categories[0].items[8].label, "Page contains next complete item");
        SendMessageW(hwnd, WM_CLOSE, 0, 0);
        Check(calls == 1 && !panel.visible(), "Close cancels without selection");
        Check(panel.show(host, anchor, [&](const std::wstring&) { ++calls; }), "Reopen after cancel");
        SendMessageW(hwnd, WM_KEYDOWN, VK_ESCAPE, 0);
        Check(calls == 1 && !panel.visible(), "Escape cancels");
        DestroyWindow(host);
        Check(panel.show(nullptr, anchor, [&](const std::wstring&) { ++calls; }), "Reopen after owner destruction");
        Check(panel.visible(), "Recreated ownerless panel visible");
        panel.hide();
        std::cout << "Symbol resources and passive panel tests passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}

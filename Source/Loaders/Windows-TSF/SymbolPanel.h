#pragma once
#include <Windows.h>
#include <functional>
#include <string>
#include <vector>

namespace KeyKey::WindowsTsf {
// The owner validates its captured TSF context in the selection callback.
// hide() invalidates callbacks before any subsequent mouse message can select.
class SymbolPanel final {
public:
    using Selection = std::function<void(const std::wstring&)>;
    SymbolPanel() = default;
    ~SymbolPanel();
    SymbolPanel(const SymbolPanel&) = delete;
    SymbolPanel& operator=(const SymbolPanel&) = delete;
    bool show(HWND owner, const RECT& anchor, Selection selection);
    void hide();
    bool visible() const { return window_ && IsWindowVisible(window_); }
private:
    static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM);
    LRESULT message(UINT, WPARAM, LPARAM);
    void rebuild();
    void page(int delta);
    int scaled(int value) const;
    HWND window_ = nullptr;
    HFONT font_ = nullptr;
    HBRUSH background_ = nullptr;
    std::vector<HWND> controls_;
    Selection selection_;
    size_t category_ = 0;
    size_t page_ = 0;
    UINT dpi_ = 96;
    COLORREF foreground_ = RGB(0,0,0);
    COLORREF backgroundColor_ = RGB(255,255,255);
};
} // namespace KeyKey::WindowsTsf

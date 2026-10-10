#pragma once
#include <Windows.h>
#include <functional>
#include <memory>
#include <string>
#include <vector>

namespace KeyKey::WindowsTsf {
// The owner validates its captured TSF context in the selection callback.
// hide() invalidates callbacks before any subsequent mouse message can select.
class SymbolPanel final {
public:
    using Selection = std::function<void(const std::wstring&)>;
    SymbolPanel();
    ~SymbolPanel();
    SymbolPanel(const SymbolPanel&) = delete;
    SymbolPanel& operator=(const SymbolPanel&) = delete;
    bool show(HWND owner, const RECT& anchor, Selection selection);
    void hide();
    bool visible() const { return window_ && IsWindowVisible(window_); }
private:
    friend struct SymbolPanelTestAccess;
    static LRESULT CALLBACK WindowProc(HWND, UINT, WPARAM, LPARAM);
    static LRESULT CALLBACK ContentProc(HWND, UINT, WPARAM, LPARAM);
    LRESULT message(UINT, WPARAM, LPARAM);
    void rebuild();
    void scrollTo(int offset);
    void scrollWheel(int delta);
    void chooseCategory();
    void updateFonts();
    bool drawColorEmoji(HDC dc, const RECT& bounds, const std::wstring& text,
                        COLORREF background, COLORREF foreground);
    void position(const RECT& desired);
    int scaled(int value) const;
    HWND window_ = nullptr;
    HWND viewport_ = nullptr;
    HWND content_ = nullptr;
    HWND scrollbar_ = nullptr;
    HFONT font_ = nullptr;
    HFONT symbolFont_ = nullptr;
    HFONT emojiFont_ = nullptr;
    HBRUSH background_ = nullptr;
    struct ColorEmojiRenderer;
    std::unique_ptr<ColorEmojiRenderer> colorEmoji_;
    bool highContrast_ = false;
    std::vector<HWND> controls_;
    Selection selection_;
    std::shared_ptr<bool> alive_ = std::make_shared<bool>(true);
    size_t category_ = 0;
    UINT dpi_ = 96;
    UINT hostDpi_ = 96;
    int scalePercent_ = 0;
    UINT fontDpi_ = 0;
    size_t columns_ = 10;
    size_t renderedCategory_ = static_cast<size_t>(-1);
    int scrollOffset_ = 0;
    int contentHeight_ = 0;
    int viewportHeight_ = 0;
    int rowStep_ = 40;
    int wheelRemainder_ = 0;
    unsigned emojiRasterizations_ = 0;
    unsigned long generation_ = 0;
    bool menuOpen_ = false;
    bool dragging_ = false;
    bool hasPosition_ = false;
    POINT position_{};
    POINT dragStart_{};
    POINT dragOrigin_{};
    COLORREF foreground_ = RGB(0,0,0);
    COLORREF backgroundColor_ = RGB(255,255,255);
};
} // namespace KeyKey::WindowsTsf

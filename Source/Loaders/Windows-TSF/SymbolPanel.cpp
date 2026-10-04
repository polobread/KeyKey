#include "SymbolPanel.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include <algorithm>
#include <mutex>

namespace KeyKey::WindowsTsf {
namespace {
constexpr wchar_t kClass[] = L"chichi77.KeyKey.TSF.SymbolPanel";
constexpr size_t kPageSize = 8;
constexpr UINT kPreviousCategory = 1, kNextCategory = 2, kClose = 3;
constexpr UINT kPreviousPage = 4, kNextPage = 5, kFirstItem = 100;
std::once_flag registration;
bool registered = false;
// Keep standard BUTTON names/accessibility, but bypass its mouse SetFocus path.
LRESULT CALLBACK PassiveButtonProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    auto original = reinterpret_cast<WNDPROC>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg == WM_LBUTTONDOWN) {
        SetCapture(hwnd);
        SendMessageW(hwnd, BM_SETSTATE, TRUE, 0);
        return 0;
    }
    if (msg == WM_LBUTTONUP && GetCapture() == hwnd) {
        ReleaseCapture();
        SendMessageW(hwnd, BM_SETSTATE, FALSE, 0);
        RECT rect{}; GetClientRect(hwnd, &rect);
        POINT point{static_cast<short>(LOWORD(lp)), static_cast<short>(HIWORD(lp))};
        if (PtInRect(&rect, point))
            SendMessageW(GetParent(hwnd), WM_COMMAND,
                MAKEWPARAM(GetDlgCtrlID(hwnd), BN_CLICKED), reinterpret_cast<LPARAM>(hwnd));
        return 0;
    }
    if (msg == WM_CAPTURECHANGED) SendMessageW(hwnd, BM_SETSTATE, FALSE, 0);
    return CallWindowProcW(original, hwnd, msg, wp, lp);
}
bool DarkAppearance() {
    DWORD light = 1, bytes = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
    HIGHCONTRASTW contrast{sizeof(contrast)};
    SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
    return !light && !(contrast.dwFlags & HCF_HIGHCONTRASTON);
}
}

SymbolPanel::~SymbolPanel() {
    hide();
    if (window_) DestroyWindow(window_);
    if (font_) DeleteObject(font_);
    if (background_) DeleteObject(background_);
}
int SymbolPanel::scaled(int value) const { return MulDiv(value, dpi_, 96); }
bool SymbolPanel::show(HWND owner, const RECT& anchor, Selection selection) {
    hide();
    if (!selection || BuiltinSymbolCategories().empty()) return false;
    std::call_once(registration, [] {
        WNDCLASSEXW wc{sizeof(wc)};
        wc.hInstance = g_module;
        wc.lpfnWndProc = WindowProc;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        wc.lpszClassName = kClass;
        registered = RegisterClassExW(&wc) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    });
    if (!registered) return false;
    if (!window_) window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        kClass, L"\x7B26\x865F\x8868", WS_POPUP | WS_BORDER,
        0, 0, 1, 1, owner, nullptr, g_module, this);
    if (!window_) return false;
    SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
    dpi_ = owner ? GetDpiForWindow(owner) : GetDpiForWindow(window_);
    if (!dpi_) dpi_ = 96;
    if (font_) DeleteObject(font_);
    font_ = CreateFontW(-scaled(16), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
        DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
        DEFAULT_PITCH, L"Segoe UI");
    foreground_ = DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
    backgroundColor_ = DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
    if (background_) DeleteObject(background_);
    background_ = CreateSolidBrush(backgroundColor_);
    MONITORINFO monitor{sizeof(monitor)};
    GetMonitorInfoW(MonitorFromRect(&anchor, MONITOR_DEFAULTTONEAREST), &monitor);
    int width = std::min(scaled(520), static_cast<int>(monitor.rcWork.right - monitor.rcWork.left));
    int height = std::min(scaled(540), static_cast<int>(monitor.rcWork.bottom - monitor.rcWork.top));
    int x = std::clamp(static_cast<int>(anchor.left), static_cast<int>(monitor.rcWork.left),
                       static_cast<int>(monitor.rcWork.right) - width);
    int y = anchor.bottom + scaled(2);
    if (y + height > monitor.rcWork.bottom) y = anchor.top - height;
    y = std::clamp(y, static_cast<int>(monitor.rcWork.top), static_cast<int>(monitor.rcWork.bottom) - height);
    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
    page_ = 0;
    selection_ = std::move(selection);
    rebuild();
    ShowWindow(window_, SW_SHOWNOACTIVATE);
    return true;
}
void SymbolPanel::hide() {
    selection_ = {};
    if (window_) ShowWindow(window_, SW_HIDE);
}
void SymbolPanel::page(int delta) {
    const size_t count = BuiltinSymbolCategories()[category_].items.size();
    const size_t pages = std::max<size_t>(1, (count + kPageSize - 1) / kPageSize);
    if (delta < 0 && page_ > 0) --page_;
    if (delta > 0 && page_ + 1 < pages) ++page_;
    rebuild();
}
void SymbolPanel::rebuild() {
    for (HWND control : controls_) DestroyWindow(control);
    controls_.clear();
    RECT rect{}; GetClientRect(window_, &rect);
    const int gap = scaled(6), toolbar = scaled(38);
    auto button = [&](UINT id, const std::wstring& label, int x, int y, int w, int h) {
        HWND control = CreateWindowExW(WS_EX_NOACTIVATE, L"BUTTON", label.c_str(),
            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW | BS_MULTILINE,
            x, y, w, h, window_, reinterpret_cast<HMENU>(static_cast<UINT_PTR>(id)), g_module, nullptr);
        SendMessageW(control, WM_SETFONT, reinterpret_cast<WPARAM>(font_), FALSE);
        auto original = reinterpret_cast<WNDPROC>(SetWindowLongPtrW(control, GWLP_WNDPROC,
            reinterpret_cast<LONG_PTR>(PassiveButtonProc)));
        SetWindowLongPtrW(control, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(original));
        controls_.push_back(control);
    };
    const auto& categories = BuiltinSymbolCategories();
    const auto& category = categories[category_];
    button(kPreviousCategory, L"\x4E0A\x4E00\x5206\x985E", gap, gap, scaled(80), toolbar);
    button(kNextCategory, L"\x4E0B\x4E00\x5206\x985E", rect.right - scaled(80)-toolbar - 3*gap, gap, scaled(80), toolbar);
    button(kClose, L"\x95DC\x9589", rect.right-toolbar-gap, gap, toolbar, toolbar);
    const int top = toolbar + 2*gap, footer = rect.bottom - toolbar - gap;
    const int row = std::max(1, (footer - top - gap) / static_cast<int>(kPageSize));
    for (size_t i = 0; i < kPageSize && page_*kPageSize+i < category.items.size(); ++i) {
        button(kFirstItem + static_cast<UINT>(i), category.items[page_*kPageSize+i].label,
               gap, top + static_cast<int>(i)*row, rect.right-2*gap, row-gap);
    }
    button(kPreviousPage, L"\x4E0A\x4E00\x9801", gap, footer, scaled(100), toolbar);
    button(kNextPage, L"\x4E0B\x4E00\x9801", rect.right-scaled(100)-gap, footer, scaled(100), toolbar);
    EnableWindow(controls_[controls_.size()-2], page_ > 0);
    EnableWindow(controls_.back(), (page_+1)*kPageSize < category.items.size());
    InvalidateRect(window_, nullptr, TRUE);
}
LRESULT CALLBACK SymbolPanel::WindowProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    auto self = reinterpret_cast<SymbolPanel*>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (msg == WM_NCCREATE) {
        self = static_cast<SymbolPanel*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
        self->window_ = hwnd;
        SetWindowLongPtrW(hwnd, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }
    return self ? self->message(msg, wp, lp) : DefWindowProcW(hwnd, msg, wp, lp);
}
LRESULT SymbolPanel::message(UINT msg, WPARAM wp, LPARAM lp) {
    switch (msg) {
    case WM_NCDESTROY: {
        HWND destroyed = window_;
        selection_ = {};
        controls_.clear();
        window_ = nullptr;
        SetWindowLongPtrW(destroyed, GWLP_USERDATA, 0);
        return DefWindowProcW(destroyed, msg, wp, lp);
    }
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_CLOSE: hide(); return 0;
    case WM_DPICHANGED: {
        dpi_ = HIWORD(wp);
        if (font_) DeleteObject(font_);
        font_ = CreateFontW(-scaled(16), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH, L"Segoe UI");
        RECT rect = *reinterpret_cast<RECT*>(lp);
        MONITORINFO monitor{sizeof(monitor)};
        if (GetMonitorInfoW(MonitorFromRect(&rect, MONITOR_DEFAULTTONEAREST), &monitor)) {
            int width = std::min(static_cast<int>(rect.right-rect.left), static_cast<int>(monitor.rcWork.right-monitor.rcWork.left));
            int height = std::min(static_cast<int>(rect.bottom-rect.top), static_cast<int>(monitor.rcWork.bottom-monitor.rcWork.top));
            int x = std::clamp(static_cast<int>(rect.left), static_cast<int>(monitor.rcWork.left), static_cast<int>(monitor.rcWork.right)-width);
            int y = std::clamp(static_cast<int>(rect.top), static_cast<int>(monitor.rcWork.top), static_cast<int>(monitor.rcWork.bottom)-height);
            SetWindowPos(window_, nullptr, x, y, width, height, SWP_NOACTIVATE | SWP_NOZORDER);
        }
        rebuild(); return 0;
    }
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
        foreground_ = DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
        backgroundColor_ = DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
        if (background_) DeleteObject(background_);
        background_ = CreateSolidBrush(backgroundColor_);
        if (font_) rebuild();
        return 0;
    case WM_KEYDOWN: if (wp == VK_ESCAPE) { hide(); return 0; } break;
    case WM_MOUSEWHEEL: page(GET_WHEEL_DELTA_WPARAM(wp) > 0 ? -1 : 1); return 0;
    case WM_COMMAND: {
        if (!visible() || !selection_ || HIWORD(wp) != BN_CLICKED) return 0;
        UINT id = LOWORD(wp);
        if (id == kClose) hide();
        else if (id == kPreviousPage || id == kNextPage) page(id == kPreviousPage ? -1 : 1);
        else if (id == kPreviousCategory || id == kNextCategory) {
            size_t count = BuiltinSymbolCategories().size();
            category_ = (category_ + (id == kPreviousCategory ? count-1 : 1)) % count;
            page_ = 0; rebuild();
        } else if (id >= kFirstItem && id < kFirstItem+kPageSize) {
            size_t index = page_*kPageSize + id-kFirstItem;
            const auto& items = BuiltinSymbolCategories()[category_].items;
            if (index < items.size()) {
                std::wstring text = items[index].text;
                auto callback = std::move(selection_);
                hide(); // Invalidates double clicks before invoking TSF owner.
                callback(text);
            }
        }
        return 0;
    }
    case WM_ERASEBKGND: {
        RECT rect{}; GetClientRect(window_, &rect);
        FillRect(reinterpret_cast<HDC>(wp), &rect, background_); return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps{}; HDC dc = BeginPaint(window_, &ps);
        SelectObject(dc, font_); SetBkMode(dc, TRANSPARENT); SetTextColor(dc, foreground_);
        RECT rect{}; GetClientRect(window_, &rect);
        rect.left = scaled(92); rect.right -= scaled(140); rect.top = scaled(6); rect.bottom = scaled(44);
        const auto& category = BuiltinSymbolCategories()[category_];
        DrawTextW(dc, category.name.c_str(), -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        GetClientRect(window_, &rect);
        rect.left = scaled(110); rect.right -= scaled(110); rect.top = rect.bottom-scaled(44);
        std::wstring label = std::to_wstring(page_+1) + L" / " +
            std::to_wstring(std::max<size_t>(1,(category.items.size()+kPageSize-1)/kPageSize));
        DrawTextW(dc, label.c_str(), -1, &rect, DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        EndPaint(window_, &ps); return 0;
    }
    case WM_DRAWITEM: {
        auto draw = reinterpret_cast<DRAWITEMSTRUCT*>(lp);
        FillRect(draw->hDC, &draw->rcItem, background_);
        FrameRect(draw->hDC, &draw->rcItem, GetSysColorBrush(COLOR_GRAYTEXT));
        SelectObject(draw->hDC, font_); SetBkMode(draw->hDC, TRANSPARENT);
        SetTextColor(draw->hDC, draw->itemState & ODS_DISABLED ? GetSysColor(COLOR_GRAYTEXT) : foreground_);
        int length = GetWindowTextLengthW(draw->hwndItem);
        std::wstring label(static_cast<size_t>(length)+1, L'\0');
        GetWindowTextW(draw->hwndItem, label.data(), length+1);
        RECT text = draw->rcItem; InflateRect(&text, -scaled(4), -scaled(2));
        DrawTextW(draw->hDC, label.c_str(), length, &text, DT_CENTER | DT_WORDBREAK | DT_NOPREFIX);
        return TRUE;
    }
    }
    return DefWindowProcW(window_, msg, wp, lp);
}
} // namespace KeyKey::WindowsTsf

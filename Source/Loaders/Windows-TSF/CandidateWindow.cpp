#include "CandidateWindow.h"

#include <algorithm>
#include <mutex>

#include "FrontendSettings.h"
#include "ModuleState.h"

namespace KeyKey::WindowsTsf {
namespace {

constexpr wchar_t kCandidateWindowClass[] = L"chichi77.KeyKey.TSF.CandidateWindow";
constexpr int kHorizontalPadding = 10;
constexpr int kVerticalPadding = 5;
constexpr int kRowGap = 2;
constexpr int kTextGap = 12;
constexpr int kMinimumWidth = 80;
constexpr int kAnchorGap = 2;

std::once_flag g_windowClassOnce;
bool g_windowClassRegistered = false;

int ScaleForDpi(int value, UINT dpi) {
    return MulDiv(value, static_cast<int>(dpi), USER_DEFAULT_SCREEN_DPI);
}

}  // namespace

CandidateWindow::~CandidateWindow() {
    if (window_) {
        DestroyWindow(window_);
    }
    if (font_) {
        DeleteObject(font_);
    }
}

bool CandidateWindow::ensureWindowClass() {
    std::call_once(g_windowClassOnce, [] {
        WNDCLASSEXW windowClass{};
        windowClass.cbSize = sizeof(windowClass);
        windowClass.hInstance = g_module;
        windowClass.lpfnWndProc = CandidateWindow::WindowProc;
        windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
        windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
        windowClass.lpszClassName = kCandidateWindowClass;
        g_windowClassRegistered = RegisterClassExW(&windowClass) != 0 ||
                                  GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    });
    return g_windowClassRegistered;
}

void CandidateWindow::ensureWindow(HWND owner) {
    if (window_ || !ensureWindowClass()) {
        return;
    }

    window_ = CreateWindowExW(
        WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE,
        kCandidateWindowClass,
        L"",
        WS_POPUP | WS_BORDER,
        0,
        0,
        1,
        1,
        owner,
        nullptr,
        g_module,
        this);
}

void CandidateWindow::show(HWND owner, const RECT& textRect,
                           const std::vector<EngineCandidate>& candidates,
                           size_t highlightedIndex) {
    candidates_ = candidates;
    highlightedIndex_ = highlightedIndex;
    const FrontendSettings settings = LoadFrontendSettings();
    horizontal_ = settings.candidateLayout == CandidateLayout::Horizontal;
    highlightColor_ = HighlightColorValue(settings.highlightColor);
    ensureWindow(owner);
    if (!window_ || candidates_.empty()) {
        hide();
        return;
    }

    SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));

    UINT dpi = owner ? GetDpiForWindow(owner) : 0;
    if (!dpi) {
        dpi = GetDpiForWindow(window_);
    }
    updateFont(dpi ? dpi : USER_DEFAULT_SCREEN_DPI);
    const SIZE contentSize = measureContent();
    const SIZE windowSize = windowSizeForContent(contentSize);

    int x = textRect.left;
    int y = textRect.bottom + ScaleForDpi(kAnchorGap, dpi_);
    HMONITOR monitor = MonitorFromRect(&textRect, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitorInfo{sizeof(monitorInfo)};
    if (GetMonitorInfoW(monitor, &monitorInfo)) {
        if (x + windowSize.cx > monitorInfo.rcWork.right) {
            x = monitorInfo.rcWork.right - windowSize.cx;
        }
        if (y + windowSize.cy > monitorInfo.rcWork.bottom) {
            y = textRect.top - windowSize.cy - ScaleForDpi(kAnchorGap, dpi_);
        }
        x = std::max(x, static_cast<int>(monitorInfo.rcWork.left));
        y = std::max(y, static_cast<int>(monitorInfo.rcWork.top));
    }

    SetWindowPos(window_, HWND_TOPMOST, x, y, windowSize.cx, windowSize.cy,
                 SWP_NOACTIVATE | SWP_SHOWWINDOW);
    InvalidateRect(window_, nullptr, FALSE);
    NotifyWinEvent(EVENT_OBJECT_IME_SHOW, window_, OBJID_CLIENT, CHILDID_SELF);
}

void CandidateWindow::hide() {
    if (window_ && IsWindowVisible(window_)) {
        ShowWindow(window_, SW_HIDE);
        NotifyWinEvent(EVENT_OBJECT_IME_HIDE, window_, OBJID_CLIENT, CHILDID_SELF);
    }
    candidates_.clear();
    cellWidths_.clear();
}

LRESULT CALLBACK CandidateWindow::WindowProc(HWND window, UINT message,
                                              WPARAM wparam, LPARAM lparam) {
    CandidateWindow* self = reinterpret_cast<CandidateWindow*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    if (message == WM_NCCREATE) {
        const auto* create = reinterpret_cast<const CREATESTRUCTW*>(lparam);
        self = static_cast<CandidateWindow*>(create->lpCreateParams);
        self->window_ = window;
        SetWindowLongPtrW(window, GWLP_USERDATA, reinterpret_cast<LONG_PTR>(self));
    }

    if (self) {
        return self->handleMessage(message, wparam, lparam);
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

LRESULT CandidateWindow::handleMessage(UINT message, WPARAM wparam, LPARAM lparam) {
    switch (message) {
        case WM_ERASEBKGND:
            return 1;
        case WM_MOUSEACTIVATE:
            return MA_NOACTIVATE;
        case WM_PAINT:
            paint();
            return 0;
        case WM_DPICHANGED: {
            updateFont(HIWORD(wparam));
            const SIZE windowSize = windowSizeForContent(measureContent());
            const auto* suggested = reinterpret_cast<const RECT*>(lparam);
            SetWindowPos(window_, nullptr, suggested->left, suggested->top,
                         windowSize.cx, windowSize.cy,
                         SWP_NOACTIVATE | SWP_NOZORDER);
            InvalidateRect(window_, nullptr, FALSE);
            return 0;
        }
        case WM_NCDESTROY: {
            HWND destroyedWindow = window_;
            window_ = nullptr;
            return DefWindowProcW(destroyedWindow, message, wparam, lparam);
        }
        default:
            return DefWindowProcW(window_, message, wparam, lparam);
    }
}

void CandidateWindow::updateFont(UINT dpi) {
    if (font_ && dpi_ == dpi) {
        return;
    }

    LOGFONTW logFont{};
    HFONT stockFont = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    GetObjectW(stockFont, sizeof(logFont), &logFont);
    logFont.lfHeight = MulDiv(logFont.lfHeight, static_cast<int>(dpi),
                              USER_DEFAULT_SCREEN_DPI);
    logFont.lfWidth = MulDiv(logFont.lfWidth, static_cast<int>(dpi),
                             USER_DEFAULT_SCREEN_DPI);

    HFONT newFont = CreateFontIndirectW(&logFont);
    if (newFont) {
        if (font_) {
            DeleteObject(font_);
        }
        font_ = newFont;
    }
    dpi_ = dpi;
}

SIZE CandidateWindow::measureContent() {
    HDC dc = GetDC(window_);
    HFONT font = font_ ? font_ : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    HGDIOBJ oldFont = SelectObject(dc, font);

    TEXTMETRICW metrics{};
    GetTextMetricsW(dc, &metrics);
    const int horizontalPadding = ScaleForDpi(kHorizontalPadding, dpi_);
    const int verticalPadding = ScaleForDpi(kVerticalPadding, dpi_);
    const int rowGap = ScaleForDpi(kRowGap, dpi_);
    rowHeight_ = metrics.tmHeight + (verticalPadding * 2);

    int contentWidth = ScaleForDpi(kMinimumWidth, dpi_);
    cellWidths_.clear();
    for (const auto& candidate : candidates_) {
        SIZE keyExtent{};
        GetTextExtentPoint32W(dc, candidate.selectionKey.c_str(),
                              static_cast<int>(candidate.selectionKey.size()),
                              &keyExtent);
        SIZE textExtent{};
        GetTextExtentPoint32W(dc, candidate.text.c_str(),
                              static_cast<int>(candidate.text.size()),
                              &textExtent);
        const int cellWidth = keyExtent.cx + ScaleForDpi(kTextGap, dpi_) +
                              textExtent.cx + (horizontalPadding * 2);
        cellWidths_.push_back(cellWidth);
        if (horizontal_) {
            contentWidth += cellWidth + rowGap;
        } else {
            contentWidth = std::max(contentWidth, cellWidth);
        }
    }
    if (horizontal_) {
        contentWidth -= ScaleForDpi(kMinimumWidth, dpi_) + rowGap;
    }

    SelectObject(dc, oldFont);
    ReleaseDC(window_, dc);

    const int contentHeight =
        horizontal_ ? rowHeight_
                    : static_cast<int>(candidates_.size()) * rowHeight_ +
                          static_cast<int>(candidates_.size() - 1) * rowGap;
    return {contentWidth, contentHeight};
}

SIZE CandidateWindow::windowSizeForContent(const SIZE& content) const {
    RECT windowRect{0, 0, content.cx, content.cy};
    AdjustWindowRectExForDpi(&windowRect, WS_POPUP | WS_BORDER, FALSE,
                             WS_EX_TOOLWINDOW | WS_EX_NOACTIVATE, dpi_);
    return {windowRect.right - windowRect.left,
            windowRect.bottom - windowRect.top};
}

void CandidateWindow::paint() {
    PAINTSTRUCT paintStruct{};
    HDC dc = BeginPaint(window_, &paintStruct);
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));

    HFONT font = font_ ? font_ : static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);

    const int horizontalPadding = ScaleForDpi(kHorizontalPadding, dpi_);
    const int rowGap = ScaleForDpi(kRowGap, dpi_);
    const int textGap = ScaleForDpi(kTextGap, dpi_);
    int horizontalOffset = 0;
    for (size_t index = 0; index < candidates_.size(); ++index) {
        RECT row{};
        if (horizontal_) {
            const int width = index < cellWidths_.size() ? cellWidths_[index] : 80;
            row = {horizontalOffset, 0, horizontalOffset + width, rowHeight_};
            horizontalOffset += width + rowGap;
        } else {
            row = {0,
                   static_cast<LONG>(index * (rowHeight_ + rowGap)),
                   client.right,
                   static_cast<LONG>(index * (rowHeight_ + rowGap) +
                                     rowHeight_)};
        }
        const bool highlighted = index == highlightedIndex_;
        if (highlighted) {
            HBRUSH brush = CreateSolidBrush(highlightColor_);
            FillRect(dc, &row, brush);
            DeleteObject(brush);
            const int luminance = GetRValue(highlightColor_) * 299 +
                                  GetGValue(highlightColor_) * 587 +
                                  GetBValue(highlightColor_) * 114;
            SetTextColor(dc, luminance >= 150000 ? RGB(0, 0, 0)
                                                  : RGB(255, 255, 255));
        } else {
            SetTextColor(dc, GetSysColor(COLOR_WINDOWTEXT));
        }

        RECT keyRect = row;
        keyRect.left += horizontalPadding;
        DrawTextW(dc, candidates_[index].selectionKey.c_str(), -1, &keyRect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

        SIZE keyExtent{};
        GetTextExtentPoint32W(dc, candidates_[index].selectionKey.c_str(),
                              static_cast<int>(candidates_[index].selectionKey.size()),
                              &keyExtent);
        RECT textRect = row;
        textRect.left += horizontalPadding + keyExtent.cx + textGap;
        DrawTextW(dc, candidates_[index].text.c_str(), -1, &textRect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    SelectObject(dc, oldFont);
    EndPaint(window_, &paintStruct);
}

}  // namespace KeyKey::WindowsTsf

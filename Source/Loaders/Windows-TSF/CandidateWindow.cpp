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

std::once_flag g_windowClassOnce;
bool g_windowClassRegistered = false;

}  // namespace

CandidateWindow::~CandidateWindow() {
    if (window_) {
        DestroyWindow(window_);
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

    HDC dc = GetDC(window_);
    HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    HGDIOBJ oldFont = SelectObject(dc, font);

    TEXTMETRICW metrics{};
    GetTextMetricsW(dc, &metrics);
    rowHeight_ = metrics.tmHeight + (kVerticalPadding * 2);
    int contentWidth = 80;
    cellWidths_.clear();
    for (const auto& candidate : candidates_) {
        const std::wstring row = candidate.selectionKey + L"  " + candidate.text;
        SIZE extent{};
        GetTextExtentPoint32W(dc, row.c_str(), static_cast<int>(row.size()), &extent);
        const int cellWidth =
            static_cast<int>(extent.cx) + (kHorizontalPadding * 2);
        cellWidths_.push_back(cellWidth);
        if (horizontal_) {
            contentWidth += cellWidth + kRowGap;
        } else {
            contentWidth = std::max(contentWidth, cellWidth);
        }
    }
    if (horizontal_) {
        contentWidth -= 80 + kRowGap;
    }

    SelectObject(dc, oldFont);
    ReleaseDC(window_, dc);

    const int width = contentWidth;
    const int height = horizontal_
                           ? rowHeight_
                           : static_cast<int>(candidates_.size()) * rowHeight_ +
                                 static_cast<int>(candidates_.size() - 1) *
                                     kRowGap;

    int x = textRect.left;
    int y = textRect.bottom + 2;
    HMONITOR monitor = MonitorFromRect(&textRect, MONITOR_DEFAULTTONEAREST);
    MONITORINFO monitorInfo{sizeof(monitorInfo)};
    if (GetMonitorInfoW(monitor, &monitorInfo)) {
        if (x + width > monitorInfo.rcWork.right) {
            x = monitorInfo.rcWork.right - width;
        }
        if (y + height > monitorInfo.rcWork.bottom) {
            y = textRect.top - height - 2;
        }
        x = std::max(x, static_cast<int>(monitorInfo.rcWork.left));
        y = std::max(y, static_cast<int>(monitorInfo.rcWork.top));
    }

    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height,
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
        case WM_NCDESTROY: {
            HWND destroyedWindow = window_;
            window_ = nullptr;
            return DefWindowProcW(destroyedWindow, message, wparam, lparam);
        }
        default:
            return DefWindowProcW(window_, message, wparam, lparam);
    }
}

void CandidateWindow::paint() {
    PAINTSTRUCT paintStruct{};
    HDC dc = BeginPaint(window_, &paintStruct);
    RECT client{};
    GetClientRect(window_, &client);
    FillRect(dc, &client, reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1));

    HFONT font = static_cast<HFONT>(GetStockObject(DEFAULT_GUI_FONT));
    HGDIOBJ oldFont = SelectObject(dc, font);
    SetBkMode(dc, TRANSPARENT);

    int horizontalOffset = 0;
    for (size_t index = 0; index < candidates_.size(); ++index) {
        RECT row{};
        if (horizontal_) {
            const int width = index < cellWidths_.size() ? cellWidths_[index] : 80;
            row = {horizontalOffset, 0, horizontalOffset + width, rowHeight_};
            horizontalOffset += width + kRowGap;
        } else {
            row = {0,
                   static_cast<LONG>(index * (rowHeight_ + kRowGap)),
                   client.right,
                   static_cast<LONG>(index * (rowHeight_ + kRowGap) +
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
        keyRect.left += kHorizontalPadding;
        DrawTextW(dc, candidates_[index].selectionKey.c_str(), -1, &keyRect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);

        SIZE keyExtent{};
        GetTextExtentPoint32W(dc, candidates_[index].selectionKey.c_str(),
                              static_cast<int>(candidates_[index].selectionKey.size()),
                              &keyExtent);
        RECT textRect = row;
        textRect.left += kHorizontalPadding + keyExtent.cx + 12;
        DrawTextW(dc, candidates_[index].text.c_str(), -1, &textRect,
                  DT_LEFT | DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX);
    }

    SelectObject(dc, oldFont);
    EndPaint(window_, &paintStruct);
}

}  // namespace KeyKey::WindowsTsf

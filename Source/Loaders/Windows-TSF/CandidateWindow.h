#pragma once

#include <Windows.h>

#include <string>
#include <vector>

#include "KeyKeyEngine.h"

namespace KeyKey::WindowsTsf {

class CandidateWindow final {
public:
    CandidateWindow() = default;
    ~CandidateWindow();
    static bool releaseWindowClass(); // Only when the module has no service objects.

    CandidateWindow(const CandidateWindow&) = delete;
    CandidateWindow& operator=(const CandidateWindow&) = delete;

    void show(HWND owner, const RECT& textRect,
              const std::vector<EngineCandidate>& candidates,
              size_t highlightedIndex);
    void hide();

private:
    friend struct TextServiceTestAccess;
    friend struct PopupLifecycleTestAccess;
    static bool ensureWindowClass();
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
    LRESULT handleMessage(UINT message, WPARAM wparam, LPARAM lparam);
    void paint();
    void traceState(const char* event) const;
    void notifyVisibility(bool visible);
    void ensureWindow(HWND owner);
    void updateFont(UINT dpi);
    SIZE measureContent();
    SIZE windowSizeForContent(const SIZE& content) const;

    HWND window_ = nullptr;
    bool shown_ = false;
    bool reportedVisible_ = false;
    HFONT font_ = nullptr;
    std::vector<EngineCandidate> candidates_;
    std::vector<int> cellWidths_;
    size_t highlightedIndex_ = 0;
    int rowHeight_ = 0;
    UINT dpi_ = USER_DEFAULT_SCREEN_DPI;
    int scalePercent_ = 0;
    bool horizontal_ = false;
    COLORREF highlightColor_ = RGB(128, 0, 128);
};

}  // namespace KeyKey::WindowsTsf

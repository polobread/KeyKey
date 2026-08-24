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

    CandidateWindow(const CandidateWindow&) = delete;
    CandidateWindow& operator=(const CandidateWindow&) = delete;

    void show(HWND owner, const RECT& textRect,
              const std::vector<EngineCandidate>& candidates,
              size_t highlightedIndex);
    void hide();

private:
    static bool ensureWindowClass();
    static LRESULT CALLBACK WindowProc(HWND window, UINT message, WPARAM wparam, LPARAM lparam);
    LRESULT handleMessage(UINT message, WPARAM wparam, LPARAM lparam);
    void paint();
    void ensureWindow(HWND owner);
    void updateFont(UINT dpi);
    SIZE measureContent();
    SIZE windowSizeForContent(const SIZE& content) const;

    HWND window_ = nullptr;
    HFONT font_ = nullptr;
    std::vector<EngineCandidate> candidates_;
    std::vector<int> cellWidths_;
    size_t highlightedIndex_ = 0;
    int rowHeight_ = 0;
    UINT dpi_ = USER_DEFAULT_SCREEN_DPI;
    bool horizontal_ = false;
    COLORREF highlightColor_ = RGB(128, 0, 128);
};

}  // namespace KeyKey::WindowsTsf

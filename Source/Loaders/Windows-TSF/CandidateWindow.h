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

    HWND window_ = nullptr;
    std::vector<EngineCandidate> candidates_;
    size_t highlightedIndex_ = 0;
};

}  // namespace KeyKey::WindowsTsf

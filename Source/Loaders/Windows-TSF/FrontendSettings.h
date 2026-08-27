#pragma once

#include <Windows.h>

#include <string>

namespace KeyKey::WindowsTsf {

enum class CandidateLayout {
    Vertical,
    Horizontal,
};

struct FrontendSettings {
    CandidateLayout candidateLayout = CandidateLayout::Vertical;
    int candidateScalePercent = 0;
    std::wstring highlightColor = L"Default";
    bool toggleWithControlBackslash = true;
    bool playSoundOnTypingError = true;
};

std::wstring SettingsDirectory();
std::wstring LoaderPreferencesPath();
std::wstring TraditionalMandarinPreferencesPath();
std::wstring AssociatedPhrasePreferencesPath();

FrontendSettings LoadFrontendSettings();
COLORREF HighlightColorValue(const std::wstring& name);

}  // namespace KeyKey::WindowsTsf

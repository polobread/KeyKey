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
void MigrateLegacyPreferences();
std::wstring LoaderPreferencesPath();
std::wstring TraditionalMandarinPreferencesPath();
std::wstring SmartMandarinPreferencesPath();
std::wstring AssociatedPhrasePreferencesPath();

FrontendSettings LoadFrontendSettings();
bool IsInputMethodVisible(const char* identifier);
COLORREF HighlightColorValue(const std::wstring& name);

}  // namespace KeyKey::WindowsTsf

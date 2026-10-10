#pragma once

#include <Windows.h>

#include <string>
#include <cstdint>

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
    bool simplifiedChineseOutput = false;
    bool defaultChineseMode = true;
};

struct DiagnosticSession {
    std::int64_t startedAt = 0;
    std::int64_t expiresAt = 0;
    bool activeAt(std::int64_t now) const;
};
std::wstring DiagnosticSettingsPath();
DiagnosticSession LoadDiagnosticSession();

std::wstring SettingsDirectory();
void MigrateLegacyPreferences();
std::wstring LoaderPreferencesPath();
std::wstring TraditionalMandarinPreferencesPath();
std::wstring SmartMandarinPreferencesPath();
std::wstring AssociatedPhrasePreferencesPath();

FrontendSettings LoadFrontendSettings();
UINT ContentDpiForScale(UINT hostDpi, HMONITOR monitor, int scalePercent);
bool SaveSimplifiedOutputPreference(bool enabled);
std::string SmartMandarinSettingsSignature();
std::string LoadInputMethodPreference(const std::string& fallback);
bool IsInputMethodVisible(const char* identifier);
COLORREF HighlightColorValue(const std::wstring& name);

}  // namespace KeyKey::WindowsTsf

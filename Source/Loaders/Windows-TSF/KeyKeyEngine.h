#pragma once

#include <Windows.h>

#include <memory>
#include <string>
#include <vector>

namespace OpenVanilla {
class PVLoaderContext;
}

namespace KeyKey::WindowsTsf {

struct EngineCandidate {
    std::wstring selectionKey;
    std::wstring text;
};

struct EngineResult {
    bool handled = false;
    bool beep = false;
    std::wstring committedText;
    std::wstring compositionText;
    LONG compositionCursor = 0;
    bool candidatesVisible = false;
    size_t highlightedCandidate = 0;
    std::vector<EngineCandidate> candidates;
};

struct KeyEvent {
    UINT virtualKey = 0;
    std::wstring text;
    bool shift = false;
    bool control = false;
    bool alt = false;
    bool capsLock = false;
    bool numLock = false;
};

// Returns true only in Mandarin modes for Ctrl chords backed by entries in
// DataTables/bpmf-punctuations.cin. General application shortcuts must remain
// outside the input-method engine.
bool IsInputMethodControlKey(const KeyEvent& event);
bool IsInputMethodControlKey(const KeyEvent& event, const std::string& method);
std::string CurrentInputMethod();
std::string ObservedInputMethod();
std::string EngineSettingsSignature(const std::string& method = "SmartMandarin");
void BeginOrderedEngineInput();
void EndOrderedEngineInput();
bool IsInputMethodAvailable(const char* identifier);
bool SelectInputMethod(const char* identifier);

class KeyKeyEngineSession final {
public:
    static std::unique_ptr<KeyKeyEngineSession> Create();
    static std::unique_ptr<KeyKeyEngineSession> CreateControlled(const std::string& method);

    ~KeyKeyEngineSession();
    KeyKeyEngineSession(const KeyKeyEngineSession&) = delete;
    KeyKeyEngineSession& operator=(const KeyKeyEngineSession&) = delete;

    bool ready() const noexcept;
    const std::string& inputMethod() const noexcept { return inputMethod_; }
    bool hasComposition() const;
    bool wantsKey(const KeyEvent& event) const;
    EngineResult handleKey(const KeyEvent& event);
    void reset();

private:
    explicit KeyKeyEngineSession(OpenVanilla::PVLoaderContext* context);
    OpenVanilla::PVLoaderContext* context_ = nullptr;
    std::string inputMethod_;
    std::string smartSettingsSignature_;
    bool controlled_ = false;
};

}  // namespace KeyKey::WindowsTsf

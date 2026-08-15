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

class KeyKeyEngineSession final {
public:
    static std::unique_ptr<KeyKeyEngineSession> Create();

    ~KeyKeyEngineSession();
    KeyKeyEngineSession(const KeyKeyEngineSession&) = delete;
    KeyKeyEngineSession& operator=(const KeyKeyEngineSession&) = delete;

    bool ready() const noexcept;
    bool hasComposition() const;
    bool wantsKey(const KeyEvent& event) const;
    EngineResult handleKey(const KeyEvent& event);
    void reset();

private:
    explicit KeyKeyEngineSession(OpenVanilla::PVLoaderContext* context);
    OpenVanilla::PVLoaderContext* context_ = nullptr;
};

}  // namespace KeyKey::WindowsTsf

// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once

#include "keykey/linux_ime/engine.h"

#include <functional>
#include <memory>
#include <string>

namespace keykey::linux_ime {

struct GuanyinmaConfig {
    InputMethod inputMethod = InputMethod::Bopomofo;
    bool smartMode = true;
    BopomofoLayout layout = BopomofoLayout::Standard;
    SmartMandarinPreferences smart;
    TablePreferences table;
    bool restrictBopomofoToBig5 = false;

    bool operator==(const GuanyinmaConfig &other) const noexcept;
    bool operator!=(const GuanyinmaConfig &other) const noexcept {
        return !(*this == other);
    }
};

// Owns the formal Rust C ABI session, its native font policy and result data.
// It never commits to an application or applies traditional/simplified filters.
class GuanyinmaSession {
public:
    using CandidateFilter = std::function<bool(const std::string &)>;

    // Empty filter uses the native headless PangoFT2/fontconfig provider.
    // Construction errors throw; operation errors preserve the last view,
    // consume/beep without replay and are available through lastError().
    GuanyinmaSession(std::string modelPath, std::string userDatabasePath,
                     GuanyinmaConfig config, CandidateFilter filter = {});
    ~GuanyinmaSession();
    GuanyinmaSession(const GuanyinmaSession &) = delete;
    GuanyinmaSession &operator=(const GuanyinmaSession &) = delete;

    EngineResult processKey(const KeyEvent &event);
    EngineResult snapshot() const;
    EngineResult selectDisplayedCandidate(std::size_t displayedIndex);
    EngineResult selectSmartCharacter(std::size_t preeditCharacterIndex);
    // Matches the Linux lifecycle policy: finish Smart readings where valid,
    // keep highlighted traditional candidates, discard unconfirmed table code.
    EngineResult finishComposition();
    // A failed reset retires the session; it can never revive old composition.
    EngineResult reset();
    EngineResult setFullWidth(bool enabled);

    bool quiet() const noexcept;
    bool valid() const noexcept;
    bool acceptsCandidate(const std::string &text) const noexcept;
    const std::string &lastError() const noexcept;
    const GuanyinmaConfig &config() const noexcept;

    // Administration operations use the same C ABI with owned UTF-8 JSON.
    // They throw on failure, and never send host effects themselves.
    std::string applyJson(const std::string &operation);
    std::string userDataJson() const;
    static void validateArchive(const std::string &archive);
    static std::string defaultUserDatabasePath();

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace keykey::linux_ime

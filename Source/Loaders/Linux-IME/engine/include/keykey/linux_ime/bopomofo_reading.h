#pragma once

#include <array>
#include <string>

namespace keykey::linux_ime {

enum class BopomofoLayout { Standard, ETen, ETen26, Hsu, HanyuPinyin };

enum class BopomofoComponent : unsigned char {
    None,
    B,
    P,
    M,
    F,
    D,
    T,
    N,
    L,
    G,
    K,
    H,
    J,
    Q,
    X,
    ZH,
    CH,
    SH,
    R,
    Z,
    C,
    S,
    I,
    U,
    UE,
    A,
    O,
    ER,
    E,
    AI,
    EI,
    AO,
    OU,
    AN,
    EN,
    ANG,
    ENG,
    ERR,
    Tone2,
    Tone3,
    Tone4,
    Tone5,
};

class BopomofoReading {
public:
    enum class Kind : std::size_t { Initial, Medial, Final, Tone, Count };

    bool combine(char key, BopomofoLayout layout);
    bool backspace(BopomofoLayout layout);
    void clear() noexcept;

    bool empty(BopomofoLayout layout) const noexcept;
    std::string queryKey() const;
    std::string displayText(BopomofoLayout layout) const;
    std::string inputKeySequence(BopomofoLayout layout) const;

    static bool isBopomofoKey(char key, BopomofoLayout layout) noexcept;

private:
    void parseKeySequence(const std::string &sequence, BopomofoLayout layout);
    void parsePinyin();
    std::array<BopomofoComponent, static_cast<std::size_t>(Kind::Count)>
        components_{};
    std::string pinyinSequence_;
};

} // namespace keykey::linux_ime

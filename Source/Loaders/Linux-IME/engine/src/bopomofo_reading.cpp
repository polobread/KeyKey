#include "keykey/linux_ime/bopomofo_reading.h"

#include <algorithm>
#include <cctype>
#include <cstddef>
#include <string>

namespace keykey::linux_ime {
namespace {

using Component = BopomofoComponent;
using Kind = BopomofoReading::Kind;

struct Mapping {
    char key;
    Component first;
    Component second = Component::None;
    Component third = Component::None;
};

struct MappingView {
    const Mapping *data;
    std::size_t size;
};

constexpr Mapping standardMappings[] = {
    {'1', Component::B},       {'q', Component::P},
    {'a', Component::M},       {'z', Component::F},
    {'2', Component::D},       {'w', Component::T},
    {'s', Component::N},       {'x', Component::L},
    {'e', Component::G},       {'d', Component::K},
    {'c', Component::H},       {'r', Component::J},
    {'f', Component::Q},       {'v', Component::X},
    {'5', Component::ZH},      {'t', Component::CH},
    {'g', Component::SH},      {'b', Component::R},
    {'y', Component::Z},       {'h', Component::C},
    {'n', Component::S},       {'u', Component::I},
    {'j', Component::U},       {'m', Component::UE},
    {'8', Component::A},       {'i', Component::O},
    {'k', Component::ER},      {',', Component::E},
    {'9', Component::AI},      {'o', Component::EI},
    {'l', Component::AO},      {'.', Component::OU},
    {'0', Component::AN},      {'p', Component::EN},
    {';', Component::ANG},     {'/', Component::ENG},
    {'-', Component::ERR},     {'6', Component::Tone2},
    {'3', Component::Tone3},   {'4', Component::Tone4},
    {'7', Component::Tone5},
};

constexpr Mapping etenMappings[] = {
    {'b', Component::B},       {'p', Component::P},
    {'m', Component::M},       {'f', Component::F},
    {'d', Component::D},       {'t', Component::T},
    {'n', Component::N},       {'l', Component::L},
    {'v', Component::G},       {'k', Component::K},
    {'h', Component::H},       {'g', Component::J},
    {'7', Component::Q},       {'c', Component::X},
    {',', Component::ZH},      {'.', Component::CH},
    {'/', Component::SH},      {'j', Component::R},
    {';', Component::Z},       {'\'', Component::C},
    {'s', Component::S},       {'e', Component::I},
    {'x', Component::U},       {'u', Component::UE},
    {'a', Component::A},       {'o', Component::O},
    {'r', Component::ER},      {'w', Component::E},
    {'i', Component::AI},      {'q', Component::EI},
    {'z', Component::AO},      {'y', Component::OU},
    {'8', Component::AN},      {'9', Component::EN},
    {'0', Component::ANG},     {'-', Component::ENG},
    {'=', Component::ERR},     {'2', Component::Tone2},
    {'3', Component::Tone3},   {'4', Component::Tone4},
    {'1', Component::Tone5},
};

constexpr Mapping hsuMappings[] = {
    {'b', Component::B},
    {'p', Component::P},
    {'m', Component::M, Component::AN},
    {'f', Component::F, Component::Tone3},
    {'d', Component::D, Component::Tone2},
    {'t', Component::T},
    {'n', Component::N, Component::EN},
    {'l', Component::L, Component::ENG, Component::ERR},
    {'g', Component::G, Component::ER},
    {'k', Component::K, Component::ANG},
    {'h', Component::H, Component::O},
    {'j', Component::J, Component::ZH, Component::Tone4},
    {'v', Component::Q, Component::CH},
    {'c', Component::X, Component::SH},
    {'r', Component::R},
    {'z', Component::Z},
    {'a', Component::C, Component::EI},
    {'s', Component::S, Component::Tone5},
    {'e', Component::I, Component::E},
    {'x', Component::U},
    {'u', Component::UE},
    {'y', Component::A},
    {'i', Component::AI},
    {'w', Component::AO},
    {'o', Component::OU},
};

constexpr Mapping eten26Mappings[] = {
    {'b', Component::B},
    {'p', Component::P, Component::OU},
    {'m', Component::M, Component::AN},
    {'f', Component::F, Component::Tone2},
    {'d', Component::D, Component::Tone5},
    {'t', Component::T, Component::ANG},
    {'n', Component::N, Component::EN},
    {'l', Component::L, Component::ENG},
    {'v', Component::G, Component::Q},
    {'k', Component::K, Component::Tone4},
    {'h', Component::H, Component::ERR},
    {'g', Component::ZH, Component::J},
    {'c', Component::SH, Component::X},
    {'y', Component::CH},
    {'j', Component::R, Component::Tone3},
    {'q', Component::Z, Component::EI},
    {'w', Component::C, Component::E},
    {'s', Component::S},
    {'e', Component::I},
    {'x', Component::U},
    {'u', Component::UE},
    {'a', Component::A},
    {'o', Component::O},
    {'r', Component::ER},
    {'i', Component::AI},
    {'z', Component::AO},
};

template <std::size_t Size>
constexpr MappingView view(const Mapping (&mappings)[Size]) noexcept {
    return MappingView{mappings, Size};
}

MappingView mappingsFor(BopomofoLayout layout) noexcept {
    switch (layout) {
    case BopomofoLayout::Standard:
        return view(standardMappings);
    case BopomofoLayout::ETen:
        return view(etenMappings);
    case BopomofoLayout::ETen26:
        return view(eten26Mappings);
    case BopomofoLayout::Hsu:
        return view(hsuMappings);
    case BopomofoLayout::HanyuPinyin:
        return MappingView{nullptr, 0};
    }
    return MappingView{nullptr, 0};
}

const Mapping *findMapping(BopomofoLayout layout, char rawKey) noexcept {
    const char key =
        static_cast<char>(std::tolower(static_cast<unsigned char>(rawKey)));
    const MappingView mappings = mappingsFor(layout);
    if (mappings.size == 0) {
        return nullptr;
    }
    const auto found = std::find_if(
        mappings.data, mappings.data + mappings.size,
        [key](const Mapping &mapping) { return mapping.key == key; });
    return found == mappings.data + mappings.size ? nullptr : found;
}

Kind kind(Component component) noexcept {
    const auto value = static_cast<unsigned int>(component);
    if (value >= static_cast<unsigned int>(Component::B) &&
        value <= static_cast<unsigned int>(Component::S)) {
        return Kind::Initial;
    }
    if (value >= static_cast<unsigned int>(Component::I) &&
        value <= static_cast<unsigned int>(Component::UE)) {
        return Kind::Medial;
    }
    if (value >= static_cast<unsigned int>(Component::A) &&
        value <= static_cast<unsigned int>(Component::ERR)) {
        return Kind::Final;
    }
    return Kind::Tone;
}

std::size_t kindIndex(Component component) noexcept {
    return static_cast<std::size_t>(kind(component));
}

const char *symbol(Component component) noexcept {
    switch (component) {
    case Component::B: return "ㄅ";
    case Component::P: return "ㄆ";
    case Component::M: return "ㄇ";
    case Component::F: return "ㄈ";
    case Component::D: return "ㄉ";
    case Component::T: return "ㄊ";
    case Component::N: return "ㄋ";
    case Component::L: return "ㄌ";
    case Component::G: return "ㄍ";
    case Component::K: return "ㄎ";
    case Component::H: return "ㄏ";
    case Component::J: return "ㄐ";
    case Component::Q: return "ㄑ";
    case Component::X: return "ㄒ";
    case Component::ZH: return "ㄓ";
    case Component::CH: return "ㄔ";
    case Component::SH: return "ㄕ";
    case Component::R: return "ㄖ";
    case Component::Z: return "ㄗ";
    case Component::C: return "ㄘ";
    case Component::S: return "ㄙ";
    case Component::I: return "ㄧ";
    case Component::U: return "ㄨ";
    case Component::UE: return "ㄩ";
    case Component::A: return "ㄚ";
    case Component::O: return "ㄛ";
    case Component::ER: return "ㄜ";
    case Component::E: return "ㄝ";
    case Component::AI: return "ㄞ";
    case Component::EI: return "ㄟ";
    case Component::AO: return "ㄠ";
    case Component::OU: return "ㄡ";
    case Component::AN: return "ㄢ";
    case Component::EN: return "ㄣ";
    case Component::ANG: return "ㄤ";
    case Component::ENG: return "ㄥ";
    case Component::ERR: return "ㄦ";
    case Component::Tone2: return "ˊ";
    case Component::Tone3: return "ˇ";
    case Component::Tone4: return "ˋ";
    case Component::Tone5: return "˙";
    case Component::None: return "";
    }
    return "";
}

char standardKey(Component component) noexcept {
    for (const Mapping &mapping : standardMappings) {
        if (mapping.first == component) {
            return mapping.key;
        }
    }
    return '\0';
}

char layoutKey(BopomofoLayout layout, Component component) noexcept {
    if (component == Component::None) {
        return '\0';
    }
    const MappingView mappings = mappingsFor(layout);
    for (std::size_t index = 0; index < mappings.size; ++index) {
        const Mapping &mapping = mappings.data[index];
        if (mapping.first == component || mapping.second == component ||
            mapping.third == component) {
            return mapping.key;
        }
    }
    return '\0';
}

void add(std::array<Component, static_cast<std::size_t>(Kind::Count)> &components,
         Component component) noexcept {
    if (component != Component::None) {
        components[kindIndex(component)] = component;
    }
}

bool isJqx(Component component) noexcept {
    return component == Component::J || component == Component::Q ||
           component == Component::X;
}

bool isZcsr(Component component) noexcept {
    return component == Component::ZH || component == Component::CH ||
           component == Component::SH || component == Component::R ||
           component == Component::Z || component == Component::C ||
           component == Component::S;
}

bool isVowel(Component component) noexcept {
    return component != Component::None && kind(component) != Kind::Initial &&
           kind(component) != Kind::Tone;
}

bool isTone(Component component) noexcept {
    return component != Component::None && kind(component) == Kind::Tone;
}

bool sequenceContainsKey(const std::string &sequence, std::size_t begin,
                         std::size_t end, char first, char second) noexcept {
    for (std::size_t index = begin; index < end; ++index) {
        if (sequence[index] == first || sequence[index] == second) {
            return true;
        }
    }
    return false;
}

bool nextIsEndOrTone(const std::string &sequence, std::size_t next,
                     BopomofoLayout layout) noexcept {
    if (next >= sequence.size()) {
        return true;
    }
    const Mapping *mapping = findMapping(layout, sequence[next]);
    return mapping != nullptr &&
           (isTone(mapping->first) || isTone(mapping->second) ||
            isTone(mapping->third));
}

bool startsWith(const std::string &value, const char *prefix) {
    return value.rfind(prefix, 0) == 0;
}

struct PinyinAlias {
    const char *text;
    const char *finalText;
};

constexpr PinyinAlias zeroInitialAliases[] = {
    {"yuan", "van"}, {"ying", "ing"}, {"yung", "iong"},
    {"yong", "iong"},
    {"yang", "iang"}, {"yue", "ve"},  {"yun", "vn"},
    {"you", "iou"},  {"yan", "ian"},  {"yin", "in"},
    {"yao", "iao"},  {"ye", "ie"},    {"yi", "i"},
    {"ya", "ia"},    {"yo", "io"},    {"yu", "v"},
    {"weng", "ueng"},
    {"wang", "uang"}, {"wen", "uen"}, {"wei", "uei"},
    {"wan", "uan"},  {"wai", "uai"},  {"wo", "uo"},
    {"wa", "ua"},    {"wu", "u"},
};

struct PinyinFinal {
    const char *text;
    Component medial;
    Component final;
};

constexpr PinyinFinal pinyinFinals[] = {
    {"iang", Component::I, Component::ANG},
    {"iong", Component::UE, Component::ENG},
    {"uang", Component::U, Component::ANG},
    {"ueng", Component::U, Component::ENG},
    {"iao", Component::I, Component::AO},
    {"iou", Component::I, Component::OU},
    {"ian", Component::I, Component::AN},
    {"ien", Component::I, Component::EN},
    {"ing", Component::I, Component::ENG},
    {"uai", Component::U, Component::AI},
    {"uei", Component::U, Component::EI},
    {"uan", Component::U, Component::AN},
    {"uen", Component::U, Component::EN},
    {"ang", Component::None, Component::ANG},
    {"eng", Component::None, Component::ENG},
    {"van", Component::UE, Component::AN},
    {"ven", Component::UE, Component::EN},
    {"ia", Component::I, Component::A},
    {"io", Component::I, Component::O},
    {"ie", Component::I, Component::E},
    {"iu", Component::I, Component::OU},
    {"in", Component::I, Component::EN},
    {"ua", Component::U, Component::A},
    {"uo", Component::U, Component::O},
    {"ui", Component::U, Component::EI},
    {"un", Component::U, Component::EN},
    {"ong", Component::U, Component::ENG},
    {"ue", Component::UE, Component::E},
    {"ve", Component::UE, Component::E},
    {"vn", Component::UE, Component::EN},
    {"ai", Component::None, Component::AI},
    {"ei", Component::None, Component::EI},
    {"ao", Component::None, Component::AO},
    {"ou", Component::None, Component::OU},
    {"an", Component::None, Component::AN},
    {"en", Component::None, Component::EN},
    {"er", Component::None, Component::ERR},
    {"i", Component::I, Component::None},
    {"u", Component::U, Component::None},
    {"v", Component::UE, Component::None},
    {"a", Component::None, Component::A},
    {"o", Component::None, Component::O},
    {"e", Component::None, Component::ER},
};

Component singleInitial(char key) noexcept {
    switch (key) {
    case 'b': return Component::B;
    case 'p': return Component::P;
    case 'm': return Component::M;
    case 'f': return Component::F;
    case 'd': return Component::D;
    case 't': return Component::T;
    case 'n': return Component::N;
    case 'l': return Component::L;
    case 'g': return Component::G;
    case 'k': return Component::K;
    case 'h': return Component::H;
    case 'j': return Component::J;
    case 'q': return Component::Q;
    case 'x': return Component::X;
    case 'r': return Component::R;
    case 'z': return Component::Z;
    case 'c': return Component::C;
    case 's': return Component::S;
    default: return Component::None;
    }
}

} // namespace

bool BopomofoReading::combine(char rawKey, BopomofoLayout layout) {
    const char key =
        static_cast<char>(std::tolower(static_cast<unsigned char>(rawKey)));
    if (layout == BopomofoLayout::HanyuPinyin) {
        if (std::isalpha(static_cast<unsigned char>(key)) != 0) {
            if (!pinyinSequence_.empty() &&
                std::isdigit(static_cast<unsigned char>(
                    pinyinSequence_.back())) != 0) {
                return false;
            }
        } else if (key >= '2' && key <= '5') {
            if (pinyinSequence_.empty() ||
                std::isdigit(static_cast<unsigned char>(
                    pinyinSequence_.back())) != 0) {
                return false;
            }
        } else {
            return false;
        }
        pinyinSequence_.push_back(key);
        parsePinyin();
        return true;
    }

    if (findMapping(layout, key) == nullptr) {
        return false;
    }
    pinyinSequence_.clear();
    std::string sequence = inputKeySequence(layout);
    sequence.push_back(key);
    parseKeySequence(sequence, layout);
    return true;
}

bool BopomofoReading::backspace(BopomofoLayout layout) {
    if (layout == BopomofoLayout::HanyuPinyin) {
        if (pinyinSequence_.empty()) {
            return false;
        }
        pinyinSequence_.pop_back();
        parsePinyin();
        return true;
    }

    std::string sequence = inputKeySequence(layout);
    if (sequence.empty()) {
        return false;
    }
    sequence.pop_back();
    parseKeySequence(sequence, layout);
    return true;
}

void BopomofoReading::clear() noexcept {
    components_.fill(Component::None);
    pinyinSequence_.clear();
}

bool BopomofoReading::empty(BopomofoLayout layout) const noexcept {
    if (layout == BopomofoLayout::HanyuPinyin) {
        return pinyinSequence_.empty();
    }
    return std::all_of(components_.begin(), components_.end(),
                       [](Component component) {
                           return component == Component::None;
                       });
}

std::string BopomofoReading::queryKey() const {
    std::string result;
    for (const Component component : components_) {
        const char key = standardKey(component);
        if (key != '\0') {
            result.push_back(key);
        }
    }
    return result;
}

std::string BopomofoReading::displayText(BopomofoLayout layout) const {
    if (layout == BopomofoLayout::HanyuPinyin) {
        return pinyinSequence_;
    }
    std::string result;
    for (const Component component : components_) {
        result += symbol(component);
    }
    return result;
}

bool BopomofoReading::isBopomofoKey(char rawKey,
                                    BopomofoLayout layout) noexcept {
    const char key =
        static_cast<char>(std::tolower(static_cast<unsigned char>(rawKey)));
    if (layout == BopomofoLayout::HanyuPinyin) {
        return std::isalpha(static_cast<unsigned char>(key)) != 0 ||
               (key >= '2' && key <= '5');
    }
    return findMapping(layout, key) != nullptr;
}

std::string
BopomofoReading::inputKeySequence(BopomofoLayout layout) const {
    std::string result;
    for (const Component component : components_) {
        const char key = layoutKey(layout, component);
        if (key != '\0') {
            result.push_back(key);
        }
    }
    return result;
}

void BopomofoReading::parseKeySequence(const std::string &sequence,
                                       BopomofoLayout layout) {
    components_.fill(Component::None);
    const char iKey = layoutKey(layout, Component::I);
    const char ueKey = layoutKey(layout, Component::UE);

    for (std::size_t index = 0; index < sequence.size(); ++index) {
        const Mapping *mapping = findMapping(layout, sequence[index]);
        if (mapping == nullptr) {
            continue;
        }
        if (mapping->second == Component::None) {
            add(components_, mapping->first);
            continue;
        }

        const bool beforeHasIorUe =
            sequenceContainsKey(sequence, 0, index, iKey, ueKey);
        const bool aheadHasIorUe = sequenceContainsKey(
            sequence, index + 1, sequence.size(), iKey, ueKey);
        const bool compositionIsEmpty =
            std::all_of(components_.begin(), components_.end(),
                        [](Component component) {
                            return component == Component::None;
                        });
        const Component head = mapping->first;
        const Component follow = mapping->second;
        const Component ending = mapping->third == Component::None
                                     ? follow
                                     : mapping->third;

        if (head == Component::E && follow != Component::E) {
            add(components_, beforeHasIorUe ? head : follow);
            continue;
        }
        if (head != Component::E && follow == Component::E) {
            add(components_, beforeHasIorUe ? follow : head);
            continue;
        }

        if (isJqx(head) != isJqx(follow)) {
            const Component jqx = isJqx(head) ? head : follow;
            const Component alternative = isJqx(head) ? follow : head;
            if (!compositionIsEmpty) {
                if (ending != follow) {
                    add(components_, ending);
                }
            } else {
                add(components_, aheadHasIorUe ? jqx : alternative);
            }
            continue;
        }

        if (sequence.size() == 1) {
            if (isVowel(head) || isTone(follow) || isZcsr(head)) {
                add(components_, head);
            } else if (isVowel(follow) || isTone(ending)) {
                add(components_, follow);
            } else {
                add(components_, ending);
            }
            continue;
        }

        const std::size_t headKind = kindIndex(head);
        if (components_[headKind] == Component::None &&
            !nextIsEndOrTone(sequence, index + 1, layout)) {
            add(components_, head);
        } else if (nextIsEndOrTone(sequence, index + 1, layout) &&
                   isZcsr(head) &&
                   compositionIsEmpty) {
            add(components_, head);
        } else if (kindIndex(head) < kindIndex(follow)) {
            add(components_, follow);
        } else {
            add(components_, ending);
        }
    }

    if (layout == BopomofoLayout::Hsu) {
        Component &initial = components_[static_cast<std::size_t>(Kind::Initial)];
        const Component medial =
            components_[static_cast<std::size_t>(Kind::Medial)];
        Component &final = components_[static_cast<std::size_t>(Kind::Final)];
        if (final == Component::ENG && initial == Component::None &&
            medial == Component::None) {
            final = Component::ERR;
        } else if (initial == Component::G &&
                   (medial == Component::I || medial == Component::UE)) {
            initial = Component::J;
        }
    }
}

void BopomofoReading::parsePinyin() {
    components_.fill(Component::None);
    std::string syllable = pinyinSequence_;

    Component tone = Component::None;
    if (!syllable.empty()) {
        switch (syllable.back()) {
        case '2': tone = Component::Tone2; break;
        case '3': tone = Component::Tone3; break;
        case '4': tone = Component::Tone4; break;
        case '5': tone = Component::Tone5; break;
        default: break;
        }
        if (tone != Component::None) {
            syllable.pop_back();
        }
    }

    std::string finalText;
    bool usedZeroInitialAlias = false;
    for (const PinyinAlias &alias : zeroInitialAliases) {
        if (syllable == alias.text) {
            finalText = alias.finalText;
            usedZeroInitialAlias = true;
            break;
        }
    }

    Component initial = Component::None;
    if (!usedZeroInitialAlias) {
        if (startsWith(syllable, "zh")) {
            initial = Component::ZH;
            finalText = syllable.substr(2);
        } else if (startsWith(syllable, "ch")) {
            initial = Component::CH;
            finalText = syllable.substr(2);
        } else if (startsWith(syllable, "sh")) {
            initial = Component::SH;
            finalText = syllable.substr(2);
        } else if (!syllable.empty()) {
            initial = singleInitial(syllable.front());
            finalText = initial == Component::None ? syllable
                                                   : syllable.substr(1);
        }
    }

    if (isZcsr(initial) && finalText == "i") {
        finalText.clear();
    }
    if (isJqx(initial) && !finalText.empty() && finalText.front() == 'u') {
        finalText.front() = 'v';
    }

    Component medial = Component::None;
    Component final = Component::None;
    for (const PinyinFinal &mapping : pinyinFinals) {
        if (finalText == mapping.text) {
            medial = mapping.medial;
            final = mapping.final;
            break;
        }
    }
    if (initial == Component::F && finalText == "ong") {
        medial = Component::None;
    }

    add(components_, initial);
    add(components_, medial);
    add(components_, final);
    add(components_, tone);
}

} // namespace keykey::linux_ime

#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/cin_dictionary.h"
#include "keykey/linux_ime/engine.h"

#include "error_sound.h"

#include <fcitx-config/configuration.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/macros.h>
#include <fcitx/addonfactory.h>
#include <fcitx/addonmanager.h>
#include <fcitx/candidatelist.h>
#include <fcitx/event.h>
#include <fcitx/inputcontext.h>
#include <fcitx/inputcontextmanager.h>
#include <fcitx/inputcontextproperty.h>
#include <fcitx/inputmethodengine.h>
#include <fcitx/inputpanel.h>
#include <fcitx/instance.h>
#include <fcitx/text.h>
#include <fcitx/userinterface.h>

#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <optional>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

namespace linux_ime = keykey::linux_ime;
namespace fcitx5_adapter = keykey::linux_ime::fcitx5_adapter;

constexpr std::uint32_t ShiftTapTimeoutMilliseconds = 300;
constexpr auto ShiftTapTimeout =
    std::chrono::milliseconds(ShiftTapTimeoutMilliseconds);

class BopomofoLayoutAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Standard");
        config.setValueByPath("EnumI18n/0", "Standard");
        config.setValueByPath("Enum/1", "ETen");
        config.setValueByPath("EnumI18n/1", "ETen");
        config.setValueByPath("Enum/2", "ETen26");
        config.setValueByPath("EnumI18n/2", "ETen 26-key");
        config.setValueByPath("Enum/3", "Hsu");
        config.setValueByPath("EnumI18n/3", "Hsu");
        config.setValueByPath("Enum/4", "HanyuPinyin");
        config.setValueByPath("EnumI18n/4", "Hanyu Pinyin");
    }
};

class BopomofoModeAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Smart");
        config.setValueByPath("EnumI18n/0", "好打注音");
        config.setValueByPath("Enum/1", "Traditional");
        config.setValueByPath("EnumI18n/1", "傳統注音");
    }
};

class CandidateWindowStyleAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Vertical");
        config.setValueByPath("EnumI18n/0", "Vertical");
        config.setValueByPath("Enum/1", "Horizontal");
        config.setValueByPath("EnumI18n/1", "Horizontal");
    }
};

#define KEYKEY_ASSOCIATED_PHRASE_OPTIONS(X)                                   \
    X(mcBopomofo, "McBopomofo", "小麥注音", true)                           \
    X(agricultureFood, "agriculture-food", "農業食品", false)               \
    X(aiDataScience, "ai-data-science", "AI 資料科學", false)               \
    X(anime, "anime", "動漫", false)                                        \
    X(biotechPharma, "biotech-pharma", "生技藥學", false)                   \
    X(business, "business", "商業", false)                                  \
    X(chinese, "chinese", "中文文學", false)                                \
    X(civilEngineering, "civil-engineering", "建築土木", false)             \
    X(education, "education", "教育", false)                                \
    X(electronics, "electronics", "電子電機", false)                        \
    X(energyEnvironment, "energy-environment", "環境能源", false)           \
    X(finance, "finance", "財會金融", false)                                \
    X(general, "general", "一般生活", false)                                \
    X(government, "government", "公務員公文", false)                        \
    X(history, "history", "歷史", false)                                    \
    X(industrialEngineering, "industrial-engineering", "工業工程", false)   \
    X(law, "law", "法律", false)                                            \
    X(manufacturing, "manufacturing", "製造機械", false)                    \
    X(materialsChemistry, "materials-chemistry", "材料化工", false)         \
    X(mediaDesign, "media-design", "媒體設計", false)                       \
    X(medicine, "medicine", "醫學", false)                                  \
    X(networkSecurity, "network-security", "網路資安", false)               \
    X(peopleContemporary, "people-contemporary", "人名－當代", false)       \
    X(peopleHistory, "people-history", "人名－歷史", false)                 \
    X(peopleOldnews, "people-oldnews", "人名－舊聞", false)                 \
    X(psychologySociety, "psychology-society", "心理社會", false)           \
    X(science, "science", "科學", false)                                    \
    X(semiconductor, "semiconductor", "晶片半導體", false)                  \
    X(software, "software", "軟體科學", false)                              \
    X(transportLogistics, "transport-logistics", "交通物流", false)

#define KEYKEY_DECLARE_ASSOCIATED_PHRASE_OPTION(member, source, label,        \
                                                 defaultValue)                 \
    fcitx::Option<bool> member{this, source, label, defaultValue};

FCITX_CONFIGURATION(
    AssociatedPhraseConfig,
    KEYKEY_ASSOCIATED_PHRASE_OPTIONS(
        KEYKEY_DECLARE_ASSOCIATED_PHRASE_OPTION))

#undef KEYKEY_DECLARE_ASSOCIATED_PHRASE_OPTION

FCITX_CONFIGURATION(VersionInfoConfig, )

FCITX_CONFIGURATION(
    KeyKeyConfig,
    fcitx::Option<VersionInfoConfig> versionInfo{
        this, "VersionInfo",
        "琦琦輸入法 — 版本 " KEYKEY_VERSION_STRING};
    fcitx::OptionWithAnnotation<std::string, BopomofoLayoutAnnotation>
        bopomofoLayout{this, "BopomofoLayout", "Bopomofo keyboard layout",
                       "Standard"};
    fcitx::OptionWithAnnotation<std::string, BopomofoModeAnnotation>
        bopomofoMode{this, "BopomofoMode", "注音模式", "Smart"};
    fcitx::OptionWithAnnotation<std::string, CandidateWindowStyleAnnotation>
        candidateWindowStyle{this, "CandidateWindowStyle",
                             "Candidate window style", "Vertical"};
    fcitx::Option<bool> traditionalToSimplified{
        this, "TraditionalToSimplified",
        "Convert Traditional Chinese output to Simplified Chinese", false};
    fcitx::Option<bool> useAllUnicodeCharacters{
        this, "UseAllUnicodeCharacters",
        "Include candidates outside Big-5", true};
    fcitx::Option<bool> playSoundOnTypingError{
        this, "PlaySoundOnTypingError", "Play a sound on typing errors", true};
    fcitx::Option<bool> toggleWithControlBackslash{
        this, "ToggleInputMethodWithControlBackslash",
        "Toggle Chinese/English with Ctrl+\\", true};
    fcitx::Option<AssociatedPhraseConfig> associatedPhrases{
        this, "AssociatedPhrases", "Associated phrase collections"};
    fcitx::HiddenOption<std::string> associatedPhraseCollections{
        this, "AssociatedPhraseCollections",
        "Legacy associated phrase collections", "McBopomofo"};)

std::vector<std::string>
enabledAssociatedPhraseCollections(const AssociatedPhraseConfig &config) {
    std::vector<std::string> result;
#define KEYKEY_APPEND_ENABLED_COLLECTION(member, source, label, defaultValue) \
    if (*config.member) {                                                      \
        result.emplace_back(source);                                           \
    }
    KEYKEY_ASSOCIATED_PHRASE_OPTIONS(KEYKEY_APPEND_ENABLED_COLLECTION)
#undef KEYKEY_APPEND_ENABLED_COLLECTION
    return result;
}

void setEnabledAssociatedPhraseCollections(
    AssociatedPhraseConfig &config,
    const std::vector<std::string> &enabledCollections) {
    const std::unordered_set<std::string> enabled(enabledCollections.begin(),
                                                   enabledCollections.end());
#define KEYKEY_SET_ENABLED_COLLECTION(member, source, label, defaultValue)    \
    config.member.setValue(enabled.find(source) != enabled.end());
    KEYKEY_ASSOCIATED_PHRASE_OPTIONS(KEYKEY_SET_ENABLED_COLLECTION)
#undef KEYKEY_SET_ENABLED_COLLECTION
}

std::string joinCollectionList(const std::vector<std::string> &collections) {
    std::string result;
    for (const std::string &collection : collections) {
        if (!result.empty()) {
            result.push_back(',');
        }
        result += collection;
    }
    return result;
}

class FcitxState : public fcitx::InputContextProperty {
public:
    explicit FcitxState(fcitx::InputContext *inputContext)
        : inputContext_(inputContext) {}

    void process(const linux_ime::Engine &engine,
                 bool smartMode,
                 bool traditionalToSimplified,
                 bool playSoundOnTypingError,
                 fcitx::CandidateLayoutHint candidateLayout,
                 const fcitx5_adapter::ErrorSound &errorSound,
                 const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent);
    bool processModeKey(bool toggleWithControlBackslash,
                        fcitx::KeyEvent &event);
    void select(std::size_t displayedIndex);
    bool selectSmartCharacter(std::size_t preeditCharacterIndex);
    void reset();
    void commitAndReset();
    bool chineseMode() const noexcept { return chineseMode_; }

private:
    struct ShiftPress {
        std::uint32_t eventTime = 0;
        std::chrono::steady_clock::time_point monotonicTime;
    };

    void toggleChineseMode();
    void apply(const linux_ime::EngineResult &result);
    void updateUi(const linux_ime::EngineResult &result);

    fcitx::InputContext *inputContext_;
    linux_ime::InputContextState context_;
    const linux_ime::Engine *sourceEngine_ = nullptr;
    // Keep the configuration that owns this composition. applyConfig mutates
    // shared engines before the next key or deactivation reaches this state.
    std::unique_ptr<linux_ime::Engine> activeEngine_;
    bool chineseMode_ = true;
    bool smartMode_ = false;
    fcitx::CandidateLayoutHint candidateLayout_ =
        fcitx::CandidateLayoutHint::Vertical;
    std::optional<ShiftPress> shiftPressedAt_;
    bool controlBackslashPressed_ = false;
};

class CandidateWord : public fcitx::CandidateWord {
public:
    CandidateWord(FcitxState *state, std::size_t displayedIndex,
                  std::string value)
        : state_(state), displayedIndex_(displayedIndex) {
        setText(fcitx::Text(std::move(value)));
    }

    void select(fcitx::InputContext *inputContext) const override {
        FCITX_UNUSED(inputContext);
        state_->select(displayedIndex_);
    }

private:
    FcitxState *state_;
    std::size_t displayedIndex_;
};

class FcitxEngine : public fcitx::InputMethodEngineV3 {
public:
    explicit FcitxEngine(fcitx::Instance *instance)
        : instance_(instance),
          bopomofoDictionary_(loadDictionary("bpmf-ext.cin")),
          cangjieDictionary_(loadDictionary("cj-ext.cin")),
          simplexDictionary_(loadDictionary("simplex-ext.cin")),
          punctuationDictionary_(loadDictionary("bpmf-punctuations.cin")),
          traditionalToSimplifiedDictionary_(loadDictionary("tc2sc.cin")),
          associatedPhraseDictionary_(loadAssociatedPhraseDictionary()),
          smartMandarinStore_(loadSmartMandarinStore()),
          standardEngine_(bopomofoDictionary_, linux_ime::InputMethod::Bopomofo,
                          linux_ime::BopomofoLayout::Standard,
                          punctuationDictionary_,
                          traditionalToSimplifiedDictionary_,
                          associatedPhraseDictionary_),
          etenEngine_(bopomofoDictionary_, linux_ime::InputMethod::Bopomofo,
                      linux_ime::BopomofoLayout::ETen, punctuationDictionary_,
                      traditionalToSimplifiedDictionary_,
                      associatedPhraseDictionary_),
          eten26Engine_(bopomofoDictionary_, linux_ime::InputMethod::Bopomofo,
                        linux_ime::BopomofoLayout::ETen26,
                        punctuationDictionary_,
                        traditionalToSimplifiedDictionary_,
                        associatedPhraseDictionary_),
          hsuEngine_(bopomofoDictionary_, linux_ime::InputMethod::Bopomofo,
                     linux_ime::BopomofoLayout::Hsu, punctuationDictionary_,
                     traditionalToSimplifiedDictionary_,
                     associatedPhraseDictionary_),
          hanyuPinyinEngine_(bopomofoDictionary_,
                            linux_ime::InputMethod::Bopomofo,
                            linux_ime::BopomofoLayout::HanyuPinyin,
                            punctuationDictionary_,
                            traditionalToSimplifiedDictionary_,
                            associatedPhraseDictionary_),
          cangjieEngine_(cangjieDictionary_, linux_ime::InputMethod::Cangjie,
                         linux_ime::BopomofoLayout::Standard, nullptr,
                         traditionalToSimplifiedDictionary_,
                         associatedPhraseDictionary_),
          simplexEngine_(simplexDictionary_, linux_ime::InputMethod::Simplex,
                         linux_ime::BopomofoLayout::Standard, nullptr,
                         traditionalToSimplifiedDictionary_,
                         associatedPhraseDictionary_),
          factory_([](fcitx::InputContext &context) {
              return new FcitxState(&context);
          }) {
        instance->inputContextManager().registerProperty(
            "chichi77KeyKeyState", &factory_);
        keyEventWatcher_ = instance->watchEvent(
            fcitx::EventType::InputContextKeyEvent,
            fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &event) {
                auto &keyEvent = static_cast<fcitx::KeyEvent &>(event);
                const std::string inputMethod =
                    instance_->inputMethod(keyEvent.inputContext());
                if (!isKeyKeyInputMethod(inputMethod)) {
                    return;
                }
                keyEvent.inputContext()
                    ->propertyFor(&factory_)
                    ->processModeKey(*config_.toggleWithControlBackslash,
                                     keyEvent);
            });
        switchEventWatcher_ = instance->watchEvent(
            fcitx::EventType::InputContextSwitchInputMethod,
            fcitx::EventWatcherPhase::PreInputMethod,
            [this](fcitx::Event &event) {
                auto &switchEvent =
                    static_cast<fcitx::InputContextSwitchInputMethodEvent &>(
                        event);
                if (isKeyKeyInputMethod(switchEvent.oldInputMethod())) {
                    switchEvent.inputContext()
                        ->propertyFor(&factory_)
                        ->commitAndReset();
                }
            });
        reloadConfig();
    }

    const fcitx::Configuration *getConfig() const override { return &config_; }

    void setConfig(const fcitx::RawConfig &config) override {
        const bool hasCheckboxConfig =
            config.get("AssociatedPhrases") != nullptr;
        config_.load(config, true);
        if (!hasCheckboxConfig) {
            migrateLegacyAssociatedPhraseConfig();
        }
        synchronizeLegacyAssociatedPhraseConfig();
        applyConfig();
        fcitx::safeSaveAsIni(config_, configFile());
    }

    void reloadConfig() override {
        config_ = KeyKeyConfig();
        fcitx::RawConfig rawConfig;
        fcitx::readAsIni(rawConfig, configFile());
        config_.load(rawConfig);
        if (rawConfig.get("AssociatedPhrases") == nullptr) {
            migrateLegacyAssociatedPhraseConfig();
        }
        synchronizeLegacyAssociatedPhraseConfig();
        applyConfig();
    }

    void keyEvent(const fcitx::InputMethodEntry &entry,
                  fcitx::KeyEvent &event) override {
        FcitxState *state = event.inputContext()->propertyFor(&factory_);
        linux_ime::KeyEvent translated;
        if (!translate(event, translated)) {
            return;
        }
        state->process(
            engineFor(entry), entry.uniqueName() == "chichi77-keykey-bopomofo" &&
                                  *config_.bopomofoMode != "Traditional",
            *config_.traditionalToSimplified,
            *config_.playSoundOnTypingError, candidateLayoutHint(), errorSound_,
            translated, event);
    }

    std::string subModeLabelImpl(const fcitx::InputMethodEntry &entry,
                                 fcitx::InputContext &inputContext) override {
        FCITX_UNUSED(entry);
        return inputContext.propertyFor(&factory_)->chineseMode() ? "中" : "英";
    }

    std::string subMode(const fcitx::InputMethodEntry &entry,
                        fcitx::InputContext &inputContext) override {
        FCITX_UNUSED(entry);
        return inputContext.propertyFor(&factory_)->chineseMode() ? "Chinese"
                                                                  : "English";
    }

    void reset(const fcitx::InputMethodEntry &entry,
               fcitx::InputContextEvent &event) override {
        FCITX_UNUSED(entry);
        event.inputContext()->propertyFor(&factory_)->reset();
    }

    void deactivate(const fcitx::InputMethodEntry &entry,
                    fcitx::InputContextEvent &event) override {
        FCITX_UNUSED(entry);
        event.inputContext()->propertyFor(&factory_)->commitAndReset();
    }

    void invokeActionImpl(const fcitx::InputMethodEntry &entry,
                          fcitx::InvokeActionEvent &event) override {
        if (entry.uniqueName() == "chichi77-keykey-bopomofo" &&
            event.action() == fcitx::InvokeActionEvent::Action::LeftClick &&
            event.cursor() >= 0 &&
            event.inputContext()->propertyFor(&factory_)->selectSmartCharacter(
                static_cast<std::size_t>(event.cursor()))) {
            event.filter();
        }
    }

private:
    static bool isKeyKeyInputMethod(const std::string &name) noexcept {
        return name == "chichi77-keykey-bopomofo" ||
               name == "chichi77-keykey-cangjie" ||
               name == "chichi77-keykey-simplex";
    }

    static std::shared_ptr<const linux_ime::CinDictionary>
    loadDictionary(const std::string &fileName) {
        const char *overrideDirectory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
        const std::string directory =
            overrideDirectory == nullptr ? KEYKEY_LINUX_DATA_DIR
                                         : overrideDirectory;
        return std::make_shared<const linux_ime::CinDictionary>(
            linux_ime::CinDictionary::loadFile(directory + "/" + fileName));
    }

    static std::shared_ptr<const linux_ime::AssociatedPhraseDictionary>
    loadAssociatedPhraseDictionary() {
        const char *overrideDirectory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
        const std::string directory =
            overrideDirectory == nullptr ? KEYKEY_LINUX_DATA_DIR
                                         : overrideDirectory;
        return std::make_shared<const linux_ime::AssociatedPhraseDictionary>(
            linux_ime::AssociatedPhraseDictionary::loadDirectory(
                directory + "/associated-phrases"));
    }

    static std::shared_ptr<const linux_ime::SmartMandarinStore>
    loadSmartMandarinStore() {
        const char *overrideDirectory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
        const std::string directory =
            overrideDirectory == nullptr ? KEYKEY_LINUX_DATA_DIR
                                         : overrideDirectory;
        auto userData = linux_ime::SmartMandarinUserData::open(
            linux_ime::SmartMandarinUserData::defaultPath());
        return linux_ime::SmartMandarinStore::open(
            directory + "/smart-mandarin.db", std::move(userData));
    }

    static std::vector<std::string>
    parseCollectionList(const std::string &value) {
        std::vector<std::string> result;
        std::unordered_set<std::string> seen;
        std::size_t start = 0;
        while (start <= value.size()) {
            const std::size_t end = value.find(',', start);
            std::string source = value.substr(
                start, end == std::string::npos ? std::string::npos
                                                 : end - start);
            const std::size_t first = source.find_first_not_of(" \t\r\n");
            if (first != std::string::npos) {
                const std::size_t last = source.find_last_not_of(" \t\r\n");
                source = source.substr(first, last - first + 1);
                if (seen.insert(source).second) {
                    result.push_back(std::move(source));
                }
            }
            if (end == std::string::npos) {
                break;
            }
            start = end + 1;
        }
        return result;
    }

    void migrateLegacyAssociatedPhraseConfig() {
        setEnabledAssociatedPhraseCollections(
            *config_.associatedPhrases.mutableValue(),
            parseCollectionList(*config_.associatedPhraseCollections));
    }

    void synchronizeLegacyAssociatedPhraseConfig() {
        config_.associatedPhraseCollections.setValue(joinCollectionList(
            enabledAssociatedPhraseCollections(*config_.associatedPhrases)));
    }

    void applyConfig() {
        const bool smart = *config_.bopomofoMode != "Traditional";
        for (linux_ime::Engine *engine : {&standardEngine_, &etenEngine_,
                                          &eten26Engine_, &hsuEngine_,
                                          &hanyuPinyinEngine_}) {
            engine->setSmartMandarinStore(smartMandarinStore_);
            engine->setSmartMandarinMode(smart);
        }
        const std::vector<std::string> enabled =
            enabledAssociatedPhraseCollections(*config_.associatedPhrases);
        standardEngine_.setAssociatedPhraseCollections(enabled);
        etenEngine_.setAssociatedPhraseCollections(enabled);
        eten26Engine_.setAssociatedPhraseCollections(enabled);
        hsuEngine_.setAssociatedPhraseCollections(enabled);
        hanyuPinyinEngine_.setAssociatedPhraseCollections(enabled);
        cangjieEngine_.setAssociatedPhraseCollections(enabled);
        simplexEngine_.setAssociatedPhraseCollections(enabled);
        const bool restrictBopomofoToBig5 = !*config_.useAllUnicodeCharacters;
        standardEngine_.setRestrictBopomofoCandidatesToBig5(
            restrictBopomofoToBig5);
        etenEngine_.setRestrictBopomofoCandidatesToBig5(
            restrictBopomofoToBig5);
        eten26Engine_.setRestrictBopomofoCandidatesToBig5(
            restrictBopomofoToBig5);
        hsuEngine_.setRestrictBopomofoCandidatesToBig5(
            restrictBopomofoToBig5);
        hanyuPinyinEngine_.setRestrictBopomofoCandidatesToBig5(
            restrictBopomofoToBig5);
    }

    const linux_ime::Engine &
    engineFor(const fcitx::InputMethodEntry &entry) const noexcept {
        if (entry.uniqueName() == "chichi77-keykey-cangjie") {
            return cangjieEngine_;
        }
        if (entry.uniqueName() == "chichi77-keykey-simplex") {
            return simplexEngine_;
        }
        const std::string &layout = *config_.bopomofoLayout;
        if (layout == "ETen") {
            return etenEngine_;
        }
        if (layout == "ETen26") {
            return eten26Engine_;
        }
        if (layout == "Hsu") {
            return hsuEngine_;
        }
        if (layout == "HanyuPinyin") {
            return hanyuPinyinEngine_;
        }
        return standardEngine_;
    }

    fcitx::CandidateLayoutHint candidateLayoutHint() const noexcept {
        return *config_.candidateWindowStyle == "Horizontal"
                   ? fcitx::CandidateLayoutHint::Horizontal
                   : fcitx::CandidateLayoutHint::Vertical;
    }

    static const std::string &configFile() {
        static const std::string path = "conf/chichi77-keykey.conf";
        return path;
    }

    static bool translate(const fcitx::KeyEvent &source,
                          linux_ime::KeyEvent &destination) {
        destination.release = source.isRelease();
        destination.capsLock = source.rawKey().states().test(fcitx::KeyState::CapsLock);
        const fcitx::KeyStates states = source.key().states();
        destination.repeat = states.test(fcitx::KeyState::Repeat);
        if (states.test(fcitx::KeyState::Shift)) {
            destination.modifiers = destination.modifiers |
                                    linux_ime::KeyModifier::Shift;
        }
        if (states.test(fcitx::KeyState::Ctrl)) {
            destination.modifiers = destination.modifiers |
                                    linux_ime::KeyModifier::Control;
        }
        if (states.test(fcitx::KeyState::Alt)) {
            destination.modifiers = destination.modifiers |
                                    linux_ime::KeyModifier::Alt;
        }
        if (states.test(fcitx::KeyState::Super) ||
            states.test(fcitx::KeyState::Super2) ||
            states.test(fcitx::KeyState::Meta) ||
            states.test(fcitx::KeyState::Hyper)) {
            destination.modifiers = destination.modifiers |
                                    linux_ime::KeyModifier::Super;
        }

        switch (source.key().sym()) {
        case FcitxKey_space:
            destination.code = linux_ime::KeyCode::Space;
            return true;
        case FcitxKey_Return:
        case FcitxKey_KP_Enter:
            destination.code = linux_ime::KeyCode::Enter;
            return true;
        case FcitxKey_BackSpace:
            destination.code = linux_ime::KeyCode::Backspace;
            return true;
        case FcitxKey_Delete:
        case FcitxKey_KP_Delete:
            destination.code = linux_ime::KeyCode::Delete;
            return true;
        case FcitxKey_Tab:
        case FcitxKey_KP_Tab:
        case FcitxKey_ISO_Left_Tab:
            destination.code = linux_ime::KeyCode::Tab;
            return true;
        case FcitxKey_Escape:
            destination.code = linux_ime::KeyCode::Escape;
            return true;
        case FcitxKey_Left:
            destination.code = linux_ime::KeyCode::Left;
            return true;
        case FcitxKey_Right:
            destination.code = linux_ime::KeyCode::Right;
            return true;
        case FcitxKey_Up:
            destination.code = linux_ime::KeyCode::Up;
            return true;
        case FcitxKey_Down:
            destination.code = linux_ime::KeyCode::Down;
            return true;
        case FcitxKey_Home:
        case FcitxKey_KP_Home:
            destination.code = linux_ime::KeyCode::Home;
            return true;
        case FcitxKey_End:
        case FcitxKey_KP_End:
            destination.code = linux_ime::KeyCode::End;
            return true;
        case FcitxKey_Page_Up:
            destination.code = linux_ime::KeyCode::PageUp;
            return true;
        case FcitxKey_Page_Down:
            destination.code = linux_ime::KeyCode::PageDown;
            return true;
        default:
            break;
        }

        const auto symbol = source.key().sym();
        if (symbol >= FcitxKey_space && symbol <= FcitxKey_asciitilde) {
            destination.code = linux_ime::KeyCode::Character;
            destination.character = static_cast<char>(symbol);
            return true;
        }
        return false;
    }

    fcitx::Instance *instance_;
    std::shared_ptr<const linux_ime::CinDictionary> bopomofoDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> cangjieDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> simplexDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> punctuationDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary>
        traditionalToSimplifiedDictionary_;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary>
        associatedPhraseDictionary_;
    std::shared_ptr<const linux_ime::SmartMandarinStore> smartMandarinStore_;
    linux_ime::Engine standardEngine_;
    linux_ime::Engine etenEngine_;
    linux_ime::Engine eten26Engine_;
    linux_ime::Engine hsuEngine_;
    linux_ime::Engine hanyuPinyinEngine_;
    linux_ime::Engine cangjieEngine_;
    linux_ime::Engine simplexEngine_;
    fcitx5_adapter::ErrorSound errorSound_;
    fcitx::FactoryFor<FcitxState> factory_;
    KeyKeyConfig config_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        keyEventWatcher_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        switchEventWatcher_;
};

#undef KEYKEY_ASSOCIATED_PHRASE_OPTIONS

void FcitxState::process(const linux_ime::Engine &sourceEngine,
                         bool smartMode,
                         bool traditionalToSimplified,
                         bool playSoundOnTypingError,
                         fcitx::CandidateLayoutHint candidateLayout,
                         const fcitx5_adapter::ErrorSound &errorSound,
                         const linux_ime::KeyEvent &event,
                         fcitx::KeyEvent &fcitxEvent) {
    candidateLayout_ = candidateLayout;
    if (sourceEngine_ != &sourceEngine || smartMode_ != smartMode) {
        commitAndReset();
        activeEngine_.reset();
        sourceEngine_ = &sourceEngine;
        smartMode_ = smartMode;
    }
    const auto current = activeEngine_ ? activeEngine_->snapshot(context_)
                                       : linux_ime::EngineResult{};
    if (!activeEngine_ || (current.preedit.empty() && current.candidates.empty())) {
        activeEngine_ = std::make_unique<linux_ime::Engine>(sourceEngine);
    }
    const linux_ime::Engine &engine = *activeEngine_;
    engine.setTraditionalToSimplifiedMode(context_,
                                          traditionalToSimplified);
    if (!chineseMode_) {
        if (event.release) {
            return;
        }
        const linux_ime::EngineResult current = engine.snapshot(context_);
        const auto modifiers = static_cast<unsigned int>(event.modifiers);
        const auto controlAltSuper =
            static_cast<unsigned int>(linux_ime::KeyModifier::Control) |
            static_cast<unsigned int>(linux_ime::KeyModifier::Alt) |
            static_cast<unsigned int>(linux_ime::KeyModifier::Super);
        const bool widthToggle =
            event.code == linux_ime::KeyCode::Space &&
            event.modifiers == linux_ime::KeyModifier::Shift;
        const bool fullWidthCharacter =
            current.fullWidthMode && (modifiers & controlAltSuper) == 0U &&
            (event.code == linux_ime::KeyCode::Space ||
             (event.code == linux_ime::KeyCode::Character &&
              event.character >= 0x20 && event.character <= 0x7E));
        if (!widthToggle && !fullWidthCharacter) {
            return;
        }
        if (fullWidthCharacter && !widthToggle) {
            linux_ime::EngineResult result = current;
            result.handled = true;
            result.commit = linux_ime::toFullWidth(
                event.code == linux_ime::KeyCode::Space
                    ? std::string(" ")
                    : std::string(1, event.character));
            apply(result);
            fcitxEvent.filterAndAccept();
            return;
        }
    }
    const fcitx::CapabilityFlags capabilities =
        inputContext_->capabilityFlags();
    const bool sensitive =
        capabilities.test(fcitx::CapabilityFlag::Password) ||
        capabilities.test(fcitx::CapabilityFlag::Sensitive);
    if (sensitive && engine.snapshot(context_).associatedPhrases) {
        context_.reset();
    }
    auto editingEvent = event;
    if (candidateLayout_ == fcitx::CandidateLayoutHint::Horizontal &&
        event.modifiers == linux_ime::KeyModifier::None &&
        !engine.snapshot(context_).candidates.empty()) {
        // Match the desktop panel: arrows along its axis select a candidate;
        // arrows across its axis change pages.
        switch (event.code) {
        case linux_ime::KeyCode::Left:
            editingEvent.code = linux_ime::KeyCode::Up;
            break;
        case linux_ime::KeyCode::Right:
            editingEvent.code = linux_ime::KeyCode::Down;
            break;
        case linux_ime::KeyCode::Up:
            editingEvent.code = linux_ime::KeyCode::Left;
            break;
        case linux_ime::KeyCode::Down:
            editingEvent.code = linux_ime::KeyCode::Right;
            break;
        default:
            break;
        }
    }
    linux_ime::EngineResult result = engine.processKey(context_, editingEvent);
    if (sensitive && result.associatedPhrases) {
        const std::string commit = std::move(result.commit);
        context_.reset();
        result = engine.snapshot(context_);
        result.handled = true;
        result.commit = commit;
    }
    if (result.beep && playSoundOnTypingError) {
        errorSound.play();
    }
    if (result.handled) {
        apply(result);
        fcitxEvent.filterAndAccept();
    } else if (result.updateUi) {
        updateUi(result);
    }
}

bool FcitxState::processModeKey(bool toggleWithControlBackslash,
                                fcitx::KeyEvent &event) {
    const fcitx::Key key = event.key();
    const fcitx::KeyStates states = key.states();
    const bool shiftKey =
        key.sym() == FcitxKey_Shift_L || key.sym() == FcitxKey_Shift_R;
    const bool control = states.test(fcitx::KeyState::Ctrl);
    const bool alt = states.test(fcitx::KeyState::Alt);
    const bool shift = states.test(fcitx::KeyState::Shift);
    const bool super = states.test(fcitx::KeyState::Super) ||
                       states.test(fcitx::KeyState::Super2) ||
                       states.test(fcitx::KeyState::Meta) ||
                       states.test(fcitx::KeyState::Hyper);

    if (shiftKey) {
        if (!event.isRelease()) {
            if (!control && !alt && !super &&
                !states.test(fcitx::KeyState::Repeat)) {
                if (!shiftPressedAt_) {
                    shiftPressedAt_ = ShiftPress{
                        static_cast<std::uint32_t>(event.time()),
                        std::chrono::steady_clock::now()};
                }
            } else {
                shiftPressedAt_.reset();
            }
            return false;
        }

        const bool trackedShift = shiftPressedAt_.has_value();
        bool tapped = false;
        if (trackedShift && !control && !alt && !super) {
            const auto releaseEventTime =
                static_cast<std::uint32_t>(event.time());
            if (shiftPressedAt_->eventTime != 0U && releaseEventTime != 0U) {
                tapped = releaseEventTime - shiftPressedAt_->eventTime <=
                         ShiftTapTimeoutMilliseconds;
            } else {
                tapped = std::chrono::steady_clock::now() -
                             shiftPressedAt_->monotonicTime <=
                         ShiftTapTimeout;
            }
        }
        shiftPressedAt_.reset();
        if (tapped) {
            toggleChineseMode();
        }
        if (trackedShift) {
            event.filterAndAccept();
            return true;
        }
        return false;
    }

    if (!event.isRelease()) {
        shiftPressedAt_.reset();
    }
    const bool backslashKey = key.sym() == FcitxKey_backslash;
    if (backslashKey && controlBackslashPressed_) {
        // Ctrl may be released before backslash. X11 can then resend a press
        // without the Ctrl state before the eventual key release, so suppress
        // every event for an owned physical key until that release arrives.
        if (event.isRelease()) {
            controlBackslashPressed_ = false;
        }
        event.filterAndAccept();
        return true;
    }
    if (backslashKey && control && !alt && !shift && !super) {
        if (!toggleWithControlBackslash) {
            // Skip both KeyKey and Fcitx global input-method handlers without
            // accepting the shortcut, so the frontend forwards it to the
            // client. The client decides whether that ends an active preedit.
            event.filter();
            return true;
        } else if (!event.isRelease()) {
            if (!controlBackslashPressed_) {
                toggleChineseMode();
                // Completing composition resets transient key state. Own the
                // held key afterwards, until its physical release arrives.
                controlBackslashPressed_ = true;
            }
        }
        event.filterAndAccept();
        return true;
    }
    return false;
}

void FcitxState::toggleChineseMode() {
    commitAndReset();
    chineseMode_ = !chineseMode_;
    inputContext_->updateUserInterface(
        fcitx::UserInterfaceComponent::StatusArea);
}

void FcitxState::select(std::size_t displayedIndex) {
    if (activeEngine_ != nullptr) {
        apply(activeEngine_->selectDisplayedCandidate(context_, displayedIndex));
    }
}

bool FcitxState::selectSmartCharacter(std::size_t preeditCharacterIndex) {
    if (activeEngine_ == nullptr || !smartMode_) {
        return false;
    }
    const linux_ime::EngineResult result =
        activeEngine_->selectSmartCharacter(context_, preeditCharacterIndex);
    if (!result.handled) {
        return false;
    }
    apply(result);
    return true;
}

void FcitxState::commitAndReset() {
    if (activeEngine_ != nullptr) {
        const linux_ime::EngineResult result =
            activeEngine_->finishComposition(context_);
        if (!result.commit.empty()) {
            inputContext_->commitString(result.commit);
        }
    }
    reset();
}

void FcitxState::reset() {
    shiftPressedAt_.reset();
    controlBackslashPressed_ = false;
    context_.reset();
    if (activeEngine_ != nullptr) {
        updateUi(activeEngine_->snapshot(context_));
    }
}

void FcitxState::apply(const linux_ime::EngineResult &result) {
    if (!result.commit.empty()) {
        inputContext_->commitString(result.commit);
    }
    updateUi(result);
}

void FcitxState::updateUi(const linux_ime::EngineResult &result) {
    auto &panel = inputContext_->inputPanel();
    panel.reset();

    if (!result.preedit.empty()) {
        fcitx::Text preedit(result.preedit, fcitx::TextFormatFlag::HighLight);
        preedit.setCursor(static_cast<int>(result.preeditCursorBytes));
        if (inputContext_->capabilityFlags().test(fcitx::CapabilityFlag::Preedit)) {
            panel.setClientPreedit(preedit);
        } else {
            panel.setPreedit(preedit);
        }
    }

    if (!result.candidates.empty()) {
        auto candidateList = std::make_unique<fcitx::CommonCandidateList>();
        for (std::size_t index = 0; index < result.candidates.size(); ++index) {
            candidateList->append<CandidateWord>(this, index,
                                                 result.candidates[index]);
        }
        const fcitx::KeyList selectionKeys{
            fcitx::Key{FcitxKey_1}, fcitx::Key{FcitxKey_2},
            fcitx::Key{FcitxKey_3}, fcitx::Key{FcitxKey_4},
            fcitx::Key{FcitxKey_5}, fcitx::Key{FcitxKey_6},
            fcitx::Key{FcitxKey_7}, fcitx::Key{FcitxKey_8},
            fcitx::Key{FcitxKey_9},
        };
        candidateList->setPageSize(9);
        candidateList->setSelectionKey(selectionKeys);
        candidateList->setLayoutHint(candidateLayout_);
        candidateList->setGlobalCursorIndex(
            static_cast<int>(result.highlightedIndex));
        panel.setCandidateList(std::move(candidateList));
        if (result.associatedPhrases) {
            panel.setAuxUp(fcitx::Text("Shift + 1-9"));
        }
    }

    inputContext_->updatePreedit();
    inputContext_->updateUserInterface(fcitx::UserInterfaceComponent::InputPanel);
}

class FcitxEngineFactory : public fcitx::AddonFactory {
public:
    fcitx::AddonInstance *create(fcitx::AddonManager *manager) override {
        return new FcitxEngine(manager->instance());
    }
};

} // namespace

FCITX_ADDON_FACTORY(FcitxEngineFactory);

#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/cin_dictionary.h"
#include "keykey/linux_ime/engine.h"
#ifndef KEYKEY_ENABLE_GUANYINMA
#define KEYKEY_ENABLE_GUANYINMA 0
#endif
#if KEYKEY_ENABLE_GUANYINMA
#include "keykey/linux_ime/guanyinma_session.h"
#endif

#include "error_sound.h"

#include <fcitx-config/configuration.h>
#include <fcitx-config/iniparser.h>
#include <fcitx-config/option.h>
#include <fcitx-utils/key.h>
#include <fcitx-utils/keysym.h>
#include <fcitx-utils/macros.h>
#include <fcitx-utils/log.h>
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
#include <algorithm>
#include <cstdint>
#include <cstdlib>
#include <memory>
#include <optional>
#include <stdexcept>
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

bool legacyInputKey(const fcitx::KeyEvent &event) {
    const auto symbol = event.key().sym();
    if (symbol >= FcitxKey_space && symbol <= FcitxKey_asciitilde) return true;
    switch (symbol) {
    case FcitxKey_Return: case FcitxKey_KP_Enter:
    case FcitxKey_BackSpace: case FcitxKey_Delete: case FcitxKey_KP_Delete:
    case FcitxKey_Tab: case FcitxKey_KP_Tab: case FcitxKey_ISO_Left_Tab:
    case FcitxKey_Escape: case FcitxKey_Left: case FcitxKey_Right:
    case FcitxKey_Up: case FcitxKey_Down: case FcitxKey_Home: case FcitxKey_KP_Home:
    case FcitxKey_End: case FcitxKey_KP_End: case FcitxKey_Page_Up: case FcitxKey_Page_Down:
        return true;
    default: return false;
    }
}

class BopomofoLayoutAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Standard");
        config.setValueByPath("EnumI18n/0", "標準");
        config.setValueByPath("Enum/1", "ETen");
        config.setValueByPath("EnumI18n/1", "倚天");
        config.setValueByPath("Enum/2", "ETen26");
        config.setValueByPath("EnumI18n/2", "倚天 26 鍵");
        config.setValueByPath("Enum/3", "Hsu");
        config.setValueByPath("EnumI18n/3", "許氏");
        config.setValueByPath("Enum/4", "HanyuPinyin");
        config.setValueByPath("EnumI18n/4", "漢語拼音");
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

#if KEYKEY_ENABLE_GUANYINMA
constexpr const char *kDefaultInputCore = "Guanyinma";
#else
constexpr const char *kDefaultInputCore = "Legacy";
#endif

class InputCoreAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Legacy");
#if KEYKEY_ENABLE_GUANYINMA
        config.setValueByPath("EnumI18n/0", "C++ 原核心");
        config.setValueByPath("Enum/1", "Guanyinma");
        config.setValueByPath("EnumI18n/1", "Guanyinma（Rust，預設）");
#else
        config.setValueByPath("EnumI18n/0", "C++ 原核心（預設）");
#endif
    }
};

class CandidateWindowStyleAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "Vertical");
        config.setValueByPath("EnumI18n/0", "直式");
        config.setValueByPath("Enum/1", "Horizontal");
        config.setValueByPath("EnumI18n/1", "橫式");
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

FCITX_CONFIGURATION(
    SmartMandarinConfig,
    fcitx::Option<bool> showCandidateListWithSpace{
        this, "ShowCandidateListWithSpace", "空白鍵開啟候選", false};
    fcitx::Option<bool> candidateCursorAtEndOfTargetBlock{
        this, "CandidateCursorAtEndOfTargetBlock",
        "選字目標在游標前方（取消為後方）", false};
    fcitx::Option<bool> clearComposingTextWithEsc{
        this, "ClearComposingTextWithEsc",
        "Esc 清除整句（候選窗／未完成讀音優先取消）", false};)

FCITX_CONFIGURATION(
    CangjieConfig,
    fcitx::ExternalOption settings{this, "Settings", "開啟倉頡設定…", "keykey-cangjie-settings"};
    fcitx::HiddenOption<bool> composeWhileTyping{this, "ComposeWhileTyping", "即時候選", false};
    fcitx::HiddenOption<bool> prefixCandidates{this, "PrefixCandidates", "未打完也能選字", false};
    fcitx::HiddenOption<bool> clearOnError{this, "ClearOnError", "錯碼清除", true};)

FCITX_CONFIGURATION(
    KeyKeyConfig,
    fcitx::OptionWithAnnotation<std::string, InputCoreAnnotation>
        inputCore{this, "InputCore", "輸入核心", kDefaultInputCore};
    fcitx::ExternalOption about{
        this, "About", "關於琦琦輸入法 — 版本 " KEYKEY_VERSION_STRING "…",
        "keykey-about"};
    fcitx::ExternalOption updates{
        this, "UpdateNotification", "更新通知與下載…",
        "keykey-update-notify"};
    fcitx::OptionWithAnnotation<std::string, BopomofoLayoutAnnotation>
        bopomofoLayout{this, "BopomofoLayout", "注音鍵盤配置",
                       "Standard"};
    fcitx::OptionWithAnnotation<std::string, BopomofoModeAnnotation>
        bopomofoMode{this, "BopomofoMode", "注音模式", "Smart"};
    fcitx::Option<CangjieConfig> cangjie{this, "Cangjie", "倉頡設定"};
    fcitx::Option<SmartMandarinConfig> smartMandarin{
        this, "SmartMandarin", "好打注音進階設定"};
    fcitx::OptionWithAnnotation<std::string, CandidateWindowStyleAnnotation>
        candidateWindowStyle{this, "CandidateWindowStyle",
                             "候選字窗方向", "Vertical"};
    fcitx::Option<bool> traditionalToSimplified{
        this, "TraditionalToSimplified",
        "繁體轉簡體輸出", false};
    fcitx::Option<bool> useAllUnicodeCharacters{
        this, "UseAllUnicodeCharacters",
        "顯示 Big5 以外的候選字", true};
    fcitx::Option<bool> playSoundOnTypingError{
        this, "PlaySoundOnTypingError", "輸入錯誤時播放提示音", true};
    fcitx::Option<bool> toggleWithControlBackslash{
        this, "ToggleInputMethodWithControlBackslash",
        "使用 Ctrl+\\ 切換中英文", true};
    fcitx::Option<AssociatedPhraseConfig> associatedPhrases{
        this, "AssociatedPhrases", "關聯詞庫"};
    fcitx::HiddenOption<std::string> associatedPhraseCollections{
        this, "AssociatedPhraseCollections",
        "舊版關聯詞庫設定", "McBopomofo"};)

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
    void select(std::size_t displayedIndex, std::uint64_t view = 0);
    bool selectSmartCharacter(std::size_t preeditCharacterIndex);
    void reset();
    bool commitAndReset(bool retireOnFailure = false);
    void commitIfEngine(const linux_ime::Engine *engine) {
        if (sourceEngine_ == engine) commitAndReset(true);
    }
    bool chineseMode() const noexcept { return chineseMode_; }
    bool usesGuanyinma() const noexcept {
#if KEYKEY_ENABLE_GUANYINMA
        return rust_ != nullptr;
#else
        return false;
#endif
    }
    std::string coreStatus() const;
    bool corePending() const noexcept { return requestedRust_ != usesGuanyinma(); }
#if KEYKEY_ENABLE_GUANYINMA
    void requestCore(bool useRust, linux_ime::GuanyinmaConfig config,
                     std::string modelPath, std::string userPath,
                     std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated,
                     std::shared_ptr<const linux_ime::CinDictionary> simplified,
                     std::vector<std::string> collections,
                     linux_ime::GuanyinmaSession::CandidateFilter filter = {});
#else
    void requestCore(bool useRust) {
        requestedRust_ = false;
        if (useRust) coreError_ = "此建置未包含 Guanyinma";
    }
#endif

private:
    struct ShiftPress {
        std::uint32_t eventTime = 0;
        std::chrono::steady_clock::time_point monotonicTime;
    };

    void toggleChineseMode();
    void apply(const linux_ime::EngineResult &result);
    void updateUi(const linux_ime::EngineResult &result);
    linux_ime::EngineResult currentView() const;
    bool quiet() const;
    void prepareCore();
#if KEYKEY_ENABLE_GUANYINMA
    void processRust(const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent,
                     bool playSound, const fcitx5_adapter::ErrorSound &errorSound);
    void applyRust(linux_ime::EngineResult result, bool offerAssociated = true);
    linux_ime::EngineResult associatedView() const;
    bool processAssociated(const linux_ime::KeyEvent &event,
                           linux_ime::EngineResult &result);
    linux_ime::EngineResult selectAssociated(std::size_t displayedIndex);
    void clearAssociated();

    std::unique_ptr<linux_ime::GuanyinmaSession> rust_;
    linux_ime::GuanyinmaConfig requestedConfig_;
    std::string modelPath_;
    std::string userPath_;
    std::uint64_t requestRevision_ = 0;
    std::uint64_t attemptedRevision_ = 0;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated_;
    std::shared_ptr<const linux_ime::CinDictionary> simplified_;
    std::vector<std::string> collections_;
    linux_ime::GuanyinmaSession::CandidateFilter candidateFilter_;
    std::vector<std::string> associatedCandidates_;
    std::size_t associatedPage_ = 0;
    std::size_t associatedHighlight_ = 0;
#endif

    fcitx::InputContext *inputContext_;
    linux_ime::InputContextState context_;
    const linux_ime::Engine *sourceEngine_ = nullptr;
    // Keep the configuration that owns this composition. applyConfig mutates
    // shared engines before the next key or deactivation reaches this state.
    std::unique_ptr<linux_ime::Engine> activeEngine_;
    bool chineseMode_ = true;
    bool smartMode_ = false;
    bool requestedRust_ = false;
    bool fullWidth_ = false;
    bool simplifiedOutput_ = false;
    bool effectsInProgress_ = false;
    std::uint64_t viewGeneration_ = 1;
    std::string coreError_;
    fcitx::CandidateLayoutHint candidateLayout_ =
        fcitx::CandidateLayoutHint::Vertical;
    std::optional<ShiftPress> shiftPressedAt_;
    bool controlBackslashPressed_ = false;
};

class CandidateWord : public fcitx::CandidateWord {
public:
    CandidateWord(FcitxState *state, std::size_t displayedIndex,
                  std::string value, std::uint64_t view, fcitx::InputContext *owner)
        : state_(state), displayedIndex_(displayedIndex), view_(view), owner_(owner->watch()) {
        setText(fcitx::Text(std::move(value)));
    }

    void select(fcitx::InputContext *inputContext) const override {
        if (owner_.get() != inputContext || !owner_.isValid()) return;
        state_->select(displayedIndex_, view_);
    }

private:
    FcitxState *state_;
    std::size_t displayedIndex_;
    std::uint64_t view_;
    fcitx::TrackableObjectReference<fcitx::InputContext> owner_;
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
                        ->commitAndReset(true);
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
        const auto original = event.inputContext()->watch();
        requestCore(*state, entry.uniqueName());
        if (!original.isValid()) return;
        linux_ime::KeyEvent translated;
        if (!translate(event, translated)) {
            return;
        }
        if (!state->usesGuanyinma() && *config_.inputCore != "Guanyinma" &&
            !legacyInputKey(event)) {
            // Preserve the old C++ path's accepted key surface. Its key type
            // remains ASCII; Rust receives native Unicode/keypad separately.
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
        auto *state = inputContext.propertyFor(&factory_);
        return std::string(state->chineseMode() ? "中文 · " : "英文 · ") +
               state->coreStatus();
    }

    void reset(const fcitx::InputMethodEntry &entry,
               fcitx::InputContextEvent &event) override {
        FCITX_UNUSED(entry);
        event.inputContext()->propertyFor(&factory_)->reset();
    }

    void deactivate(const fcitx::InputMethodEntry &entry,
                    fcitx::InputContextEvent &event) override {
        FCITX_UNUSED(entry);
        event.inputContext()->propertyFor(&factory_)->commitAndReset(true);
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
    void requestCore(FcitxState &state, const std::string &method) const {
#if KEYKEY_ENABLE_GUANYINMA
        linux_ime::GuanyinmaConfig settings;
        settings.inputMethod = method == "chichi77-keykey-cangjie"
            ? linux_ime::InputMethod::Cangjie
            : method == "chichi77-keykey-simplex"
                ? linux_ime::InputMethod::Simplex
                : linux_ime::InputMethod::Bopomofo;
        settings.smartMode = settings.inputMethod == linux_ime::InputMethod::Bopomofo &&
                             *config_.bopomofoMode != "Traditional";
        const std::string &layout = *config_.bopomofoLayout;
        settings.layout = layout == "ETen" ? linux_ime::BopomofoLayout::ETen
            : layout == "ETen26" ? linux_ime::BopomofoLayout::ETen26
            : layout == "Hsu" ? linux_ime::BopomofoLayout::Hsu
            : layout == "HanyuPinyin" ? linux_ime::BopomofoLayout::HanyuPinyin
            : linux_ime::BopomofoLayout::Standard;
        const auto &smart = *config_.smartMandarin;
        settings.smart = {*smart.showCandidateListWithSpace,
                          *smart.candidateCursorAtEndOfTargetBlock,
                          *smart.clearComposingTextWithEsc};
        const auto &table = *config_.cangjie;
        settings.table = {*table.composeWhileTyping, *table.prefixCandidates,
                          *table.clearOnError};
        settings.restrictBopomofoToBig5 = !*config_.useAllUnicodeCharacters;
        const char *overrideDirectory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
        const std::string directory = overrideDirectory == nullptr
            ? KEYKEY_LINUX_DATA_DIR : overrideDirectory;
        state.requestCore(*config_.inputCore == "Guanyinma", settings,
            directory + "/smart-mandarin.db",
            linux_ime::GuanyinmaSession::defaultUserDatabasePath(),
            associatedPhraseDictionary_, traditionalToSimplifiedDictionary_,
            enabledAssociatedPhraseCollections(*config_.associatedPhrases));
#else
        FCITX_UNUSED(method);
        state.requestCore(*config_.inputCore == "Guanyinma");
#endif
    }

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
        auto &cangjie = *config_.cangjie.mutableValue();
        if (*cangjie.composeWhileTyping) cangjie.clearOnError.setValue(false);
        const linux_ime::TablePreferences nextCangjie{
            *cangjie.composeWhileTyping, *cangjie.prefixCandidates, *cangjie.clearOnError};
        if (cangjieOptionsLoaded_ &&
            (nextCangjie.composeWhileTyping != cangjieOptions_.composeWhileTyping ||
             nextCangjie.prefixCandidates != cangjieOptions_.prefixCandidates ||
             nextCangjie.clearOnError != cangjieOptions_.clearOnError)) {
            instance_->inputContextManager().foreach([this](fcitx::InputContext *context) {
                context->propertyFor(&factory_)->commitIfEngine(&cangjieEngine_);
                return true;
            });
        }
        cangjieOptions_ = nextCangjie;
        cangjieOptionsLoaded_ = true;
        cangjieEngine_.setTablePreferences(nextCangjie);
        const bool smart = *config_.bopomofoMode != "Traditional";
        const auto &preferences = *config_.smartMandarin;
        for (linux_ime::Engine *engine : {&standardEngine_, &etenEngine_,
                                          &eten26Engine_, &hsuEngine_,
                                          &hanyuPinyinEngine_}) {
            engine->setSmartMandarinStore(smartMandarinStore_);
            engine->setSmartMandarinMode(smart);
            engine->setSmartMandarinPreferences({
                *preferences.showCandidateListWithSpace,
                *preferences.candidateCursorAtEndOfTargetBlock,
                *preferences.clearComposingTextWithEsc});
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
        instance_->inputContextManager().foreach([this](fcitx::InputContext *context) {
            const auto method = instance_->inputMethod(context);
            if (isKeyKeyInputMethod(method)) {
                requestCore(*context->propertyFor(&factory_), method);
            }
            return true;
        });
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
        destination.rawShift = source.rawKey().states().test(fcitx::KeyState::Shift);
        destination.numLock = source.rawKey().states().test(fcitx::KeyState::NumLock);
        destination.keypad = source.rawKey().isKeyPad();
        destination.text = fcitx::Key::keySymToUTF8(source.rawKey().sym());
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
        case FcitxKey_KP_Left:
            destination.code = linux_ime::KeyCode::Left;
            return true;
        case FcitxKey_Right:
        case FcitxKey_KP_Right:
            destination.code = linux_ime::KeyCode::Right;
            return true;
        case FcitxKey_Up:
        case FcitxKey_KP_Up:
            destination.code = linux_ime::KeyCode::Up;
            return true;
        case FcitxKey_Down:
        case FcitxKey_KP_Down:
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
        case FcitxKey_KP_Page_Up:
            destination.code = linux_ime::KeyCode::PageUp;
            return true;
        case FcitxKey_Page_Down:
        case FcitxKey_KP_Page_Down:
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
        if (!destination.text.empty() &&
            fcitx::Key::keySymToUnicode(source.rawKey().sym()) >= 0x20U &&
            fcitx::Key::keySymToUnicode(source.rawKey().sym()) != 0x7FU) {
            destination.code = linux_ime::KeyCode::Character;
            if (destination.text.size() == 1) destination.character = destination.text[0];
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
    linux_ime::TablePreferences cangjieOptions_;
    bool cangjieOptionsLoaded_ = false;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        keyEventWatcher_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        switchEventWatcher_;
};

#undef KEYKEY_ASSOCIATED_PHRASE_OPTIONS

std::string FcitxState::coreStatus() const {
    std::string result = usesGuanyinma() ? "Guanyinma（Rust）" : "C++ 原核心";
    if (corePending()) {
        result += requestedRust_ ? " → Guanyinma（組字完成後切換）"
                                 : " → C++ 原核心（組字完成後切換）";
    }
    if (!coreError_.empty()) result += "；" + coreError_;
    return result;
}

linux_ime::EngineResult FcitxState::currentView() const {
#if KEYKEY_ENABLE_GUANYINMA
    if (rust_) {
        return associatedCandidates_.empty() ? rust_->snapshot() : associatedView();
    }
#endif
    return activeEngine_ ? activeEngine_->snapshot(context_) : linux_ime::EngineResult{};
}

bool FcitxState::quiet() const {
    const auto view = currentView();
    return !effectsInProgress_ && view.preedit.empty() && view.candidates.empty()
#if KEYKEY_ENABLE_GUANYINMA
           && (!rust_ || rust_->quiet())
#endif
        ;
}

#if KEYKEY_ENABLE_GUANYINMA
void FcitxState::requestCore(bool useRust, linux_ime::GuanyinmaConfig config,
    std::string modelPath, std::string userPath,
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated,
    std::shared_ptr<const linux_ime::CinDictionary> simplified,
    std::vector<std::string> collections,
    linux_ime::GuanyinmaSession::CandidateFilter filter) {
    if (useRust != requestedRust_ || config != requestedConfig_ ||
        modelPath != modelPath_ || userPath != userPath_ || collections != collections_ ||
        requestRevision_ == 0) {
        ++requestRevision_;
        coreError_.clear();
    }
    requestedRust_ = useRust;
    requestedConfig_ = std::move(config);
    modelPath_ = std::move(modelPath);
    userPath_ = std::move(userPath);
    associated_ = std::move(associated);
    simplified_ = std::move(simplified);
    collections_ = std::move(collections);
    candidateFilter_ = std::move(filter);
    // Saving a preference never finishes composition or switches the backend.
    if (corePending() || !coreError_.empty()) updateUi(currentView());
}
#endif

void FcitxState::prepareCore() {
    if (!quiet()) return;
#if KEYKEY_ENABLE_GUANYINMA
    if (requestedRust_) {
        if (rust_ && rust_->valid() && rust_->config() == requestedConfig_) return;
        if (attemptedRevision_ == requestRevision_) return;
        attemptedRevision_ = requestRevision_;
        try {
            auto replacement = std::make_unique<linux_ime::GuanyinmaSession>(
                modelPath_, userPath_, requestedConfig_, candidateFilter_);
            replacement->setFullWidth(fullWidth_);
            if (!replacement->lastError().empty()) {
                throw std::runtime_error(replacement->lastError());
            }
            rust_ = std::move(replacement);
            context_.reset();
            clearAssociated();
            coreError_.clear();
            ++viewGeneration_;
            FCITX_INFO() << "KeyKey active core: Guanyinma";
        } catch (const std::exception &error) {
            coreError_ = std::string("Guanyinma 無法啟用：") + error.what();
            FCITX_WARN() << coreError_;
        }
    } else if (rust_) {
        fullWidth_ = rust_->snapshot().fullWidthMode;
        rust_.reset();
        clearAssociated();
        ++viewGeneration_;
        FCITX_INFO() << "KeyKey active core: Legacy";
    }
#endif
    if (!usesGuanyinma() && activeEngine_ &&
        activeEngine_->snapshot(context_).fullWidthMode != fullWidth_) {
        linux_ime::KeyEvent toggle;
        toggle.code = linux_ime::KeyCode::Space;
        toggle.modifiers = linux_ime::KeyModifier::Shift;
        activeEngine_->processKey(context_, toggle);
    }
}

#if KEYKEY_ENABLE_GUANYINMA
void FcitxState::clearAssociated() {
    associatedCandidates_.clear();
    associatedPage_ = 0;
    associatedHighlight_ = 0;
}

linux_ime::EngineResult FcitxState::associatedView() const {
    linux_ime::EngineResult result;
    result.fullWidthMode = fullWidth_;
    result.associatedPhrases = !associatedCandidates_.empty();
    result.candidatePage = associatedPage_;
    result.candidatePageCount = (associatedCandidates_.size() + 8U) / 9U;
    result.highlightedIndex = associatedHighlight_;
    const std::size_t first = associatedPage_ * 9U;
    const std::size_t end = std::min(first + 9U, associatedCandidates_.size());
    if (first < end) {
        result.candidates.assign(associatedCandidates_.begin() + static_cast<std::ptrdiff_t>(first),
                                 associatedCandidates_.begin() + static_cast<std::ptrdiff_t>(end));
    }
    return result;
}

linux_ime::EngineResult FcitxState::selectAssociated(std::size_t displayedIndex) {
    const std::size_t absolute = associatedPage_ * 9U + displayedIndex;
    if (displayedIndex >= 9U || absolute >= associatedCandidates_.size()) {
        auto result = associatedView();
        result.handled = true;
        result.beep = true;
        return result;
    }
    const std::string selected = associatedCandidates_[absolute];
    clearAssociated();
    auto result = rust_->snapshot();
    result.handled = true;
    // This is FE raw text, unlike an already-width-converted core effect.
    result.commit = fullWidth_ ? linux_ime::toFullWidth(selected) : selected;
    return result;
}

bool FcitxState::processAssociated(const linux_ime::KeyEvent &event,
                                  linux_ime::EngineResult &result) {
    if (associatedCandidates_.empty()) return false;
    if (event.release) {
        result = associatedView();
        return true;
    }
    const auto modifiers = static_cast<unsigned int>(event.modifiers);
    const auto shortcuts = static_cast<unsigned int>(linux_ime::KeyModifier::Control) |
                           static_cast<unsigned int>(linux_ime::KeyModifier::Alt) |
                           static_cast<unsigned int>(linux_ime::KeyModifier::Super);
    const bool hasShortcut = (modifiers & shortcuts) != 0U;
    const bool shift = !hasShortcut &&
                       (event.rawShift || event.modifiers == linux_ime::KeyModifier::Shift);
    const auto shifted = std::string("!@#$%^&*(").find(event.character);
    if (event.code == linux_ime::KeyCode::Character &&
        !hasShortcut &&
        (shift || (event.modifiers == linux_ime::KeyModifier::None && shifted != std::string::npos))) {
        const std::size_t index = event.character >= '1' && event.character <= '9'
            ? static_cast<std::size_t>(event.character - '1') : shifted;
        if (index != std::string::npos) {
            result = selectAssociated(index);
            return true;
        }
    }
    if (event.code == linux_ime::KeyCode::Enter || event.code == linux_ime::KeyCode::Escape ||
        event.code == linux_ime::KeyCode::Backspace) {
        clearAssociated();
        result = rust_->snapshot();
        result.handled = event.code != linux_ime::KeyCode::Backspace;
        result.updateUi = true;
        return true;
    }
    if (event.modifiers == linux_ime::KeyModifier::None) {
        const std::size_t count = associatedCandidates_.size();
        const std::size_t pages = (count + 8U) / 9U;
        std::size_t absolute = associatedPage_ * 9U + associatedHighlight_;
        switch (event.code) {
        case linux_ime::KeyCode::Up:
            absolute = (absolute + count - 1U) % count;
            break;
        case linux_ime::KeyCode::Down:
            absolute = (absolute + 1U) % count;
            break;
        case linux_ime::KeyCode::Home:
            absolute = 0;
            break;
        case linux_ime::KeyCode::End:
            absolute = count - 1U;
            break;
        case linux_ime::KeyCode::Space:
        case linux_ime::KeyCode::Right:
        case linux_ime::KeyCode::PageDown:
            absolute = ((associatedPage_ + 1U) % pages) * 9U;
            break;
        case linux_ime::KeyCode::Left:
        case linux_ime::KeyCode::PageUp:
            absolute = ((associatedPage_ + pages - 1U) % pages) * 9U;
            break;
        default:
            clearAssociated();
            return false;
        }
        associatedPage_ = absolute / 9U;
        associatedHighlight_ = absolute % 9U;
        result = associatedView();
        result.handled = true;
        return true;
    }
    clearAssociated();
    return false;
}

void FcitxState::applyRust(linux_ime::EngineResult result, bool offerAssociated) {
    fullWidth_ = result.fullWidthMode;
    coreError_ = rust_->lastError();
    const auto capabilities = inputContext_->capabilityFlags();
    const bool sensitive = capabilities.test(fcitx::CapabilityFlag::Password) ||
                           capabilities.test(fcitx::CapabilityFlag::Sensitive);
    if (offerAssociated && !sensitive && !smartMode_ && associated_ &&
        !result.commit.empty() && rust_->quiet()) {
        associatedCandidates_ = associated_->candidates(result.commit, collections_);
        associatedCandidates_.erase(std::remove_if(associatedCandidates_.begin(), associatedCandidates_.end(),
            [this](const std::string &text) { return !rust_->acceptsCandidate(text); }),
            associatedCandidates_.end());
        associatedPage_ = 0;
        associatedHighlight_ = 0;
    }
    if (simplifiedOutput_ && simplified_ && !result.commit.empty()) {
        result.commit = linux_ime::toSimplifiedChinese(result.commit, *simplified_);
    }
    if (!associatedCandidates_.empty()) {
        auto view = associatedView();
        view.commit = std::move(result.commit);
        view.handled = result.handled;
        view.beep = result.beep;
        view.deleteBackward = result.deleteBackward;
        view.sendReturn = result.sendReturn;
        view.discardComposition = result.discardComposition;
        result = std::move(view);
    }
    apply(result);
}

void FcitxState::processRust(const linux_ime::KeyEvent &event,
                            fcitx::KeyEvent &fcitxEvent, bool playSound,
                            const fcitx5_adapter::ErrorSound &errorSound) {
    if (effectsInProgress_ || !rust_->valid()) {
        // A retired/failed operation is never applied a second time.
        fcitxEvent.filterAndAccept();
        return;
    }
    const auto modifiers = static_cast<unsigned int>(event.modifiers);
    const auto shortcuts = static_cast<unsigned int>(linux_ime::KeyModifier::Control) |
                           static_cast<unsigned int>(linux_ime::KeyModifier::Alt) |
                           static_cast<unsigned int>(linux_ime::KeyModifier::Super);
    const bool widthToggle = event.code == linux_ime::KeyCode::Space &&
                             (event.rawShift || event.modifiers == linux_ime::KeyModifier::Shift) &&
                             (modifiers & shortcuts) == 0U;
    if (widthToggle) {
        if (!event.release && !event.repeat) {
            applyRust(rust_->setFullWidth(!fullWidth_), false);
        }
        fcitxEvent.filterAndAccept();
        return;
    }
    if (!chineseMode_) {
        if (event.release || (modifiers & shortcuts) != 0U || !fullWidth_) return;
        const std::string text = event.code == linux_ime::KeyCode::Space ? " "
            : event.code == linux_ime::KeyCode::Character ? event.text : std::string{};
        if (text.empty()) return;
        auto result = rust_->snapshot();
        result.commit = linux_ime::toFullWidth(text);
        result.handled = true;
        applyRust(std::move(result), false);
        fcitxEvent.filterAndAccept();
        return;
    }
    const auto capabilities = inputContext_->capabilityFlags();
    if (capabilities.test(fcitx::CapabilityFlag::Password) ||
        capabilities.test(fcitx::CapabilityFlag::Sensitive)) clearAssociated();

    auto editing = event;
    if (associatedCandidates_.empty() &&
        rust_->config().inputMethod == linux_ime::InputMethod::Bopomofo &&
        !rust_->snapshot().candidates.empty() &&
        event.code == linux_ime::KeyCode::Character &&
        (event.modifiers == linux_ime::KeyModifier::None ||
         event.modifiers == linux_ime::KeyModifier::Shift) &&
        (event.character == '<' || event.character == '>')) {
        // The native FE owns this binding. Shift used to type '<'/'>' is not
        // a modifier on the resulting semantic paging operation.
        editing.code = event.character == '>' ? linux_ime::KeyCode::PageDown : linux_ime::KeyCode::PageUp;
        editing.modifiers = linux_ime::KeyModifier::None;
        editing.rawShift = false;
        editing.text.clear();
    }
    if (candidateLayout_ == fcitx::CandidateLayoutHint::Horizontal &&
        event.modifiers == linux_ime::KeyModifier::None && !currentView().candidates.empty()) {
        switch (editing.code) {
        case linux_ime::KeyCode::Left: editing.code = linux_ime::KeyCode::Up; break;
        case linux_ime::KeyCode::Right: editing.code = linux_ime::KeyCode::Down; break;
        case linux_ime::KeyCode::Up: editing.code = linux_ime::KeyCode::Left; break;
        case linux_ime::KeyCode::Down: editing.code = linux_ime::KeyCode::Right; break;
        default: break;
        }
    }
    linux_ime::EngineResult result;
    const bool overlay = processAssociated(editing, result);
    if (!overlay) result = rust_->processKey(editing);
    if (result.beep && playSound) errorSound.play();
    const bool handled = result.handled;
    if (handled || result.updateUi) applyRust(std::move(result), !overlay);
    if (handled) fcitxEvent.filterAndAccept();
}
#endif

void FcitxState::process(const linux_ime::Engine &sourceEngine,
                         bool smartMode,
                         bool traditionalToSimplified,
                         bool playSoundOnTypingError,
                         fcitx::CandidateLayoutHint candidateLayout,
                         const fcitx5_adapter::ErrorSound &errorSound,
                         const linux_ime::KeyEvent &event,
                         fcitx::KeyEvent &fcitxEvent) {
    candidateLayout_ = candidateLayout;
    simplifiedOutput_ = traditionalToSimplified;
    const bool smartPreferencesChanged = smartMode && activeEngine_ &&
        !(activeEngine_->smartMandarinPreferences() ==
          sourceEngine.smartMandarinPreferences());
    if (sourceEngine_ != &sourceEngine || smartMode_ != smartMode ||
        smartPreferencesChanged) {
        if (!commitAndReset()) {
            fcitxEvent.filterAndAccept();
            return;
        }
        activeEngine_.reset();
#if KEYKEY_ENABLE_GUANYINMA
        rust_.reset();
        attemptedRevision_ = 0;
#endif
        sourceEngine_ = &sourceEngine;
        smartMode_ = smartMode;
    }
    const auto current = currentView();
    if (!activeEngine_ || (current.preedit.empty() && current.candidates.empty())) {
        activeEngine_ = std::make_unique<linux_ime::Engine>(sourceEngine);
    }
    if (!event.release) prepareCore();
#if KEYKEY_ENABLE_GUANYINMA
    if (rust_) {
        processRust(event, fcitxEvent, playSoundOnTypingError, errorSound);
        return;
    }
#endif
    if (!legacyInputKey(fcitxEvent)) return;
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
            // The press was passed to the client. Filter other IM handlers
            // without accepting its release, so the client can clear Shift.
            // Accepting only the release leaves applications with Shift held.
            event.filter();
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
                const auto original = inputContext_->watch();
                toggleChineseMode();
                if (!original.isValid()) {
                    event.filterAndAccept();
                    return true;
                }
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
    if (!commitAndReset()) return;
    chineseMode_ = !chineseMode_;
    inputContext_->updateUserInterface(
        fcitx::UserInterfaceComponent::StatusArea);
}

void FcitxState::select(std::size_t displayedIndex, std::uint64_t view) {
    if (effectsInProgress_ || (view != 0 && view != viewGeneration_)) return;
#if KEYKEY_ENABLE_GUANYINMA
    if (rust_) {
        const bool overlay = !associatedCandidates_.empty();
        applyRust(overlay ? selectAssociated(displayedIndex)
                          : rust_->selectDisplayedCandidate(displayedIndex), !overlay);
        return;
    }
#endif
    if (activeEngine_ != nullptr) {
        apply(activeEngine_->selectDisplayedCandidate(context_, displayedIndex));
    }
}

bool FcitxState::selectSmartCharacter(std::size_t preeditCharacterIndex) {
    if (effectsInProgress_) return false;
#if KEYKEY_ENABLE_GUANYINMA
    if (rust_) {
        if (!smartMode_ || !associatedCandidates_.empty()) return false;
        auto result = rust_->selectSmartCharacter(preeditCharacterIndex);
        const bool handled = result.handled;
        if (handled) applyRust(std::move(result), false);
        return handled;
    }
#endif
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

bool FcitxState::commitAndReset(bool retireOnFailure) {
#if !KEYKEY_ENABLE_GUANYINMA
    FCITX_UNUSED(retireOnFailure);
#endif
    if (effectsInProgress_) return false;
    const auto original = inputContext_->watch();
    if (!inputContext_->hasFocus() &&
        inputContext_->capabilityFlags().test(
            fcitx::CapabilityFlag::ClientUnfocusCommit)) {
        // GTK/Qt frontends with this capability commit the visible client
        // preedit before reporting focus-out. Committing the engine buffer
        // again here would duplicate the composition in the document.
        reset();
        return original.isValid();
    }
#if KEYKEY_ENABLE_GUANYINMA
    if (rust_) {
        clearAssociated();
        auto result = rust_->finishComposition();
        if (!rust_->lastError().empty()) {
            coreError_ = rust_->lastError();
            if (retireOnFailure || !inputContext_->hasFocus()) reset();
            else updateUi(result);
            return false;
        }
        applyRust(std::move(result), false);
        if (!original.isValid()) return false;
        reset();
        return original.isValid();
    }
#endif
    if (activeEngine_ != nullptr) {
        const linux_ime::EngineResult result =
            activeEngine_->finishComposition(context_);
        if (!result.commit.empty()) {
            inputContext_->commitString(result.commit);
            if (!original.isValid()) return false;
        }
    }
    reset();
    return original.isValid();
}

void FcitxState::reset() {
    shiftPressedAt_.reset();
    controlBackslashPressed_ = false;
    context_.reset();
#if KEYKEY_ENABLE_GUANYINMA
    clearAssociated();
    if (rust_) {
        fullWidth_ = rust_->snapshot().fullWidthMode;
        const auto result = rust_->reset();
        if (!rust_->valid()) {
            coreError_ = rust_->lastError();
            rust_.reset();
            attemptedRevision_ = 0;
        }
        updateUi(result);
        return;
    }
#endif
    if (activeEngine_ != nullptr) {
        updateUi(activeEngine_->snapshot(context_));
    }
}

void FcitxState::apply(const linux_ime::EngineResult &result) {
    if (effectsInProgress_) return;
    fullWidth_ = result.fullWidthMode;
    effectsInProgress_ = true;
    const auto original = inputContext_->watch();
    // Fcitx APIs deliver to this InputContext and return no application ack.
    // This batch is consumed once here; snapshots never enter this path.
    if (result.discardComposition) {
        inputContext_->inputPanel().reset();
        inputContext_->updatePreedit();
        if (!original.isValid()) return;
    }
    if (result.deleteBackward && original.isValid()) {
        inputContext_->forwardKey(fcitx::Key(FcitxKey_BackSpace));
        if (!original.isValid()) return;
        inputContext_->forwardKey(fcitx::Key(FcitxKey_BackSpace), true);
        if (!original.isValid()) return;
    }
    if (!result.commit.empty()) {
        inputContext_->commitString(result.commit);
        if (!original.isValid()) return;
    }
    if (result.sendReturn && original.isValid()) {
        inputContext_->forwardKey(fcitx::Key(FcitxKey_Return));
        if (!original.isValid()) return;
        inputContext_->forwardKey(fcitx::Key(FcitxKey_Return), true);
        if (!original.isValid()) return;
    }
    effectsInProgress_ = false;
    updateUi(result);
}

void FcitxState::updateUi(const linux_ime::EngineResult &result) {
    const auto original = inputContext_->watch();
    ++viewGeneration_;
    auto &panel = inputContext_->inputPanel();
    panel.reset();

    if (!result.preedit.empty()) {
        fcitx::Text preedit;
        if (result.hasMarkedPhrase && result.markedPreeditStartBytes <= result.preedit.size() &&
            result.markedPreeditLengthBytes <= result.preedit.size() - result.markedPreeditStartBytes) {
            const auto start = result.markedPreeditStartBytes;
            const auto end = start + result.markedPreeditLengthBytes;
            preedit.append(result.preedit.substr(0, start), fcitx::TextFormatFlag::Underline);
            preedit.append(result.preedit.substr(start, end - start), fcitx::TextFormatFlag::HighLight);
            preedit.append(result.preedit.substr(end), fcitx::TextFormatFlag::Underline);
        } else {
            preedit.append(result.preedit, fcitx::TextFormatFlag::Underline);
        }
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
                                                 result.candidates[index], viewGeneration_, inputContext_);
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
    if (corePending() || !coreError_.empty()) panel.setAuxDown(fcitx::Text(coreStatus()));
    if (!result.phraseFeedback.empty()) {
        panel.setAuxUp(fcitx::Text(result.phraseAdded ? "已加入詞庫：" + result.phraseFeedback
                                                     : "詞庫已有：" + result.phraseFeedback));
    }

    inputContext_->updatePreedit();
    if (!original.isValid()) return;
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

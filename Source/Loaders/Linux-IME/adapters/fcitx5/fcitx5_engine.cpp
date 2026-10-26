#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/cin_dictionary.h"
#include "keykey/linux_ime/guanyinma_session.h"

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

class SelectionKeysConstrain {
public:
    bool check(const std::string &value) const {
        if (value.empty() || value.size() > 32) return false;
        std::unordered_set<unsigned char> used;
        for (const unsigned char ch : value) if (ch < 0x21 || ch > 0x7e || !used.insert(ch).second) return false;
        return true;
    }
    void dumpDescription(fcitx::RawConfig &) const {}
};
class WildcardConstrain {
public:
    bool check(const std::string &value) const {
        return value.empty() || (value.size() == 1 && static_cast<unsigned char>(value[0]) >= 0x21 && static_cast<unsigned char>(value[0]) <= 0x7e);
    }
    void dumpDescription(fcitx::RawConfig &) const {}
};

class SelectionKeysAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        const std::vector<std::string> keys{"123456789", "12345678", "asdfghjk", "asdfzxcv", "asdfjkl;"};
        for (std::size_t i = 0; i < keys.size(); ++i) {
            config.setValueByPath("Enum/" + std::to_string(i), keys[i]);
            config.setValueByPath("EnumI18n/" + std::to_string(i), keys[i]);
        }
    }
};

class PunctuationAnnotation : public fcitx::EnumAnnotation {
public:
    void dumpDescription(fcitx::RawConfig &config) const {
        fcitx::EnumAnnotation::dumpDescription(config);
        config.setValueByPath("Enum/0", "original"); config.setValueByPath("EnumI18n/0", "原始標點");
        config.setValueByPath("Enum/1", "mixed"); config.setValueByPath("EnumI18n/1", "中英混合標點");
        config.setValueByPath("Enum/2", "half"); config.setValueByPath("EnumI18n/2", "半形標點");
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
    fcitx::Option<bool> showCandidateListWithSpace{this, "ShowCandidateListWithSpace", "空白鍵開啟候選", false};
    fcitx::Option<bool> candidateCursorAtEndOfTargetBlock{this, "CandidateCursorAtEndOfTargetBlock", "選字目標在游標前方（取消為後方）", false};
    fcitx::Option<bool> clearComposingTextWithEsc{this, "ClearComposingTextWithEsc", "Esc 清除整句（候選窗／未完成讀音優先取消）", false};
    fcitx::Option<int, fcitx::IntConstrain> maxCompletedSyllables{this, "ComposingTextBufferSize", "組字長度（音節）", 10, fcitx::IntConstrain(10, 20)};
    fcitx::Option<std::string, SelectionKeysConstrain, fcitx::DefaultMarshaller<std::string>, SelectionKeysAnnotation> candidateSelectionKeys{this, "CandidateSelectionKeys", "選字鍵", "123456789"};
    fcitx::Option<bool> selectionReturnsToEnd{this, "SelectionReturnsToEnd", "選字後游標回到句尾", false};
    fcitx::Option<bool> shiftAlwaysUppercase{this, "ShiftKeyAlwaysCommitUppercaseCharacters", "按住 Shift 輸入字母一律大寫", false};
    fcitx::Option<bool> useBigrams{this, "UseBigrams", "使用上下文組句", true};
    fcitx::Option<bool> learnCandidateOverrides{this, "LearnCandidateOverrides", "記憶選字偏好", true};
    fcitx::Option<bool> learnBigrams{this, "LearnBigrams", "學習相鄰詞", true};)

#define KEYKEY_TABLE_OPTIONS(prefixOption, realtime, prefix, clear, query, maximum, first, one, many) \
    fcitx::Option<bool> composeWhileTyping{this, "ComposeWhileTyping", "即時候選", realtime}; \
    fcitx::prefixOption<bool> prefixCandidates{this, "PrefixCandidates", "未打完也能選字", prefix}; \
    fcitx::Option<bool> clearOnError{this, "ClearOnError", "錯碼清除", clear}; \
    fcitx::Option<bool> queryAtMaximum{this, "ShouldCommitAtMaximumRadicalLength", "滿碼時查詢候選", query}; \
    fcitx::Option<bool> learnSelection{this, "UseDynamicFrequency", "動態詞頻（記憶選字）", false}; \
    fcitx::Option<std::string, SelectionKeysConstrain, fcitx::DefaultMarshaller<std::string>, SelectionKeysAnnotation> candidateSelectionKeys{this, "CandidateSelectionKeys", "選字鍵", "123456789"}; \
    fcitx::OptionWithAnnotation<std::string, PunctuationAnnotation> punctuation{this, "PunctuationStyle", "標點符號", "original"}; \
    fcitx::Option<int, fcitx::IntConstrain> maximumRadicalLength{this, "MaximumRadicalLength", "最長字根數", maximum, fcitx::IntConstrain(1, maximum)}; \
    fcitx::Option<bool> spaceAsFirstSelectionKey{this, "UseSpaceAsFirstCandidateSelectionKey", "以空白鍵作為第一個選字鍵", false}; \
    fcitx::Option<bool> spaceCommitsFirstOnSinglePage{this, "SendFirstCandidateWithSpaceWithOnePageList", "只有一頁候選時以空白鍵送出首字", first}; \
    fcitx::Option<std::string, WildcardConstrain> wildcardOne{this, "MatchOneChar", "單一字根通配字（空白為停用）", one}; \
    fcitx::Option<std::string, WildcardConstrain> wildcardMany{this, "MatchZeroOrMoreChar", "多個字根通配字（空白為停用）", many};

FCITX_CONFIGURATION(CangjieConfig,
    fcitx::ExternalOption settings{this, "Settings", "開啟倉頡設定…", "keykey-cangjie-settings"};
    KEYKEY_TABLE_OPTIONS(Option, false, false, true, false, 5, true, "?", "*"))
FCITX_CONFIGURATION(SimplexConfig,
    KEYKEY_TABLE_OPTIONS(HiddenOption, false, false, false, true, 2, false, "", ""))
#undef KEYKEY_TABLE_OPTIONS

FCITX_CONFIGURATION(
    KeyKeyConfig,
    fcitx::ExternalOption userPhrases{this, "UserPhrases", "管理自訂詞與學習資料…", "keykey-user-phrases"};
    fcitx::ExternalOption about{this, "About", "關於琦琦輸入法 — 版本 " KEYKEY_VERSION_STRING "…", "keykey-about"};
    fcitx::ExternalOption updates{this, "UpdateNotification", "更新通知與下載…", "keykey-update-notify"};
    fcitx::OptionWithAnnotation<std::string, BopomofoLayoutAnnotation> bopomofoLayout{this, "BopomofoLayout", "注音鍵盤配置", "Standard"};
    fcitx::OptionWithAnnotation<std::string, BopomofoModeAnnotation> bopomofoMode{this, "BopomofoMode", "注音模式", "Smart"};
    fcitx::Option<std::string, SelectionKeysConstrain, fcitx::DefaultMarshaller<std::string>, SelectionKeysAnnotation> traditionalSelectionKeys{this, "TraditionalSelectionKeys", "傳統注音選字鍵", "123456789"};
    fcitx::Option<CangjieConfig> cangjie{this, "Cangjie", "倉頡設定"};
    fcitx::Option<SimplexConfig> simplex{this, "Simplex", "簡易設定"};
    fcitx::Option<SmartMandarinConfig> smartMandarin{this, "SmartMandarin", "好打注音進階設定"};
    fcitx::OptionWithAnnotation<std::string, CandidateWindowStyleAnnotation> candidateWindowStyle{this, "CandidateWindowStyle", "候選字窗方向", "Vertical"};
    fcitx::Option<bool> traditionalToSimplified{this, "TraditionalToSimplified", "繁體轉簡體輸出", false};
    fcitx::Option<bool> useAllUnicodeCharacters{this, "UseAllUnicodeCharacters", "顯示 Big5 以外的候選字", true};
    fcitx::Option<bool> playSoundOnTypingError{this, "PlaySoundOnTypingError", "輸入錯誤時播放提示音", true};
    fcitx::Option<bool> toggleWithControlBackslash{this, "ToggleInputMethodWithControlBackslash", "使用 Ctrl+\\ 切換中英文", true};
    fcitx::Option<bool> toggleWithShift{this, "ToggleInputModeWithShift", "單按 Shift 切換中英文", true};
    fcitx::Option<bool> defaultChineseMode{this, "DefaultChineseMode", "啟動時使用中文模式", true};
    fcitx::Option<bool> ignoreCapsLockInChinese{this, "IgnoreCapsLockInChinese", "中文模式忽略 Caps Lock", false};
    fcitx::Option<bool> literalKeypad{this, "LiteralKeypad", "數字鍵盤直接輸入數字符號", true};
    fcitx::Option<bool> useUserPhrases{this, "UseUserPhrases", "使用自訂詞庫", true};
    fcitx::Option<AssociatedPhraseConfig> associatedPhrases{this, "AssociatedPhrases", "關聯詞庫"};)

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

template<typename Config> linux_ime::TablePreferences tablePreferences(const Config &source) {
    linux_ime::TablePreferences value;
    value.composeWhileTyping = *source.composeWhileTyping;
    value.prefixCandidates = *source.prefixCandidates;
    value.clearOnError = *source.clearOnError && !value.composeWhileTyping;
    value.queryAtMaximum = *source.queryAtMaximum;
    value.learnSelection = *source.learnSelection;
    value.candidateSelectionKeys = *source.candidateSelectionKeys;
    value.punctuation = *source.punctuation;
    value.maximumRadicalLength = static_cast<std::size_t>(*source.maximumRadicalLength);
    value.spaceAsFirstSelectionKey = *source.spaceAsFirstSelectionKey;
    value.spaceCommitsFirstOnSinglePage = *source.spaceCommitsFirstOnSinglePage;
    value.wildcardOne = *source.wildcardOne;
    value.wildcardMany = *source.wildcardMany;
    return value;
}
linux_ime::GuanyinmaConfig sessionSettings(const KeyKeyConfig &config, const std::string &method) {
    linux_ime::GuanyinmaConfig settings;
    settings.inputMethod = method == "chichi77-keykey-cangjie" ? linux_ime::InputMethod::Cangjie
        : method == "chichi77-keykey-simplex" ? linux_ime::InputMethod::Simplex : linux_ime::InputMethod::Bopomofo;
    settings.smartMode = settings.inputMethod == linux_ime::InputMethod::Bopomofo && *config.bopomofoMode != "Traditional";
    const std::string &layout = *config.bopomofoLayout;
    settings.layout = layout == "ETen" ? linux_ime::BopomofoLayout::ETen
        : layout == "ETen26" ? linux_ime::BopomofoLayout::ETen26
        : layout == "Hsu" ? linux_ime::BopomofoLayout::Hsu
        : layout == "HanyuPinyin" ? linux_ime::BopomofoLayout::HanyuPinyin : linux_ime::BopomofoLayout::Standard;
    const auto &smart = *config.smartMandarin;
    settings.smart.showCandidateListWithSpace = *smart.showCandidateListWithSpace;
    settings.smart.candidateCursorAtEndOfTargetBlock = *smart.candidateCursorAtEndOfTargetBlock;
    settings.smart.clearComposingTextWithEsc = *smart.clearComposingTextWithEsc;
    settings.smart.maxCompletedSyllables = static_cast<std::size_t>(*smart.maxCompletedSyllables);
    settings.smart.candidateSelectionKeys = *smart.candidateSelectionKeys;
    settings.smart.selectionReturnsToEnd = *smart.selectionReturnsToEnd;
    settings.smart.shiftAlwaysUppercase = *smart.shiftAlwaysUppercase;
    settings.smart.useBigrams = *smart.useBigrams;
    settings.smart.learnCandidateOverrides = *smart.learnCandidateOverrides;
    settings.smart.learnBigrams = *smart.learnBigrams;
    settings.table = tablePreferences(*config.cangjie);
    settings.simplex = tablePreferences(*config.simplex);
    settings.traditionalSelectionKeys = *config.traditionalSelectionKeys;
    settings.ignoreCapsLockInChinese = *config.ignoreCapsLockInChinese;
    settings.literalKeypad = *config.literalKeypad;
    settings.userPhrases = *config.useUserPhrases;
    settings.restrictBopomofoToBig5 = !*config.useAllUnicodeCharacters;
    return settings;
}


class FcitxState : public fcitx::InputContextProperty {
public:
    explicit FcitxState(fcitx::InputContext *inputContext) : inputContext_(inputContext) {}
    void process(bool traditionalToSimplified, bool playSoundOnTypingError,
                 fcitx::CandidateLayoutHint candidateLayout,
                 const fcitx5_adapter::ErrorSound &errorSound,
                 const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent);
    bool processModeKey(bool toggleWithControlBackslash, fcitx::KeyEvent &event,
                        bool toggleWithShift = true);
    void initializeMode(bool chinese) { if (!modeInitialized_) { chineseMode_ = chinese; modeInitialized_ = true; } }
    void select(std::size_t displayedIndex, std::uint64_t view = 0);
    bool selectSmartCharacter(std::size_t preeditCharacterIndex);
    void reset();
    bool commitAndReset(bool retireOnFailure = false);
    bool chineseMode() const noexcept { return chineseMode_; }
    bool usesGuanyinma() const noexcept { return rust_ != nullptr; }
    std::string coreStatus() const;
    bool settingsPending() const noexcept { return requestRevision_ != activeRevision_; }
    void requestSession(linux_ime::GuanyinmaConfig config,
                     std::string modelPath, std::string userPath,
                     std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated,
                     std::shared_ptr<const linux_ime::CinDictionary> simplified,
                     std::vector<std::string> collections,
                     linux_ime::GuanyinmaSession::CandidateFilter filter = {});
private:
    struct ShiftPress { std::uint32_t eventTime = 0; std::chrono::steady_clock::time_point monotonicTime; };
    void toggleChineseMode();
    void apply(const linux_ime::EngineResult &result);
    void updateUi(const linux_ime::EngineResult &result);
    linux_ime::EngineResult currentView() const;
    bool quiet() const;
    void prepareSession();
    void processRust(const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent,
                     bool playSound, const fcitx5_adapter::ErrorSound &errorSound);
    void applyRust(linux_ime::EngineResult result, bool offerAssociated = true);
    linux_ime::EngineResult associatedView() const;
    bool processAssociated(const linux_ime::KeyEvent &event, linux_ime::EngineResult &result);
    linux_ime::EngineResult selectAssociated(std::size_t displayedIndex);
    void clearAssociated();
    std::unique_ptr<linux_ime::GuanyinmaSession> rust_;
    linux_ime::GuanyinmaConfig requestedConfig_;
    std::string modelPath_, userPath_;
    std::uint64_t requestRevision_ = 0, attemptedRevision_ = 0, activeRevision_ = 0;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated_;
    std::shared_ptr<const linux_ime::CinDictionary> simplified_;
    std::vector<std::string> collections_;
    linux_ime::GuanyinmaSession::CandidateFilter candidateFilter_;
    std::vector<std::string> associatedCandidates_;
    std::size_t associatedPage_ = 0, associatedHighlight_ = 0;
    fcitx::InputContext *inputContext_;
    bool chineseMode_ = true, modeInitialized_ = false, fullWidth_ = false;
    bool simplifiedOutput_ = false, effectsInProgress_ = false;
    std::uint64_t viewGeneration_ = 1;
    std::string coreError_;
    fcitx::CandidateLayoutHint candidateLayout_ = fcitx::CandidateLayoutHint::Vertical;
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
          traditionalToSimplifiedDictionary_(loadDictionary("tc2sc.cin")),
          associatedPhraseDictionary_(loadAssociatedPhraseDictionary()),
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
                keyEvent.inputContext()->propertyFor(&factory_)->initializeMode(*config_.defaultChineseMode);
                keyEvent.inputContext()
                    ->propertyFor(&factory_)
                    ->processModeKey(*config_.toggleWithControlBackslash,
                                     keyEvent, *config_.toggleWithShift);
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
        config_.load(config, true);
        applyConfig();
        fcitx::safeSaveAsIni(config_, configFile());
    }

    void reloadConfig() override {
        config_ = KeyKeyConfig();
        fcitx::RawConfig rawConfig;
        fcitx::readAsIni(rawConfig, configFile());
        config_.load(rawConfig);
        applyConfig();
    }

    void keyEvent(const fcitx::InputMethodEntry &entry,
                  fcitx::KeyEvent &event) override {
        FcitxState *state = event.inputContext()->propertyFor(&factory_);
        const auto original = event.inputContext()->watch();
        state->initializeMode(*config_.defaultChineseMode);
        requestSession(*state, entry.uniqueName());
        if (!original.isValid()) return;
        linux_ime::KeyEvent translated;
        if (!translate(event, translated)) {
            return;
        }
        state->process(
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

    void activate(const fcitx::InputMethodEntry &entry,
                  fcitx::InputContextEvent &event) override {
        auto *state = event.inputContext()->propertyFor(&factory_);
        state->initializeMode(*config_.defaultChineseMode);
        requestSession(*state, entry.uniqueName());
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
    void requestSession(FcitxState &state, const std::string &method) const {
        const char *overrideDirectory = std::getenv("CHICHI77_KEYKEY_DATA_DIR");
        const std::string directory = overrideDirectory == nullptr ? KEYKEY_LINUX_DATA_DIR : overrideDirectory;
        state.requestSession(sessionSettings(config_, method), directory + "/smart-mandarin.db", linux_ime::GuanyinmaSession::defaultUserDatabasePath(),
            associatedPhraseDictionary_, traditionalToSimplifiedDictionary_, enabledAssociatedPhraseCollections(*config_.associatedPhrases));
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

    void applyConfig() {
        auto &cangjie = *config_.cangjie.mutableValue();
        if (*cangjie.composeWhileTyping) cangjie.clearOnError.setValue(false);
        auto &simplex = *config_.simplex.mutableValue();
        if (*simplex.composeWhileTyping) simplex.clearOnError.setValue(false);
        for (auto *punctuation : {&cangjie.punctuation, &simplex.punctuation}) {
            if (**punctuation != "original" && **punctuation != "mixed" && **punctuation != "half") punctuation->setValue("original");
        }
        instance_->inputContextManager().foreach([this](fcitx::InputContext *context) {
            const auto method = instance_->inputMethod(context);
            if (isKeyKeyInputMethod(method)) requestSession(*context->propertyFor(&factory_), method);
            return true;
        });
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
    std::shared_ptr<const linux_ime::CinDictionary> traditionalToSimplifiedDictionary_;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associatedPhraseDictionary_;
    fcitx5_adapter::ErrorSound errorSound_;
    fcitx::FactoryFor<FcitxState> factory_;
    KeyKeyConfig config_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        keyEventWatcher_;
    std::unique_ptr<fcitx::HandlerTableEntry<fcitx::EventHandler>>
        switchEventWatcher_;
};

#undef KEYKEY_ASSOCIATED_PHRASE_OPTIONS

std::string FcitxState::coreStatus() const {
    std::string result = "Guanyinma（Rust）";
    if (rust_ && settingsPending()) result += "；組字完成後套用設定";
    if (!coreError_.empty()) result += "；" + coreError_;
    return result;
}

linux_ime::EngineResult FcitxState::currentView() const {
    if (rust_) return associatedCandidates_.empty() ? rust_->snapshot() : associatedView();
    linux_ime::EngineResult result;
    result.fullWidthMode = fullWidth_;
    return result;
}

bool FcitxState::quiet() const {
    const auto view = currentView();
    return !effectsInProgress_ && view.preedit.empty() && view.candidates.empty() && (!rust_ || rust_->quiet());
}

void FcitxState::requestSession(linux_ime::GuanyinmaConfig config,
    std::string modelPath, std::string userPath,
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary> associated,
    std::shared_ptr<const linux_ime::CinDictionary> simplified,
    std::vector<std::string> collections,
    linux_ime::GuanyinmaSession::CandidateFilter filter) {
    if (config != requestedConfig_ || modelPath != modelPath_ || userPath != userPath_ ||
        collections != collections_ || requestRevision_ == 0) {
        ++requestRevision_;
        coreError_.clear();
    }
    requestedConfig_ = std::move(config);
    modelPath_ = std::move(modelPath);
    userPath_ = std::move(userPath);
    associated_ = std::move(associated);
    simplified_ = std::move(simplified);
    collections_ = std::move(collections);
    candidateFilter_ = std::move(filter);
    // Retain the active session and its candidate ownership until a safe boundary.
    if (rust_ && (settingsPending() || !coreError_.empty())) updateUi(currentView());
}

void FcitxState::prepareSession() {
    if (!quiet() || requestRevision_ == 0 || activeRevision_ == requestRevision_ ||
        attemptedRevision_ == requestRevision_) return;
    attemptedRevision_ = requestRevision_;
    try {
        auto replacement = std::make_unique<linux_ime::GuanyinmaSession>(modelPath_, userPath_, requestedConfig_, candidateFilter_);
        replacement->setFullWidth(fullWidth_);
        if (!replacement->lastError().empty()) throw std::runtime_error(replacement->lastError());
        rust_ = std::move(replacement);
        activeRevision_ = requestRevision_;
        clearAssociated();
        coreError_.clear();
        ++viewGeneration_;
        FCITX_INFO() << "KeyKey active core: Guanyinma";
    } catch (const std::exception &error) {
        coreError_ = std::string("Guanyinma 無法啟用：") + error.what();
        FCITX_WARN() << coreError_;
    }
}

void FcitxState::clearAssociated() {
    associatedCandidates_.clear();
    associatedPage_ = 0;
    associatedHighlight_ = 0;
}

linux_ime::EngineResult FcitxState::associatedView() const {
    linux_ime::EngineResult result;
    result.fullWidthMode = fullWidth_;
    result.candidateSelectionKeys = "123456789";
    result.candidatePageSize = 9;
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
    if (!rust_->lastError().empty()) coreError_ = rust_->lastError();
    else if (!settingsPending()) coreError_.clear();
    const auto capabilities = inputContext_->capabilityFlags();
    const bool sensitive = capabilities.test(fcitx::CapabilityFlag::Password) ||
                           capabilities.test(fcitx::CapabilityFlag::Sensitive);
    if (offerAssociated && !sensitive && !rust_->config().smartMode && associated_ &&
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

void FcitxState::process(bool traditionalToSimplified, bool playSoundOnTypingError,
                         fcitx::CandidateLayoutHint candidateLayout,
                         const fcitx5_adapter::ErrorSound &errorSound,
                         const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent) {
    candidateLayout_ = candidateLayout;
    simplifiedOutput_ = traditionalToSimplified;
    const auto original = inputContext_->watch();
    if (rust_ && (rust_->config().inputMethod != requestedConfig_.inputMethod ||
                  rust_->config().smartMode != requestedConfig_.smartMode ||
                  rust_->config().layout != requestedConfig_.layout)) {
        if (!commitAndReset()) { fcitxEvent.filterAndAccept(); return; }
        if (!original.isValid()) return;
    }
    if (!event.release) prepareSession();
    const bool incompatible = rust_ && (rust_->config().inputMethod != requestedConfig_.inputMethod ||
        rust_->config().smartMode != requestedConfig_.smartMode || rust_->config().layout != requestedConfig_.layout);
    if (!rust_ || incompatible) {
        if (playSoundOnTypingError && !event.release) errorSound.play();
        fcitxEvent.filterAndAccept();
        updateUi(currentView());
        return;
    }
    processRust(event, fcitxEvent, playSoundOnTypingError, errorSound);
}

bool FcitxState::processModeKey(bool toggleWithControlBackslash,
                                fcitx::KeyEvent &event, bool toggleWithShift) {
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
        if (!toggleWithShift) { shiftPressedAt_.reset(); return false; }
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
    if (effectsInProgress_ || !rust_ || (view != 0 && view != viewGeneration_)) return;
    const bool overlay = !associatedCandidates_.empty();
    applyRust(overlay ? selectAssociated(displayedIndex) : rust_->selectDisplayedCandidate(displayedIndex), !overlay);
}

bool FcitxState::selectSmartCharacter(std::size_t preeditCharacterIndex) {
    if (effectsInProgress_ || !rust_ || !rust_->config().smartMode || !associatedCandidates_.empty()) return false;
    auto result = rust_->selectSmartCharacter(preeditCharacterIndex);
    const bool handled = result.handled;
    if (handled) applyRust(std::move(result), false);
    return handled;
}

bool FcitxState::commitAndReset(bool retireOnFailure) {
    if (effectsInProgress_) return false;
    const auto original = inputContext_->watch();
    if (!inputContext_->hasFocus() && inputContext_->capabilityFlags().test(fcitx::CapabilityFlag::ClientUnfocusCommit)) {
        // The frontend already committed its client preedit on focus-out.
        reset();
        return original.isValid();
    }
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
    }
    reset();
    return original.isValid();
}

void FcitxState::reset() {
    shiftPressedAt_.reset();
    controlBackslashPressed_ = false;
    clearAssociated();
    if (rust_) {
        fullWidth_ = rust_->snapshot().fullWidthMode;
        const auto result = rust_->reset();
        if (!rust_->valid()) {
            coreError_ = rust_->lastError();
            rust_.reset();
            attemptedRevision_ = 0;
            activeRevision_ = 0;
        }
        updateUi(result);
        return;
    }
    updateUi(currentView());
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
        fcitx::KeyList selectionKeys;
        const auto &keys = result.candidateSelectionKeys;
        for (const unsigned char key : keys) selectionKeys.emplace_back(static_cast<fcitx::KeySym>(key));
        const auto pageSize = result.candidatePageSize ? result.candidatePageSize : std::max<std::size_t>(keys.size(), 1);
        candidateList->setPageSize(static_cast<int>(pageSize));
        candidateList->setSelectionKey(selectionKeys);
        candidateList->setLayoutHint(candidateLayout_);
        candidateList->setGlobalCursorIndex(
            static_cast<int>(result.highlightedIndex));
        panel.setCandidateList(std::move(candidateList));
        if (result.associatedPhrases) {
            panel.setAuxUp(fcitx::Text("Shift + 1-9"));
        }
    }
    if ((rust_ && settingsPending()) || !coreError_.empty()) panel.setAuxDown(fcitx::Text(coreStatus()));
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

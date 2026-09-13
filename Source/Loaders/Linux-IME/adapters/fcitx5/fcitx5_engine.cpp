#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/cin_dictionary.h"
#include "keykey/linux_ime/engine.h"

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

#include <cstdlib>
#include <memory>
#include <string>
#include <unordered_set>
#include <utility>
#include <vector>

namespace {

namespace linux_ime = keykey::linux_ime;

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
    KeyKeyConfig,
    fcitx::OptionWithAnnotation<std::string, BopomofoLayoutAnnotation>
        bopomofoLayout{this, "BopomofoLayout", "Bopomofo keyboard layout",
                       "Standard"};
    fcitx::Option<bool> traditionalToSimplified{
        this, "TraditionalToSimplified",
        "Convert Traditional Chinese output to Simplified Chinese", false};
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
                 bool traditionalToSimplified,
                 const linux_ime::KeyEvent &event, fcitx::KeyEvent &fcitxEvent);
    void select(std::size_t displayedIndex);
    void reset();

private:
    void apply(const linux_ime::EngineResult &result);
    void updateUi(const linux_ime::EngineResult &result);

    fcitx::InputContext *inputContext_;
    linux_ime::InputContextState context_;
    const linux_ime::Engine *activeEngine_ = nullptr;
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

class FcitxEngine : public fcitx::InputMethodEngineV2 {
public:
    explicit FcitxEngine(fcitx::Instance *instance)
        : bopomofoDictionary_(loadDictionary("bpmf-ext.cin")),
          cangjieDictionary_(loadDictionary("cj-ext.cin")),
          simplexDictionary_(loadDictionary("simplex-ext.cin")),
          punctuationDictionary_(loadDictionary("bpmf-punctuations.cin")),
          traditionalToSimplifiedDictionary_(loadDictionary("tc2sc.cin")),
          associatedPhraseDictionary_(loadAssociatedPhraseDictionary()),
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
        linux_ime::KeyEvent translated;
        if (!translate(event, translated)) {
            return;
        }
        event.inputContext()->propertyFor(&factory_)->process(
            engineFor(entry), *config_.traditionalToSimplified, translated,
            event);
    }

    void reset(const fcitx::InputMethodEntry &entry,
               fcitx::InputContextEvent &event) override {
        FCITX_UNUSED(entry);
        event.inputContext()->propertyFor(&factory_)->reset();
    }

    void deactivate(const fcitx::InputMethodEntry &entry,
                    fcitx::InputContextEvent &event) override {
        reset(entry, event);
    }

private:
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
        const std::vector<std::string> enabled =
            enabledAssociatedPhraseCollections(*config_.associatedPhrases);
        standardEngine_.setAssociatedPhraseCollections(enabled);
        etenEngine_.setAssociatedPhraseCollections(enabled);
        eten26Engine_.setAssociatedPhraseCollections(enabled);
        hsuEngine_.setAssociatedPhraseCollections(enabled);
        hanyuPinyinEngine_.setAssociatedPhraseCollections(enabled);
        cangjieEngine_.setAssociatedPhraseCollections(enabled);
        simplexEngine_.setAssociatedPhraseCollections(enabled);
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

    static const std::string &configFile() {
        static const std::string path = "conf/chichi77-keykey.conf";
        return path;
    }

    static bool translate(const fcitx::KeyEvent &source,
                          linux_ime::KeyEvent &destination) {
        destination.release = source.isRelease();
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

    std::shared_ptr<const linux_ime::CinDictionary> bopomofoDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> cangjieDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> simplexDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary> punctuationDictionary_;
    std::shared_ptr<const linux_ime::CinDictionary>
        traditionalToSimplifiedDictionary_;
    std::shared_ptr<const linux_ime::AssociatedPhraseDictionary>
        associatedPhraseDictionary_;
    linux_ime::Engine standardEngine_;
    linux_ime::Engine etenEngine_;
    linux_ime::Engine eten26Engine_;
    linux_ime::Engine hsuEngine_;
    linux_ime::Engine hanyuPinyinEngine_;
    linux_ime::Engine cangjieEngine_;
    linux_ime::Engine simplexEngine_;
    fcitx::FactoryFor<FcitxState> factory_;
    KeyKeyConfig config_;
};

#undef KEYKEY_ASSOCIATED_PHRASE_OPTIONS

void FcitxState::process(const linux_ime::Engine &engine,
                         bool traditionalToSimplified,
                         const linux_ime::KeyEvent &event,
                         fcitx::KeyEvent &fcitxEvent) {
    if (activeEngine_ != &engine) {
        context_.reset();
        activeEngine_ = &engine;
    }
    engine.setTraditionalToSimplifiedMode(context_,
                                          traditionalToSimplified);
    const linux_ime::EngineResult result = engine.processKey(context_, event);
    if (result.handled) {
        apply(result);
        fcitxEvent.filterAndAccept();
    } else if (result.updateUi) {
        updateUi(result);
    }
}

void FcitxState::select(std::size_t displayedIndex) {
    if (activeEngine_ != nullptr) {
        apply(activeEngine_->selectDisplayedCandidate(context_, displayedIndex));
    }
}

void FcitxState::reset() {
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

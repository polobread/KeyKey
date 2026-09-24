#include "keykey/linux_ime/associated_phrase_dictionary.h"
#include "keykey/linux_ime/candidate_encoding.h"
#include "keykey/linux_ime/cin_dictionary.h"
#include "keykey/linux_ime/engine.h"

#include <algorithm>
#include <cstdlib>
#include <iostream>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <unordered_set>
#include <vector>
#include <sqlite3.h>
#include <unistd.h>

namespace {

using keykey::linux_ime::CinDictionary;
using keykey::linux_ime::AssociatedPhraseDictionary;
using keykey::linux_ime::BopomofoLayout;
using keykey::linux_ime::BopomofoReading;
using keykey::linux_ime::Engine;
using keykey::linux_ime::EngineResult;
using keykey::linux_ime::InputContextState;
using keykey::linux_ime::InputMethod;
using keykey::linux_ime::KeyCode;
using keykey::linux_ime::KeyEvent;
using keykey::linux_ime::KeyModifier;
using keykey::linux_ime::filterBig5HkscsCandidates;
using keykey::linux_ime::isBig5HkscsRepresentable;
using keykey::linux_ime::toFullWidth;
using keykey::linux_ime::toSimplifiedChinese;

void require(bool condition, const std::string &message) {
    if (!condition) {
        throw std::runtime_error(message);
    }
}

KeyEvent character(char value) {
    return KeyEvent{KeyCode::Character, value, KeyModifier::None, false, false};
}

void combineSequence(BopomofoReading &reading, const std::string &sequence,
                     BopomofoLayout layout) {
    for (const char key : sequence) {
        require(reading.combine(key, layout),
                "Bopomofo layout rejected a valid key");
    }
}

void testCinParserHandlesBomCrlfAndPercentKey() {
    std::istringstream input(
        "\xEF\xBB\xBF%gen_inp\r\n"
        "%endkey  ,.%\r\n"
        "%keyname begin\r\n"
        "a 日\r\n"
        ", ，\r\n"
        ". 。\r\n"
        "% ％\r\n"
        "%keyname end\r\n"
        "%chardef begin\r\n"
        "# #\r\n"
        "% ％\r\n"
        "a 日\r\n"
        "a 曰\r\n"
        "%chardef end\r\n");
    const CinDictionary dictionary = CinDictionary::load(input);
    require(dictionary.keyCount() == 3, "CIN key count mismatch");
    require(dictionary.entryCount() == 4, "CIN entry count mismatch");
    require(dictionary.candidates("#").at(0) == "#",
            "Legal hash key was discarded as a comment");
    require(dictionary.candidates("%").at(0) == "％",
            "Legal percent key was discarded");
    require(dictionary.candidates("a").at(1) == "曰",
            "CIN candidate order changed");
    require(dictionary.keyName("a") == "日", "CIN key name was not parsed");
    require(dictionary.hasKeyName(",") && dictionary.hasKeyName("%"),
            "CIN punctuation key names were not parsed");
    require(dictionary.isEndKey(",") && dictionary.isEndKey(".") &&
                dictionary.isEndKey("%") && !dictionary.isEndKey("a"),
            "CIN %endkey metadata was not parsed");
}

void testCinParserRejectsIncompleteData() {
    std::istringstream missingSection("%gen_inp\n");
    bool rejectedMissingSection = false;
    try {
        static_cast<void>(CinDictionary::load(missingSection));
    } catch (const std::runtime_error &) {
        rejectedMissingSection = true;
    }
    require(rejectedMissingSection, "CIN without %chardef was accepted");

    std::istringstream unterminated("%chardef begin\na 日\n");
    bool rejectedUnterminatedSection = false;
    try {
        static_cast<void>(CinDictionary::load(unterminated));
    } catch (const std::runtime_error &) {
        rejectedUnterminatedSection = true;
    }
    require(rejectedUnterminatedSection,
            "CIN with an unterminated %chardef was accepted");

    std::istringstream unterminatedKeyNames(
        "%keyname begin\na 日\n%chardef begin\na 日\n%chardef end\n");
    bool rejectedUnterminatedKeyNames = false;
    try {
        static_cast<void>(CinDictionary::load(unterminatedKeyNames));
    } catch (const std::runtime_error &) {
        rejectedUnterminatedKeyNames = true;
    }
    require(rejectedUnterminatedKeyNames,
            "CIN with an unterminated %keyname was accepted");
}

void testCinWildcardMatchingPreservesTableOrder() {
    std::istringstream input(
        "%chardef begin\n"
        "b 水\n"
        "abc 晶\n"
        "a 日\n"
        "ab 明\n"
        "aa 昌\n"
        "aa 昍\n"
        "%chardef end\n");
    const CinDictionary dictionary = CinDictionary::load(input);

    const std::vector<std::string> one =
        dictionary.candidatesMatching("a?", '?', '*');
    require(one == std::vector<std::string>({"昌", "昍", "明"}),
            "Single-character wildcard order changed");

    const std::vector<std::string> zeroOrMore =
        dictionary.candidatesMatching("a*", '?', '*');
    require(zeroOrMore ==
                std::vector<std::string>({"日", "昌", "昍", "明", "晶"}),
            "Zero-or-more wildcard order changed");
}

std::shared_ptr<const CinDictionary> loadRealBopomofoDictionary() {
    return std::make_shared<const CinDictionary>(CinDictionary::loadFile(
        std::string(KEYKEY_TEST_DATA_DIR) + "/bpmf-ext.cin"));
}

std::shared_ptr<const CinDictionary> loadRealDictionary(const char *fileName) {
    return std::make_shared<const CinDictionary>(CinDictionary::loadFile(
        std::string(KEYKEY_TEST_DATA_DIR) + "/" + fileName));
}

std::shared_ptr<const CinDictionary> loadLinuxData(const char *fileName) {
    return std::make_shared<const CinDictionary>(CinDictionary::loadFile(
        std::string(KEYKEY_TEST_LINUX_DATA_DIR) + "/" + fileName));
}

std::shared_ptr<const AssociatedPhraseDictionary>
loadRealAssociatedPhraseDictionary() {
    static const auto dictionary =
        std::make_shared<const AssociatedPhraseDictionary>(
            AssociatedPhraseDictionary::loadDirectory(
                KEYKEY_TEST_ASSOCIATED_PHRASE_DATA_DIR));
    return dictionary;
}

void testAssociatedPhraseParserFiltersAndSorts() {
    std::istringstream input(
        "\xEF\xBB\xBF詞\t詞頻\t注音\t分類\r\n"
        "甲乙\t2\t-\t測試\r\n"
        "甲乙\t20\t-\t測試\r\n"
        "甲丁\t30\t-\t測試\r\n"
        "甲丙\t1\t-\t測試\r\n"
        "乙甲 5000000\r\n"
        "A甲 900000\r\n"
        "甲 900000\r\n"
        "王小明 800000\r\n");
    const auto entries = AssociatedPhraseDictionary::parseCollection(
        input, std::unordered_set<std::string>{"王小明"});

    const auto first = entries.find("甲");
    require(first != entries.end() &&
                first->second == std::vector<std::string>({"丁", "乙"}),
            "Associated-phrase rows were not filtered, deduplicated, or sorted");
    const auto second = entries.find("乙");
    require(second != entries.end() &&
                second->second == std::vector<std::string>({"甲"}),
            "Whitespace-separated associated phrases were not parsed");
    require(entries.find("王") == entries.end(),
            "Associated-phrase exclusions were ignored");
}

void testRealAssociatedPhraseCollections() {
    const auto dictionary = loadRealAssociatedPhraseDictionary();
    require(dictionary->collections().size() == 30,
            "The built-in associated-phrase collection count changed");
    require(dictionary->collections().front().source == "McBopomofo" &&
                dictionary->collections().front().displayName == "小麥注音",
            "The base associated-phrase collection metadata changed");
    require(dictionary->entryCount() > 10000,
            "The built-in associated-phrase data is unexpectedly small");

    bool foundGeneral = false;
    bool foundChinese = false;
    for (const auto &collection : dictionary->collections()) {
        foundGeneral = foundGeneral ||
                       (collection.source == "general" &&
                        collection.displayName == "一般生活");
        foundChinese = foundChinese ||
                       (collection.source == "chinese" &&
                        collection.displayName == "中文文學");
    }
    require(foundGeneral && foundChinese,
            "Shared associated-phrase display-name overrides were not applied");

    const std::vector<std::string> base =
        dictionary->candidates("今", {"McBopomofo"});
    require(!base.empty() && base.front() == "天",
            "The base collection no longer recommends 今天 first");
    require(dictionary->candidates("今", {}).empty(),
            "An empty collection selection did not disable associated phrases");

    const std::vector<std::string> history =
        dictionary->candidates("臺", {"history"});
    require(!history.empty() && history.front() == "灣史",
            "The history collection did not expose 臺灣史");

    const std::vector<std::string> general =
        dictionary->candidates("一", {"general"});
    require(std::find(general.begin(), general.end(), "卡通") != general.end(),
            "The general collection did not expose 一卡通");

    const std::vector<std::string> merged =
        dictionary->candidates("中", {"government", "McBopomofo"});
    require(!merged.empty() && merged.front() == "程計畫" &&
                std::find(merged.begin(), merged.end(), "國") != merged.end(),
            "Enabled collection order was not preserved");
    require(std::unordered_set<std::string>(merged.begin(), merged.end()).size() ==
                merged.size(),
            "Duplicate associated phrases were not removed across collections");
}

void testAssociatedPhraseKeyboardFlow() {
    Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::Standard,
                  loadRealDictionary("bpmf-punctuations.cin"),
                  loadLinuxData("tc2sc.cin"),
                  loadRealAssociatedPhraseDictionary());
    InputContextState context;
    const auto commitHead = [&]() {
        for (const char key : std::string("rup")) {
            engine.processKey(context, character(key));
        }
        engine.processKey(
            context,
            KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
        return engine.processKey(context, character('1'));
    };

    auto result = commitHead();
    require(result.handled && result.commit == "今" &&
                result.associatedPhrases && result.preedit.empty() &&
                !result.candidates.empty() && result.candidates.front() == "天",
            "Selecting 今 did not open its headless associated phrases");
    result = engine.processKey(context, character('1'));
    require(result.handled && !result.associatedPhrases &&
                result.candidates.empty() && result.commit.empty() &&
                result.preedit == "ㄅ",
            "An unshifted Bopomofo key selected or retained an associated phrase");
    context.reset();

    result = commitHead();
    require(result.associatedPhrases,
            "Associated phrases did not reopen after another commit");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '!', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.commit == "天" &&
                !result.associatedPhrases && result.candidates.empty(),
            "Shift+1 did not commit only the associated-phrase suffix");

    result = commitHead();
    result = engine.processKey(context, character('!'));
    require(result.handled && result.commit == "天" &&
                !result.associatedPhrases,
            "A framework-normalized Shift+1 did not select the associated phrase");

    result = commitHead();
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Enter, '\0', KeyModifier::None, false, false});
    require(result.handled && result.commit.empty() &&
                !result.associatedPhrases,
            "Enter did not dismiss associated phrases without committing");

    result = commitHead();
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false, false});
    require(!result.handled && result.updateUi && result.commit.empty() &&
                !result.associatedPhrases && result.candidates.empty(),
            "Backspace did not dismiss associated phrases before pass-through");

    result = commitHead();
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, 'c', KeyModifier::Control, true, false});
    require(!result.handled && !result.updateUi && result.associatedPhrases &&
                !result.candidates.empty(),
            "A shortcut key release changed associated phrases");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, 'c', KeyModifier::Control, false, true});
    require(!result.handled && result.updateUi && result.commit.empty() &&
                !result.associatedPhrases && result.candidates.empty(),
            "A repeated application shortcut did not dismiss associated phrases before pass-through");

    engine.setAssociatedPhraseCollections({});
    result = commitHead();
    require(result.commit == "今" && !result.associatedPhrases &&
                result.candidates.empty(),
            "Disabling every collection did not disable associated phrases");
}

void testRealDataTypingFlow() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;

    auto result = engine.processKey(context, character('5'));
    require(result.handled && result.preedit == "ㄓ", "5 must compose ㄓ");
    result = engine.processKey(context, character('j'));
    require(result.preedit == "ㄓㄨ", "5j must compose ㄓㄨ");
    result = engine.processKey(context, character('/'));
    require(result.preedit == "ㄓㄨㄥ", "5j/ must compose ㄓㄨㄥ");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled, "Space must be handled during composition");
    require(!result.candidates.empty() && result.candidates.front() == "中",
            "Real bpmf-ext.cin must return 中 first for 5j/");

    result = engine.processKey(context, character('1'));
    require(result.commit == "中", "Candidate 1 must commit 中");
    require(result.preedit.empty() && result.candidates.empty(),
            "Commit must clear composition state");
}

void testBopomofoContinuousTypingAndInputErrors() {
    std::istringstream input(
        "%chardef begin\n"
        "5j/ 中\n"
        "5j/ 忠\n"
        "jp 文\n"
        "jp 聞\n"
        "%chardef end\n");
    auto dictionary =
        std::make_shared<const CinDictionary>(CinDictionary::load(input));
    Engine engine(dictionary);
    InputContextState context;

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false,
                          false});
    require(result.candidates == std::vector<std::string>({"中", "忠"}),
            "First reading did not open the expected candidate list");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Down, '\0', KeyModifier::None, false,
                          false});
    require(result.highlightedIndex == 1,
            "Candidate highlight did not move before continuous input");

    result = engine.processKey(context, character('j'));
    require(result.handled && !result.beep && result.commit == "忠" &&
                result.preedit == "ㄨ" && result.candidates.empty(),
            "Next Bopomofo key did not commit the highlight and start a new reading");
    result = engine.processKey(context, character('p'));
    require(result.handled && result.preedit == "ㄨㄣ",
            "Continuous input did not extend the new reading");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false,
                          false});
    require(result.candidates == std::vector<std::string>({"文", "聞"}),
            "Second reading did not open its candidate list");
    result = engine.processKey(context, character('1'));
    require(result.commit == "文" && result.preedit.empty(),
            "Continuous input did not complete the second syllable");

    result = engine.processKey(context, character('='));
    require(!result.handled && !result.beep && result.preedit.empty(),
            "An unmapped key was captured without an active reading");

    result = engine.processKey(context, character('5'));
    require(result.preedit == "ㄓ", "Error test did not start a reading");
    result = engine.processKey(context, character('='));
    require(result.handled && result.beep && result.commit.empty() &&
                result.preedit == "ㄓ" && result.candidates.empty(),
            "An invalid printable key leaked through or damaged the reading");

    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, 'c', KeyModifier::Control, false, false});
    require(!result.handled && !result.beep && result.preedit == "ㄓ",
            "An application shortcut was captured or changed the reading");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false,
                          false});
    require(result.handled && result.beep && result.commit.empty() &&
                result.preedit == "ㄓ" && result.candidates.empty(),
            "A no-candidate query did not preserve the reading and report an error");

    struct LayoutCase {
        BopomofoLayout layout;
        const char *readingKeys;
        const char *readingPreedit;
        char nextKey;
        const char *nextPreedit;
    };
    const LayoutCase layouts[] = {
        {BopomofoLayout::Standard, "5j/", "ㄓㄨㄥ", 'j', "ㄨ"},
        {BopomofoLayout::ETen, ",x-", "ㄓㄨㄥ", 'x', "ㄨ"},
        {BopomofoLayout::ETen26, "gxl", "ㄓㄨㄥ", 'x', "ㄨ"},
        {BopomofoLayout::Hsu, "jxl", "ㄓㄨㄥ", 'x', "ㄨ"},
        {BopomofoLayout::HanyuPinyin, "zhong", "zhong", 'w', "w"},
    };
    for (const LayoutCase &layout : layouts) {
        Engine layoutEngine(dictionary, InputMethod::Bopomofo, layout.layout);
        InputContextState layoutContext;
        for (const char key : std::string(layout.readingKeys)) {
            layoutEngine.processKey(layoutContext, character(key));
        }
        result = layoutEngine.processKey(layoutContext, character('\\'));
        require(result.handled && result.beep && result.commit.empty() &&
                    result.preedit == layout.readingPreedit &&
                    result.candidates.empty(),
                "A Windows-supported layout leaked an invalid printable key or changed its reading");
        result = layoutEngine.processKey(
            layoutContext,
            KeyEvent{KeyCode::Character, 'c', KeyModifier::Control, false,
                     false});
        require(!result.handled && !result.beep && result.commit.empty() &&
                    result.preedit == layout.readingPreedit &&
                    result.candidates.empty(),
                "A Windows-supported layout captured a shortcut or changed its reading");
        result = layoutEngine.processKey(
            layoutContext,
            KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
        require(result.candidates.size() == 2,
                "A Windows-supported layout did not open candidates");
        result = layoutEngine.processKey(layoutContext,
                                         character(layout.nextKey));
        require(result.handled && !result.beep && result.commit == "中" &&
                    result.preedit == layout.nextPreedit &&
                    result.candidates.empty(),
                "A Windows-supported layout did not continue into the next reading");
    }
}

void testAllBopomofoLayoutsUseCanonicalDictionaryKeys() {
    struct LayoutCase {
        BopomofoLayout layout;
        const char *keys;
        const char *preedit;
    };
    const LayoutCase cases[] = {
        {BopomofoLayout::Standard, "5j/", "ㄓㄨㄥ"},
        {BopomofoLayout::ETen, ",x-", "ㄓㄨㄥ"},
        {BopomofoLayout::ETen26, "gxl", "ㄓㄨㄥ"},
        {BopomofoLayout::Hsu, "jxl", "ㄓㄨㄥ"},
        {BopomofoLayout::HanyuPinyin, "zhong", "zhong"},
    };

    for (const LayoutCase &testCase : cases) {
        Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                      testCase.layout);
        InputContextState context;
        EngineResult result;
        for (const char key : std::string(testCase.keys)) {
            result = engine.processKey(context, character(key));
        }
        require(result.handled && result.preedit == testCase.preedit,
                "Bopomofo layout produced the wrong preedit");
        result = engine.processKey(
            context,
            KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
        require(!result.candidates.empty() && result.candidates.front() == "中",
                "Bopomofo layout did not query canonical 5j/");
        result = engine.processKey(context, character('1'));
        require(result.commit == "中",
                "Bopomofo layout did not commit its first candidate");
    }
}

void testBopomofoLayoutTonesAndAmbiguities() {
    struct LayoutCase {
        BopomofoLayout layout;
        const char *keys;
    };
    const LayoutCase cases[] = {
        {BopomofoLayout::Standard, "x/3"},
        {BopomofoLayout::ETen, "l-3"},
        {BopomofoLayout::ETen26, "llj"},
        {BopomofoLayout::Hsu, "llf"},
        {BopomofoLayout::HanyuPinyin, "leng3"},
    };

    for (const LayoutCase &testCase : cases) {
        BopomofoReading reading;
        combineSequence(reading, testCase.keys, testCase.layout);
        require(reading.queryKey() == "x/3",
                "Layout failed to normalize ㄌㄥˇ to Standard keys");
        const std::string expected =
            testCase.layout == BopomofoLayout::HanyuPinyin ? "leng3" : "ㄌㄥˇ";
        require(reading.displayText(testCase.layout) == expected,
                "Layout displayed the wrong ㄌㄥˇ preedit");
        require(reading.hasToneMarker(),
                "Layout did not retain its explicit tone marker");
        require(reading.backspace(testCase.layout),
                "Layout did not remove the last key");
        require(reading.queryKey() == "x/",
                "Layout backspace did not preserve ㄌㄥ");
        require(!reading.hasToneMarker(),
                "Layout backspace did not remove its tone marker");
    }

    BopomofoReading eten26Single;
    combineSequence(eten26Single, "g", BopomofoLayout::ETen26);
    require(eten26Single.displayText(BopomofoLayout::ETen26) == "ㄓ",
            "ETen26 single ambiguous g must resolve to ㄓ");

    BopomofoReading hsuSingle;
    combineSequence(hsuSingle, "l", BopomofoLayout::Hsu);
    require(hsuSingle.displayText(BopomofoLayout::Hsu) == "ㄦ",
            "Hsu single ambiguous l must resolve to ㄦ");
}

void testBopomofoLayoutToneTypingFlows() {
    struct LayoutCase {
        BopomofoLayout layout;
        const char *tone2;
        const char *tone3;
        const char *tone4;
        const char *tone5;
    };
    const LayoutCase cases[] = {
        {BopomofoLayout::Standard, "a86", "a83", "a84", "a87"},
        {BopomofoLayout::ETen, "ma2", "ma3", "ma4", "ma1"},
        {BopomofoLayout::ETen26, "maf", "maj", "mak", "mad"},
        {BopomofoLayout::Hsu, "myd", "myf", "myj", "mys"},
        {BopomofoLayout::HanyuPinyin, "ma2", "ma3", "ma4", "ma5"},
    };

    for (const LayoutCase &testCase : cases) {
        Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                      testCase.layout);
        InputContextState context;
        std::string committed;
        const char *sequences[] = {testCase.tone2, testCase.tone3,
                                   testCase.tone4, testCase.tone5};
        for (const char *sequence : sequences) {
            EngineResult result;
            for (const char key : std::string(sequence)) {
                result = engine.processKey(context, character(key));
            }
            require(!result.candidates.empty(),
                    "A tone sequence did not immediately open real candidates");
            result = engine.processKey(context, character('1'));
            committed += result.commit;
        }
        require(committed == "麻馬罵嘛",
                "A layout did not commit all four Mandarin tone fixtures");
    }

    std::istringstream singleCandidateInput(
        "%chardef begin\n"
        "a86 麻\n"
        "%chardef end\n");
    auto singleCandidateDictionary = std::make_shared<const CinDictionary>(
        CinDictionary::load(singleCandidateInput));
    Engine singleCandidateEngine(singleCandidateDictionary);
    InputContextState singleCandidateContext;
    singleCandidateEngine.processKey(singleCandidateContext, character('a'));
    singleCandidateEngine.processKey(singleCandidateContext, character('8'));
    auto result =
        singleCandidateEngine.processKey(singleCandidateContext, character('6'));
    require(result.handled && result.commit == "麻" && result.preedit.empty() &&
                result.candidates.empty(),
            "A tone query did not immediately commit its sole candidate");

    Engine pinyin(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::HanyuPinyin);
    InputContextState context;
    result = pinyin.processKey(context, character('z'));
    require(result.preedit == "z", "Pinyin incomplete initial was lost");
    result = pinyin.processKey(context, character('h'));
    require(result.preedit == "zh", "Pinyin incomplete digraph was lost");
    result = pinyin.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false,
                          false});
    require(result.preedit == "z", "Pinyin incomplete input did not backspace");
    result = pinyin.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false,
                          false});
    require(result.preedit.empty(),
            "Pinyin incomplete input did not clear after backspace");
}

void testHanyuPinyinAliasesAndToneValidation() {
    struct PinyinCase {
        const char *keys;
        const char *canonicalKeys;
    };
    const PinyinCase cases[] = {
        {"ba", "18"},     {"po", "qi"},    {"me", "ak"},
        {"fei", "zo"},    {"diao", "2ul"}, {"tun", "wjp"},
        {"neng", "s/"},   {"lve", "xm,"},  {"gang", "e;"},
        {"kou", "d."},    {"heng", "c/"},  {"ji", "ru"},
        {"quan", "fm0"},  {"xiong", "vm/"}, {"zhi", "5"},
        {"chi", "t"},     {"shi", "g"},    {"ri", "b"},
        {"zi", "y"},      {"ci", "h"},     {"si", "n"},
        {"yi", "u"},      {"wu", "j"},     {"yu", "m"},
        {"yuan", "m0"},   {"yue", "m,"},   {"yun", "mp"},
        {"ying", "u/"},   {"yong", "m/"},  {"wai", "j9"},
        {"wei", "jo"},    {"wan", "j0"},   {"wen", "jp"},
        {"wang", "j;"},   {"weng", "j/"},  {"fong", "z/"},
        {"zhong4", "5j/4"},
    };

    for (const PinyinCase &testCase : cases) {
        BopomofoReading reading;
        combineSequence(reading, testCase.keys,
                        BopomofoLayout::HanyuPinyin);
        require(reading.queryKey() == testCase.canonicalKeys,
                "Hanyu Pinyin normalization mismatch");
    }

    BopomofoReading reading;
    combineSequence(reading, "zhong4", BopomofoLayout::HanyuPinyin);
    require(!reading.combine('a', BopomofoLayout::HanyuPinyin),
            "Hanyu Pinyin accepted a letter after a tone");
    require(!reading.combine('3', BopomofoLayout::HanyuPinyin),
            "Hanyu Pinyin accepted a second tone");
    require(reading.displayText(BopomofoLayout::HanyuPinyin) == "zhong4",
            "Rejected Hanyu Pinyin key changed the preedit");
}

bool isKnownUnrepresentable(BopomofoLayout layout,
                            const std::string &canonicalKeys) {
    // Multi-component physical keys create genuine collisions. Keep the
    // non-round-trippable real-data readings explicit so coverage cannot
    // silently shrink when the parser or pinned CIN data changes.
    static const std::set<std::string> eten26 = {
        ",", ",3", ",4", ",6", ",7", "3", "4", "6", "7", "a",
        "c", "f", "f7", "o", "o4", "q", "r", "s", "s6", "v",
        "v.4", "v/4", "v06", "vj06", "w", "x",
    };
    static const std::set<std::string> hsu = {
        ",", ",3", ",4", ",6", ",7", "/", "3", "4", "6", "7",
        "a", "c", "d", "e", "f", "f7", "o", "o4", "r", "s",
        "s6", "v", "v.4", "v/4", "v06", "vj06", "x",
    };
    if (layout == BopomofoLayout::ETen26) {
        return eten26.count(canonicalKeys) != 0;
    }
    if (layout == BopomofoLayout::Hsu) {
        return hsu.count(canonicalKeys) != 0;
    }
    return false;
}

const char *layoutName(BopomofoLayout layout) {
    switch (layout) {
    case BopomofoLayout::Standard: return "Standard";
    case BopomofoLayout::ETen: return "ETen";
    case BopomofoLayout::ETen26: return "ETen26";
    case BopomofoLayout::Hsu: return "Hsu";
    case BopomofoLayout::HanyuPinyin: return "HanyuPinyin";
    }
    return "Unknown";
}

void testRealBopomofoDictionaryRoundTripsAcrossSymbolLayouts() {
    const auto dictionary = loadRealBopomofoDictionary();
    const std::vector<std::string> canonicalKeys = dictionary->keys();
    require(canonicalKeys.size() == 1541,
            "Unexpected number of unique bpmf-ext.cin readings");

    const BopomofoLayout layouts[] = {
        BopomofoLayout::Standard,
        BopomofoLayout::ETen,
        BopomofoLayout::ETen26,
        BopomofoLayout::Hsu,
    };
    std::vector<std::string> unexpectedFailures;
    std::string coverageSummary;
    for (const BopomofoLayout layout : layouts) {
        std::size_t tested = 0;
        for (const std::string &canonical : canonicalKeys) {
            BopomofoReading source;
            combineSequence(source, canonical, BopomofoLayout::Standard);
            if (source.queryKey() != canonical) {
                continue;
            }

            const std::string translated = source.inputKeySequence(layout);
            BopomofoReading roundTrip;
            combineSequence(roundTrip, translated, layout);
            if (roundTrip.queryKey() == canonical) {
                ++tested;
            } else if (!isKnownUnrepresentable(layout, canonical)) {
                unexpectedFailures.push_back(
                    std::string(layoutName(layout)) + ":" + canonical +
                    "->" + translated + "->" + roundTrip.queryKey());
            }
        }
        if (!coverageSummary.empty()) {
            coverageSummary += ", ";
        }
        coverageSummary += std::string(layoutName(layout)) + "=" +
                           std::to_string(tested);
        const std::size_t expectedCoverage =
            layout == BopomofoLayout::ETen26
                ? 1495U
                : (layout == BopomofoLayout::Hsu ? 1494U : 1521U);
        require(tested == expectedCoverage,
                std::string(layoutName(layout)) +
                    " real-dictionary round-trip coverage changed");
    }
    std::string failureSummary;
    for (const std::string &failure : unexpectedFailures) {
        if (!failureSummary.empty()) {
            failureSummary += ", ";
        }
        failureSummary += failure;
    }
    require(unexpectedFailures.empty(),
            "Unexpected symbol-layout round-trip failures (" + coverageSummary +
                "): " + failureSummary);
}

void testContextsAreIndependent() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState first;
    InputContextState second;

    engine.processKey(first, character('5'));
    engine.processKey(first, character('j'));
    engine.processKey(first, character('/'));
    engine.processKey(
        first, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    engine.processKey(second, character('s'));
    require(engine.snapshot(first).preedit == "ㄓㄨㄥ" &&
                !engine.snapshot(first).candidates.empty() &&
                engine.snapshot(first).candidates.front() == "中",
            "First context candidate state was corrupted");
    require(engine.snapshot(second).preedit == "ㄋ" &&
                engine.snapshot(second).candidates.empty(),
            "First context candidates leaked into the second context");

    first.reset();
    require(engine.snapshot(first).preedit.empty() &&
                engine.snapshot(first).candidates.empty(),
            "Reset did not clear the selected context");
    require(engine.snapshot(second).preedit == "ㄋ",
            "Reset of the first context corrupted the second context");

    engine.processKey(
        first, KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, false});
    engine.setTraditionalToSimplifiedMode(second, true);
    require(engine.snapshot(first).fullWidthMode &&
                !engine.snapshot(second).fullWidthMode,
            "Full-width mode leaked between input contexts");
    require(!engine.snapshot(first).traditionalToSimplifiedMode &&
                engine.snapshot(second).traditionalToSimplifiedMode,
            "Output-filter mode leaked between input contexts");
}

void testBopomofoBig5CandidateFilter() {
    require(isBig5HkscsRepresentable("誒") &&
                isBig5HkscsRepresentable("𤦩") &&
                !isBig5HkscsRepresentable("𠔅"),
            "Big-5 HKSCS representability anchors changed");
    require(filterBig5HkscsCandidates({"誒", "𠔅", "𤦩"}) ==
                std::vector<std::string>({"誒", "𤦩"}),
            "Big-5 candidate filtering changed order or membership");

    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;
    engine.processKey(context, character(','));
    auto result = engine.processKey(context, character('4'));
    require(result.candidates.size() == Engine::CandidatesPerPage &&
                result.candidates.at(0) == "誒" &&
                result.candidates.at(1) == "𠔅",
            "A tone key did not immediately open Unicode Bopomofo candidates");

    context.reset();
    engine.setRestrictBopomofoCandidatesToBig5(true);
    engine.processKey(context, character(','));
    result = engine.processKey(context, character('4'));
    require(result.candidates ==
                std::vector<std::string>({"誒", "𤦩", "𨗴"}),
            "Bopomofo Big-5 filtering changed the real candidate list");
    result = engine.processKey(context, character('2'));
    require(result.commit == "𤦩",
            "Big-5 filtered candidate selection committed the wrong text");
}

void testRealCangjieTypingFlow() {
    Engine engine(loadRealDictionary("cj-ext.cin"), InputMethod::Cangjie);
    InputContextState context;

    auto result = engine.processKey(context, character('a'));
    require(result.handled && result.preedit == "日",
            "Cangjie a must display the 日 key name");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() >= 2 && result.candidates.at(0) == "日" &&
                result.candidates.at(1) == "曰",
            "Real cj-ext.cin candidate order changed for a");
    result = engine.processKey(context, character('1'));
    require(result.commit == "日", "Cangjie candidate 1 must commit 日");

    result = engine.processKey(context, character(','));
    require(result.handled && result.commit == "，" &&
                result.preedit.empty() && result.candidates.empty(),
            "Cangjie direct punctuation must commit its sole result");

    engine.processKey(context, character('b'));
    engine.processKey(context, character('q'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && result.commit == "用" &&
                result.preedit.empty() && result.candidates.empty(),
            "Cangjie Space must directly commit a sole candidate");

    for (const char key : std::string("zzzzz")) {
        engine.processKey(context, character(key));
    }
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit.empty() &&
                result.candidates.empty(),
            "Cangjie query errors must clear the reading by default");

    for (const char key : std::string("abcdef")) {
        result = engine.processKey(context, character(key));
    }
    require(result.preedit == "日月金木水",
            "Cangjie accepted more than five roots");

    context.reset();
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '?', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.commit == "？",
            "Cangjie shifted direct punctuation was not normalized");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, ',', KeyModifier::Control, false,
                          false});
    require(!result.handled && result.commit.empty(),
            "Cangjie Ctrl punctuation shortcut must pass through");

    result = engine.processKey(context, character('a'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '?', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.preedit == "日？" &&
                result.candidates.empty() && result.commit.empty(),
            "Cangjie one-character wildcard was treated as an end key");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() > 2 && result.candidates.at(0) == "昌" &&
                result.candidates.at(1) == "昍" &&
                result.candidates.at(2) == "明",
            "Cangjie one-character wildcard candidates changed");
    result = engine.processKey(context, character('1'));
    require(result.commit == "昌",
            "Cangjie one-character wildcard candidate must commit 昌");

    engine.processKey(context, character('a'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '*', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.preedit == "日＊" &&
                result.candidates.empty() && result.commit.empty(),
            "Cangjie zero-or-more wildcard was treated as an end key");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() > 2 && result.candidates.at(0) == "日" &&
                result.candidates.at(1) == "曰" &&
                result.candidates.at(2) == "昌",
            "Cangjie zero-or-more wildcard candidates changed");
    result = engine.processKey(context, character('1'));
    require(result.commit == "日",
            "Cangjie zero-or-more wildcard candidate must commit 日");
}

void testRealSimplexTypingFlowAndCodeLimit() {
    Engine engine(loadRealDictionary("simplex-ext.cin"), InputMethod::Simplex);
    InputContextState context;

    auto result = engine.processKey(context, character('a'));
    require(result.handled && result.preedit == "日",
            "Simplex a must display the 日 key name");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() >= 2 && result.candidates.at(0) == "日" &&
                result.candidates.at(1) == "曰",
            "Real simplex-ext.cin candidate order changed for a");
    result = engine.processKey(context, character('2'));
    require(result.commit == "曰", "Simplex candidate 2 must commit 曰");

    result = engine.processKey(context, character('a'));
    require(result.preedit == "日" && result.candidates.empty(),
            "Simplex must wait for its second root");
    result = engine.processKey(context, character('b'));
    require(result.preedit == "日月" && result.candidates.size() > 1 &&
                result.candidates.front() == "明",
            "Simplex must query candidates at its two-root limit");
    result = engine.processKey(context, character('1'));
    require(result.commit == "明", "Simplex full-code candidate 1 must commit 明");

    engine.processKey(context, character('w'));
    result = engine.processKey(context, character('x'));
    require(result.handled && result.commit == "䍤" &&
                result.preedit.empty() && result.candidates.empty(),
            "Simplex full code with one candidate must commit immediately");

    result = engine.processKey(context, character(','));
    require(result.handled && result.preedit == "，" &&
                result.candidates.size() == 3 &&
                result.candidates.at(0) == "，" &&
                result.candidates.at(1) == "、",
            "Simplex direct punctuation must open its real candidate list");
    result = engine.processKey(context, character('2'));
    require(result.commit == "、",
            "Simplex punctuation candidate 2 must commit 、");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '+', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.preedit == "＋" &&
                result.candidates.empty(),
            "Simplex shifted non-end symbol did not remain in the reading");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() == 2 && result.candidates.at(0) == "＋" &&
                result.candidates.at(1) == "＝",
            "Simplex non-end punctuation did not query on Space");
    result = engine.processKey(context, character('2'));
    require(result.commit == "＝",
            "Simplex non-end punctuation candidate 2 must commit ＝");

    engine.processKey(context, character('a'));
    result = engine.processKey(context, character('b'));
    require(result.preedit == "日月", "Simplex full-code preedit changed");
    result = engine.processKey(context, character('c'));
    require(result.handled && result.commit == "明" && result.preedit == "金" &&
                result.candidates.empty(),
            "Simplex continuous typing did not commit the highlighted candidate");
}

void testCandidatePagingAndSelection() {
    std::istringstream input(
        "%chardef begin\n"
        "5j/ candidate-01\n5j/ candidate-02\n5j/ candidate-03\n"
        "5j/ candidate-04\n5j/ candidate-05\n5j/ candidate-06\n"
        "5j/ candidate-07\n5j/ candidate-08\n5j/ candidate-09\n"
        "5j/ candidate-10\n5j/ candidate-11\n5j/ candidate-12\n"
        "%chardef end\n");
    auto dictionary =
        std::make_shared<const CinDictionary>(CinDictionary::load(input));
    Engine engine(std::move(dictionary));
    InputContextState context;

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 0 && result.candidatePageCount == 2 &&
                result.candidates.size() == 9,
            "First candidate page metadata is wrong");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 1 && result.candidates.size() == 3 &&
                result.candidates.front() == "candidate-10",
            "Space did not advance to the second candidate page");
    result = engine.processKey(context, character('1'));
    require(result.commit == "candidate-10",
            "Candidate key selected from the wrong page");
}

void testCandidateKeyboardNavigation() {
    std::ostringstream definitions;
    definitions << "%chardef begin\n";
    for (int index = 1; index <= 12; ++index) {
        definitions << "5j/ candidate-" << index << '\n';
    }
    definitions << "%chardef end\n";
    std::istringstream input(definitions.str());
    auto dictionary =
        std::make_shared<const CinDictionary>(CinDictionary::load(input));
    Engine engine(std::move(dictionary));
    InputContextState context;

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});

    auto result = engine.processKey(
        context, KeyEvent{KeyCode::End, '\0', KeyModifier::None, false, false});
    require(result.handled && result.candidatePage == 1 &&
                result.highlightedIndex == 2 &&
                result.candidates.at(2) == "candidate-12",
            "End did not move to the final candidate");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Home, '\0', KeyModifier::None, false, false});
    require(result.handled && result.candidatePage == 0 &&
                result.highlightedIndex == 0 &&
                result.candidates.front() == "candidate-1",
            "Home did not move to the first candidate");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Up, '\0', KeyModifier::None, false, false});
    require(result.handled && result.candidatePage == 1 &&
                result.highlightedIndex == 2 &&
                result.candidates.at(2) == "candidate-12",
            "Up did not wrap to the final candidate");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Down, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 0 && result.highlightedIndex == 0,
            "Down did not wrap to the first candidate");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::PageDown, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 1 && result.highlightedIndex == 0 &&
                result.candidates.front() == "candidate-10",
            "PageDown did not advance and reset the highlight");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Down, '\0', KeyModifier::None, false, false});
    require(result.highlightedIndex == 1,
            "Down did not move the highlight on the current page");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Enter, '\0', KeyModifier::None, false, false});
    require(result.commit == "candidate-11",
            "Enter did not commit the highlighted candidate");

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    result = engine.processKey(
        context, KeyEvent{KeyCode::Left, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 1 && result.highlightedIndex == 0,
            "Left did not wrap to the final page");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Right, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 0 && result.highlightedIndex == 0,
            "Right did not wrap to the first page");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::PageUp, '\0', KeyModifier::None, false, false});
    require(result.candidatePage == 1 && result.highlightedIndex == 0,
            "PageUp did not wrap to the final page");
}

void testPunctuationAndSymbolShortcuts() {
    auto punctuationDictionary = loadRealDictionary("bpmf-punctuations.cin");
    Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::Standard, punctuationDictionary);
    InputContextState context;

    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Character, ',', KeyModifier::Control, false,
                          false});
    require(result.handled && result.commit == "，" && result.preedit.empty(),
            "Ctrl+, did not commit the full-width comma");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '.', KeyModifier::Control, false,
                          false});
    require(result.handled && result.commit == "。",
            "Ctrl+. did not commit the ideographic full stop");

    engine.processKey(context, character('s'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, ',', KeyModifier::Control, false,
                          false});
    require(result.handled && result.commit.empty() && result.preedit == "ㄋ",
            "A punctuation shortcut changed an active reading");
    engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});

    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '0', KeyModifier::Control, false,
                          false});
    require(result.handled && result.preedit == "，" &&
                result.candidatePageCount > 10 &&
                result.candidates.size() == Engine::CandidatesPerPage &&
                result.candidates.front() == "，" &&
                result.candidates.at(1) == "、",
            "Ctrl+0 did not open the real punctuation candidate list");
    result = engine.processKey(context, character('2'));
    require(result.commit == "、",
            "The punctuation list did not use normal candidate selection");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, 'a', KeyModifier::Control, false,
                          false});
    require(!result.handled && result.commit.empty(),
            "An undefined Ctrl shortcut did not pass through");
}

void testFullWidthModeAndAsciiMapping() {
    require(toFullWidth("Az09!~ 中文é") == "Ａｚ０９！～　中文é",
            "Full-width conversion changed the ASCII mapping or non-ASCII text");

    Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::Standard,
                  loadRealDictionary("bpmf-punctuations.cin"));
    InputContextState context;

    engine.processKey(context, character('s'));
    auto result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, false});
    require(result.handled && result.fullWidthMode && result.preedit == "ㄋ",
            "Shift+Space did not enable full-width mode or preserve reading");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, true});
    require(result.handled && result.fullWidthMode && result.preedit == "ㄋ",
            "Repeated Shift+Space toggled width or changed reading");
    engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});

    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, 'A', KeyModifier::Shift, false,
                          false});
    require(result.handled && result.commit == "Ａ" && result.fullWidthMode,
            "Full-width mode did not convert a shifted ASCII letter");
    result = engine.processKey(context, character('Z'));
    require(result.handled && result.commit == "Ｚ",
            "Full-width mode did not handle Fcitx-normalized uppercase input");
    result = engine.processKey(context, character('['));
    require(result.handled && result.commit == "［",
            "Full-width mode did not convert an unmapped ASCII punctuation key");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && result.commit == "　",
            "Full-width mode did not convert ASCII space");

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(!result.candidates.empty(),
            "Candidate list did not open before a width-mode toggle");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, false});
    require(result.handled && !result.fullWidthMode && !result.candidates.empty(),
            "Width toggle closed an active candidate list");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, false});
    require(result.fullWidthMode && !result.candidates.empty(),
            "Second width toggle did not preserve active candidates");
    result = engine.processKey(context, character('1'));
    require(result.commit == "中" && result.fullWidthMode,
            "Full-width mode changed a non-ASCII candidate commit");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, ',', KeyModifier::Control, false,
                          false});
    require(result.commit == "，" && result.fullWidthMode,
            "Full-width mode changed a table-backed punctuation commit");

    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::Shift, false, false});
    require(result.handled && !result.fullWidthMode,
            "Shift+Space did not return to half-width mode");
    result = engine.processKey(context, character('['));
    require(!result.handled && result.commit.empty(),
            "Half-width mode captured an unmapped application key");
}

void testTraditionalToSimplifiedOutputFilter() {
    const auto conversion = loadLinuxData("tc2sc.cin");
    require(conversion->entryCount() == 3058,
            "Traditional-to-Simplified mapping count changed");
    require(toSimplifiedChinese("國學體臺灣 A𠀀", *conversion) ==
                "国学体台湾 A𠀀",
            "Traditional-to-Simplified mapping or pass-through changed");

    Engine engine(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::Standard,
                  loadRealDictionary("bpmf-punctuations.cin"), conversion);
    InputContextState context;

    const auto composeReading = [&](const std::string &keys) {
        EngineResult result;
        for (const char key : keys) {
            result = engine.processKey(context, character(key));
        }
        if (!result.candidates.empty() || !result.commit.empty()) {
            return result;
        }
        return engine.processKey(
            context,
            KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    };

    auto result = composeReading("w96");
    require(result.candidates.size() > 1 && result.candidates[1] == "臺",
            "Real Bopomofo data did not expose 臺 before filtering");

    engine.setTraditionalToSimplifiedMode(context, true);
    result = engine.snapshot(context);
    require(result.traditionalToSimplifiedMode && !result.candidates.empty(),
            "Enabling Traditional-to-Simplified closed active candidates");
    std::string simplified;
    result = engine.processKey(context, character('2'));
    simplified += result.commit;
    result = composeReading("j0");
    require(!result.candidates.empty() && result.candidates.front() == "灣",
            "Real Bopomofo data did not expose 灣 before filtering");
    result = engine.processKey(context, character('1'));
    simplified += result.commit;
    require(simplified == "台湾" && result.traditionalToSimplifiedMode,
            "臺灣 was not converted to Simplified Chinese");

    context.reset();
    require(engine.snapshot(context).traditionalToSimplifiedMode,
            "Context reset discarded Traditional-to-Simplified mode");
    engine.setTraditionalToSimplifiedMode(context, false);
    std::string traditional;
    composeReading("w96");
    result = engine.processKey(context, character('2'));
    traditional += result.commit;
    composeReading("j0");
    result = engine.processKey(context, character('1'));
    traditional += result.commit;
    require(traditional == "臺灣" && !result.traditionalToSimplifiedMode,
            "Disabling Traditional-to-Simplified did not restore output");
}

void testModifiedAndReleaseKeysPassThrough() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;

    const KeyEvent shortcuts[] = {
        {KeyCode::Character, 'c', KeyModifier::Control, false, false},
        {KeyCode::Character, 'f', KeyModifier::Alt, false, false},
        {KeyCode::Character, 'l', KeyModifier::Super, false, false},
        {KeyCode::Left, '\0', KeyModifier::Control, false, false},
        {KeyCode::Character, 'c', KeyModifier::Control, false, true},
    };

    auto result = engine.processKey(context, shortcuts[0]);
    require(!result.handled && result.preedit.empty(),
            "Ctrl+C without composition must pass through");

    engine.processKey(context, character('5'));
    for (const KeyEvent &shortcut : shortcuts) {
        result = engine.processKey(context, shortcut);
        require(!result.handled && !result.beep && result.commit.empty() &&
                    result.preedit == "ㄓ" && result.candidates.empty(),
                "An application shortcut changed an active reading");
    }
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, 'j', KeyModifier::None, true, false});
    require(!result.handled && result.preedit == "ㄓ",
            "A key release changed an active reading");

    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(!result.candidates.empty() && result.candidates.front() == "中",
            "Shortcut-boundary test did not open the expected candidates");
    const std::vector<std::string> expectedCandidates = result.candidates;
    for (const KeyEvent &shortcut : shortcuts) {
        result = engine.processKey(context, shortcut);
        require(!result.handled && !result.beep && result.commit.empty() &&
                    result.preedit == "ㄓㄨㄥ" &&
                    result.candidates == expectedCandidates &&
                    result.highlightedIndex == 0,
                "An application shortcut changed an active candidate list");
    }
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, '1', KeyModifier::None, true, false});
    require(!result.handled && result.commit.empty() &&
                result.candidates == expectedCandidates,
            "A candidate-key release selected or changed a candidate");
    result = engine.processKey(context, character('1'));
    require(result.handled && result.commit == "中" &&
                result.preedit.empty() && result.candidates.empty(),
            "Candidate selection failed after application shortcuts");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Character, '1', KeyModifier::None, true, false});
    require(!result.handled && result.commit.empty() &&
                result.preedit.empty(),
            "A candidate-key release caused a duplicate commit");
}

void testBackspaceAndEscape() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;

    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false,
                          false});
    require(!result.handled && result.preedit.empty() &&
                result.candidates.empty(),
            "Backspace without composition must pass through to the app");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false,
                          false});
    require(!result.handled && result.preedit.empty() &&
                result.candidates.empty(),
            "Escape without composition must pass through to the app");

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit == "ㄓ", "Backspace must remove medial");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit.empty(), "Escape must cancel composition");

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    engine.processKey(context, character('/'));
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(!result.candidates.empty() && result.candidates.front() == "中",
            "Edit-boundary test did not open the expected candidate list");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false,
                          false});
    require(result.handled && result.commit.empty() &&
                result.preedit == "ㄓㄨ" && result.candidates.empty(),
            "Backspace in candidates must close the list and remove only the final");

    result = engine.processKey(context, character('/'));
    require(result.handled && result.preedit == "ㄓㄨㄥ",
            "Reading did not resume after candidate Backspace");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(!result.candidates.empty(),
            "Candidate list did not reopen after editing the reading");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false,
                          false});
    require(result.handled && result.commit.empty() && result.preedit.empty() &&
                result.candidates.empty(),
            "Escape in candidates must cancel the complete reading");

    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false,
                          false});
    require(!result.handled && result.preedit.empty() &&
                result.candidates.empty(),
            "Escape after canceling candidates must return to pass-through");
}

void testBopomofoReadingBlocksHostEditingKeys() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;

    engine.processKey(context, character('5'));
    auto result = engine.processKey(context, character('j'));
    require(result.preedit == "ㄓㄨ",
            "Editing-key test did not create the expected reading");

    const KeyCode editingKeys[] = {
        KeyCode::Left,   KeyCode::Right, KeyCode::Up,     KeyCode::Down,
        KeyCode::Home,   KeyCode::End,   KeyCode::PageUp, KeyCode::PageDown,
        KeyCode::Delete, KeyCode::Tab,
    };
    for (const KeyCode code : editingKeys) {
        result = engine.processKey(
            context, KeyEvent{code, '\0', KeyModifier::None, false, false});
        require(result.handled && result.beep && result.preedit == "ㄓㄨ" &&
                    result.candidates.empty() && result.commit.empty(),
                "An unmodified host editing key escaped or changed the reading");
        result = engine.processKey(
            context, KeyEvent{code, '\0', KeyModifier::Shift, false, false});
        require(result.handled && result.beep && result.preedit == "ㄓㄨ" &&
                    result.candidates.empty() && result.commit.empty(),
                "A Shift editing key escaped or changed the reading");
    }

    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Left, '\0', KeyModifier::Control, false, false});
    require(!result.handled && !result.beep && result.preedit == "ㄓㄨ",
            "Ctrl+Left must remain an application shortcut during a reading");

    result = engine.processKey(context, character('/'));
    require(result.handled && result.preedit == "ㄓㄨㄥ",
            "Editing-key test could not finish its reading");
    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && !result.candidates.empty(),
            "Editing-key test could not open candidates");
    const auto candidates = result.candidates;
    for (const KeyCode code : editingKeys) {
        if (code == KeyCode::Delete || code == KeyCode::Tab) {
            result = engine.processKey(
                context,
                KeyEvent{code, '\0', KeyModifier::None, false, false});
            require(result.handled && result.beep &&
                        result.candidates == candidates && result.commit.empty(),
                    "An invalid candidate editing key escaped or changed state");
        }
        result = engine.processKey(
            context, KeyEvent{code, '\0', KeyModifier::Shift, false, false});
        require(result.handled && result.beep &&
                    result.candidates == candidates && result.commit.empty(),
                "A Shift editing key escaped or changed candidates");
    }

    result = engine.processKey(
        context,
        KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit.empty() &&
                result.candidates.empty(),
            "Editing-key test could not cancel its candidates");
    for (const KeyCode code : editingKeys) {
        result = engine.processKey(
            context, KeyEvent{code, '\0', KeyModifier::None, false, false});
        require(!result.handled && !result.beep && result.preedit.empty(),
                "A host editing key was captured without a composition");
    }
}

void testSmartMandarinModelVersion() {
    sqlite3 *database = nullptr;
    require(sqlite3_open_v2(KEYKEY_TEST_SMART_DB, &database,
                            SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK,
            "Smart Mandarin model database did not open");
    sqlite3_stmt *statement = nullptr;
    const char *query =
        "SELECT (SELECT COUNT(*) FROM unigrams), "
        "(SELECT COUNT(*) FROM bigrams)";
    const int prepared = sqlite3_prepare_v2(database, query, -1, &statement,
                                            nullptr);
    require(prepared == SQLITE_OK && sqlite3_step(statement) == SQLITE_ROW,
            "Smart Mandarin model counts could not be read");
    const int unigrams = sqlite3_column_int(statement, 0);
    const int bigrams = sqlite3_column_int(statement, 1);
    sqlite3_finalize(statement);
    sqlite3_close(database);
    require(unigrams == 114235 && bigrams == 885614,
            "Smart Mandarin model version does not match macOS");
}

void testSmartMandarinComposition() {
    const auto store = keykey::linux_ime::SmartMandarinStore::open(
        KEYKEY_TEST_SMART_DB);
    require(store != nullptr, "Smart Mandarin database did not open");
    for (const auto &[query, expected] :
         std::vector<std::pair<std::string, std::string>>{
             {"L_", "不"}, {"ac", "列"}, {"8_", "密"}, {"@j", "印"},
             {"Qd", "代"}, {"IJ", "環"}, {"1_", "日"}, {"\\O", "你"},
             {"Dd", "血"}}) {
        keykey::linux_ime::SmartComposition composition;
        require(store->compose({query}, {}, composition) &&
                    composition.text == expected,
                "Smart Mandarin preferred an uncommon first-syllable reading");
        const auto candidates = store->candidates({query}, 0, composition);
        require(!candidates.empty() && candidates.front() == expected,
                "Smart Mandarin first-syllable candidate order diverged");
    }
    keykey::linux_ime::SmartComposition phrase;
    require(store->compose({"ac", "Dk", "n_"}, {}, phrase) &&
                phrase.text == "列上去",
            "Smart Mandarin did not compose 列上去");
    Engine engine(loadRealBopomofoDictionary());
    engine.setSmartMandarinStore(store);
    engine.setSmartMandarinMode(true);
    InputContextState context;
    EngineResult result;
    for (char key : std::string("su3cl3")) {
        result = engine.processKey(context, character(key));
    }
    require(result.handled && result.commit.empty() &&
                result.preedit == "你好",
            "Smart Mandarin did not compose two readings before commit");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && !result.candidates.empty() &&
                result.preedit == "你好",
            "Smart Mandarin did not offer candidates for the last reading");
    if (result.candidates.size() > 1) {
        result = engine.processKey(context, character('2'));
        require(result.handled && result.preedit != "你好" &&
                    result.commit.empty(),
                "Smart Mandarin candidate did not override the last reading");
        context.reset();
        for (char key : std::string("su3cl3")) {
            result = engine.processKey(context, character(key));
        }
        result = engine.processKey(
            context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    }
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit == "你好" &&
                result.candidates.empty(),
            "Closing Smart Mandarin candidates lost the composition");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Enter, '\0', KeyModifier::None, false, false});
    require(result.commit == "你好" && result.preedit.empty(),
            "Enter did not commit the Smart Mandarin composition");

    for (char key : std::string("su3cl3")) {
        result = engine.processKey(context, character(key));
    }
    result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false, false});
    require(result.preedit == "你", "Backspace did not remove the last reading");
    for (char key : std::string("cl3")) {
        result = engine.processKey(context, character(key));
    }
    result = engine.processKey(
        context, KeyEvent{KeyCode::Left, '\0', KeyModifier::None, false, false});
    require(result.preedit == "你好" && result.preeditCursorBytes == 3,
            "Smart Mandarin did not move its cursor between readings");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && !result.candidates.empty(),
            "Smart Mandarin did not open candidates at the cursor");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});
    require(result.preeditCursorBytes == 3 && result.preedit == "你好",
            "Closing cursor candidates moved the Smart Mandarin cursor");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false, false});
    require(result.preedit == "好" && result.preeditCursorBytes == 0,
            "Smart Mandarin did not delete before its cursor");
    for (char key : std::string("su3")) {
        result = engine.processKey(context, character(key));
    }
    require(result.preedit == "你好" && result.preeditCursorBytes == 3,
            "Smart Mandarin did not insert a reading at its cursor");
    engine.processKey(
        context, KeyEvent{KeyCode::Home, '\0', KeyModifier::None, false, false});
    result = engine.processKey(
        context, KeyEvent{KeyCode::Delete, '\0', KeyModifier::None, false, false});
    require(result.preedit == "好" && result.preeditCursorBytes == 0,
            "Smart Mandarin Delete did not remove the current reading");
    context.reset();
    for (char key : std::string("rup")) {
        result = engine.processKey(context, character(key));
    }
    result = engine.processKey(context, character('='));
    require(result.beep && result.preedit == "ㄐㄧㄣ",
            "Invalid key changed an unfinished Smart Mandarin reading");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.handled && !result.preedit.empty() &&
                result.preedit != "ㄐㄧㄣ",
            "Space did not finish a first-tone Smart Mandarin reading");
    context.reset();
    engine.setSmartMandarinMode(false);
    for (char key : std::string("su3")) {
        result = engine.processKey(context, character(key));
    }
    require(result.preedit == "ㄋㄧˇ" && !result.candidates.empty(),
            "Traditional mode did not restore single-reading candidates");
}

void testSmartMandarinUserData() {
    using keykey::linux_ime::SmartMandarinStore;
    using keykey::linux_ime::SmartMandarinUserData;
    char path[] = "/tmp/keykey-smart-user-XXXXXX";
    const int temporary = mkstemp(path);
    require(temporary >= 0, "Could not create a temporary user-data path");
    close(temporary);
    unlink(path);
    auto user = SmartMandarinUserData::open(path);
    require(user != nullptr, "Could not create Smart Mandarin user data");
    require(SmartMandarinUserData::readingToQuery("ㄋㄧˇ ㄏㄠˇ").size() == 4,
            "Custom phrase reading was not encoded");
    require(SmartMandarinUserData::queryToReading(
                SmartMandarinUserData::readingToQuery("ㄋㄧˇ ㄏㄠˇ")) ==
                "ㄋㄧˇ ㄏㄠˇ",
            "Custom phrase reading did not round trip");
    require(!user->addPhrase("甲乙", "ㄋㄧˇ"),
            "A mismatched custom phrase was accepted");
    require(user->addPhrase("甲乙", "ㄋㄧˇ ㄏㄠˇ"),
            "Could not add a custom phrase");
    require(user->phrases().size() == 1 &&
                user->phrases().front().first == "甲乙",
            "Custom phrase did not appear in the user database");
    {
        const auto store = SmartMandarinStore::open(KEYKEY_TEST_SMART_DB, user);
        Engine engine(loadRealBopomofoDictionary());
        engine.setSmartMandarinStore(store);
        engine.setSmartMandarinMode(true);
        InputContextState context;
        EngineResult result;
        for (char key : std::string("su3cl3")) {
            result = engine.processKey(context, character(key));
        }
        require(result.preedit == "甲乙",
                "Custom phrase did not enter the composition graph");
    }
    require(user->removePhrase("甲乙", "ㄋㄧˇ ㄏㄠˇ"),
            "Could not remove a custom phrase");
    require(user->phrases().empty(), "Removed custom phrase remained visible");
    const auto base = SmartMandarinStore::open(KEYKEY_TEST_SMART_DB);
    const std::string query = SmartMandarinUserData::readingToQuery("ㄏㄠˇ");
    keykey::linux_ime::SmartComposition composition;
    require(base->compose({query}, {}, composition),
            "Could not compose a reading for learning test");
    const auto candidates = base->candidates({query}, 0, composition);
    require(candidates.size() > 1 && candidates[0] != candidates[1],
            "Learning test needs distinct candidates");
    {
        const auto store = SmartMandarinStore::open(KEYKEY_TEST_SMART_DB, user);
        Engine engine(loadRealBopomofoDictionary());
        engine.setSmartMandarinStore(store);
        engine.setSmartMandarinMode(true);
        InputContextState context;
        for (char key : std::string("cl3")) {
            engine.processKey(context, character(key));
        }
        const auto opened = engine.processKey(
            context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
        require(opened.candidates.size() > 1 &&
                    opened.candidates[1] == candidates[1],
                "Engine did not expose the candidate to learn");
        const auto selected = engine.processKey(context, character('2'));
        require(selected.handled && selected.preedit == candidates[1] &&
                    user->learnedCandidate(query) == candidates[1],
                "Choosing a candidate did not save learning");
    }
    user.reset();
    const auto reopened = SmartMandarinUserData::open(path);
    require(reopened && reopened->learnedCandidate(query) == candidates[1],
            "Candidate choice was not persisted");
    const auto learnedStore = SmartMandarinStore::open(KEYKEY_TEST_SMART_DB,
                                                       reopened);
    require(learnedStore->compose({query}, {}, composition) &&
                composition.text == candidates[1],
            "Saved candidate choice did not affect new compositions");
    require(reopened->resetLearning(),
            "Could not clear the candidate choice before bigram test");
    {
        Engine engine(loadRealBopomofoDictionary());
        engine.setSmartMandarinStore(learnedStore);
        engine.setSmartMandarinMode(true);
        InputContextState context;
        for (char key : std::string("su3cl3")) {
            engine.processKey(context, character(key));
        }
        const auto opened = engine.processKey(
            context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
        require(opened.candidates.size() > 1,
                "Could not open sentence candidates for bigram learning");
        engine.processKey(context, character('2'));
        double learnedScore = -1;
        require(reopened->learnedBigram(
                    SmartMandarinUserData::readingToQuery("ㄋㄧˇ"), query,
                    "你", opened.candidates[1], learnedScore) &&
                    learnedScore == 0,
                "Sentence candidate selection did not learn the adjacent word");
    }
    require(reopened->addPhrase("甲乙", "ㄋㄧˇ ㄏㄠˇ"),
            "Could not restore custom phrase before learning reset");
    require(reopened->resetLearning() &&
                reopened->learnedCandidate(query).empty() &&
                reopened->phrases().size() == 1,
            "Reset learning removed custom phrases or retained learning");
    require(learnedStore->compose({query}, {}, composition) &&
                composition.text == candidates[0],
            "Reset learning did not restore normal composition");
    unlink(path);
}

} // namespace

int main(int argc, char **argv) {
    try {
        if (argc == 2 && std::string(argv[1]) == "--smart-only") {
            testSmartMandarinModelVersion();
            testSmartMandarinComposition();
            testSmartMandarinUserData();
            std::cout << "Smart Mandarin tests passed\n";
            return EXIT_SUCCESS;
        }
        testCinParserHandlesBomCrlfAndPercentKey();
        testCinParserRejectsIncompleteData();
        testCinWildcardMatchingPreservesTableOrder();
        testAssociatedPhraseParserFiltersAndSorts();
        testRealAssociatedPhraseCollections();
        testAssociatedPhraseKeyboardFlow();
        testRealDataTypingFlow();
        testBopomofoContinuousTypingAndInputErrors();
        testAllBopomofoLayoutsUseCanonicalDictionaryKeys();
        testBopomofoLayoutTonesAndAmbiguities();
        testBopomofoLayoutToneTypingFlows();
        testHanyuPinyinAliasesAndToneValidation();
        testRealBopomofoDictionaryRoundTripsAcrossSymbolLayouts();
        testContextsAreIndependent();
        testBopomofoBig5CandidateFilter();
        testRealCangjieTypingFlow();
        testRealSimplexTypingFlowAndCodeLimit();
        testCandidatePagingAndSelection();
        testCandidateKeyboardNavigation();
        testPunctuationAndSymbolShortcuts();
        testFullWidthModeAndAsciiMapping();
        testTraditionalToSimplifiedOutputFilter();
        testModifiedAndReleaseKeysPassThrough();
        testBackspaceAndEscape();
        testBopomofoReadingBlocksHostEditingKeys();
        testSmartMandarinModelVersion();
        testSmartMandarinComposition();
        testSmartMandarinUserData();
    } catch (const std::exception &error) {
        std::cerr << "FAILED: " << error.what() << '\n';
        return EXIT_FAILURE;
    }
    std::cout << "All Linux engine tests passed\n";
    return EXIT_SUCCESS;
}

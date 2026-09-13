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
        require(reading.backspace(testCase.layout),
                "Layout did not remove the last key");
        require(reading.queryKey() == "x/",
                "Layout backspace did not preserve ㄌㄥ");
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
            for (const char key : std::string(sequence)) {
                engine.processKey(context, character(key));
            }
            auto result = engine.processKey(
                context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None,
                                  false, false});
            require(!result.candidates.empty(),
                    "A tone sequence did not open real candidates");
            result = engine.processKey(context, character('1'));
            committed += result.commit;
        }
        require(committed == "麻馬罵嘛",
                "A layout did not commit all four Mandarin tone fixtures");
    }

    Engine pinyin(loadRealBopomofoDictionary(), InputMethod::Bopomofo,
                  BopomofoLayout::HanyuPinyin);
    InputContextState context;
    auto result = pinyin.processKey(context, character('z'));
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
    engine.processKey(second, character('s'));
    require(engine.snapshot(first).preedit == "ㄓ", "First context was corrupted");
    require(engine.snapshot(second).preedit == "ㄋ", "Second context was corrupted");
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
    engine.processKey(context, character('4'));
    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
    require(result.candidates.size() == Engine::CandidatesPerPage &&
                result.candidates.at(0) == "誒" &&
                result.candidates.at(1) == "𠔅",
            "Unicode Bopomofo candidates changed before Big-5 filtering");

    context.reset();
    engine.setRestrictBopomofoCandidatesToBig5(true);
    engine.processKey(context, character(','));
    engine.processKey(context, character('4'));
    result = engine.processKey(
        context, KeyEvent{KeyCode::Space, '\0', KeyModifier::None, false, false});
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
        for (const char key : keys) {
            engine.processKey(context, character(key));
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

    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Character, 'c', KeyModifier::Control, false, false});
    require(!result.handled && result.preedit.empty(), "Ctrl+C must pass through");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Character, '5', KeyModifier::None, true, false});
    require(!result.handled && result.preedit.empty(), "Key release must pass through");
}

void testBackspaceAndEscape() {
    Engine engine(loadRealBopomofoDictionary());
    InputContextState context;

    engine.processKey(context, character('5'));
    engine.processKey(context, character('j'));
    auto result = engine.processKey(
        context, KeyEvent{KeyCode::Backspace, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit == "ㄓ", "Backspace must remove medial");
    result = engine.processKey(
        context, KeyEvent{KeyCode::Escape, '\0', KeyModifier::None, false, false});
    require(result.handled && result.preedit.empty(), "Escape must cancel composition");
}

} // namespace

int main() {
    try {
        testCinParserHandlesBomCrlfAndPercentKey();
        testCinParserRejectsIncompleteData();
        testCinWildcardMatchingPreservesTableOrder();
        testAssociatedPhraseParserFiltersAndSorts();
        testRealAssociatedPhraseCollections();
        testAssociatedPhraseKeyboardFlow();
        testRealDataTypingFlow();
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
    } catch (const std::exception &error) {
        std::cerr << "FAILED: " << error.what() << '\n';
        return EXIT_FAILURE;
    }
    std::cout << "All Linux engine tests passed\n";
    return EXIT_SUCCESS;
}

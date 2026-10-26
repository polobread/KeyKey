// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Linux FE/C ABI integration, using isolated stores and the real model.
#include "keykey/linux_ime/guanyinma_session.h"
#include "keykey/linux_ime/candidate_font_support.h"
#include "keykey/linux_ime/smart_mandarin_user_data.h"

#include <json-c/json.h>
#include <sqlite3.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <sys/stat.h>
#include <unistd.h>

using namespace keykey::linux_ime;
namespace {
void require(bool condition, const std::string &message) { if (!condition) throw std::runtime_error(message); }
struct JsonDelete { void operator()(json_object *p) const { if (p) json_object_put(p); } };
using Json = std::unique_ptr<json_object, JsonDelete>;
Json parse(const std::string &text) {
    Json value(json_tokener_parse(text.c_str())); require(bool(value), "Invalid integration JSON"); return value;
}
json_object *get(json_object *value, const char *key) {
    json_object *child = nullptr; require(json_object_object_get_ex(value, key, &child), std::string("Missing ") + key); return child;
}
std::size_t count(json_object *value) { return json_object_array_length(value); }
std::string encoded(const std::string &value) {
    Json json(json_object_new_string(value.c_str())); return json_object_to_json_string_ext(json.get(), JSON_C_TO_STRING_PLAIN);
}
struct Scratch {
    std::filesystem::path directory;
    unsigned serial = 0;
    Scratch() {
        std::string pattern = "/tmp/keykey-guanyinma-integration-XXXXXX";
        const auto path = mkdtemp(pattern.data()); require(path, "Cannot create isolated test directory"); directory = path;
    }
    ~Scratch() { std::error_code error; std::filesystem::remove_all(directory, error); }
    std::string path(const std::string &name = "user") { return (directory / (name + std::to_string(serial++) + ".db")).string(); }
};
KeyEvent character(char ch) { KeyEvent event; event.character = ch; return event; }
EngineResult type(GuanyinmaSession &session, const std::string &text) {
    auto result = session.snapshot();
    for (char ch : text) {
        result = session.processKey(character(ch));
        require(session.lastError().empty(), "Key failure: " + session.lastError());
    }
    return result;
}
EngineResult key(GuanyinmaSession &session, KeyCode code) { KeyEvent event; event.code = code; return session.processKey(event); }
const auto acceptAll = [](const std::string &) { return true; };
GuanyinmaConfig traditional() { GuanyinmaConfig config; config.smartMode = false; return config; }
GuanyinmaConfig table(InputMethod method) { GuanyinmaConfig config; config.inputMethod = method; return config; }

void traditionalFlow(const std::string &model, Scratch &scratch) {
    GuanyinmaSession session(model, scratch.path(), traditional(), acceptAll);
    require(session.quiet() && session.valid(), "New session is not quiet");
    require(type(session, "5j/").preedit == "ㄓㄨㄥ", "Traditional reading mapping");
    auto view = key(session, KeyCode::Space);
    require(view.candidates.size() == 9, "Linux nine-candidate mapping");
    const auto expected = view.candidates[1];
    auto result = session.selectDisplayedCandidate(1);
    require(result.commit == expected && result.handled, "Page-local candidate mapping");
    require(session.snapshot().commit.empty() && !session.snapshot().handled, "Snapshot replayed host effects");
    require(session.quiet(), "Completed session not quiet");
}
void handoffFlow(const std::string &model, Scratch &scratch) {
    GuanyinmaSession smart(model, scratch.path(), {}, acceptAll);
    type(smart, "5j/");
    require(smart.finishComposition().commit == "中", "Smart handoff did not complete reading");
    require(smart.finishComposition().commit.empty(), "Repeated handoff duplicated commit");
    GuanyinmaSession plain(model, scratch.path(), traditional(), acceptAll);
    type(plain, "5j/"); key(plain, KeyCode::Space);
    auto highlighted = key(plain, KeyCode::Down);
    require(plain.finishComposition().commit == highlighted.candidates[highlighted.highlightedIndex], "Traditional handoff lost highlight");
    for (auto method : {InputMethod::Cangjie, InputMethod::Simplex}) {
        GuanyinmaSession input(model, scratch.path(), table(method), acceptAll);
        require(!type(input, "a").preedit.empty(), "Table code missing");
        require(input.finishComposition().commit.empty() && input.quiet(), "Unconfirmed table code leaked to host");
    }
}
void physicalKeys(const std::string &model, Scratch &scratch) {
    GuanyinmaSession input(model, scratch.path(), traditional(), acceptAll);
    auto event = character('1'); event.numLock = true;
    require(input.processKey(event).preedit == "ㄅ", "Global NumLock changed main-keyboard input");
    input.reset(); event.keypad = true;
    require(input.processKey(event).commit == "1" && input.quiet(), "Keypad number entered phonetics");
    event = character('S'); event.capsLock = true;
    require(input.processKey(event).commit == "S", "CapsLock actual text was lost");
    event = character('5'); event.release = true;
    require(!input.processKey(event).handled && input.quiet(), "Key release changed composition");
    input.setFullWidth(true);
    event = character('!'); event.rawShift = true;
    require(input.processKey(event).commit == "！", "Raw Shift/full-width mapping");
    require(input.snapshot().fullWidthMode, "Width snapshot missing");
}
void unicodeCoordinates(const std::string &model, Scratch &scratch) {
    GuanyinmaSession input(model, scratch.path(), {}, acceptAll);
    type(input, "5j/ ");
    input.applyJson("{\"type\":\"direct_text\",\"text\":\"😀\"}");
    require(input.snapshot().preedit == "中😀" && input.snapshot().preeditCursorBytes == 7, "Scalar to UTF-8 byte cursor failed");
    KeyEvent mark; mark.code = KeyCode::Left; mark.rawShift = true;
    const auto marked = input.processKey(mark);
    require(marked.hasMarkedPhrase && marked.markedPreeditStartBytes == 3 && marked.markedPreeditLengthBytes == 4,
            "Supplementary-plane phrase mark did not map to UTF-8 bytes");
    key(input, KeyCode::Escape);
    input.applyJson("{\"type\":\"set_cursor\",\"index\":2}");
    type(input, "5j/ ");
    const auto result = input.selectSmartCharacter(2);
    require(result.handled && !result.candidates.empty(), "Smart click did not map supplementary text to reading");
    require(input.selectSmartCharacter(999).beep, "Out-of-range click not rejected");
}
void filtering(const std::string &model, Scratch &scratch) {
    GuanyinmaSession input(model, scratch.path(), traditional(), [](const std::string &text) { return text != "中"; });
    type(input, "5j/");
    const auto result = key(input, KeyCode::Space);
    require(!result.candidates.empty() && std::find(result.candidates.begin(), result.candidates.end(), "中") == result.candidates.end(), "Candidate callback not applied before display");
    require(!input.acceptsCandidate("中"), "FE overlay policy differs from core policy");
    CandidateFontSupport native;
    require(native.accepts("ASCII") && !native.accepts(std::string("\xff", 1)), "Native font provider failed valid/invalid UTF-8 smoke");
}
void learningStores(const std::string &model, Scratch &scratch) {
    const auto store = scratch.path();
    const auto query = SmartMandarinUserData::readingToQuery("ㄓㄨㄥ ㄓㄨㄥ");
    GuanyinmaSession first(model, store, {}, acceptAll);
    first.applyJson("{\"type\":\"add_user_phrase\",\"qstring\":" + encoded(query) + ",\"text\":\"中中\"}");
    GuanyinmaSession second(model, store, {}, acceptAll);
    auto data = parse(second.userDataJson());
    require(count(get(get(data.get(), "data"), "phrases")) == 1, "Second admin session missed custom phrase");
    second.applyJson("{\"type\":\"reset_method_learning\",\"method\":\"smart\"}");
    require(count(get(get(parse(first.userDataJson()).get(), "data"), "phrases")) == 1, "Smart reset removed custom phrase");
    GuanyinmaSession isolated(model, scratch.path(), {}, acceptAll);
    require(count(get(get(parse(isolated.userDataJson()).get(), "data"), "phrases")) == 0, "Different backend store was contaminated");
    struct stat status{}; require(stat(store.c_str(), &status) == 0 && (status.st_mode & 0777) == 0600, "Private user DB permissions");
}
void legacyImport(const std::string &model, Scratch &scratch) {
    const auto source = scratch.path("legacy");
    auto legacy = SmartMandarinUserData::open(source);
    require(bool(legacy) && legacy->addPhrase("中中", "ㄓㄨㄥ ㄓㄨㄥ"), "Cannot create real Linux writer fixture");
    const auto query = SmartMandarinUserData::readingToQuery("ㄓㄨㄥ");
    require(legacy->learn(query, "鐘", query, "中"), "Cannot write real Linux learning fixture");
    const auto size = std::filesystem::file_size(source);
    GuanyinmaSession target(model, scratch.path(), {}, acceptAll);
    target.applyJson("{\"type\":\"import_legacy_user_data\",\"path\":" + encoded(source) + "}");
    const auto data = parse(target.userDataJson()); auto *state = get(data.get(), "data");
    require(count(get(state, "phrases")) == 1 && count(get(state, "overrides")) == 1 && count(get(state, "bigrams")) == 1, "Legacy import lost phrases or learning");
    require(std::filesystem::file_size(source) == size && legacy->phrases().size() == 1 && legacy->learnedCandidate(query) == "鐘", "Legacy import mutated source");
    require(type(target, "5j/ ").preedit == "鐘", "Imported Linux candidate preference did not affect actual input");
}
void failureAndReset(const std::string &model, Scratch &scratch) {
    const auto path = scratch.path();
    GuanyinmaSession input(model, path, {}, acceptAll);
    type(input, "5");
    sqlite3 *lock = nullptr;
    require(sqlite3_open(path.c_str(), &lock) == SQLITE_OK, "Cannot open lock fixture");
    require(sqlite3_exec(lock, "BEGIN EXCLUSIVE", nullptr, nullptr, nullptr) == SQLITE_OK, "Cannot lock fixture");
    const auto before = input.snapshot().preedit;
    auto result = input.processKey(character('j'));
    require(result.beep && result.handled && result.commit.empty() && !input.lastError().empty() && result.preedit == before, "Failed operation mutated view or emitted effects");
    input.reset();
    require(!input.valid() && input.quiet() && input.snapshot().preedit.empty(), "Reset failure revived old composition");
    sqlite3_exec(lock, "ROLLBACK", nullptr, nullptr, nullptr);
    sqlite3_close(lock);
}
void configurationAndPaths(const std::string &model, Scratch &scratch) {
    GuanyinmaConfig config;
    auto changed = config; changed.table.prefixCandidates = true;
    require(config != changed && config == GuanyinmaConfig{}, "Configuration value ownership");
    bool refused = false;
    try { GuanyinmaSession invalid(model, model, config, acceptAll); }
    catch (const std::exception &) { refused = true; }
    require(refused, "Shared model accepted as user DB");
    const auto alias = scratch.directory / "model-alias.db";
    std::filesystem::create_symlink(model, alias);
    refused = false;
    try { GuanyinmaSession invalid(model, alias.string(), config, acceptAll); }
    catch (const std::exception &) { refused = true; }
    require(refused, "Shared model alias accepted as user DB");
    GuanyinmaSession input(model, scratch.path(), config, acceptAll);
    refused = false;
    try { input.applyJson("{\"type\":\"unknown\"}"); } catch (const std::exception &) { refused = true; }
    require(refused && input.quiet() && input.snapshot().commit.empty(), "Invalid operation was ignored or emitted effects");
}
} // namespace

int main(int argc, char **argv) {
    try {
        require(argc == 2, "Usage: keykey_linux_guanyinma_tests MODEL");
        const auto model = std::filesystem::canonical(argv[1]).string();
        Scratch scratch;
        traditionalFlow(model, scratch);
        handoffFlow(model, scratch);
        physicalKeys(model, scratch);
        unicodeCoordinates(model, scratch);
        filtering(model, scratch);
        learningStores(model, scratch);
        legacyImport(model, scratch);
        failureAndReset(model, scratch);
        configurationAndPaths(model, scratch);
        std::cout << "9 Linux/C ABI integration groups passed; stores isolated; snapshots never replay effects\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

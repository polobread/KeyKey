// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/guanyinma_session.h"
#include "keykey/linux_ime/candidate_encoding.h"
#include "keykey/linux_ime/candidate_font_support.h"

#include "guanyinma.h"
#include <json-c/json.h>

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <limits>
#include <stdexcept>
#include <sys/stat.h>
#include <utility>
#include <vector>

namespace keykey::linux_ime {
namespace {

struct JsonDeleter { void operator()(json_object *p) const { if (p) json_object_put(p); } };
using Json = std::unique_ptr<json_object, JsonDeleter>;
constexpr std::size_t MaximumResultBytes = 64U * 1024U * 1024U;

Json object() { return Json(json_object_new_object()); }
Json parse(const std::string &text) {
    if (text.size() > MaximumResultBytes || text.size() > static_cast<std::size_t>(std::numeric_limits<int>::max()))
        throw std::runtime_error("Guanyinma JSON exceeds the size limit");
    std::unique_ptr<json_tokener, decltype(&json_tokener_free)> tokener(json_tokener_new(), json_tokener_free);
    if (!tokener) throw std::bad_alloc();
    json_tokener_set_flags(tokener.get(), JSON_TOKENER_STRICT);
    Json value(json_tokener_parse_ex(tokener.get(), text.c_str(), static_cast<int>(text.size())));
    if (json_tokener_get_error(tokener.get()) != json_tokener_success || !value)
        throw std::runtime_error("Invalid Guanyinma JSON result");
    auto end = json_tokener_get_parse_end(tokener.get());
    while (end < text.size() && std::isspace(static_cast<unsigned char>(text[end]))) ++end;
    if (end != text.size() || json_object_get_type(value.get()) != json_type_object)
        throw std::runtime_error("Invalid Guanyinma JSON object");
    return value;
}
void put(json_object *value, const char *key, const std::string &text) {
    if (text.size() > static_cast<std::size_t>(std::numeric_limits<int>::max())) throw std::length_error("JSON string too long");
    json_object_object_add(value, key, json_object_new_string_len(text.data(), static_cast<int>(text.size())));
}
void put(json_object *value, const char *key, const char *text) { put(value, key, std::string(text)); }
void put(json_object *value, const char *key, bool flag) { json_object_object_add(value, key, json_object_new_boolean(flag)); }
void put(json_object *value, const char *key, std::size_t count) {
    if (count > static_cast<std::size_t>(std::numeric_limits<std::int64_t>::max())) throw std::length_error("JSON index too large");
    json_object_object_add(value, key, json_object_new_int64(static_cast<std::int64_t>(count)));
}
std::string dump(json_object *value) { return json_object_to_json_string_ext(value, JSON_C_TO_STRING_PLAIN); }
json_object *field(json_object *value, const char *key) {
    json_object *result = nullptr;
    if (!json_object_object_get_ex(value, key, &result)) throw std::runtime_error(std::string("Missing Guanyinma field: ") + key);
    return result;
}
std::string stringValue(json_object *value) {
    if (!value || json_object_get_type(value) != json_type_string) throw std::runtime_error("Invalid Guanyinma string");
    return std::string(json_object_get_string(value), static_cast<std::size_t>(json_object_get_string_len(value)));
}
std::string stringField(json_object *value, const char *key) { return stringValue(field(value, key)); }
std::size_t integerValue(json_object *value) {
    if (!value || json_object_get_type(value) != json_type_int || json_object_get_int64(value) < 0)
        throw std::runtime_error("Invalid Guanyinma index");
    const auto number = json_object_get_uint64(value);
    if (number > std::numeric_limits<std::size_t>::max()) throw std::runtime_error("Guanyinma index overflow");
    return static_cast<std::size_t>(number);
}
std::size_t integerField(json_object *value, const char *key) { return integerValue(field(value, key)); }
bool booleanField(json_object *value, const char *key) {
    auto *result = field(value, key);
    if (!result || json_object_get_type(result) != json_type_boolean) throw std::runtime_error("Invalid Guanyinma boolean");
    return json_object_get_boolean(result) != 0;
}
std::vector<std::string> strings(json_object *value) {
    if (!value || json_object_get_type(value) != json_type_array) throw std::runtime_error("Invalid Guanyinma array");
    std::vector<std::string> result;
    const auto count = json_object_array_length(value);
    result.reserve(count);
    for (std::size_t i = 0; i < count; ++i) result.push_back(stringValue(json_object_array_get_idx(value, i)));
    return result;
}
std::size_t scalarCount(const std::string &text) {
    return static_cast<std::size_t>(std::count_if(text.begin(), text.end(), [](unsigned char ch) { return (ch & 0xc0U) != 0x80U; }));
}
std::size_t byteOffset(const std::string &text, std::size_t scalars) {
    std::size_t offset = 0;
    while (offset < text.size() && scalars) {
        ++offset;
        while (offset < text.size() && (static_cast<unsigned char>(text[offset]) & 0xc0U) == 0x80U) ++offset;
        --scalars;
    }
    if (scalars) throw std::runtime_error("Guanyinma cursor is outside visible text");
    return offset;
}
std::string diagnostic() {
    std::size_t size = 0;
    if (guanyinma_last_error(nullptr, 0, &size) != GUANYINMA_BUFFER_TOO_SMALL || !size || size > MaximumResultBytes)
        return "Guanyinma operation failed";
    std::vector<std::uint8_t> buffer(size);
    if (guanyinma_last_error(buffer.data(), buffer.size(), &size) != GUANYINMA_OK) return "Guanyinma operation failed";
    return reinterpret_cast<const char *>(buffer.data());
}
void check(std::int32_t status) { if (status != GUANYINMA_OK) throw std::runtime_error(diagnostic()); }
std::string readResult(::GuanyinmaResult *handle) {
    struct Guard { ::GuanyinmaResult *value; ~Guard() { guanyinma_result_close(&value); } } guard{handle};
    std::size_t size = 0;
    if (guanyinma_result_json(handle, nullptr, 0, &size) != GUANYINMA_BUFFER_TOO_SMALL || !size || size > MaximumResultBytes)
        throw std::runtime_error("Cannot read Guanyinma result size");
    std::vector<std::uint8_t> buffer(size);
    check(guanyinma_result_json(handle, buffer.data(), buffer.size(), &size));
    if (size == 0 || buffer[size - 1] != 0) throw std::runtime_error("Invalid Guanyinma result buffer");
    return std::string(reinterpret_cast<const char *>(buffer.data()), size - 1);
}
void clearEffects(EngineResult &value) {
    value.handled = false;
    value.updateUi = false;
    value.beep = false;
    value.commit.clear();
    value.deleteBackward = false;
    value.sendReturn = false;
    value.discardComposition = false;
    value.phraseFeedback.clear();
    value.phraseAdded = false;
}
bool samePath(const std::filesystem::path &a, const std::filesystem::path &b) {
    if (a.empty() || b.empty()) return false;
    std::error_code error;
    if (std::filesystem::equivalent(a, b, error)) return true;
    error.clear();
    const auto aa = std::filesystem::weakly_canonical(a, error);
    if (error) return false;
    const auto bb = std::filesystem::weakly_canonical(b, error);
    return !error && aa == bb;
}
void prepareUserPath(const std::string &path, const std::string &model) {
    if (path.empty()) throw std::runtime_error("Guanyinma requires a private user database path");
    if (samePath(path, model) || samePath(path, SmartMandarinUserData::defaultPath()))
        throw std::runtime_error("Guanyinma user database must differ from the model and legacy profile");
    const auto parent = std::filesystem::path(path).parent_path();
    if (!parent.empty()) {
        std::error_code error;
        const bool created = std::filesystem::create_directories(parent, error);
        if (error) throw std::runtime_error("Cannot create Guanyinma user directory: " + error.message());
        if (created || parent.filename() == "chichi77-keykey") {
            if (chmod(parent.c_str(), 0700) != 0) throw std::runtime_error("Cannot secure Guanyinma user directory");
        }
    }
}
const char *layoutName(BopomofoLayout layout) {
    switch (layout) {
    case BopomofoLayout::Standard: return "standard";
    case BopomofoLayout::ETen: return "eten";
    case BopomofoLayout::ETen26: return "eten26";
    case BopomofoLayout::Hsu: return "hsu";
    case BopomofoLayout::HanyuPinyin: return "hanyu_pinyin";
    }
    throw std::runtime_error("Unsupported Bopomofo layout");
}
const char *keyName(KeyCode code) {
    switch (code) {
    case KeyCode::Space: return "space";
    case KeyCode::Enter: return "return";
    case KeyCode::Backspace: return "backspace";
    case KeyCode::Delete: return "delete";
    case KeyCode::Tab: return "tab";
    case KeyCode::Escape: return "escape";
    case KeyCode::Left: return "left";
    case KeyCode::Right: return "right";
    case KeyCode::Up: return "up";
    case KeyCode::Down: return "down";
    case KeyCode::Home: return "home";
    case KeyCode::End: return "end";
    case KeyCode::PageUp: return "page_up";
    case KeyCode::PageDown: return "page_down";
    case KeyCode::Character: break;
    }
    throw std::runtime_error("Unsupported key");
}
Json operation(const char *type) { auto result = object(); put(result.get(), "type", type); return result; }

} // namespace

bool GuanyinmaConfig::operator==(const GuanyinmaConfig &other) const noexcept {
    return inputMethod == other.inputMethod && smartMode == other.smartMode && layout == other.layout &&
           smart == other.smart && table.composeWhileTyping == other.table.composeWhileTyping &&
           table.prefixCandidates == other.table.prefixCandidates && table.clearOnError == other.table.clearOnError &&
           restrictBopomofoToBig5 == other.restrictBopomofoToBig5;
}

class GuanyinmaSession::Impl {
public:
    Impl(std::string model, std::string user, GuanyinmaConfig preferences, CandidateFilter filter)
        : config(std::move(preferences)), candidateFilter(std::move(filter)) {
        if (guanyinma_abi_version() != 1) throw std::runtime_error("Unsupported Guanyinma ABI");
        prepareUserPath(user, model);
        if (!candidateFilter) {
            nativeFonts = std::make_unique<CandidateFontSupport>();
            candidateFilter = [this](const std::string &text) { return nativeFonts->accepts(text); };
        }
        auto root = object();
        const bool smart = config.inputMethod == InputMethod::Bopomofo && config.smartMode;
        put(root.get(), "method", config.inputMethod == InputMethod::Cangjie ? "cangjie" :
            config.inputMethod == InputMethod::Simplex ? "simplex" : smart ? "smart" : "traditional");
        put(root.get(), "profile", "desktop");
        put(root.get(), "layout", layoutName(config.layout));
        put(root.get(), "user_database", user);
        put(root.get(), "traditional_selection_keys", "123456789");
        put(root.get(), "table_selection_keys", "123456789");
        auto behaviors = object();
        put(behaviors.get(), "ignore_caps_lock_in_chinese", false);
        put(behaviors.get(), "literal_keypad", true);
        json_object_object_add(root.get(), "behaviors", behaviors.release());
        auto learning = object();
        put(learning.get(), "user_phrases", true);
        put(learning.get(), "candidate_overrides", smart);
        put(learning.get(), "bigrams", smart);
        put(learning.get(), "table_learning", false);
        json_object_object_add(root.get(), "learning", learning.release());
        auto options = object();
        put(options.get(), "use_bigrams", true);
        put(options.get(), "space_opens_candidates", config.smart.showCandidateListWithSpace);
        put(options.get(), "candidate_cursor_at_end", config.smart.candidateCursorAtEndOfTargetBlock);
        put(options.get(), "clear_composing_with_escape", config.smart.clearComposingTextWithEsc);
        put(options.get(), "max_completed_syllables", std::size_t{10});
        put(options.get(), "shift_at_limit", false);
        put(options.get(), "selection_returns_to_end", false);
        put(options.get(), "candidate_selection_keys", "123456789");
        json_object_object_add(root.get(), "smart", options.release());
        auto cangjie = object();
        put(cangjie.get(), "realtime", config.table.composeWhileTyping);
        put(cangjie.get(), "prefix", config.table.prefixCandidates);
        put(cangjie.get(), "clear_on_error", config.table.clearOnError && !config.table.composeWhileTyping);
        put(cangjie.get(), "query_at_maximum", false);
        put(cangjie.get(), "learn_selection", false);
        json_object_object_add(root.get(), "cangjie", cangjie.release());
        auto simplex = object();
        put(simplex.get(), "query_at_maximum", true);
        put(simplex.get(), "clear_on_error", false);
        put(simplex.get(), "learn_selection", false);
        json_object_object_add(root.get(), "simplex", simplex.release());
        const auto json = dump(root.get());
        check(guanyinma_session_open_with_candidate_filter(
            reinterpret_cast<const std::uint8_t *>(model.data()), model.size(),
            reinterpret_cast<const std::uint8_t *>(json.data()), json.size(), acceptsCallback, this, &session));
        try {
            if (chmod(user.c_str(), 0600) != 0) throw std::runtime_error("Cannot secure Guanyinma user database");
            ::GuanyinmaResult *result = nullptr;
            check(guanyinma_session_snapshot(session, &result));
            decode(readResult(result));
        } catch (...) {
            guanyinma_session_close(&session);
            throw;
        }
    }
    ~Impl() { guanyinma_session_close(&session); }
    static std::int32_t GUANYINMA_CALL acceptsCallback(void *context, const std::uint8_t *bytes, std::size_t size) noexcept {
        try { return static_cast<Impl *>(context)->accepts(std::string(reinterpret_cast<const char *>(bytes), size)) ? 1 : 0; }
        catch (...) { return 0; }
    }
    bool accepts(const std::string &text) const {
        if (config.inputMethod == InputMethod::Bopomofo && config.restrictBopomofoToBig5 && !isBig5HkscsRepresentable(text)) return false;
        return candidateFilter(text);
    }
    EngineResult decode(const std::string &text) {
        auto root = parse(text);
        if (integerField(root.get(), "schema_version") != 1 || stringField(root.get(), "kind") != "session" ||
            stringField(root.get(), "cursor_unit") != "unicode_scalar") throw std::runtime_error("Unsupported Guanyinma session schema");
        EngineResult value;
        value.preedit = stringField(root.get(), "visible_text");
        value.preeditCursorBytes = byteOffset(value.preedit, integerField(root.get(), "cursor"));
        value.candidates = strings(field(root.get(), "displayed_candidates"));
        const auto all = strings(field(root.get(), "candidates"));
        value.candidatePage = integerField(root.get(), "page");
        value.candidatePageCount = integerField(root.get(), "page_count");
        auto *highlight = field(root.get(), "highlight");
        value.highlightedIndex = highlight ? integerValue(highlight) : 0;
        const auto pageSize = integerField(root.get(), "page_size");
        if (!pageSize || pageSize > 32 || value.candidates.size() > pageSize ||
            (!value.candidates.empty() && (value.highlightedIndex >= value.candidates.size() || value.candidatePage >= value.candidatePageCount)))
            throw std::runtime_error("Invalid Guanyinma candidate page");
        value.fullWidthMode = booleanField(root.get(), "full_width");
        if (auto *mark = field(root.get(), "marked_phrase")) {
            const auto start = integerField(mark, "text_start");
            const auto length = integerField(mark, "text_length");
            if (length > std::numeric_limits<std::size_t>::max() - start)
                throw std::runtime_error("Guanyinma marked range overflow");
            value.markedPreeditStartBytes = byteOffset(value.preedit, start);
            const auto end = byteOffset(value.preedit, start + length);
            value.markedPreeditLengthBytes = end - value.markedPreeditStartBytes;
            value.hasMarkedPhrase = length != 0;
        }
        auto *effects = field(root.get(), "effects");
        value.commit = stringField(effects, "commit");
        value.handled = booleanField(effects, "handled");
        value.beep = booleanField(effects, "beep");
        value.deleteBackward = booleanField(effects, "delete_backward");
        value.sendReturn = booleanField(effects, "send_return");
        value.discardComposition = booleanField(effects, "discard_composition");
        auto *feedback = field(effects, "phrase_feedback");
        if (feedback) {
            value.phraseFeedback = stringField(feedback, "text");
            value.phraseAdded = booleanField(feedback, "added");
        }
        value.updateUi = true;
        isQuiet = value.preedit.empty() && all.empty() && stringField(root.get(), "composition").empty() &&
                  stringField(root.get(), "reading").empty() && stringField(root.get(), "code").empty();
        lastJson = text;
        lastView = value;
        clearEffects(lastView);
        error.clear();
        return value;
    }
    std::string apply(const std::string &json) {
        if (!session) throw std::runtime_error("Guanyinma session has been retired");
        ::GuanyinmaResult *result = nullptr;
        const auto status = guanyinma_session_apply(session, reinterpret_cast<const std::uint8_t *>(json.data()), json.size(), &result);
        if (status != GUANYINMA_OK) { error = diagnostic(); throw std::runtime_error(error); }
        const auto text = readResult(result);
        decode(text);
        return text;
    }
    EngineResult perform(Json json) {
        try { return decode(apply(dump(json.get()))); }
        catch (const std::exception &failure) {
            error = failure.what();
            auto value = lastView;
            value.handled = true;
            value.updateUi = true;
            value.beep = true;
            return value;
        }
    }

    GuanyinmaConfig config;
    CandidateFilter candidateFilter;
    std::unique_ptr<CandidateFontSupport> nativeFonts;
    ::GuanyinmaSession *session = nullptr;
    EngineResult lastView;
    std::string lastJson;
    std::string error;
    bool isQuiet = true;
};

GuanyinmaSession::GuanyinmaSession(std::string modelPath, std::string userDatabasePath,
                                   GuanyinmaConfig config, CandidateFilter filter)
    : impl_(std::make_unique<Impl>(std::move(modelPath), std::move(userDatabasePath), config, std::move(filter))) {}
GuanyinmaSession::~GuanyinmaSession() = default;
EngineResult GuanyinmaSession::snapshot() const { return impl_->lastView; }
bool GuanyinmaSession::quiet() const noexcept { return impl_->isQuiet; }
bool GuanyinmaSession::valid() const noexcept { return impl_->session != nullptr; }
bool GuanyinmaSession::acceptsCandidate(const std::string &text) const noexcept {
    try { return impl_->accepts(text); } catch (...) { return false; }
}
const std::string &GuanyinmaSession::lastError() const noexcept { return impl_->error; }
const GuanyinmaConfig &GuanyinmaSession::config() const noexcept { return impl_->config; }

EngineResult GuanyinmaSession::processKey(const KeyEvent &event) {
    // Native FE owns width gestures; it deliberately sends semantic operations.
    auto op = operation(event.code == KeyCode::Character ? "character" : "key");
    if (event.code == KeyCode::Character) {
        put(op.get(), "text", event.text.empty() ? std::string(1, event.character) : event.text);
    } else put(op.get(), "key", keyName(event.code));
    auto modifiers = object();
    const auto mask = static_cast<unsigned int>(event.modifiers);
    const auto has = [mask](KeyModifier bit) { return (mask & static_cast<unsigned int>(bit)) != 0; };
    put(modifiers.get(), "shift", event.rawShift || has(KeyModifier::Shift));
    put(modifiers.get(), "control", has(KeyModifier::Control));
    put(modifiers.get(), "alt", has(KeyModifier::Alt));
    put(modifiers.get(), "command", has(KeyModifier::Super));
    put(modifiers.get(), "caps_lock", event.capsLock);
    put(modifiers.get(), "keypad", event.keypad);
    put(modifiers.get(), "num_lock", event.numLock);
    put(modifiers.get(), "repeat", event.repeat);
    put(modifiers.get(), "release", event.release);
    json_object_object_add(op.get(), "modifiers", modifiers.release());
    return impl_->perform(std::move(op));
}
EngineResult GuanyinmaSession::selectDisplayedCandidate(std::size_t index) {
    if (index >= impl_->lastView.candidates.size()) {
        auto result = snapshot(); result.handled = true; result.beep = true; return result;
    }
    auto op = operation("select"); put(op.get(), "index", index); return impl_->perform(std::move(op));
}
EngineResult GuanyinmaSession::selectSmartCharacter(std::size_t index) {
    if (!impl_->config.smartMode || impl_->config.inputMethod != InputMethod::Bopomofo) return snapshot();
    try {
        auto root = parse(impl_->lastJson);
        const auto reading = stringField(root.get(), "reading");
        // The core cannot open candidates while an unfinished reading is active.
        if (!reading.empty()) { auto result = snapshot(); result.handled = true; result.beep = true; return result; }
        auto *segments = field(root.get(), "segments");
        if (!segments || json_object_get_type(segments) != json_type_array) throw std::runtime_error("Invalid Guanyinma segments");
        std::size_t offset = 0;
        for (std::size_t i = 0; i < json_object_array_length(segments); ++i) {
            auto *segment = json_object_array_get_idx(segments, i);
            const auto size = scalarCount(stringField(segment, "text"));
            const auto span = integerField(segment, "span");
            if (index >= offset && index - offset < size && span) {
                const auto readingIndex = integerField(segment, "start") + std::min(index - offset, span - 1);
                auto op = operation("open_candidates"); put(op.get(), "index", readingIndex); return impl_->perform(std::move(op));
            }
            offset += size;
        }
    } catch (const std::exception &error) { impl_->error = error.what(); }
    auto result = snapshot(); result.handled = true; result.beep = true; return result;
}
EngineResult GuanyinmaSession::finishComposition() {
    auto op = operation("finish_composition");
    put(op.get(), "complete_reading", true);
    put(op.get(), "select_highlighted_candidate", true);
    put(op.get(), "discard_table_code", true);
    return impl_->perform(std::move(op));
}
EngineResult GuanyinmaSession::reset() {
    auto result = impl_->perform(operation("reset"));
    if (!impl_->error.empty()) {
        guanyinma_session_close(&impl_->session);
        const bool width = impl_->lastView.fullWidthMode;
        impl_->lastView = {};
        impl_->lastView.fullWidthMode = width;
        impl_->lastJson.clear();
        impl_->isQuiet = true;
        result = impl_->lastView;
        result.handled = true;
        result.updateUi = true;
        result.beep = true;
    }
    return result;
}
EngineResult GuanyinmaSession::setFullWidth(bool enabled) {
    auto op = operation("set_full_width"); put(op.get(), "enabled", enabled); return impl_->perform(std::move(op));
}
std::string GuanyinmaSession::applyJson(const std::string &operation) { return impl_->apply(operation); }
std::string GuanyinmaSession::userDataJson() const {
    if (!impl_->session) throw std::runtime_error("Guanyinma session has been retired");
    ::GuanyinmaResult *result = nullptr;
    check(guanyinma_session_user_data(impl_->session, &result));
    return readResult(result);
}
void GuanyinmaSession::validateArchive(const std::string &archive) {
    check(guanyinma_user_archive_validate(reinterpret_cast<const std::uint8_t *>(archive.data()), archive.size()));
}
std::string GuanyinmaSession::defaultUserDatabasePath() {
    const char *overridePath = std::getenv("CHICHI77_KEYKEY_GUANYINMA_USER_DB");
    if (overridePath && *overridePath) return overridePath;
    const char *xdg = std::getenv("XDG_DATA_HOME");
    if (xdg && *xdg) return std::string(xdg) + "/chichi77-keykey/guanyinma-user.db";
    const char *home = std::getenv("HOME");
    return home && *home ? std::string(home) + "/.local/share/chichi77-keykey/guanyinma-user.db" : std::string{};
}

} // namespace keykey::linux_ime

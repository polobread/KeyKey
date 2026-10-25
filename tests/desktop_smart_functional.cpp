// Explicit Rust migration recorder for production desktop input modules.
// Included production sources retain their copyright and license notices.
// Never registers/loads an installed IMK/TSF or opens a real user profile.
#include "OVIMSmartMandarin.h"
#include "OVIMTraditionalMandarin.h"
#include "OVIMGeneric.h"
#include "PVLoaderService.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include "PVBasicKeyValueMapImpl.h"
#ifdef _WIN32
#include "WindowsTableInputMethod.h"
#endif

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace OpenVanilla;
namespace fs = std::filesystem;

namespace {

void require(bool condition, const std::string& message) {
    if (!condition) throw std::runtime_error(message);
}

std::string json(const std::string& text) {
    std::ostringstream output;
    output << '"';
    for (unsigned char c : text) {
        if (c == '"' || c == '\\') output << '\\' << c;
        else if (c < 32) {
            output << "\\u" << std::hex << std::setw(4) << std::setfill('0')
                   << static_cast<unsigned>(c) << std::dec;
        } else output << c;
    }
    output << '"';
    return output.str();
}

std::string strings(const std::vector<std::string>& values) {
    std::ostringstream output;
    output << '[';
    for (std::size_t i = 0; i < values.size(); ++i) {
        if (i) output << ',';
        output << json(values[i]);
    }
    output << ']';
    return output.str();
}

std::vector<std::string> columns(const std::string& line) {
    std::vector<std::string> result;
    std::size_t begin = 0;
    for (;;) {
        const auto end = line.find('\t', begin);
        result.push_back(line.substr(begin, end == std::string::npos ? end : end - begin));
        if (end == std::string::npos) return result;
        begin = end + 1;
    }
}

bool methodValid(const std::string& method) {
    return method == "smart" || method == "traditional" ||
           method == "cangjie" || method == "simplex";
}

unsigned keyCode(const std::string& key) {
    static const std::map<std::string, unsigned> keys = {
        {"RETURN", OVKeyCode::Return}, {"BACKSPACE", OVKeyCode::Backspace},
        {"ESCAPE", OVKeyCode::Esc}, {"END", OVKeyCode::End},
        {"LEFT", OVKeyCode::Left}, {"RIGHT", OVKeyCode::Right},
        {"SPACE", OVKeyCode::Space}, {"DOWN", OVKeyCode::Down},
        {"PAGE_DOWN", OVKeyCode::PageDown}, {"PAGE_UP", OVKeyCode::PageUp},
    };
    const auto found = keys.find(key);
    require(found != keys.end(), "Unknown KEY argument: " + key);
    return found->second;
}

std::pair<std::string, std::string> optionValue(const std::string& argument) {
    const auto split = argument.find('=');
    require(split != std::string::npos, "OPTION requires key=value");
    const auto key = argument.substr(0, split);
    const auto value = argument.substr(split + 1);
    if (key == "layout") require(value == "standard" || value == "hsu", "Invalid layout");
    else if (key == "punctuation") require(value == "0" || value == "1" || value == "2",
                                         "Invalid punctuation mode");
    else {
        require(key == "realtime" || key == "prefix" || key == "dynamic" ||
                    key == "clear_on_error" || key == "space_selects", "Unknown option: " + key);
        require(value == "true" || value == "false", "OPTION requires true/false: " + key);
    }
    return {key, value};
}

void validateOperation(const std::vector<std::string>& row) {
    const auto& operation = row[3];
    const auto& argument = row[4];
    if (operation == "KEY") keyCode(argument);
    else if (operation == "TYPE") {
        require(std::all_of(argument.begin(), argument.end(), [](unsigned char c) {
                    return c >= 32 && c < 127;
                }), "TYPE requires printable ASCII keys");
    } else if (operation == "OPEN") {
        require(!argument.empty() &&
                    std::all_of(argument.begin(), argument.end(), [](char c) {
                        return c >= '0' && c <= '9';
                    }), "OPEN requires a non-negative reading index");
        static_cast<void>(std::stoull(argument));
    } else if (operation == "SELECT") require(!argument.empty(), "SELECT requires candidate text");
    else if (operation == "OPTION") static_cast<void>(optionValue(argument));
    else if (operation == "METHOD") require(methodValid(argument), "Unknown METHOD: " + argument);
    else if (operation == "REOPEN" || operation == "RESET_LEARNING") {
        require(argument.empty(), operation + " takes no argument");
    } else throw std::runtime_error("Unknown operation: " + operation);
}

// URI read-only mode applies to main; attached learning databases remain writable.
// The wrapper's protected constructor is used only to express the open flags.
class ReadOnlyModel final : public OVSQLiteConnection {
public:
    static std::unique_ptr<OVSQLiteConnection> open(const fs::path& path) {
        require(fs::is_regular_file(path), "Model file does not exist");
        const auto absolute = fs::absolute(path).generic_u8string();
        std::ostringstream uri;
        uri << "file:";
        for (unsigned char c : absolute) {
            if ((c >= 'a' && c <= 'z') || (c >= 'A' && c <= 'Z') ||
                (c >= '0' && c <= '9') || c == '/' || c == ':' ||
                c == '-' || c == '_' || c == '.') uri << c;
            else uri << '%' << std::hex << std::uppercase << std::setw(2)
                     << std::setfill('0') << static_cast<unsigned>(c) << std::dec;
        }
        uri << "?mode=ro";
        sqlite3* handle = nullptr;
        const auto status = sqlite3_open_v2(uri.str().c_str(), &handle,
            SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, nullptr);
        if (status != SQLITE_OK) {
            const std::string error = handle ? sqlite3_errmsg(handle) : "no SQLite handle";
            if (handle) sqlite3_close(handle);
            throw std::runtime_error("Could not open read-only model: " + error);
        }
        if (sqlite3_db_readonly(handle, "main") != 1) {
            sqlite3_close(handle);
            throw std::runtime_error("Main model is not read-only");
        }
        return std::unique_ptr<OVSQLiteConnection>(new ReadOnlyModel(handle, absolute));
    }

private:
    ReadOnlyModel(sqlite3* handle, const std::string& path) : OVSQLiteConnection(handle, path) {}
};

class InspectableSmart final : public OVIMSmartMandarin {
public:
    void checkpoint() {
        // Production persistence API, forced to avoid the 3.5-second timer in
        // deterministic migration traces. This does not change scoring.
        require(m_LM->saveUserBigramCacheAndCandidateOverrideCache(true, true),
                "Could not checkpoint isolated Smart Mandarin learning");
    }
};

#ifndef _WIN32
class InspectableGeneric final : public OVIMGeneric {
public:
    InspectableGeneric(const std::string& name, OVDatabaseService* database)
        : OVIMGeneric(name, database) {}
    sqlite3* learning() const {
        return m_userDatabaseConnection ? m_userDatabaseConnection->connection() : nullptr;
    }
};
#endif

std::string rowArrays(sqlite3* handle, const std::string& sql, int count) {
    if (!handle) return "[]";
    sqlite3_stmt* raw = nullptr;
    require(sqlite3_prepare_v2(handle, sql.c_str(), -1, &raw, nullptr) == SQLITE_OK,
            "Could not query isolated learning: " + std::string(sqlite3_errmsg(handle)));
    std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)> statement(raw, sqlite3_finalize);
    std::ostringstream output;
    output << '[';
    bool first = true;
    int status = SQLITE_ROW;
    while ((status = sqlite3_step(raw)) == SQLITE_ROW) {
        if (!first) output << ',';
        first = false;
        output << '[';
        for (int i = 0; i < count; ++i) {
            if (i) output << ',';
            const auto* value = sqlite3_column_text(raw, i);
            output << json(value ? reinterpret_cast<const char*>(value) : "");
        }
        output << ']';
    }
    require(status == SQLITE_DONE, "Could not read isolated learning rows");
    output << ']';
    return output.str();
}

class Harness {
public:
    Harness(const fs::path& model, const fs::path& profile, const std::string& method)
        : modelPath_(model), profilePath_(profile), method_(method) {
        require(!fs::exists(profilePath_), "Migration profile must be fresh");
        fs::create_directories(profilePath_);
        initialize();
    }

    ~Harness() {
        try { close(); } catch (...) {}
    }

    const std::string& method() const { return method_; }

    std::string composition() const {
        return PVCombinedUTF16TextBuffer(composing_, reading_).composedText();
    }

    void press(unsigned code) {
        OVKey key = loader_->makeOVKey(code);
        auto* panel = candidates_->accessVerticalCandidatePanel();
        if (panel->isVisible()) {
            const auto state = panel->handleKeyEvent(key, loader_.get());
            if (state == PVCandidateState::CandidateChosen) {
                const auto text = panel->chosenCandidateString();
                const auto index = panel->chosenCandidateIndex();
                panel->hide();
                panel->cancelEventHandler();
                context_->candidateSelected(candidates_.get(), text, index,
                    &reading_, &composing_, loader_.get());
            } else if (state == PVCandidateState::Canceled) {
                panel->hide();
                panel->cancelEventHandler();
                context_->candidateCanceled(candidates_.get(), &reading_, &composing_, loader_.get());
            } else if (state == PVCandidateState::Ignored) {
                context_->candidateNonPanelKeyReceived(
                    candidates_.get(), &key, &reading_, &composing_, loader_.get());
            }
        } else context_->handleKey(&key, &reading_, &composing_, candidates_.get(), loader_.get());
        consumeCommit();
    }

    void pageKey(const std::string& name) {
        auto* panel = candidates_->accessVerticalCandidatePanel();
        require(panel->isVisible(), name + " requires visible candidates");
        const auto before = panel->currentPage();
        if (name == "PAGE_DOWN") require(before + 1 < panel->pageCount(), name + " has no next page");
        else require(before > 0, name + " has no previous page");
        press(keyCode(name));
        const auto expected = name == "PAGE_DOWN" ? before + 1 : before - 1;
        require(panel->currentPage() == expected, name + " did not advance to expected page");
    }

    std::string operate(const std::string& operation, const std::string& argument) {
        if (operation == "TYPE") {
            for (unsigned char key : argument) press(key);
        } else if (operation == "KEY") {
            if (argument == "PAGE_DOWN" || argument == "PAGE_UP") pageKey(argument);
            else press(keyCode(argument));
        } else if (operation == "OPEN") {
            if (method_ != "smart") return "OPEN is supported only by Smart Mandarin";
            open(std::stoull(argument));
        } else if (operation == "SELECT") select(argument);
        else if (operation == "OPTION") {
            const auto option = optionValue(argument);
            if (!optionSupported(option.first)) return "OPTION " + argument;
            preserveVisible();
            close();
            options_[option.first] = option.second;
            initialize();
        } else if (operation == "METHOD") {
            if (method_ != argument) {
                preserveVisible();
                close();
                methodOptions_[method_] = options_;
                method_ = argument;
                options_ = methodOptions_[method_];
                initialize();
            }
        } else if (operation == "REOPEN" || operation == "RESET_LEARNING") {
            require(composition().empty(), operation + " requires empty composition");
            close();
            if (operation == "RESET_LEARNING") {
                // Only this harness-created child directory is ever removed.
                require(profilePath_.filename().u8string().find("desktop-case-") == 0,
                        "Refusing to reset an unowned profile");
                fs::remove_all(profilePath_);
                fs::create_directories(profilePath_);
            }
            initialize();
        }
        return "";
    }

    void snapshot(std::ostream& output, const std::string& caseName, std::size_t step,
                  const std::string& profile, const std::string& operation,
                  const std::string& argument, const std::string& unsupported) {
        const auto combined = PVCombinedUTF16TextBuffer(composing_, reading_);
        auto* panel = candidates_->accessVerticalCandidatePanel();
        std::vector<std::string> values;
        if (panel->isVisible()) {
            auto* list = panel->candidateList();
            for (std::size_t i = 0; i < list->size(); ++i) values.push_back(list->candidateAtIndex(i));
        }
        output << "{\"case\":" << json(caseName) << ",\"step\":" << step
               << ",\"profile\":" << json(profile) << ",\"method\":" << json(method_)
               << ",\"operation\":" << json(operation) << ",\"argument\":" << json(argument)
               << ",\"committed\":" << json(committed_)
               << ",\"composition\":" << json(combined.composedText())
               << ",\"reading\":" << json(reading_.composedText())
               << ",\"cursor\":" << combined.cursorPosition()
               << ",\"cursor_unit\":\"unicode_scalar\""
               << ",\"candidates\":" << strings(values)
               << ",\"page\":" << (panel->isVisible() ? panel->currentPage() : 0)
               << ",\"page_size\":" << panel->candidatesPerPage()
               << ",\"highlight\":" << (panel->isVisible() ? panel->currentHightlightIndex() : 0)
               << ",\"options\":{";
        bool first = true;
        for (const auto& option : options_) {
            if (!first) output << ',';
            first = false;
            output << json(option.first) << ':' << json(option.second);
        }
        output << "},\"learning\":" << learning();
        if (!unsupported.empty()) output << ",\"unsupported\":" << json(unsupported);
        output << "}\n";
        require(output.good(), "Could not write migration trace");
    }

private:
    bool optionSupported(const std::string& key) const {
        const bool table = method_ == "cangjie" || method_ == "simplex";
        if (key == "layout") return !table;
        if (key == "space_selects") return method_ == "smart";
        if (key == "prefix" || key == "punctuation") return method_ == "cangjie";
        return table;
    }

    bool boolean(const std::string& key, bool fallback) const {
        const auto found = options_.find(key);
        return found == options_.end() ? fallback : found->second == "true";
    }

    void initialize() {
        connection_ = ReadOnlyModel::open(modelPath_);
        database_.reset(OVSQLiteDatabaseService::ServiceWithExistingConnection(connection_.get()));
        loader_.reset(new PVLoaderService("zh_TW", nullptr, database_.get()));
        candidates_.reset(new PVCandidateService(loader_.get()));
        if (method_ == "smart") module_.reset(new InspectableSmart);
        else if (method_ == "traditional") module_.reset(new OVIMTraditionalMandarin);
        else {
            const auto name = method_ == "cangjie" ? "Generic-cj-cin" : "Generic-simplex-cin";
#ifdef _WIN32
            module_.reset(new KeyKey::WindowsTsf::WindowsTableInputMethod(name, database_.get()));
#else
            module_.reset(new InspectableGeneric(name, database_.get()));
#endif
        }
        OVPathInfo paths;
        paths.writablePath = profilePath_.u8string();
        require(module_->initialize(&paths, loader_.get()), "Could not initialize " + method_);
        if (method_ == "smart") {
            require(sqlite3_db_readonly(connection_->connection(), "userdb") == 0,
                    "Smart learning database is not writable");
        }
        PVBasicKeyValueMapImpl map;
        OVKeyValueMap config(&map);
        const auto layout = options_.find("layout");
        config.setKeyStringValue("KeyboardLayout",
            layout != options_.end() && layout->second == "hsu" ? "Hsu" : "Standard");
        if (method_ == "smart" || method_ == "traditional") {
            config.setKeyStringValue("CandidateSelectionKeys", "12345678");
        }
        config.setKeyBoolValue("ShowCandidateListWithSpace", boolean("space_selects", false));
        config.setKeyBoolValue("CandidateCursorAtEndOfTargetBlock", false);
        config.setKeyBoolValue("ClearComposingTextWithEsc", false);
        config.setKeyIntValue("ComposingTextBufferSize", 10);
        if (method_ == "cangjie" || method_ == "simplex") {
            config.setKeyBoolValue("ComposeWhileTyping", boolean("realtime", false));
            config.setKeyBoolValue("PrefixCandidates", boolean("prefix", false));
            config.setKeyBoolValue("UseDynamicFrequency", boolean("dynamic", true));
            config.setKeyBoolValue("ClearReadingBufferAtCompositionError",
                                  boolean("clear_on_error", true));
            const auto punctuation = options_.find("punctuation");
            const auto mode = method_ != "cangjie" || punctuation == options_.end()
                ? "0" : punctuation->second;
            config.setKeyStringValue("UseOverrideTable", mode == "1"
                ? "Punctuations-cj-mixedwidth-cin" : mode == "2"
                ? "Punctuations-cj-halfwidth-cin" : "");
        }
        module_->loadConfig(&config, loader_.get());
        context_.reset(module_->createContext());
        require(context_ != nullptr, "Could not create input context");
        context_->startSession(loader_.get());
        reading_.clear();
        composing_.clear();
    }

    void checkpoint() {
        if (auto* smart = dynamic_cast<InspectableSmart*>(module_.get())) smart->checkpoint();
    }

    void close() {
        if (!context_) return;
        checkpoint();
        context_->stopSession(loader_.get());
        context_.reset();
        module_.reset();
        candidates_.reset();
        loader_.reset();
        database_.reset();
        connection_.reset();
        reading_.clear();
        composing_.clear();
    }

    void consumeCommit() {
        if (composing_.isCommitted()) {
            committed_ += composing_.composedCommittedText();
            composing_.finishCommit();
        }
    }

    void preserveVisible() {
        // Same preservation contract as desktop loader method/config switches:
        // exact visible combined text is retained before retiring old context.
        committed_ += composition();
        context_->clear(loader_.get());
        reading_.clear();
        composing_.clear();
    }

    void open(std::size_t index) {
        require(reading_.isEmpty(), "OPEN requires a completed reading");
        require(!candidates_->accessVerticalCandidatePanel()->isVisible(),
                "OPEN requires a closed candidate panel");
        const auto count = composing_.codePointCount();
        require(index < count, "OPEN index outside composition");
        require(composing_.cursorPosition() <= count, "OPEN cursor outside composition");
        for (std::size_t step = 0; step < count && composing_.cursorPosition() != index; ++step) {
            const auto before = composing_.cursorPosition();
            const bool left = before > index;
            press(left ? OVKeyCode::Left : OVKeyCode::Right);
            require(composing_.cursorPosition() == (left ? before - 1 : before + 1),
                    "OPEN cursor did not advance");
        }
        require(composing_.cursorPosition() == index, "OPEN failed to reach target");
        press(OVKeyCode::Down);
    }

    void select(const std::string& text) {
        auto* panel = candidates_->accessVerticalCandidatePanel();
        require(panel->isVisible(), "SELECT requires candidates");
        auto* list = panel->candidateList();
        std::size_t index = 0;
        while (index < list->size() && list->candidateAtIndex(index) != text) ++index;
        require(index < list->size(), "Candidate not found: " + text);
        require(panel->candidatesPerPage() > 0, "SELECT has zero page size");
        const auto page = index / panel->candidatesPerPage();
        const auto count = panel->pageCount();
        require(page < count && panel->currentPage() < count, "SELECT page outside list");
        for (std::size_t step = 0; step < count && panel->currentPage() != page; ++step) {
            pageKey(panel->currentPage() < page ? "PAGE_DOWN" : "PAGE_UP");
        }
        require(panel->currentPage() == page, "SELECT failed to reach page");
        // Follow the real candidate event handler, retaining configured selection
        // keys for Traditional/Hsu and table methods.
        const auto local = index % panel->candidatesPerPage();
        const auto selectionKey = panel->candidateKeyAtIndex(local);
        require(selectionKey.keyCode() != 0, "SELECT has no selection key");
        press(selectionKey.keyCode());
    }

    std::string learning() {
        std::string overrides = "[]", bigrams = "[]", unigrams = "[]", table = "[]";
        if (method_ == "smart") {
            checkpoint();
            auto* handle = connection_->connection();
            overrides = rowArrays(handle, "SELECT qstring,current FROM userdb.user_candidate_override_cache "
                "ORDER BY qstring,current", 2);
            bigrams = rowArrays(handle, "SELECT qstring,previous,current,CAST(probability AS TEXT) "
                "FROM userdb.user_bigram_cache ORDER BY qstring,previous,current,probability", 4);
            unigrams = rowArrays(handle, "SELECT qstring,current,CAST(probability AS TEXT),CAST(backoff AS TEXT) "
                "FROM userdb.user_unigrams ORDER BY qstring,current,probability,backoff", 4);
        } else if (method_ == "cangjie" || method_ == "simplex") {
#ifndef _WIN32
            auto* generic = dynamic_cast<InspectableGeneric*>(module_.get());
            if (generic && generic->learning()) {
                table = rowArrays(generic->learning(),
                    "SELECT key,value,CAST(count AS TEXT) FROM user_frequency ORDER BY key,value,count", 3);
            }
#else
            auto* generic = dynamic_cast<KeyKey::WindowsTsf::WindowsTableInputMethod*>(module_.get());
            const auto path = fs::u8path(generic->frequencyPath());
            if (fs::exists(path)) {
                auto learningConnection = ReadOnlyModel::open(path);
                if (learningConnection->hasTable("user_frequency")) table = rowArrays(
                    learningConnection->connection(),
                    "SELECT key,value,CAST(count AS TEXT) FROM user_frequency ORDER BY key,value,count", 3);
            }
#endif
        }
        return "{\"overrides\":" + overrides + ",\"bigrams\":" + bigrams +
               ",\"unigrams\":" + unigrams + ",\"table\":" + table + "}";
    }

    fs::path modelPath_, profilePath_;
    std::string method_, committed_;
    std::map<std::string, std::string> options_;
    std::map<std::string, std::map<std::string, std::string>> methodOptions_;
    std::unique_ptr<OVSQLiteConnection> connection_;
    std::unique_ptr<OVSQLiteDatabaseService> database_;
    std::unique_ptr<OVInputMethod> module_;
    std::unique_ptr<PVLoaderService> loader_;
    std::unique_ptr<PVCandidateService> candidates_;
    std::unique_ptr<OVEventHandlingContext> context_;
    PVTextBuffer reading_, composing_;
};

}  // namespace

int main(int argc, char** argv) {
    std::size_t lineNumber = 0;
    std::string caseName;
    try {
        require(argc == 5, "Usage: desktop_migration DATABASE FIXTURE SCRATCH_DIR TRACE_FILE");
        std::ifstream input(fs::u8path(argv[2]), std::ios::binary);
        require(input.good(), "Could not read migration fixture");
        const auto scratch = fs::absolute(fs::u8path(argv[3]));
        fs::create_directories(scratch);
        std::ofstream trace(fs::u8path(argv[4]), std::ios::binary);
        require(trace.good(), "Could not open migration trace output");
        std::unique_ptr<Harness> harness;
        std::set<std::string> seen;
        std::string profile, initialMethod;
        std::size_t caseCount = 0, steps = 0, skippedCases = 0, step = 0;
        std::string line;
        while (std::getline(input, line)) {
            ++lineNumber;
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty() || line[0] == '#') continue;
            const auto row = columns(line);
            require(row.size() == 5, "Expected 5 TSV columns");
            require(!row[0].empty(), "Empty case name");
            require(row[1] == "hardware" || row[1] == "touch", "Unknown profile: " + row[1]);
            require(methodValid(row[2]), "Unknown method: " + row[2]);
            validateOperation(row);
            if (row[0] != caseName) {
                require(seen.insert(row[0]).second, "Case rows must be contiguous");
                caseName = row[0];
                profile = row[1];
                initialMethod = row[2];
                step = 0;
                harness.reset();
                if (profile == "hardware") {
                    ++caseCount;
                    harness.reset(new Harness(fs::u8path(argv[1]),
                        scratch / ("desktop-case-" + std::to_string(caseCount)), initialMethod));
                } else ++skippedCases;
            }
            require(profile == row[1] && initialMethod == row[2], "Case profile/initial method changed");
            ++step;
            if (profile == "touch") continue;
            const auto unsupported = harness->operate(row[3], row[4]);
            harness->snapshot(trace, caseName, step, profile, row[3], row[4], unsupported);
            ++steps;
        }
        require(caseCount > 0 && steps > 0, "Fixture has no desktop migration cases");
        harness.reset();
        trace.flush();
        require(trace.good(), "Could not finish migration trace");
        std::cout << "desktop migration: recorded " << caseCount << " cases / "
                  << steps << " snapshots; skipped " << skippedCases << " touch cases\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << "desktop migration: FAIL case=" << caseName << " line="
                  << lineNumber << ": " << error.what() << '\n';
        return 1;
    }
}

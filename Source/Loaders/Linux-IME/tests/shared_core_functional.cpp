// Manual Rust migration baseline recorder for the production Unix core.
// It never loads Fcitx or an installed IME and writes only caller-owned scratch.
#include "keykey/linux_ime/engine.h"

#include <sqlite3.h>
#include <unistd.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <iomanip>
#include <iostream>
#include <limits>
#include <map>
#include <memory>
#include <set>
#include <sstream>
#include <stdexcept>
#include <string>
#include <vector>
#include <cstdlib>

namespace {
using namespace keykey::linux_ime;

void require(bool condition, const std::string &message) {
    if (!condition) throw std::runtime_error(message);
}

std::vector<std::string> fields(const std::string &line) {
    std::vector<std::string> result;
    std::size_t start = 0;
    for (;;) {
        const auto end = line.find('\t', start);
        result.push_back(line.substr(start, end - start));
        if (end == std::string::npos) return result;
        start = end + 1;
    }
}

std::string json(const std::string &value) {
    std::ostringstream output;
    output << '"';
    for (const char byte : value) {
        const auto character = static_cast<unsigned char>(byte);
        switch (character) {
        case '"': output << "\\\""; break;
        case '\\': output << "\\\\"; break;
        case '\b': output << "\\b"; break;
        case '\f': output << "\\f"; break;
        case '\n': output << "\\n"; break;
        case '\r': output << "\\r"; break;
        case '\t': output << "\\t"; break;
        default:
            if (character < 0x20U)
                output << "\\u" << std::hex << std::setw(4)
                       << std::setfill('0') << static_cast<unsigned int>(character)
                       << std::dec;
            else output << static_cast<char>(character);
        }
    }
    output << '"';
    return output.str();
}

std::string jsonArray(const std::vector<std::string> &values) {
    std::string output = "[";
    for (const auto &value : values) {
        if (output.size() > 1) output += ',';
        output += json(value);
    }
    return output + ']';
}

const std::map<std::string, KeyCode> keyCodes{
    {"RETURN", KeyCode::Enter}, {"BACKSPACE", KeyCode::Backspace},
    {"ESCAPE", KeyCode::Escape}, {"END", KeyCode::End},
    {"LEFT", KeyCode::Left}, {"RIGHT", KeyCode::Right},
    {"SPACE", KeyCode::Space}, {"PAGE_DOWN", KeyCode::PageDown},
    {"PAGE_UP", KeyCode::PageUp}, {"DOWN", KeyCode::Down},
};

bool validMethod(const std::string &method) {
    return method == "smart" || method == "traditional" ||
           method == "cangjie" || method == "simplex";
}

std::size_t readingIndex(const std::string &value) {
    require(!value.empty() &&
            value.find_first_not_of("0123456789") == std::string::npos,
            "OPEN requires a nonnegative reading index");
    const auto result = std::stoull(value);
    require(result <= static_cast<unsigned long long>(
                std::numeric_limits<std::size_t>::max()),
            "OPEN reading index is out of range");
    return static_cast<std::size_t>(result);
}

bool boolean(const std::string &value) {
    require(value == "0" || value == "1" || value == "false" || value == "true",
            "Boolean option requires 0/1/false/true");
    return value == "1" || value == "true";
}

void validateOperation(const std::string &operation, const std::string &argument) {
    if (operation == "TYPE") {
        require(!argument.empty() &&
                std::all_of(argument.begin(), argument.end(),
                    [](unsigned char character) {
                        return character >= 0x20U && character < 0x7fU;
                    }), "TYPE requires a nonempty printable ASCII key sequence");
    } else if (operation == "KEY") {
        require(keyCodes.count(argument) != 0, "Unknown KEY: " + argument);
    } else if (operation == "OPEN") {
        static_cast<void>(readingIndex(argument));
    } else if (operation == "SELECT") {
        require(!argument.empty(), "SELECT requires candidate text");
    } else if (operation == "METHOD") {
        require(validMethod(argument), "Unknown METHOD: " + argument);
    } else if (operation == "OPTION") {
        const auto separator = argument.find('=');
        require(separator != std::string::npos, "OPTION requires key=value");
        const auto key = argument.substr(0, separator);
        const auto value = argument.substr(separator + 1);
        if (key == "layout")
            require(value == "standard" || value == "hsu", "Unknown layout: " + value);
        else if (key == "punctuation")
            require(value == "0" || value == "1" || value == "2",
                    "Punctuation option requires 0/1/2");
        else {
            require(key == "realtime" || key == "prefix" || key == "dynamic" ||
                    key == "clear_on_error" || key == "space_selects",
                    "Unknown OPTION key: " + key);
            static_cast<void>(boolean(value));
        }
    } else {
        require(operation == "REOPEN" || operation == "RESET_LEARNING",
                "Unknown operation: " + operation);
        require(argument.empty(), operation + " takes no argument");
    }
}

class Scratch {
public:
    explicit Scratch(const std::filesystem::path &parent) {
        require(std::filesystem::is_directory(parent), "SCRATCH must be an existing directory");
        auto pattern = (parent / "unix-migration-XXXXXX").string();
        std::vector<char> buffer(pattern.begin(), pattern.end());
        buffer.push_back('\0');
        const auto created = mkdtemp(buffer.data());
        require(created != nullptr, "Could not create isolated scratch directory");
        path = created;
    }
    ~Scratch() {
        std::error_code ignored;
        std::filesystem::remove_all(path, ignored);
    }
    std::filesystem::path path;
};

std::string learningRows(sqlite3 *database, const char *query, int width) {
    sqlite3_stmt *raw = nullptr;
    require(sqlite3_prepare_v2(database, query, -1, &raw, nullptr) == SQLITE_OK,
            "Could not query isolated learning database");
    const std::unique_ptr<sqlite3_stmt, decltype(&sqlite3_finalize)>
        statement(raw, sqlite3_finalize);
    std::string result = "[";
    int status;
    while ((status = sqlite3_step(statement.get())) == SQLITE_ROW) {
        if (result.size() > 1) result += ',';
        result += '[';
        for (int column = 0; column < width; ++column) {
            if (column != 0) result += ',';
            const auto text = sqlite3_column_text(statement.get(), column);
            result += json(text ? reinterpret_cast<const char *>(text) : "");
        }
        result += ']';
    }
    require(status == SQLITE_DONE, "Could not read isolated learning rows");
    return result + ']';
}

class Session {
public:
    Session(std::string model, const std::filesystem::path &tables,
            std::filesystem::path scratch, std::string method)
        : model_(std::move(model)), tables_(tables),
          scratch_(std::move(scratch)), method_(std::move(method)) {
        std::filesystem::create_directories(scratch_);
        userPath_ = (scratch_ / "learning.sqlite3").string();
        reopen();
    }

    void run(const std::string &operation, const std::string &argument) {
        unsupported_.clear();
        if (operation == "TYPE") {
            for (const char character : argument) {
                if (character == ' ') press(KeyCode::Space);
                else accept(engine_->processKey(context_,
                        KeyEvent{KeyCode::Character, character}));
            }
        } else if (operation == "KEY") {
            press(keyCodes.at(argument));
        } else if (operation == "OPEN") {
            if (method_ == "smart")
                accept(engine_->selectSmartCharacter(context_, readingIndex(argument)));
            else unsupported_ = "OPEN requires Smart Mandarin";
        } else if (operation == "SELECT") {
            const auto pageCount = result_.candidatePageCount;
            bool selected = false;
            for (std::size_t visited = 0; visited < pageCount; ++visited) {
                const auto found = std::find(result_.candidates.begin(),
                                             result_.candidates.end(), argument);
                if (found != result_.candidates.end()) {
                    const auto index = static_cast<std::size_t>(
                        found - result_.candidates.begin());
                    accept(engine_->selectDisplayedCandidate(context_, index));
                    selected = true;
                    break;
                }
                if (visited + 1 < pageCount) press(KeyCode::PageDown);
            }
            require(selected, "Candidate not found: " + argument);
        } else if (operation == "OPTION") {
            option(argument);
        } else if (operation == "METHOD") {
            accept(engine_->finishComposition(context_));
            method_ = argument;
            buildEngine();
        } else if (operation == "REOPEN") {
            require(result_.preedit.empty(), "REOPEN requires empty composition");
            reopen();
        } else if (operation == "RESET_LEARNING") {
            require(result_.preedit.empty(), "RESET_LEARNING requires empty composition");
            require(user_->resetLearning(), "Could not reset isolated learning");
            reopen();
        }
    }

    void snapshot(std::ostream &output, const std::string &name,
                  std::size_t step, const std::string &profile,
                  const std::string &operation, const std::string &argument) const {
        output << "{\"case\":" << json(name) << ",\"step\":" << step
               << ",\"profile\":" << json(profile)
               << ",\"method\":" << json(method_)
               << ",\"operation\":" << json(operation)
               << ",\"argument\":" << json(argument)
               << ",\"committed\":" << json(committed_)
               << ",\"composition\":" << json(result_.preedit)
               << ",\"reading\":null"
               << ",\"cursor\":" << result_.preeditCursorBytes
               << ",\"cursor_unit\":\"utf8_bytes\""
               << ",\"candidates\":" << jsonArray(allCandidates())
               << ",\"page\":" << result_.candidatePage
               << ",\"page_size\":" << Engine::CandidatesPerPage
               << ",\"highlight\":" << result_.highlightedIndex
               << ",\"learning\":" << learning()
               << ",\"unsupported\":" << json(unsupported_)
               << ",\"capabilities\":{\"reading\":false,\"learning\":"
               << (method_ == "smart" ? "true" : "false")
               << ",\"table_learning\":false,\"associated_phrases\":false,\"unsupported_options\":[\"dynamic\",\"punctuation\"]}"
               << ",\"handled\":" << (result_.handled ? "true" : "false")
               << ",\"beep\":" << (result_.beep ? "true" : "false") << "}\n";
    }

private:
    struct Options {
        TablePreferences table;
        SmartMandarinPreferences smart;
    };

    void buildEngine() {
        const auto tableName = method_ == "cangjie" ? "cj-ext.cin" :
                               method_ == "simplex" ? "simplex-ext.cin" : "bpmf-ext.cin";
        const auto dictionary = std::make_shared<CinDictionary>(
            CinDictionary::loadFile((tables_ / tableName).string()));
        const auto punctuation = std::make_shared<CinDictionary>(
            CinDictionary::loadFile((tables_ / "bpmf-punctuations.cin").string()));
        const auto inputMethod = method_ == "cangjie" ? InputMethod::Cangjie :
                                 method_ == "simplex" ? InputMethod::Simplex :
                                 InputMethod::Bopomofo;
        const auto layout = layout_ == "hsu" ? BopomofoLayout::Hsu :
                                             BopomofoLayout::Standard;
        engine_ = std::make_unique<Engine>(dictionary, inputMethod, layout, punctuation);
        engine_->setTablePreferences(options_[method_].table);
        engine_->setSmartMandarinPreferences(options_[method_].smart);
        if (method_ == "smart") {
            const auto store = SmartMandarinStore::open(model_, user_);
            require(store != nullptr, "Could not open the real Smart Mandarin model");
            engine_->setSmartMandarinStore(store);
            engine_->setSmartMandarinMode(true);
        }
        context_ = InputContextState{};
        result_ = engine_->snapshot(context_);
    }

    void reopen() {
        engine_.reset();
        user_.reset();
        user_ = SmartMandarinUserData::open(userPath_);
        require(user_ != nullptr, "Could not open isolated learning database");
        buildEngine();
    }

    void option(const std::string &argument) {
        const auto separator = argument.find('=');
        const auto key = argument.substr(0, separator);
        const auto value = argument.substr(separator + 1);
        if (key == "dynamic" || key == "punctuation") {
            unsupported_ = "OPTION " + key + " is unsupported by the Unix core";
        } else if (key == "layout") {
            accept(engine_->finishComposition(context_));
            layout_ = value;
            buildEngine();
        } else {
            auto &options = options_[method_];
            const bool enabled = boolean(value);
            if (key == "realtime") options.table.composeWhileTyping = enabled;
            else if (key == "prefix") options.table.prefixCandidates = enabled;
            else if (key == "clear_on_error") options.table.clearOnError = enabled;
            else if (key == "space_selects") options.smart.showCandidateListWithSpace = enabled;
            engine_->setTablePreferences(options.table);
            engine_->setSmartMandarinPreferences(options.smart);
            result_ = engine_->snapshot(context_);
        }
    }

    std::vector<std::string> allCandidates() const {
        std::vector<std::string> candidates;
        if (result_.candidatePageCount == 0) return candidates;
        // The copy isolates navigation from the live session's page/highlight.
        auto probe = context_;
        auto result = engine_->snapshot(probe);
        for (std::size_t page = result.candidatePage; page > 0; --page)
            result = engine_->processKey(probe, KeyEvent{KeyCode::PageUp});
        require(result.candidatePage == 0, "Could not inspect first candidate page");
        const auto count = result.candidatePageCount;
        for (std::size_t page = 0; page < count; ++page) {
            require(result.candidatePage == page, "Candidate page capture did not advance");
            candidates.insert(candidates.end(), result.candidates.begin(), result.candidates.end());
            if (page + 1 < count)
                result = engine_->processKey(probe, KeyEvent{KeyCode::PageDown});
        }
        return candidates;
    }

    std::string learning() const {
        sqlite3 *raw = nullptr;
        require(sqlite3_open_v2(userPath_.c_str(), &raw, SQLITE_OPEN_READONLY, nullptr) == SQLITE_OK,
                "Could not inspect isolated learning database");
        const std::unique_ptr<sqlite3, decltype(&sqlite3_close)> database(raw, sqlite3_close);
        const auto overrides = learningRows(database.get(),
            "SELECT qstring,current FROM user_candidate_override_cache ORDER BY qstring,current", 2);
        const auto bigrams = learningRows(database.get(),
            "SELECT qstring,previous,current,printf('%.17g',probability) "
            "FROM user_bigram_cache ORDER BY qstring,previous,current,probability", 4);
        const auto unigrams = learningRows(database.get(),
            "SELECT qstring,current,printf('%.17g',probability),printf('%.17g',backoff) "
            "FROM user_unigrams ORDER BY qstring,current,probability,backoff", 4);
        return "{\"overrides\":" + overrides + ",\"bigrams\":" + bigrams +
               ",\"unigrams\":" + unigrams + ",\"table\":[]}";
    }

    void press(KeyCode code) {
        accept(engine_->processKey(context_, KeyEvent{code}));
    }
    void accept(EngineResult result) {
        committed_ += result.commit;
        result_ = std::move(result);
    }

    std::string model_;
    std::filesystem::path tables_;
    std::filesystem::path scratch_;
    std::string userPath_;
    std::string method_;
    std::string layout_ = "standard";
    std::map<std::string, Options> options_;
    std::shared_ptr<SmartMandarinUserData> user_;
    std::unique_ptr<Engine> engine_;
    InputContextState context_;
    EngineResult result_;
    std::string committed_;
    std::string unsupported_;
};
} // namespace

int main(int argc, char **argv) {
    std::string caseName;
    std::size_t lineNumber = 0;
    try {
        require(argc == 6,
                "Usage: shared_core_functional FIXTURE DB BPMF_CIN SCRATCH TRACE");
        std::ifstream input(argv[1]);
        require(input.good(), "Could not open migration fixture");
        std::ofstream output(argv[5]);
        require(output.good(), "Could not open migration trace");
        Scratch scratch(argv[4]);
        std::unique_ptr<Session> session;
        std::set<std::string> closedCases;
        std::string currentCase, initialMethod, currentProfile;
        std::size_t cases = 0, steps = 0, localStep = 0, skipped = 0;
        std::string line;
        while (std::getline(input, line)) {
            ++lineNumber;
            if (!line.empty() && line.back() == '\r') line.pop_back();
            if (line.empty() || line[0] == '#') continue;
            const auto row = fields(line);
            require(row.size() == 5, "Expected exactly five TSV fields");
            caseName = row[0];
            require(!caseName.empty(), "Case name must not be empty");
            require(row[1] == "hardware" || row[1] == "touch",
                    "Unknown profile: " + row[1]);
            require(validMethod(row[2]), "Unknown method: " + row[2]);
            validateOperation(row[3], row[4]);
            if (caseName != currentCase) {
                if (!currentCase.empty()) closedCases.insert(currentCase);
                require(closedCases.count(caseName) == 0, "Case rows must be contiguous");
                currentCase = caseName;
                currentProfile = row[1];
                initialMethod = row[2];
                localStep = 0;
                session.reset();
                if (currentProfile == "hardware") {
                    session = std::make_unique<Session>(
                        argv[2], std::filesystem::path(argv[3]).parent_path(),
                        scratch.path / ("case-" + std::to_string(cases)), initialMethod);
                    ++cases;
                }
            } else {
                require(row[1] == currentProfile, "Case profile changed within a case");
                require(row[2] == initialMethod, "Initial method changed within a case");
            }
            ++localStep;
            if (currentProfile == "touch") {
                ++skipped;
                continue;
            }
            session->run(row[3], row[4]);
            session->snapshot(output, caseName, localStep, currentProfile, row[3], row[4]);
            require(output.good(), "Could not write migration snapshot");
            ++steps;
        }
        require(input.eof(), "Could not read complete fixture");
        require(steps > 0, "No hardware migration steps executed");
        output.close();
        require(output.good(), "Could not close migration trace");
        std::cerr << "Unix migration baseline: " << cases << " hardware cases, "
                  << steps << " snapshots; " << skipped
                  << " touch operations explicitly skipped\n";
        return 0;
    } catch (const std::exception &error) {
        std::cerr << "Unix migration baseline failure: " << caseName
                  << " line " << lineNumber << ": " << error.what() << '\n';
        return 1;
    }
}

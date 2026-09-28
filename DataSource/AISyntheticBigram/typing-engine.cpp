// Offline adapter to the production macOS/Windows Smart Mandarin composer.
// The engine's original copyright and license remain in its included sources.
#include "OVIMSmartMandarin.h"
#include <iomanip>
#include <memory>
#include <sstream>
#include <stdexcept>

using namespace OpenVanilla;

static std::string quote(const std::string& value) {
    std::ostringstream out;
    out << '"';
    for (unsigned char c : value) {
        if (c == '"' || c == '\\') out << '\\' << c;
        else if (c < 32) out << "\\u" << std::hex << std::setw(4) << std::setfill('0') << int(c);
        else out << c;
    }
    out << '"';
    return out.str();
}

class Probe : public ManjusriComposer {
public:
    explicit Probe(LanguageModel* lm) : ManjusriComposer(lm) { clear(); }

    void state(const std::string& popped = "") {
        std::cout << "{\"text\":" << quote(composedString())
                  << ",\"popped\":" << quote(popped) << ",\"segments\":[";
        bool first = true;
        for (auto it = m_latestFastPath.begin(); it + 1 < m_latestFastPath.end(); ++it) {
            const auto& node = *it->nodePointer;
            if (it->text.empty()) continue;
            if (!first) std::cout << ',';
            first = false;
            std::cout << "{\"start\":" << node.location().first - 1
                      << ",\"length\":" << node.location().second
                      << ",\"query\":" << quote(node.queryString())
                      << ",\"text\":" << quote(it->text) << '}';
        }
        std::cout << "]}" << std::endl;
    }

    void candidates(size_t index) {
        collectCandidates(index + 1, false);
        std::cout << "[";
        bool first = true;
        for (const auto& candidate : m_latestCandidate) {
            const auto& node = *candidate.second;
            if (!first) std::cout << ',';
            first = false;
            std::cout << "{\"start\":" << node.location().first - 1
                      << ",\"length\":" << node.location().second
                      << ",\"query\":" << quote(node.queryString())
                      << ",\"text\":" << quote(candidate.first.first) << '}';
        }
        std::cout << "]" << std::endl;
    }
};

int main(int argc, char** argv) {
    if (argc != 2) return 2;
    auto* db = OVSQLiteConnection::Open(argv[1]);
    if (!db) return 2;
    db->execute("PRAGMA query_only=ON");
    if (!db->hasTable("unigrams") || !db->hasTable("bigrams")) return 2;
    // Match OVIMSmartMandarin::initialize: characters absent from the frequency
    // model (e.g. 臺) remain selectable through the bundled BPMF table.
    std::unique_ptr<OVSQLiteDatabaseService> service(
        OVSQLiteDatabaseService::ServiceWithExistingConnection(db, false));
    std::unique_ptr<OVKeyValueDataTableInterface> external(
        db->hasTable("Mandarin-bpmf-cin")
            ? service->createKeyValueDataTableInterface("Mandarin-bpmf-cin") : nullptr);
    // Fresh model, no user database, no cross-sentence learning or overrides.
    LanguageModel model(db, external.get(), false, false, true, false, false);
    Node::SetUNK(model.UNKUnigram().probability, model.UNKUnigram().backoff);
    Probe composer(&model);
    std::string line;
    while (std::getline(std::cin, line)) {
        try {
            auto tab = line.find('\t');
            auto command = line.substr(0, tab);
            auto argument = tab == std::string::npos ? "" : line.substr(tab + 1);
            if (command == "reset") composer.clear();
            else if (command == "insert") {
                if (argument.size() != 2 || !model.isInDictionary(argument))
                    throw std::runtime_error("unknown reading");
                if (!composer.insertAt(composer.cursorRightBound(), argument))
                    throw std::runtime_error("insert failed");
                composer.update();
            } else if (command == "candidates") {
                composer.candidates(std::stoul(argument));
                continue;
            } else if (command == "select") {
                if (!composer.chooseCandidate(std::stoul(argument)))
                    throw std::runtime_error("selection failed");
            } else if (command == "shift") {
                auto popped = composer.shift();
                composer.update();
                composer.state(popped);
                continue;
            } else throw std::runtime_error("unknown command");
            composer.state();
        } catch (const std::exception& error) {
            std::cout << "{\"error\":" << quote(error.what()) << "}" << std::endl;
        }
    }
}

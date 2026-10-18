// Exercises the shared desktop module against the real bundled SQLite table.
#include "OVIMGeneric.h"
#include "../Source/Loaders/Windows-TSF/WindowsTableInputMethod.h"
#include "PVLoaderService.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include "PVBasicKeyValueMapImpl.h"
#include "../Source/Shared/CangjiePrefix.h"
#include <memory>
#include <stdexcept>
#include <iostream>
using namespace OpenVanilla;
static void check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }

class Harness {
public:
    std::unique_ptr<OVSQLiteConnection> connection;
    std::unique_ptr<OVSQLiteDatabaseService> database;
    std::unique_ptr<OVIMGeneric> module;
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    PVBasicKeyValueMapImpl map;
    OVKeyValueMap config;
    std::unique_ptr<OVIMGenericContext> context;
    Harness(const char* db, const char* directory, bool realtime, bool prefix, bool windows)
        : connection(OVSQLiteConnection::Open(db)),
          database(OVSQLiteDatabaseService::ServiceWithExistingConnection(connection.get())),
          module(windows ? static_cast<OVIMGeneric*>(new KeyKey::WindowsTsf::WindowsTableInputMethod("Generic-cj-cin", database.get()))
                         : new OVIMGeneric("Generic-cj-cin", database.get())), loader("zh_TW", 0, database.get()),
          candidates(&loader), config(&map) {
        OVPathInfo paths; paths.writablePath = directory;
        check(module->initialize(&paths, &loader), "Module did not initialize");
        config.setKeyBoolValue("UseDynamicFrequency", false);
        config.setKeyBoolValue("ComposeWhileTyping", realtime);
        config.setKeyBoolValue("PrefixCandidates", prefix);
        config.setKeyBoolValue("ShouldCommitAtMaximumRadicalLength", true);
        module->loadConfig(&config, &loader);
        context.reset(static_cast<OVIMGenericContext*>(module->createContext()));
        context->startSession(&loader);
    }
    ~Harness() { context->stopSession(&loader); }
    std::vector<std::string> values() {
        std::vector<std::string> result;
        if (!candidates.accessVerticalCandidatePanel()->isVisible()) return result;
        OVCandidateList* list = candidates.accessVerticalCandidatePanel()->candidateList();
        for (size_t i = 0; i < list->size(); ++i) result.push_back(list->candidateAtIndex(i));
        return result;
    }
    void press(unsigned code) {
        OVKey key = loader.makeOVKey(code);
        PVVerticalCandidatePanel* panel = candidates.accessVerticalCandidatePanel();
        if (panel->isVisible()) {
            const PVCandidateState::State state = panel->handleKeyEvent(key, &loader);
            if (state == PVCandidateState::CandidateChosen) {
                const std::string text = panel->chosenCandidateString();
                const size_t index = panel->chosenCandidateIndex();
                panel->hide(); panel->cancelEventHandler();
                context->candidateSelected(&candidates, text, index, &reading, &composing, &loader);
            } else if (state == PVCandidateState::Canceled) {
                panel->hide();
                context->candidateCanceled(&candidates, &reading, &composing, &loader);
            } else if (state == PVCandidateState::Ignored) {
                check(context->candidateNonPanelKeyReceived(&candidates, &key, &reading, &composing, &loader),
                      "Candidate handler rejected a radical");
            }
        } else {
            check(context->handleKey(&key, &reading, &composing, &candidates, &loader), "Radical passed through");
        }
    }
    void type(const std::string& text) { for (size_t i = 0; i < text.size(); ++i) press(text[i]); }
};
struct Accept { bool operator()(const std::string&) const { return true; } };
struct RejectCompat {
    bool operator()(const std::string& text) const { return text != "豈"; }
};
int main(int argc, char** argv) {
    try {
        check(argc == 4, "Expected database, temporary directory and module kind");
        const bool windows = std::string(argv[3]) == "windows";
        for (int realtime = 0; realtime < 2; ++realtime) for (int prefix = 0; prefix < 2; ++prefix) {
            Harness h(argv[1], argv[2], realtime != 0, prefix != 0, windows);
            h.type("hk");
            const auto values = h.values();
            check(values.empty() == !realtime, "Realtime dependency failed");
            check((std::find(values.begin(), values.end(), "喬") != values.end()) ==
                  (realtime && prefix), "Prefix dependency failed");
        }
        Harness h(argv[1], argv[2], true, true, windows);
        const size_t counts[] = {38, 40, 11, 2, 1};
        const char* roots[] = {"竹", "竹大", "竹大口", "竹大口月", "竹大口月口"};
        for (size_t i = 0; i < 5; ++i) {
            h.press(std::string("hkrbr")[i]);
            check(h.composing.composedCommittedText().empty(), "Preview auto-committed");
            check(h.reading.composedText() == roots[i], "Wrong root display");
            check(h.values().size() == counts[i], "Wrong exact/prefix count");
            if (i == 1) h.press(OVKeyCode::PageDown);
            if (i == 2) check(h.candidates.accessVerticalCandidatePanel()->currentPage() == 0,
                              "Root change retained the old page");
        }
        h.press(OVKeyCode::Backspace);
        check(h.values() == std::vector<std::string>({"喬", "䀉"}), "Backspace did not refresh");
        h.press(OVKeyCode::Return);
        check(h.composing.composedCommittedText() == "喬", "Enter did not select Qiao");
        h.composing.finishCommit();
        h.type("hkrbra");
        check(h.composing.composedCommittedText() == "喬" && h.reading.composedText() == "日",
              "Sixth radical did not start the next character");
        h.press(OVKeyCode::Esc);
        h.composing.finishCommit();
        h.type("hk?");
        check(h.values().size() > 36, "Wildcard was limited as a prefix");
        h.press(OVKeyCode::Esc);
        h.type("hzz");
        check(h.values().empty(), "Stale preview survived an unmatched code");
        h.press(OVKeyCode::Backspace);

        KeyKeyCangjie::Selection selection(std::vector<std::string>(1, "是"));
        for (int i = 0; i < 100; ++i) selection.consider("候選" + std::to_string(i), Accept());
        selection.consider("的", Accept());
        selection.consider("是", Accept());
        check(selection.values().size() == 36 && selection.values().front() == "的",
              "Ranking was applied after truncation");
        KeyKeyCangjie::Selection aliases(std::vector<std::string>{});
        aliases.consider("豈", RejectCompat());
        aliases.consider("豈", RejectCompat());
        aliases.consider("豈", Accept());
        aliases.consider("，", Accept()); aliases.consider("★", Accept());
        check(aliases.values() == std::vector<std::string>{"豈"}, "Glyph refill/identity/filter failed");
        check(KeyKeyCangjie::ranks().size() == 1500 && KeyKeyCangjie::rank("喬") == 1215, "Rank resource drifted");

        Harness learned(argv[1], argv[2], true, true, windows);
        learned.context->stopSession(&learned.loader);
        learned.config.setKeyBoolValue("UseDynamicFrequency", true);
        learned.module->loadConfig(&learned.config, &learned.loader);
        learned.context->startSession(&learned.loader);
        learned.type("hk");
        const auto values = learned.values();
        const size_t qiao = std::find(values.begin(), values.end(), "喬") - values.begin();
        check(qiao < values.size(), "Learned session missing Qiao");
        learned.context->candidateSelected(&learned.candidates, "喬", qiao,
                                           &learned.reading, &learned.composing, &learned.loader);
        learned.context->stopSession(&learned.loader);
        auto learning = std::unique_ptr<OVSQLiteConnection>(OVSQLiteConnection::Open(
            (std::string(argv[2]) + "/Generic-cj-cin-DynamicCandidateOrder.sqlite3")));
        auto rows = std::unique_ptr<OVSQLiteStatement>(learning->prepare(
            "SELECT count(*) FROM user_frequency WHERE key='hk' AND value='喬'"));
        check(rows && rows->step() == SQLITE_ROW && rows->intOfColumn(0) == 0,
              "Prefix selection polluted short-code learning");
        rows.reset();
        check(learning->execute("INSERT INTO user_frequency VALUES ('hk','喬',9999),('hk','𥫜',500)") == SQLITE_OK,
              "Could not seed historical ordering");
        learned.context->startSession(&learned.loader);
        learned.type("hk");
        const auto ordered = learned.values();
        check(ordered.size() == 40 && ordered.front() == "𥫜" && ordered[4] == "喬",
              "Learning crossed the exact/prefix boundary");
        std::cout << (windows ? "Windows table module: " : "Shared desktop module: ") << "dependencies, Qiao, paging, wildcard, ranking and learning passed\n";
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

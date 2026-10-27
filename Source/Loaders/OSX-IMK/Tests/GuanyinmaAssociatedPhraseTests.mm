// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Actual native filter and adapter in an isolated, headless process.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacAdapter.h"
#include "OVAFAssociatedPhrase.h"
#include "PVBasicKeyValueMapImpl.h"
#include "PVCandidate.h"
#include "PVLoaderService.h"
#include "PVTextBuffer.h"
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>

using namespace OpenVanilla;
namespace fs = std::filesystem;
static size_t checks;
static void require(bool value, const char* message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}
static void sql(sqlite3* database, const char* statement) {
    char* error = nullptr;
    if (sqlite3_exec(database, statement, nullptr, nullptr, &error) != SQLITE_OK) {
        std::string text = error ? error : "SQL fixture failed";
        sqlite3_free(error);
        throw std::runtime_error(text);
    }
}
static void fixture(const fs::path& path, const char* rows) {
    sqlite3* database = nullptr;
    require(sqlite3_open(path.c_str(), &database) == SQLITE_OK, "create isolated fixture");
    sql(database,
        "CREATE TABLE unigrams(qstring TEXT,current TEXT,probability REAL,backoff REAL);"
        "CREATE TABLE bigrams(qstring TEXT,previous TEXT,current TEXT,probability REAL);"
        "CREATE TABLE \"Mandarin-bpmf-cin\"(key TEXT,value TEXT);"
        "CREATE TABLE \"Generic-cj-cin\"(key TEXT,value TEXT);"
        "CREATE TABLE \"Generic-simplex-cin\"(key TEXT,value TEXT);"
        "CREATE TABLE associated_phrases(headchar TEXT,data TEXT,source TEXT);");
    sql(database, rows);
    sqlite3_close(database);
}
class AssociatedPackage : public OVModulePackage {
public:
    size_t numberOfModules(OVLoaderService*) override { return 1; }
    OVModule* moduleAtIndex(size_t, OVLoaderService*) override { return new OVAFAssociatedPhrase; }
};
class Harness {
public:
    std::unique_ptr<OVSQLiteDatabaseService> database;
    PVLoaderService loader;
    PVCandidateService candidates;
    PVTextBuffer reading, composing;
    explicit Harness(const fs::path& path)
        : database(OVSQLiteDatabaseService::Create(path.u8string())),
          loader("zh_TW", nullptr, database.get()), candidates(&loader) {
        require(database != nullptr, "open native fixture service");
    }
    OVOneDimensionalCandidatePanel* panel() { return candidates.useOneDimensionalCandidatePanel(); }
    void reset() {
        reading.clear(); composing.clear();
        reading.finishCommit(); composing.finishCommit();
        panel()->hide(); panel()->reset(); panel()->candidateList()->clear();
    }
    std::vector<std::string> values() {
        std::vector<std::string> output;
        auto* list = panel()->candidateList();
        for (size_t i = 0; i < list->size(); ++i) output.push_back(list->candidateAtIndex(i));
        return output;
    }
    bool direct(OVEventHandlingContext* context, const std::string& text = "中") {
        return context->handleDirectText(text, &reading, &composing, &candidates, &loader);
    }
};
static void run(const fs::path& model, const fs::path& root) {
    const auto native = root / "native.db", rust = root / "rust.db", missing = root / "missing.db";
    fixture(native,
        "INSERT INTO associated_phrases VALUES('中','native-a,shared','A'),('中','native-b,shared','B');");
    fixture(rust,
        "INSERT INTO associated_phrases VALUES('中','discarded','A'),"
        "('中','rust-a,shared,,','A'),('中','rust-b,shared','B');");
    fixture(missing, "DROP TABLE associated_phrases;");
    Harness h(native), other(native);
    std::unique_ptr<OVModulePackage> package(GuanyinmaWrapModulePackage(
        new AssociatedPackage, rust.u8string(), "", true));
    std::unique_ptr<OVModule> module(package->moduleAtIndex(0, &h.loader));
    OVPathInfo paths;
    require(module->moduleInitialize(&paths, &h.loader), "initialize native filter");
    PVBasicKeyValueMapImpl values;
    OVKeyValueMap config(&values);
    config.setKeyStringValue("EnabledCollections", "B,A");
    module->loadConfig(&config, &h.loader);
    std::unique_ptr<OVEventHandlingContext> context(module->createContext());
    require(h.direct(context.get()), "native path handles a single committed character");
    require(h.values() == std::vector<std::string>({"native-b", "shared", "native-a"}), "inactive Rust retains original query");
    require(h.composing.isCommitted() && h.composing.composedCommittedText() == "中", "FE commits original head");
    h.reset();

    PVBasicKeyValueMapImpl coreValues;
    OVKeyValueMap coreConfig(&coreValues);
    std::string error;
    std::unique_ptr<OVEventHandlingContext> input(GuanyinmaCreateInputContext(
        "TraditionalMandarin", model.u8string(), "", &coreConfig, &error));
    require(input != nullptr, "open real Rust context");
    input->startSession(&h.loader);
    OVKey escape = h.loader.makeOVKey(OVKeyCode::Esc);
    input->handleKey(&escape, &h.reading, &h.composing, &h.candidates, &h.loader);
    h.reset();
    require(h.direct(context.get()), "active Rust handles associated query");
    require(h.values() == std::vector<std::string>({"rust-b", "shared", "rust-a", ""}), "Rust ordering, last source row and dedup reach native panel");
    require(h.panel()->isVisible() && h.panel()->candidatesPerPage() == 9, "FE retains native panel and page size");
    require(other.direct(context.get()), "other candidate service remains usable");
    require(other.values() == std::vector<std::string>({"native-b", "shared", "native-a"}), "Rust context never captures another service");
    other.reset(); h.reset();

    OVKey choose = h.loader.makeOVKey('@', false, false, false, true);
    require(h.direct(context.get()), "prepare associated selection");
    require(context->handleKey(&choose, &h.reading, &h.composing, &h.candidates, &h.loader), "Shift number selection remains FE handled");
    require(h.composing.composedCommittedText() == "中shared", "FE selects suffix without committing head twice");
    require(!h.panel()->isVisible(), "FE hides panel after selection");
    h.reset();

    require(!h.direct(context.get(), "AB"), "FE retains multi-scalar gate");
    require(!h.direct(context.get(), "A"), "FE retains codepoint range gate");
    h.reading.setText("ㄅ");
    require(!h.direct(context.get()), "FE retains composing gate");
    h.reset();
    config.setKeyStringValue("EnabledCollections", ""); module->loadConfig(&config, &h.loader);
    require(!h.direct(context.get()) && !h.composing.isCommitted(), "empty collection selection disables interception");
    config.setKeyStringValue("EnabledCollections", "B,A"); module->loadConfig(&config, &h.loader);

    std::unique_ptr<OVModulePackage> badPackage(GuanyinmaWrapModulePackage(new AssociatedPackage, missing.u8string(), "", true));
    std::unique_ptr<OVModule> badModule(badPackage->moduleAtIndex(0, &h.loader));
    require(badModule->moduleInitialize(&paths, &h.loader), "initialize error-path native filter");
    badModule->loadConfig(&config, &h.loader);
    std::unique_ptr<OVEventHandlingContext> bad(badModule->createContext());
    require(h.direct(bad.get()) && h.values().empty(), "Rust query failure never falls back to native candidates");
    h.reset();
    input->stopSession(&h.loader);
    require(h.direct(context.get()), "native path resumes after real Rust deactivation");
    require(h.values() == std::vector<std::string>({"native-b", "shared", "native-a"}), "deactivated Rust no longer owns routing");
}
int main(int argc, char** argv) {
    @autoreleasepool {
        try {
            if (argc != 3) throw std::runtime_error("expected model and scratch paths");
            run(argv[1], argv[2]);
            std::cout << "{\"checks\":" << checks << ",\"status\":\"passed\"}\n";
            return 0;
        } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
    }
}

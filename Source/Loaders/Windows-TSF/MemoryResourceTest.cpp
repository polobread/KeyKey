#include "PVModuleSystem.h"
#include "OVSQLiteDatabaseService.h"
#include "ModuleState.h"

#include <array>
#include <atomic>
#include <filesystem>
#include <iostream>
#include <memory>
#include <stdexcept>
#include <string>

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0}, g_serverLocks{0};
}

namespace {
using namespace OpenVanilla;
void Check(bool ok, const char* message) {
    if (!ok) throw std::runtime_error(message);
}
std::string Utf8(const std::filesystem::path& path) {
    return OVUTF8::FromUTF16(path.wstring());
}
sqlite3_int64 SqliteMemory() { return sqlite3_memory_used(); }

void FailedOpenChecks(const std::filesystem::path& profile) {
    const auto missing = Utf8(profile / L"missing-parent" / L"database.db");
    sqlite3* native = nullptr;
    Check(sqlite3_open(missing.c_str(), &native) != SQLITE_OK && native,
          "Failure fixture did not allocate a SQLite handle");
    Check(sqlite3_close(native) == SQLITE_OK, "Close native failure fixture");
    const auto before = SqliteMemory();
    for (int i = 0; i < 256; ++i) {
        std::unique_ptr<OVSQLiteConnection> connection(OVSQLiteConnection::Open(missing));
        Check(!connection, "Invalid database path unexpectedly opened");
        Check(SqliteMemory() == before, "Failed open retained SQLite allocations");
    }
    std::cout << "256 failed opens: SQLite bytes " << before << " -> " << SqliteMemory() << '\n';
}

struct Counts {
    std::array<int, 4> created{}, destroyed{}, finalized{};
};
const std::array<std::string, 4> kModules{"excluded", "unused", "active", "failed"};
class CountingModule final : public OVModule {
public:
    CountingModule(Counts& counts, size_t index) : counts_(counts), index_(index) { ++counts_.created[index_]; }
    ~CountingModule() override { ++counts_.destroyed[index_]; }
    const std::string identifier() const override { return kModules[index_]; }
    bool initialize(OVPathInfo*, OVLoaderService*) override { return index_ != 3; }
    void finalize() override { ++counts_.finalized[index_]; }
private:
    Counts& counts_;
    size_t index_;
};
class CountingPackage final : public OVModulePackage {
public:
    explicit CountingPackage(Counts& counts) : counts_(counts) {}
    size_t numberOfModules(OVLoaderService*) override { return kModules.size(); }
    OVModule* moduleAtIndex(size_t index, OVLoaderService*) override { return new CountingModule(counts_, index); }
private:
    Counts& counts_;
};
class TestPolicy final : public PVLoaderPolicy {
public:
    explicit TestPolicy(std::filesystem::path directory) : PVLoaderPolicy({}), directory_(std::move(directory)) {}
    const std::string propertyListPathFromIdentifier(const std::string& identifier) override {
        return Utf8(directory_ / (identifier + ".plist"));
    }
private:
    std::filesystem::path directory_;
};
void ModuleChecks(const std::filesystem::path& profile) {
    for (int iteration = 0; iteration < 100; ++iteration) {
        Counts counts;
        OVPathInfo paths;
        PVLoaderService service;
        TestPolicy policy(profile);
        PVStaticModulePackageLoadingSystem packages(paths, true);
        Check(packages.addInitializedPackage("counting", new CountingPackage(counts)), "Add fixture package");
        PVModulePackageManager packageManager({&packages}, {}, &policy, &service);
        {
            PVModuleManager modules(&packageManager, {"excluded"}, &service);
            Check(counts.created == std::array<int, 4>{1, 1, 1, 1} && counts.destroyed[0] == 1,
                  "Excluded module not released immediately");
            Check(modules.moduleWithName("active", &policy, &service) != nullptr &&
                  modules.moduleWithName("failed", &policy, &service) == nullptr, "Module initialization fixture");
        }
        Check(counts.destroyed == counts.created, "Manager retained excluded, unused or failed modules");
        Check(counts.finalized == std::array<int, 4>{0, 0, 1, 1}, "Module finalize lifecycle changed");
    }
    std::cout << "100 managers released excluded, unused, initialized and failed modules exactly once\n";
}

void ParserChecks() {
    const std::string text(65536, 'x');
    const auto xml = "<plist><dict><key>Text</key><string>" + text +
        "</string><key>Items</key><array><string>A&amp;B</string>"
        "<dict><key>N</key><string>nested</string></dict></array></dict></plist>";
    for (int i = 0; i < 100; ++i) {
        std::unique_ptr<PVPlistValue> parsed(PVPropertyList::ParsePlistFromString(xml.c_str()));
        Check(parsed && parsed->stringValueForKey("Text") == text, "Large plist value changed");
        auto* items = parsed->valueForKey("Items");
        Check(items && items->arraySize() == 2 && items->arrayElementAtIndex(0)->stringValue() == "A&B" &&
              items->arrayElementAtIndex(1)->stringValueForKey("N") == "nested", "Nested plist or escape changed");
        const auto broken = xml.substr(0, xml.size() - 8);
        std::unique_ptr<PVPlistValue> invalid(PVPropertyList::ParsePlistFromString(broken.c_str()));
        Check(!invalid, "Malformed plist was accepted");
        std::unique_ptr<PVPlistValue> next(PVPropertyList::ParsePlistFromString(
            "<plist><dict><key>Text</key><string>next</string></dict></plist>"));
        Check(next && next->stringValueForKey("Text") == "next", "Parser retained text after failure");
    }
    std::cout << "100 large/nested, malformed and subsequent plist parse cycles passed\n";
}
}

int wmain() {
    try {
        wchar_t executable[32768]{};
        Check(GetModuleFileNameW(nullptr, executable, 32768) != 0, "Executable path");
        const auto profile = std::filesystem::path(executable).parent_path() /
            (L"memory-resource-profile-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
        std::filesystem::create_directories(profile);
        struct Cleanup {
            std::filesystem::path path;
            ~Cleanup() { std::error_code error; std::filesystem::remove_all(path, error); }
        } cleanup{profile};
        SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str());
        FailedOpenChecks(profile);
        ModuleChecks(profile);
        ParserChecks();
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}

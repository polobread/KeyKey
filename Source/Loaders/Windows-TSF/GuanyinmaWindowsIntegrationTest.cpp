// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "KeyKeyEngine.h"
#include "GuanyinmaWindowsUserData.h"
#include "FrontendSettings.h"
#include "SharedFileAccess.h"
#include "ModuleState.h"
#include "sqlite3.h"
#include <atomic>
#include <filesystem>
#include <iostream>
#include <stdexcept>

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0}, g_serverLocks{0};
}
using namespace KeyKey::WindowsTsf;
namespace {
void Check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
void Core(bool rust) {
    SettingsFileLock lock(LoaderPreferencesPath());
    Check(bool(lock) && WriteSharedSettingsFile(LoaderPreferencesPath(),
        std::string("<plist><dict><key>PrimaryInputMethod</key><string>SmartMandarin</string><key>InputCore</key><string>") +
        (rust ? "Guanyinma" : "Manjusri") + "</string></dict></plist>"), "write core preference");
}
EngineResult Key(KeyKeyEngineSession& session, UINT key) { KeyEvent event; event.virtualKey = key; event.numLock = true; return session.handleKey(event); }
EngineResult Type(KeyKeyEngineSession& session, const std::string& text) {
    EngineResult result;
    for (char c : text) result = Key(session, c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
    return result;
}
void Input(const std::filesystem::path& model) {
    Check(!LoadFrontendSettings().guanyinmaCore, "default core must remain Manjusri");
    Core(true);
    for (const auto* method : {"SmartMandarin", "TraditionalMandarin", "Generic-cj-cin", "Generic-simplex-cin"}) {
        auto session = KeyKeyEngineSession::CreateControlled(method);
        Check(session && session->ready() && session->usesGuanyinma(), "native Rust session open");
        if (std::string(method) == "SmartMandarin") {
            const auto result = Type(*session, "su3cl3");
            Check(result.compositionText == L"你好" && result.compositionCursor == 2, "Rust UTF-16 composition bridge");
            const auto committed = Key(*session, VK_RETURN);
            Check(committed.committedText == L"你好", "Rust commit through native buffer");
        } else {
            auto result = Type(*session, std::string(method) == "TraditionalMandarin" ? "su3" : "a");
            if (!result.candidatesVisible) result = Key(*session, VK_SPACE);
            Check(result.candidatesVisible && !result.candidates.empty(), "Rust candidates through native panel");
            if (std::string(method) == "TraditionalMandarin") {
                const auto first = result.candidates.front().text;
                result = Key(*session, VK_NEXT);
                Check(result.candidatesVisible && !result.candidates.empty() && result.candidates.front().text != first,
                    "native page navigation must retain Rust candidate order");
            }
            const auto expected = result.candidates.front().text;
            Check(result.candidates.front().selectionKey == L"1", "page-local candidate label");
            result = Key(*session, '1');
            if (result.committedText != expected) std::cerr << method << ": selection failed, commit length=" << result.committedText.size() << " composition length=" << result.compositionText.size() << '\n';
            Check(result.committedText == expected, "Rust candidate selection through native key");
        }
    }
    auto session = KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Type(*session, "s"); Core(false);
    auto result = Key(*session, 'U');
    Check(session->usesGuanyinma() && result.compositionText == L"ㄋㄧ", "core switch must defer unfinished reading");
    Key(*session, VK_ESCAPE); Check(session->usesGuanyinma(), "old core owns clearing event");
    result = Key(*session, 'S');
    Check(!session->usesGuanyinma() && result.compositionText == L"ㄋ", "next input adopts core once empty");
    Key(*session, VK_ESCAPE); Core(true);
    result = Key(*session, 'S'); Check(session->usesGuanyinma(), "switch back to Rust");
    Key(*session, VK_ESCAPE); Type(*session, "su3"); Key(*session, VK_DOWN); Core(false);
    result = Key(*session, '1'); Check(session->usesGuanyinma(), "old candidate callback must remain on Rust");
    result = Key(*session, VK_NUMPAD7);
    Check(result.committedText.back() == L'7' && !session->hasComposition(), "numpad flushes original core composition");
    result = Key(*session, 'S'); Check(!session->usesGuanyinma(), "switch after candidate and commit effects");
    session.reset(); Core(true);
    {
        GuanyinmaWindowsUserData words(model.wstring());
        Check(words.save({0, L"\u0378", L"ㄋㄧˇ"}), "unsupported glyph fixture");
        auto filtered = KeyKeyEngineSession::CreateControlled("SmartMandarin");
        result = Type(*filtered, "su3");
        Check(result.compositionText == L"你", "native glyph callback must reject unsupported graph text");
        result = Key(*filtered, VK_DOWN);
        for (const auto& candidate : result.candidates) Check(candidate.text != L"\u0378", "unsupported candidate reached native panel");
    }
    session = KeyKeyEngineSession::CreateControlled("SmartMandarin");
    Type(*session, "s");
    sqlite3* locked = nullptr;
    Check(sqlite3_open16((SettingsDirectory() + L"\\GuanyinmaUserData.db").c_str(), &locked) == SQLITE_OK, "lock fixture connection");
    Check(sqlite3_exec(locked, "BEGIN EXCLUSIVE", nullptr, nullptr, nullptr) == SQLITE_OK, "exclusive user-store lock");
    result = Key(*session, 'U');
    Check(result.beep && result.compositionText == L"ㄋ" && result.committedText.empty(), "failed key must preserve last native view without effects");
    sqlite3_exec(locked, "ROLLBACK", nullptr, nullptr, nullptr);
    result = Key(*session, 'U'); Check(result.compositionText == L"ㄋㄧ", "recovery must process the next key once");
    Check(sqlite3_exec(locked, "BEGIN EXCLUSIVE", nullptr, nullptr, nullptr) == SQLITE_OK, "reset failure lock");
    session->reset();
    sqlite3_exec(locked, "ROLLBACK", nullptr, nullptr, nullptr); sqlite3_close(locked);
    result = Key(*session, 'S'); Check(result.compositionText == L"ㄋ", "failed clear must not resurrect old graph");
    std::cout << "Windows four-method adapter, candidates, UTF-16, keypad and safe dual-core switching passed\n";
}
void Data(const std::filesystem::path& model, const std::filesystem::path& directory) {
    Core(true);
    GuanyinmaWindowsUserData data(model.wstring());
    Check(data.save({0, L"妮好", L"ㄋㄧˇ,ㄏㄠˇ"}), "Rust phrase insert");
    auto rows = data.load(); Check(rows.size() == 1 && rows[0].text == L"妮好", "Rust phrase load");
    const auto old = rows[0].rowid;
    Core(false); // Open settings owner is fixed despite a new input preference.
    Check(data.save({old, L"妮豪", L"ㄋㄧˇ,ㄏㄠˊ"}), "bound Rust phrase update");
    Check(LoadUserPhrases().empty(), "Rust edit touched Manjusri words");
    const auto backup = directory / L"備份.json";
    Check(data.exportData(backup.wstring()), "complete JSON export");
    Check(!data.exportData(model.wstring()) && !data.exportData((directory / L"GuanyinmaUserData.db").wstring()) &&
        !data.exportData((directory / L"SmartMandarinUserData.db").wstring()), "export overwrote live data");
    const auto alias = directory / L"alias.json";
    Check(CreateHardLinkW(alias.c_str(), (directory / L"GuanyinmaUserData.db").c_str(), nullptr), "hardlink fixture");
    Check(!data.exportData(alias.wstring()), "export overwrote live-data hardlink");
    rows = data.load();
    Check(!data.remove(old), "stale row token after reload");
    Check(data.resetLearning() && data.load().size() == 1, "reset must preserve custom phrases");
    rows = data.load(); Check(data.remove(rows[0].rowid) && data.load().empty(), "Rust phrase delete");
    Check(data.importData(backup.wstring()) && data.load()[0].text == L"妮豪", "JSON backup roundtrip");
    const auto corrupt = directory / L"invalid.json";
    Check(WriteSharedSettingsFile(corrupt.wstring(), "{\"format\":\"guanyinma_user_data\",\"phrases\":[{}]}"), "bad fixture");
    Check(!data.importData(corrupt.wstring()) && data.load().size() == 1, "invalid import must preserve data");
    Check(SaveUserPhrase({0, L"您好", L"ㄋㄧㄣˊ,ㄏㄠˇ"}), "legacy source fixture");
    const auto legacy = directory / L"SmartMandarinUserData.db";
    std::string before, after; ReadSharedSettingsFile(legacy.wstring(), before);
    Check(data.importData(legacy.wstring()) && data.load().size() == 2, "explicit legacy import");
    ReadSharedSettingsFile(legacy.wstring(), after); Check(before == after, "legacy import modified source");
    std::cout << "Windows bound user data, CRUD, reset, JSON/legacy imports and export identity protection passed\n";
}
}
int main(int argc, char** argv) {
    g_module = GetModuleHandleW(nullptr);
    const auto directory = std::filesystem::temp_directory_path() / (L"KeyKey-Guanyinma-" + std::to_wstring(GetCurrentProcessId()));
    std::filesystem::create_directories(directory);
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", directory.c_str());
    wchar_t executable[32768]{}; GetModuleFileNameW(nullptr, executable, 32768);
    const auto model = std::filesystem::path(executable).parent_path() / L"Databases/KeyKey.db";
    int status = 0;
    try { if (argc == 2 && std::string(argv[1]) == "data") Data(model, directory); else Input(model); }
    catch (const std::exception& error) { std::cerr << error.what() << '\n'; status = 1; }
    catch (...) { std::cerr << "Windows adapter exception\n"; status = 1; }
    Check(ShutdownEngineRuntime(), "runtime still owned");
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", nullptr);
    std::filesystem::remove_all(directory);
    return status;
}

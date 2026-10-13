#include "Diagnostics.h"
#include "FrontendSettings.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <iterator>
#include <chrono>
#include <stdexcept>

using namespace KeyKey::WindowsTsf;
namespace {
constexpr std::int64_t kDuration = 3 * 24 * 60 * 60;
constexpr std::uintmax_t kLimit = 10 * 1024 * 1024;
void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Session(std::int64_t started, std::int64_t expires) {
    { std::ofstream file(DiagnosticSettingsPath());
      file << "<plist><dict><key>StartedAtUtc</key><string>" << started <<
          "</string><key>ExpiresAtUtc</key><string>" << expires << "</string></dict></plist>"; }
    RefreshDiagnosticsSettings();
}
void SizedFile(const std::filesystem::path& path, std::uintmax_t size) {
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file.seekp(size - 1); file.put('\0');
}
}

int main() {
    const auto directory = std::filesystem::current_path() /
        (L"diagnostics-test-" + std::to_wstring(GetCurrentProcessId()));
    const auto log = directory / L"KeyKeyTsf.log";
    const auto backup = directory / L"KeyKeyTsf.log.1";
    try {
        Check(std::filesystem::create_directory(directory), "Test directory already exists");
        Check(SetEnvironmentVariableW(L"TMP", directory.c_str()) &&
              SetEnvironmentVariableW(L"TEMP", directory.c_str()) &&
              SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", directory.c_str()), "Cannot isolate diagnostics");
        RefreshDiagnosticsSettings();
        Trace("default off");
        Check(!DiagnosticsEnabled() && !std::filesystem::exists(log), "Default-off diagnostics wrote a log");

        const auto now = std::chrono::duration_cast<std::chrono::seconds>(
            std::chrono::system_clock::now().time_since_epoch()).count();
        Check(!DiagnosticSession{now, now + kDuration}.activeAt(now + kDuration), "Deadline must stop immediately");
        Check(DiagnosticSession{now, now + kDuration}.activeAt(now + kDuration - 1), "Three-day window ended early");
        for (const auto session : {DiagnosticSession{now - kDuration, now},
                 DiagnosticSession{now + 60, now + 60 + kDuration}, DiagnosticSession{now, now + kDuration + 1}}) {
            Session(session.startedAt, session.expiresAt);
            Trace("expired or invalid must stay off");
            Check(!DiagnosticsEnabled() && !std::filesystem::exists(log), "Expired/future/extended diagnostics wrote a log");
        }
        Session(now, now + kDuration);
        Trace("diagnostics-switch-test value=%d", 42);
        { std::ifstream file(log); const std::string content{std::istreambuf_iterator<char>(file), {}};
          Check(content.find("pid=") != std::string::npos && content.find("value=42") != std::string::npos,
              "Enabled diagnostics did not write expected metadata"); }

        SizedFile(log, kLimit);
        Trace("rotate full log");
        Check(std::filesystem::file_size(log) < kLimit && std::filesystem::file_size(backup) == kLimit,
            "Rotation did not retain one bounded backup");
        SizedFile(log, kLimit); Trace("rotate again");
        Check(std::filesystem::file_size(backup) == kLimit && std::filesystem::file_size(log) < kLimit,
            "Repeated rotation exceeded the log cap");
        SizedFile(log, kLimit + 1); SizedFile(backup, kLimit + 1); Trace("old oversized logs");
        Check(std::filesystem::file_size(log) < kLimit && !std::filesystem::exists(backup),
            "Old oversized files bypassed the cap");

        const auto size = std::filesystem::file_size(log);
        Session(0, 0); Trace("manual disable");
        Check(std::filesystem::file_size(log) == size, "Disabled diagnostics appended to existing log");
        Session(now - kDuration, now); Trace("expired session");
        Check(std::filesystem::file_size(log) == size, "Expired diagnostics appended to existing log");
        std::filesystem::remove(log);
        std::filesystem::remove(DiagnosticSettingsPath());
        std::filesystem::remove(directory);
        std::cout << "Runtime diagnostics default-off, three-day deadline and 20 MiB cap passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}

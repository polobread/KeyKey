#include "Diagnostics.h"

#include <Windows.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <iterator>
#include <chrono>
#include <mutex>
#include <string>
#include "FrontendSettings.h"

namespace KeyKey::WindowsTsf {
namespace {
std::mutex g_settingsMutex;
DiagnosticSession g_session;
std::chrono::steady_clock::time_point g_refreshed{};
constexpr LONGLONG kLogLimit = 10 * 1024 * 1024;

bool ReparsePoint(const std::wstring& path) {
    const DWORD attributes = GetFileAttributesW(path.c_str());
    return attributes != INVALID_FILE_ATTRIBUTES && (attributes & FILE_ATTRIBUTE_REPARSE_POINT);
}

void AppendBounded(const std::wstring& path, const char* line, DWORD length) {
    // Serialize x64/x86 hosts sharing the same Temp directory. Never block
    // typing behind another process's diagnostic write: a busy log may skip.
    std::uint64_t hash = 14695981039346656037ULL;
    for (const wchar_t character : path) { hash ^= character; hash *= 1099511628211ULL; }
    const auto name = L"Local\\chichi77.KeyKey.Diagnostics." + std::to_wstring(hash);
    HANDLE mutex = CreateMutexW(nullptr, FALSE, name.c_str());
    if (!mutex) return;
    const DWORD locked = WaitForSingleObject(mutex, 0);
    if (locked != WAIT_OBJECT_0 && locked != WAIT_ABANDONED) { CloseHandle(mutex); return; }
    const auto backup = path + L".1";
    HANDLE file = INVALID_HANDLE_VALUE;
    if (!ReparsePoint(path) && !ReparsePoint(backup)) {
        file = CreateFileW(path.c_str(), FILE_APPEND_DATA | FILE_READ_ATTRIBUTES,
            FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
            OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        LARGE_INTEGER size{};
        if (file != INVALID_HANDLE_VALUE && !GetFileSizeEx(file, &size)) {
            CloseHandle(file); file = INVALID_HANDLE_VALUE;
        }
        if (file != INVALID_HANDLE_VALUE &&
            size.QuadPart + length > kLogLimit) {
            CloseHandle(file); file = INVALID_HANDLE_VALUE;
            // An oversized log from an older build must not become an
            // oversized backup. Ordinary rotation retains at most one file.
            const bool rotated = size.QuadPart > kLogLimit
                ? DeleteFileW(path.c_str()) != FALSE
                : MoveFileExW(path.c_str(), backup.c_str(), MOVEFILE_REPLACE_EXISTING) != FALSE;
            if (rotated) file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
                FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr,
                OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
        }
        // Enforce the same cap on a backup left by an older build.
        WIN32_FILE_ATTRIBUTE_DATA attributes{};
        if (GetFileAttributesExW(backup.c_str(), GetFileExInfoStandard, &attributes) &&
            (attributes.nFileSizeHigh || attributes.nFileSizeLow > kLogLimit)) DeleteFileW(backup.c_str());
        if (file != INVALID_HANDLE_VALUE) {
            DWORD written = 0;
            WriteFile(file, line, length, &written, nullptr);
            CloseHandle(file);
        }
    }
    ReleaseMutex(mutex); CloseHandle(mutex);
}
}  // namespace

void RefreshDiagnosticsSettings() {
    std::lock_guard<std::mutex> lock(g_settingsMutex);
    g_session = LoadDiagnosticSession();
    g_refreshed = std::chrono::steady_clock::now();
}

bool DiagnosticsEnabled() {
    std::lock_guard<std::mutex> lock(g_settingsMutex);
    const auto steadyNow = std::chrono::steady_clock::now();
    if (steadyNow - g_refreshed >= std::chrono::seconds(1)) {
        g_session = LoadDiagnosticSession();
        g_refreshed = steadyNow;
    }
    const auto now = std::chrono::duration_cast<std::chrono::seconds>(
        std::chrono::system_clock::now().time_since_epoch()).count();
    return g_session.activeAt(now);
}

void Trace(const char* format, ...) {
    if (!DiagnosticsEnabled()) return;
    char message[1024]{};
    va_list arguments;
    va_start(arguments, format);
    const int messageLength = vsnprintf(message, sizeof(message), format, arguments);
    va_end(arguments);
    if (messageLength <= 0) return;

    SYSTEMTIME now{};
    GetLocalTime(&now);
    char line[1200]{};
    const int lineLength = snprintf(
        line, sizeof(line), "%04u-%02u-%02u %02u:%02u:%02u.%03u pid=%lu tid=%lu %.*s\r\n",
        now.wYear, now.wMonth, now.wDay,
        now.wHour, now.wMinute, now.wSecond, now.wMilliseconds,
        GetCurrentProcessId(), GetCurrentThreadId(),
        std::min(messageLength, static_cast<int>(sizeof(message) - 1)), message);
    if (lineLength <= 0) return;

    wchar_t path[MAX_PATH]{};
    const DWORD pathLength = GetTempPathW(static_cast<DWORD>(std::size(path)), path);
    constexpr wchar_t fileName[] = L"KeyKeyTsf.log";
    if (!pathLength || pathLength >= std::size(path) ||
        pathLength + std::size(fileName) > std::size(path)) {
        return;
    }
    wcscat_s(path, fileName);

    AppendBounded(path, line, static_cast<DWORD>(
        std::min(lineLength, static_cast<int>(sizeof(line) - 1))));
}

}  // namespace KeyKey::WindowsTsf

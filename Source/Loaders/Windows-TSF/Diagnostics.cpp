#include "Diagnostics.h"

#include <Windows.h>

#include <algorithm>
#include <cstdarg>
#include <cstdio>
#include <iterator>

namespace KeyKey::WindowsTsf {

void Trace(const char* format, ...) {
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
        line, sizeof(line), "%02u:%02u:%02u.%03u pid=%lu tid=%lu %.*s\r\n",
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

    HANDLE file = CreateFileW(path, FILE_APPEND_DATA,
                              FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE,
                              nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE) return;
    DWORD written = 0;
    WriteFile(file, line,
              static_cast<DWORD>(std::min(lineLength,
                                          static_cast<int>(sizeof(line) - 1))),
              &written, nullptr);
    CloseHandle(file);
}

}  // namespace KeyKey::WindowsTsf

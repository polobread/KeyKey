#pragma once
#include <Windows.h>
#include <atomic>
#include <cstdint>
#include <string>

namespace KeyKey::WindowsTsf {
// The C++ frontend and C# settings app use the same UTF-16 FNV-1a lock name.
inline std::wstring SettingsLockName(const std::wstring& path) {
    wchar_t absolute[32768]{};
    const DWORD length=GetFullPathNameW(path.c_str(),32768,absolute,nullptr);
    if (!length || length>=32768) return {};
    std::uint64_t hash=14695981039346656037ULL;
    for (DWORD i=0;i<length;++i) {
        wchar_t value=absolute[i];
        if (value==L'/') value=L'\\';
        if (value>=L'A' && value<=L'Z') value+=L'a'-L'A';
        hash^=static_cast<std::uint16_t>(value); hash*=1099511628211ULL;
    }
    return L"Local\\chichi77.KeyKey.Settings."+std::to_wstring(hash);
}
class SettingsFileLock final {
public:
    explicit SettingsFileLock(const std::wstring& path,DWORD timeout=250) {
        const auto name=SettingsLockName(path);
        if (name.empty()) return;
        handle_=CreateMutexW(nullptr,FALSE,name.c_str());
        if (!handle_) return;
        const DWORD result=WaitForSingleObject(handle_,timeout);
        locked_=result==WAIT_OBJECT_0 || result==WAIT_ABANDONED;
    }
    ~SettingsFileLock() { if (locked_) ReleaseMutex(handle_); if (handle_) CloseHandle(handle_); }
    SettingsFileLock(const SettingsFileLock&)=delete;
    SettingsFileLock& operator=(const SettingsFileLock&)=delete;
    explicit operator bool() const { return locked_; }
private:
    HANDLE handle_=nullptr;
    bool locked_=false;
};
inline bool ReadSharedSettingsFile(const std::wstring& path,std::string& text) {
    text.clear();
    HANDLE file=CreateFileW(path.c_str(),GENERIC_READ,FILE_SHARE_READ|FILE_SHARE_WRITE|FILE_SHARE_DELETE,
        nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
    if (file==INVALID_HANDLE_VALUE) return false;
    LARGE_INTEGER size{};
    bool ok=GetFileSizeEx(file,&size) && size.QuadPart>=0 && size.QuadPart<=16*1024*1024;
    if (ok) {
        text.resize(static_cast<size_t>(size.QuadPart));
        DWORD read=0;
        ok=ReadFile(file,text.data(),static_cast<DWORD>(text.size()),&read,nullptr) && read==text.size();
    }
    CloseHandle(file);
    if (!ok) { text.clear(); SetLastError(ERROR_READ_FAULT); }
    return ok;
}
// Caller holds SettingsFileLock across reading, merging and replacing the file.
inline bool WriteSharedSettingsFile(const std::wstring& path,const std::string& text) {
    static std::atomic<unsigned> sequence{0};
    const auto temporary=path+L".tmp."+std::to_wstring(GetCurrentProcessId())+L"."+std::to_wstring(++sequence);
    HANDLE file=CreateFileW(temporary.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
    if (file==INVALID_HANDLE_VALUE) return false;
    DWORD written=0;
    bool ok=WriteFile(file,text.data(),static_cast<DWORD>(text.size()),&written,nullptr) && written==text.size();
    WIN32_FILE_ATTRIBUTE_DATA previous{};
    FILETIME now{}; GetSystemTimeAsFileTime(&now);
    ULARGE_INTEGER timestamp{}; timestamp.LowPart=now.dwLowDateTime; timestamp.HighPart=now.dwHighDateTime;
    if (GetFileAttributesExW(path.c_str(),GetFileExInfoStandard,&previous)) {
        ULARGE_INTEGER old{}; old.LowPart=previous.ftLastWriteTime.dwLowDateTime; old.HighPart=previous.ftLastWriteTime.dwHighDateTime;
        if (timestamp.QuadPart<=old.QuadPart+10000000ULL) timestamp.QuadPart=old.QuadPart+10000000ULL;
    }
    now={timestamp.LowPart,timestamp.HighPart};
    ok=ok && SetFileTime(file,nullptr,nullptr,&now) && FlushFileBuffers(file);
    CloseHandle(file);
    if (ok) ok=MoveFileExW(temporary.c_str(),path.c_str(),MOVEFILE_REPLACE_EXISTING|MOVEFILE_WRITE_THROUGH)!=FALSE;
    if (!ok) DeleteFileW(temporary.c_str());
    return ok;
}
}

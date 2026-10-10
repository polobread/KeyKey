#pragma once

#include <Windows.h>

#include <atomic>

namespace KeyKey::WindowsTsf {

extern HMODULE g_module;
extern std::atomic<long> g_objectCount;
extern std::atomic<long> g_serverLocks;

// A base outlives all derived members, including engine sessions and HWNDs.
class ModuleObjectLifetime {
protected:
    ModuleObjectLifetime() { ++g_objectCount; }
    ~ModuleObjectLifetime() { --g_objectCount; }
    ModuleObjectLifetime(const ModuleObjectLifetime&) = delete;
    ModuleObjectLifetime& operator=(const ModuleObjectLifetime&) = delete;
};

}  // namespace KeyKey::WindowsTsf

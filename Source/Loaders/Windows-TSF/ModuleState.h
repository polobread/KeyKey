#pragma once

#include <Windows.h>

#include <atomic>

namespace KeyKey::WindowsTsf {

extern HMODULE g_module;
extern std::atomic<long> g_objectCount;
extern std::atomic<long> g_serverLocks;

}  // namespace KeyKey::WindowsTsf

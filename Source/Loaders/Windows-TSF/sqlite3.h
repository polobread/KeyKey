#pragma once

// The dual-core build uses Cargo.lock's bundled SQLite for both native cores.
// In particular, WinSQLite uses stdcall on x86 while Rust expects cdecl.
// The header is copied from the locked dependency, never from the old SQLite
// snapshot under Source/ExternalLibraries/sqlite.
#if KEYKEY_ENABLE_GUANYINMA
#include <guanyinma_sqlite3.h>
#elif __has_include(<winsqlite3.h>)
#include <winsqlite3.h>
#elif __has_include(<winsqlite/winsqlite3.h>)
#include <winsqlite/winsqlite3.h>
#else
#error The Windows SDK WinSQLite header is required.
#endif

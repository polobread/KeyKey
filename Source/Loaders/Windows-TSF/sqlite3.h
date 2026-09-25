#pragma once

// The OpenVanilla and Manjusri code includes <sqlite3.h>. On Windows, resolve
// that include to the Windows SDK's system SQLite instead of the legacy copy
// under Source/ExternalLibraries/sqlite.
#if __has_include(<winsqlite3.h>)
#include <winsqlite3.h>
#elif __has_include(<winsqlite/winsqlite3.h>)
#include <winsqlite/winsqlite3.h>
#else
#error The Windows SDK WinSQLite header is required.
#endif

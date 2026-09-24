#pragma once

// The OpenVanilla and Manjusri code includes <sqlite3.h>. On Windows, resolve
// that include to the Windows SDK's system SQLite instead of the legacy copy
// under Source/ExternalLibraries/sqlite.
#include <winsqlite3.h>

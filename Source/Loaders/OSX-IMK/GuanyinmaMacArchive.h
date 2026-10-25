/*
 * Portable user-data and legacy MJSR archive transfer for the macOS frontend.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#ifndef GUANYINMA_MAC_ARCHIVE_H
#define GUANYINMA_MAC_ARCHIVE_H

#import <Foundation/Foundation.h>

// Reads only the explicitly named archive. JSON is validated from its original
// bytes by the core before Foundation decoding. MJSR text and its complete
// optional learning database are decoded before returning a portable archive.
// A missing MJSR learning section preserves existing learning (smart = null).
// The returned dictionary is autoreleased; NULL/nil means no data was imported.
NSDictionary* GuanyinmaReadArchive(NSString* path, NSError** error);

// Writes a complete portable JSON backup through a private same-directory
// temporary file and atomic rename. Both Smart and table learning domains must
// be present and non-null. The caller names model/user/source paths that must
// never be replaced, including their -journal/-wal/-shm paths and aliases.
// Partial archives are accepted only by the reader/importer.
// Existing SQLite files, symlinks and nonregular destinations are also refused.
bool GuanyinmaWriteArchive(NSString* path, NSDictionary* archive,
    NSArray* protectedPaths, NSError** error);

#endif

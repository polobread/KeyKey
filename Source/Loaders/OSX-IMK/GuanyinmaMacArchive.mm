/*
 * Portable user-data and legacy MJSR archive transfer for the macOS frontend.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 *
 * MJSR 1.0.0 compatibility follows BPMFUserPhraseHelper (Yahoo! Inc., 2012,
 * BSD 3-Clause). The new parser validates all domains before any core mutation.
 */
#include "GuanyinmaMacArchive.h"

#ifndef KEYKEY_ENABLE_GUANYINMA
#define KEYKEY_ENABLE_GUANYINMA 0
#endif

#if KEYKEY_ENABLE_GUANYINMA
#include "../../Guanyinma/include/guanyinma.h"
#include "GuanyinmaMacReadingCodec.h"
#include <sqlite3.h>
#include <algorithm>
#include <cerrno>
#include <cstring>
#include <cstdlib>
#include <cmath>
#include <fcntl.h>
#include <locale.h>
#include <string>
#include <sys/stat.h>
#include <unistd.h>
#include <vector>

namespace {

const NSUInteger MaximumArchiveBytes = 64 * 1024 * 1024;
const NSUInteger MaximumDatabaseBytes = 32 * 1024 * 1024;
NSString* const ArchiveErrorDomain = @"GuanyinmaArchiveError";

static bool Fail(NSError** error, NSString* message, NSInteger code = 1)
{
    if (error) *error = [NSError errorWithDomain:ArchiveErrorDomain code:code
        userInfo:[NSDictionary dictionaryWithObject:message forKey:NSLocalizedDescriptionKey]];
    return false;
}

static std::string UTF8(NSString* string)
{
    NSData* data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return data ? std::string(static_cast<const char*>([data bytes]), [data length]) : std::string();
}

static NSString* String(const char* bytes, size_t length)
{
    return [[[NSString alloc] initWithBytes:bytes length:length encoding:NSUTF8StringEncoding] autorelease];
}

static NSString* CoreError()
{
    size_t required = 0;
    if (guanyinma_last_error(NULL, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL || !required)
        return @"Invalid Guanyinma user-data archive";
    std::vector<uint8_t> data(required);
    if (guanyinma_last_error(&data[0], data.size(), &required) != GUANYINMA_OK)
        return @"Invalid Guanyinma user-data archive";
    NSString* message = String(reinterpret_cast<const char*>(&data[0]), required - 1);
    return [message length] ? message : @"Invalid Guanyinma user-data archive";
}

static bool ValidateData(NSData* data, NSError** error)
{
    if (!data || [data length] > MaximumArchiveBytes)
        return Fail(error, @"The user-data archive is too large or unavailable");
    if (guanyinma_user_archive_validate(static_cast<const uint8_t*>([data bytes]),
        [data length]) != GUANYINMA_OK)
        return Fail(error, CoreError(), 2);
    return true;
}

static bool ValidPath(NSString* path, NSError** error)
{
    if (![path isKindOfClass:[NSString class]] || ![path length] || ![path isAbsolutePath] ||
        [path rangeOfCharacterFromSet:[NSCharacterSet characterSetWithRange:NSMakeRange(0, 1)]].location != NSNotFound ||
        ![path dataUsingEncoding:NSUTF8StringEncoding] || ![path fileSystemRepresentation])
        return Fail(error, @"An absolute, valid UTF-8 archive path is required");
    return true;
}

static bool ParseNumber(NSString* text, double* result)
{
    std::string bytes = UTF8(text);
    if (bytes.empty() || bytes.find('\0') != std::string::npos) return false;
    // Native SQLite exports decimal/scientific scores. strtod_l also accepts
    // hexadecimal floats; those are not the numeric format used by MJSR or
    // the core's legacy f64 parser.
    size_t index = (bytes[0] == '+' || bytes[0] == '-') ? 1 : 0;
    bool digits = false;
    while (index < bytes.size() && bytes[index] >= '0' && bytes[index] <= '9') {
        digits = true; ++index;
    }
    if (index < bytes.size() && bytes[index] == '.') {
        ++index;
        while (index < bytes.size() && bytes[index] >= '0' && bytes[index] <= '9') {
            digits = true; ++index;
        }
    }
    if (!digits) return false;
    if (index < bytes.size() && (bytes[index] == 'e' || bytes[index] == 'E')) {
        ++index;
        if (index < bytes.size() && (bytes[index] == '+' || bytes[index] == '-')) ++index;
        size_t exponent = index;
        while (index < bytes.size() && bytes[index] >= '0' && bytes[index] <= '9') ++index;
        if (index == exponent) return false;
    }
    if (index != bytes.size()) return false;
    locale_t locale = newlocale(LC_NUMERIC_MASK, "C", NULL);
    if (!locale) return false;
    char* end = NULL;
    errno = 0;
    double number = strtod_l(bytes.c_str(), &end, locale);
    freelocale(locale);
    if (end == bytes.c_str() || end != bytes.c_str() + bytes.size() || !std::isfinite(number))
        return false;
    *result = number;
    return true;
}

static NSArray* Fields(NSString* line)
{
    NSMutableArray* fields = [NSMutableArray array];
    for (NSString* field in [line componentsSeparatedByCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]])
        if ([field length]) [fields addObject:field];
    return fields;
}

static bool WriteBytes(int descriptor, NSData* data)
{
    const uint8_t* bytes = static_cast<const uint8_t*>([data bytes]);
    size_t left = [data length];
    while (left) {
        ssize_t written = write(descriptor, bytes, left);
        if (written < 0 && errno == EINTR) continue;
        if (written <= 0) return false;
        bytes += written;
        left -= static_cast<size_t>(written);
    }
    return true;
}

struct TemporaryDatabase {
    std::string directory;
    std::string path;
    ~TemporaryDatabase()
    {
        if (!path.empty()) {
            unlink(path.c_str());
            unlink((path + "-journal").c_str());
            unlink((path + "-wal").c_str());
            unlink((path + "-shm").c_str());
        }
        if (!directory.empty()) rmdir(directory.c_str());
    }
    bool create(NSData* data, NSError** error)
    {
        NSString* pattern = [NSTemporaryDirectory() stringByAppendingPathComponent:
            @"keykey-guanyinma-archive-XXXXXX"];
        std::string bytes = UTF8(pattern);
        std::vector<char> name(bytes.begin(), bytes.end());
        name.push_back(0);
        if (!mkdtemp(&name[0])) return Fail(error, @"Cannot create a private archive decoding directory");
        directory = &name[0];
        path = directory + "/learning.db";
        int file = open(path.c_str(), O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
        if (file < 0) return Fail(error, @"Cannot create a private archive decoding file");
        bool ok = WriteBytes(file, data);
        if (close(file) != 0) ok = false;
        return ok ? true : Fail(error, @"Cannot write the private archive decoding file");
    }
};

struct SQLiteConnection {
    sqlite3* value;
    SQLiteConnection() : value(NULL) {}
    ~SQLiteConnection() { if (value) sqlite3_close(value); }
};

struct SQLiteStatement {
    sqlite3_stmt* value;
    SQLiteStatement() : value(NULL) {}
    ~SQLiteStatement() { if (value) sqlite3_finalize(value); }
};

static bool SQLiteFailure(NSError** error, sqlite3* database, NSString* context)
{
    NSString* reason = database ? String(sqlite3_errmsg(database), strlen(sqlite3_errmsg(database))) : nil;
    return Fail(error, reason ? [NSString stringWithFormat:@"%@: %@", context, reason] : context, 3);
}

static NSString* ColumnText(sqlite3_stmt* statement, int column)
{
    if (sqlite3_column_type(statement, column) != SQLITE_TEXT) return nil;
    const unsigned char* data = sqlite3_column_text(statement, column);
    return data ? String(reinterpret_cast<const char*>(data), sqlite3_column_bytes(statement, column)) : nil;
}

static bool ColumnNumber(sqlite3_stmt* statement, int column, double* result)
{
    int type = sqlite3_column_type(statement, column);
    if (type == SQLITE_INTEGER || type == SQLITE_FLOAT) {
        *result = sqlite3_column_double(statement, column);
        return std::isfinite(*result);
    }
    return type == SQLITE_TEXT && ParseNumber(ColumnText(statement, column), result);
}

static bool CheckColumns(sqlite3* database, const char* query, NSArray* expected, NSError** error)
{
    SQLiteStatement statement;
    if (sqlite3_prepare_v2(database, query, -1, &statement.value, NULL) != SQLITE_OK)
        return SQLiteFailure(error, database, @"Cannot inspect MJSR learning columns");
    NSMutableArray* names = [NSMutableArray array];
    int status;
    while ((status = sqlite3_step(statement.value)) == SQLITE_ROW) {
        NSString* name = ColumnText(statement.value, 1);
        if (!name) return Fail(error, @"Invalid MJSR learning column name");
        [names addObject:name];
    }
    if (status != SQLITE_DONE || ![names isEqualToArray:expected])
        return Fail(error, @"The MJSR learning database has an unsupported schema");
    return true;
}

static NSDictionary* ReadLearning(NSData* bytes, NSError** error)
{
    if (![bytes length] || [bytes length] > MaximumDatabaseBytes) {
        Fail(error, @"Invalid MJSR learning database size");
        return nil;
    }
    TemporaryDatabase temporary;
    if (!temporary.create(bytes, error)) return nil;
    SQLiteConnection connection;
    if (sqlite3_open_v2(":memory:", &connection.value,
        SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE | SQLITE_OPEN_URI, NULL) != SQLITE_OK) {
        SQLiteFailure(error, connection.value, @"Cannot open the archive decoder");
        return nil;
    }
    sqlite3_busy_timeout(connection.value, 1000);
#ifdef SQLITE_DBCONFIG_DEFENSIVE
    sqlite3_db_config(connection.value, SQLITE_DBCONFIG_DEFENSIVE, 1, NULL);
#endif
#ifdef SQLITE_DBCONFIG_TRUSTED_SCHEMA
    sqlite3_db_config(connection.value, SQLITE_DBCONFIG_TRUSTED_SCHEMA, 0, NULL);
#endif
    NSString* filePath = String(temporary.path.data(), temporary.path.size());
    NSString* uri = [[[NSURL fileURLWithPath:filePath] absoluteString] stringByAppendingString:@"?mode=ro&immutable=1"];
    bool plain = [bytes length] >= 16 && !memcmp([bytes bytes], "SQLite format 3\0", 16);
    SQLiteStatement attach;
    const char* attachSQL = plain ? "ATTACH DATABASE ? AS cache" :
        "ATTACH DATABASE ? AS cache KEY 'mjsrexport'";
    if (sqlite3_prepare_v2(connection.value, attachSQL, -1, &attach.value, NULL) != SQLITE_OK ||
        sqlite3_bind_text(attach.value, 1, [uri UTF8String], -1, SQLITE_TRANSIENT) != SQLITE_OK ||
        sqlite3_step(attach.value) != SQLITE_DONE ||
        sqlite3_db_readonly(connection.value, "cache") != 1) {
        SQLiteFailure(error, connection.value,
            @"Cannot decode the MJSR learning database with this SQLite provider");
        return nil;
    }
    SQLiteStatement integrity;
    if (sqlite3_prepare_v2(connection.value, "PRAGMA cache.integrity_check(1)", -1,
        &integrity.value, NULL) != SQLITE_OK || sqlite3_step(integrity.value) != SQLITE_ROW ||
        ![ColumnText(integrity.value, 0) isEqualToString:@"ok"] ||
        sqlite3_step(integrity.value) != SQLITE_DONE) {
        Fail(error, @"The MJSR learning database is damaged");
        return nil;
    }
    SQLiteStatement schema;
    if (sqlite3_prepare_v2(connection.value,
        "SELECT name,type FROM cache.sqlite_master ORDER BY rowid", -1, &schema.value, NULL) != SQLITE_OK) {
        SQLiteFailure(error, connection.value, @"Cannot inspect the MJSR learning database");
        return nil;
    }
    NSMutableSet* tables = [NSMutableSet set];
    int status;
    while ((status = sqlite3_step(schema.value)) == SQLITE_ROW) {
        NSString* name = ColumnText(schema.value, 0);
        NSString* type = ColumnText(schema.value, 1);
        if (![type isEqualToString:@"table"] ||
            !([name isEqualToString:@"user_bigram_cache"] ||
              [name isEqualToString:@"user_candidate_override_cache"])) {
            Fail(error, @"The MJSR learning database contains unsupported objects");
            return nil;
        }
        [tables addObject:name];
    }
    if (status != SQLITE_DONE || [tables count] != 2 ||
        !CheckColumns(connection.value, "PRAGMA cache.table_info(user_bigram_cache)",
            [NSArray arrayWithObjects:@"qstring", @"previous", @"current", @"probability", nil], error) ||
        !CheckColumns(connection.value, "PRAGMA cache.table_info(user_candidate_override_cache)",
            [NSArray arrayWithObjects:@"qstring", @"current", nil], error)) {
        if (error && !*error) Fail(error, @"The MJSR learning database is incomplete");
        return nil;
    }
    NSMutableArray* bigrams = [NSMutableArray array];
    SQLiteStatement bigramRows;
    if (sqlite3_prepare_v2(connection.value,
        "SELECT qstring,previous,current,probability FROM cache.user_bigram_cache ORDER BY rowid",
        -1, &bigramRows.value, NULL) != SQLITE_OK) {
        SQLiteFailure(error, connection.value, @"Cannot read MJSR Bigram learning");
        return nil;
    }
    while ((status = sqlite3_step(bigramRows.value)) == SQLITE_ROW) {
        NSString* query = ColumnText(bigramRows.value, 0);
        NSString* previous = ColumnText(bigramRows.value, 1);
        NSString* current = ColumnText(bigramRows.value, 2);
        double probability;
        if (!query || !previous || !current || !ColumnNumber(bigramRows.value, 3, &probability) ||
            [bigrams count] >= 200) {
            Fail(error, @"Invalid MJSR Bigram learning row");
            return nil;
        }
        [bigrams addObject:[NSDictionary dictionaryWithObjectsAndKeys:query, @"qstring",
            previous, @"previous", current, @"current",
            [NSNumber numberWithDouble:probability], @"probability", nil]];
    }
    if (status != SQLITE_DONE) {
        SQLiteFailure(error, connection.value, @"Cannot finish reading MJSR Bigram learning");
        return nil;
    }
    NSMutableArray* overrides = [NSMutableArray array];
    SQLiteStatement overrideRows;
    if (sqlite3_prepare_v2(connection.value,
        "SELECT qstring,current FROM cache.user_candidate_override_cache ORDER BY rowid",
        -1, &overrideRows.value, NULL) != SQLITE_OK) {
        SQLiteFailure(error, connection.value, @"Cannot read MJSR candidate learning");
        return nil;
    }
    while ((status = sqlite3_step(overrideRows.value)) == SQLITE_ROW) {
        NSString* query = ColumnText(overrideRows.value, 0);
        NSString* current = ColumnText(overrideRows.value, 1);
        if (!query || !current || [overrides count] >= 200) {
            Fail(error, @"Invalid MJSR candidate learning row");
            return nil;
        }
        [overrides addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            query, @"qstring", current, @"current", nil]];
    }
    if (status != SQLITE_DONE) {
        SQLiteFailure(error, connection.value, @"Cannot finish reading MJSR candidate learning");
        return nil;
    }
    return [NSDictionary dictionaryWithObjectsAndKeys:
        overrides, @"overrides", bigrams, @"bigrams", nil];
}

static int HexValue(unichar value)
{
    if (value >= '0' && value <= '9') return value - '0';
    if (value >= 'a' && value <= 'f') return value - 'a' + 10;
    if (value >= 'A' && value <= 'F') return value - 'A' + 10;
    return -1;
}

static NSDictionary* ReadMJSR(NSData* bytes, NSError** error)
{
    NSString* text = [[[NSString alloc] initWithData:bytes encoding:NSUTF8StringEncoding] autorelease];
    if (!text) { Fail(error, @"MJSR archives must use valid UTF-8"); return nil; }
    text = [[text stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"]
        stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
    if ([text hasPrefix:@"\uFEFF"]) text = [text substringFromIndex:1];
    NSArray* lines = [text componentsSeparatedByString:@"\n"];
    if (![lines count] || ![[[lines objectAtIndex:0] stringByTrimmingCharactersInSet:
        [NSCharacterSet whitespaceCharacterSet]] isEqualToString:@"MJSR version 1.0.0"]) {
        Fail(error, @"Unsupported user-data archive format");
        return nil;
    }
    NSMutableArray* phrases = [NSMutableArray array];
    NSMutableData* database = [NSMutableData data];
    bool inDatabase = false, foundDatabase = false, endedDatabase = false;
    int highNibble = -1;
    for (NSUInteger index = 1; index < [lines count]; ++index) {
        NSString* line = [[lines objectAtIndex:index] stringByTrimmingCharactersInSet:
            [NSCharacterSet whitespaceCharacterSet]];
        if (![line length]) continue;
        if ([line isEqualToString:@"<database>"]) {
            if (foundDatabase || endedDatabase) { Fail(error, @"Repeated MJSR learning section"); return nil; }
            inDatabase = foundDatabase = true;
            continue;
        }
        if ([line isEqualToString:@"</database>"]) {
            if (!inDatabase || highNibble >= 0) { Fail(error, @"Invalid MJSR learning section"); return nil; }
            inDatabase = false;
            endedDatabase = true;
            continue;
        }
        if (inDatabase) {
            for (NSUInteger i = 0; i < [line length]; ++i) {
                unichar value = [line characterAtIndex:i];
                if ([[NSCharacterSet whitespaceCharacterSet] characterIsMember:value]) continue;
                int nibble = HexValue(value);
                if (nibble < 0) { Fail(error, @"Invalid hexadecimal MJSR learning data"); return nil; }
                if (highNibble < 0) highNibble = nibble;
                else {
                    uint8_t byte = static_cast<uint8_t>((highNibble << 4) | nibble);
                    [database appendBytes:&byte length:1];
                    highNibble = -1;
                    if ([database length] > MaximumDatabaseBytes) {
                        Fail(error, @"The MJSR learning database is too large"); return nil;
                    }
                }
            }
            continue;
        }
        if ([line hasPrefix:@"#"]) continue;
        if (endedDatabase) { Fail(error, @"Unexpected data after the MJSR learning section"); return nil; }
        NSArray* fields = Fields(line);
        if ([fields count] != 4) { Fail(error, @"Invalid MJSR custom-word row"); return nil; }
        std::string reading = UTF8([fields objectAtIndex:1]);
        std::pair<std::string, size_t> query;
        const NSUInteger textLength = [[fields objectAtIndex:0]
            lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4;
        if (!GuanyinmaMacEncodeReading(reading, query.first, query.second) || !query.second ||
            GuanyinmaMacDecodeReading(query.first) != reading || query.second != textLength) {
            Fail(error, @"Invalid MJSR custom-word reading"); return nil;
        }
        double probability, backoff;
        if (!ParseNumber([fields objectAtIndex:2], &probability) ||
            !ParseNumber([fields objectAtIndex:3], &backoff)) {
            Fail(error, @"Invalid numeric MJSR custom-word score"); return nil;
        }
        NSString* queryString = String(query.first.data(), query.first.size());
        [phrases addObject:[NSDictionary dictionaryWithObjectsAndKeys:
            queryString, @"qstring", [fields objectAtIndex:0], @"current",
            [NSNumber numberWithDouble:probability], @"probability",
            [NSNumber numberWithDouble:backoff], @"backoff", nil]];
    }
    if (inDatabase || (foundDatabase && (!endedDatabase || highNibble >= 0 || ![database length]))) {
        Fail(error, @"Truncated MJSR learning section"); return nil;
    }
    NSDictionary* smart = foundDatabase ? ReadLearning(database, error) : nil;
    if (foundDatabase && !smart) return nil;
    NSDictionary* archive = [NSDictionary dictionaryWithObjectsAndKeys:
        @"guanyinma_user_data", @"format", [NSNumber numberWithInt:1], @"schema_version",
        phrases, @"phrases", smart ? static_cast<id>(smart) : static_cast<id>([NSNull null]), @"smart",
        [NSNull null], @"table", nil];
    NSData* json = [NSJSONSerialization dataWithJSONObject:archive options:0 error:error];
    return ValidateData(json, error) ? archive : nil;
}

static NSData* ReadFileBounded(NSString* path, NSError** error)
{
    int file = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (file < 0) {
        Fail(error, @"Cannot open the selected archive as a regular file");
        return nil;
    }
    struct stat attributes;
    if (fstat(file, &attributes) != 0 || !S_ISREG(attributes.st_mode) ||
        attributes.st_size < 0 || static_cast<unsigned long long>(attributes.st_size) > MaximumArchiveBytes) {
        close(file);
        Fail(error, @"The archive must be a regular file of at most 64 MiB");
        return nil;
    }
    NSMutableData* bytes = [NSMutableData dataWithCapacity:static_cast<NSUInteger>(attributes.st_size)];
    uint8_t block[64 * 1024];
    while (true) {
        size_t remaining = MaximumArchiveBytes - [bytes length];
        size_t request = std::min(sizeof(block), remaining + 1);
        ssize_t count = read(file, block, request);
        if (count < 0 && errno == EINTR) continue;
        if (count < 0) {
            close(file);
            Fail(error, @"Cannot read the selected archive");
            return nil;
        }
        if (!count) break;
        if (static_cast<size_t>(count) > remaining) {
            close(file);
            Fail(error, @"The archive exceeds the 64 MiB size limit");
            return nil;
        }
        [bytes appendBytes:block length:static_cast<NSUInteger>(count)];
    }
    if (close(file) != 0) {
        Fail(error, @"Cannot finish reading the selected archive");
        return nil;
    }
    return bytes;
}

static NSString* ResolvedPath(NSString* path)
{
    return [[[NSURL fileURLWithPath:[path stringByStandardizingPath]]
        URLByResolvingSymlinksInPath] path];
}

static bool DestinationAllowed(NSString* path, NSArray* protectedPaths, NSError** error)
{
    struct stat target;
    bool exists = lstat([path fileSystemRepresentation], &target) == 0;
    if (!exists && errno != ENOENT) return Fail(error, @"Cannot inspect the archive destination");
    if (exists && !S_ISREG(target.st_mode))
        return Fail(error, @"The archive destination must be a regular file, not a symlink or directory");
    NSString* resolved = ResolvedPath(path);
    for (id entry in protectedPaths) {
        if (![entry isKindOfClass:[NSString class]])
            return Fail(error, @"Invalid protected archive path");
        if (!ValidPath(entry, error)) return false;
        // Journals and WAL state belong to the protected database as well.
        // Protect their names even when no sidecar currently exists.
        for (NSString* suffix in [NSArray arrayWithObjects:@"", @"-journal", @"-wal", @"-shm", nil]) {
            NSString* protectedPath = [entry stringByAppendingString:suffix];
            struct stat protectedFile;
            if ([resolved isEqualToString:ResolvedPath(protectedPath)] ||
                (exists && stat([protectedPath fileSystemRepresentation], &protectedFile) == 0 &&
                    target.st_dev == protectedFile.st_dev && target.st_ino == protectedFile.st_ino))
                return Fail(error, @"The archive destination aliases a protected database, sidecar or source file");
        }
    }
    if (exists) {
        int file = open([path fileSystemRepresentation], O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
        if (file < 0) return Fail(error, @"Cannot inspect the existing archive destination");
        char header[16] = {};
        ssize_t count;
        do { count = read(file, header, sizeof(header)); } while (count < 0 && errno == EINTR);
        close(file);
        if (count < 0) return Fail(error, @"Cannot inspect the existing archive destination");
        if (count == sizeof(header) && !memcmp(header, "SQLite format 3\0", sizeof(header)))
            return Fail(error, @"A SQLite database cannot be replaced by a user-data archive");
    }
    return true;
}

} // namespace

NSDictionary* GuanyinmaReadArchive(NSString* path, NSError** error)
{
    if (error) *error = nil;
    if (!ValidPath(path, error)) return nil;
    NSData* bytes = ReadFileBounded(path, error);
    if (!bytes) return nil;
    const uint8_t* data = static_cast<const uint8_t*>([bytes bytes]);
    size_t index = 0;
    while (index < [bytes length] && (data[index] == ' ' || data[index] == '\t' ||
        data[index] == '\r' || data[index] == '\n')) ++index;
    if (index < [bytes length] && data[index] == '{') {
        // Validate original bytes before Foundation folds duplicate object keys.
        if (!ValidateData(bytes, error)) return nil;
        id archive = [NSJSONSerialization JSONObjectWithData:bytes options:0 error:error];
        return [archive isKindOfClass:[NSDictionary class]] ? archive : nil;
    }
    return ReadMJSR(bytes, error);
}

bool GuanyinmaWriteArchive(NSString* path, NSDictionary* archive,
    NSArray* protectedPaths, NSError** error)
{
    if (error) *error = nil;
    if (!ValidPath(path, error) || ![archive isKindOfClass:[NSDictionary class]] ||
        (protectedPaths && ![protectedPaths isKindOfClass:[NSArray class]]))
        return Fail(error, @"Invalid user-data archive export arguments");
    if (![NSJSONSerialization isValidJSONObject:archive])
        return Fail(error, @"The user-data archive cannot be represented as JSON");
    NSData* bytes = [NSJSONSerialization dataWithJSONObject:archive
        options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:error];
    if (!ValidateData(bytes, error)) return false;
    if (![[archive objectForKey:@"smart"] isKindOfClass:[NSDictionary class]] ||
        ![[archive objectForKey:@"table"] isKindOfClass:[NSArray class]])
        return Fail(error, @"A complete backup requires both Smart and table learning data");
    if (!DestinationAllowed(path, protectedPaths, error)) return false;
    NSString* directory = [path stringByDeletingLastPathComponent];
    std::string pattern = UTF8([directory stringByAppendingPathComponent:@".GuanyinmaArchive-XXXXXX"]);
    std::vector<char> temporary(pattern.begin(), pattern.end());
    temporary.push_back(0);
    int file = mkstemp(&temporary[0]);
    if (file < 0) return Fail(error, @"Cannot create an archive file in the selected directory");
    bool ok = fchmod(file, 0600) == 0 && WriteBytes(file, bytes) && fsync(file) == 0;
    if (close(file) != 0) ok = false;
    if (ok) ok = DestinationAllowed(path, protectedPaths, error);
    if (ok && rename(&temporary[0], [path fileSystemRepresentation]) != 0) ok = false;
    if (!ok) {
        unlink(&temporary[0]);
        if (error && !*error) Fail(error, @"Cannot atomically replace the user-data archive");
        return false;
    }
    return true;
}

#else

NSDictionary* GuanyinmaReadArchive(NSString*, NSError** error)
{
    if (error) *error = [NSError errorWithDomain:@"GuanyinmaArchiveError" code:1
        userInfo:[NSDictionary dictionaryWithObject:@"Guanyinma is not enabled in this build"
            forKey:NSLocalizedDescriptionKey]];
    return nil;
}

bool GuanyinmaWriteArchive(NSString*, NSDictionary*, NSArray*, NSError** error)
{
    GuanyinmaReadArchive(nil, error);
    return false;
}

#endif

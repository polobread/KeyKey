// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Archive compatibility uses the actual legacy exporter and isolated files.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacArchive.h"
#include "GuanyinmaMacUserData.h"
#include "BPMFUserPhraseHelper.h"
#include "guanyinma.h"
#include <sqlite3.h>
#include <spawn.h>
#include <signal.h>
#include <sys/resource.h>
#include <sys/wait.h>
#include <sys/stat.h>
#include <unistd.h>
#include <cstring>
#include <set>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <memory>
#include <stdexcept>

using namespace OpenVanilla;
namespace fs = std::filesystem;
extern char** environ;
static size_t checks;
static std::string executable;
static void require(bool value, const std::string& message) {
    ++checks;
    if (!value) throw std::runtime_error(message);
}
static NSString* native(const fs::path& path) {
    auto bytes = path.u8string();
    return [[[NSString alloc] initWithBytes:bytes.data() length:bytes.size()
                                  encoding:NSUTF8StringEncoding] autorelease];
}
static NSData* bytes(const fs::path& path) { return [NSData dataWithContentsOfFile:native(path)]; }
static void write(const fs::path& path, NSData* data) {
    require([data writeToFile:native(path) atomically:YES], "write isolated fixture");
}
static NSData* encoded(id value) {
    return [NSJSONSerialization dataWithJSONObject:value options:0 error:NULL];
}
static NSDictionary* copyDictionary(NSDictionary* value) {
    return [NSJSONSerialization JSONObjectWithData:encoded(value) options:NSJSONReadingMutableContainers error:NULL];
}
static NSDictionary* fullArchive() {
    return @{
        @"format": @"guanyinma_user_data", @"schema_version": @1,
        @"phrases": @[@{@"qstring": @"0_0_", @"current": @"士事",
                         @"probability": @(-0.0000001), @"backoff": @(-3.0)}],
        @"smart": @{
            @"overrides": @[@{@"qstring": @"0_", @"current": @"事"}],
            @"bigrams": @[@{@"qstring": @"0_ \\O", @"previous": @"是", @"current": @"妳", @"probability": @0.0}]},
        @"table": @[
            @{@"method": @"cangjie", @"code": @"a", @"current": @"曰", @"count": @2},
            @{@"method": @"simplex", @"code": @"ab", @"current": @"晴", @"count": @1}]
    };
}
static bool importData(GuanyinmaMacUserData& store, NSDictionary* archive) {
    return store.apply(@{@"type": @"import_user_data", @"archive": archive});
}
static void sql(sqlite3* db, const char* text) {
    char* error = NULL;
    auto status = sqlite3_exec(db, text, NULL, NULL, &error);
    std::string message = error ? error : "";
    sqlite3_free(error);
    require(status == SQLITE_OK, "isolated SQLite operation: " + message);
}

class Session {
    GuanyinmaSession* session = NULL;
    static NSDictionary* decode(GuanyinmaResult* result) {
        size_t length = 0;
        require(guanyinma_result_json(result, NULL, 0, &length) == GUANYINMA_BUFFER_TOO_SMALL, "probe session JSON");
        std::vector<uint8_t> data(length);
        require(guanyinma_result_json(result, data.data(), data.size(), &length) == GUANYINMA_OK, "read session JSON");
        guanyinma_result_close(&result);
        id object = [NSJSONSerialization JSONObjectWithData:
            [NSData dataWithBytes:data.data() length:length - 1] options:0 error:NULL];
        require([object isKindOfClass:[NSDictionary class]], "session JSON dictionary");
        return object;
    }
public:
    Session(const fs::path& model, const fs::path& user, NSString* method = @"smart") {
        NSData* config = encoded(@{@"method": method, @"user_database": native(user),
            @"learning": @{@"user_phrases": @YES, @"candidate_overrides": @YES,
                             @"bigrams": @YES, @"table_learning": @YES}});
        auto path = model.u8string();
        require(guanyinma_session_open(reinterpret_cast<const uint8_t*>(path.data()), path.size(),
            reinterpret_cast<const uint8_t*>(config.bytes), config.length, &session) == GUANYINMA_OK, "open archive input session");
    }
    ~Session() { guanyinma_session_close(&session); }
    NSDictionary* apply(NSDictionary* operation) {
        NSData* json = encoded(operation);
        GuanyinmaResult* result = NULL;
        require(guanyinma_session_apply(session, reinterpret_cast<const uint8_t*>(json.bytes),
                                       json.length, &result) == GUANYINMA_OK, "apply archive input operation");
        return decode(result);
    }
    NSDictionary* type(const std::string& text) {
        NSDictionary* result = nil;
        for (char value : text) result = apply(@{@"type": @"character", @"text": [NSString stringWithFormat:@"%c", value]});
        return result;
    }
};

// Always generate compatibility input with the production legacy exporter.
// Its embedded cache may be encrypted by the macOS SQLite provider.
static fs::path legacyExport(const fs::path& root, bool invalidCache = false) {
    const auto source = root / (invalidCache ? "bad-cache-source.db" : "legacy-source.db");
    const auto archive = root / (invalidCache ? "bad-cache.mjsr" : "native.mjsr");
    std::unique_ptr<OVSQLiteConnection> db(OVSQLiteConnection::Open(source.u8string()));
    require(db != nullptr, "open isolated legacy source");
    require(db->execute("CREATE TABLE user_unigrams(qstring,current,probability,backoff)") == SQLITE_OK, "legacy phrase schema");
    require(db->execute("CREATE TABLE user_candidate_override_cache(qstring,current)") == SQLITE_OK, "legacy override schema");
    require(db->execute("CREATE TABLE user_bigram_cache(qstring,previous,current,probability)") == SQLITE_OK, "legacy Bigram schema");
    auto qi = Manjusri::BPMFUserPhraseHelper::QString("ㄑㄧˊ,ㄑㄧˊ").first;
    require(db->execute("INSERT INTO user_unigrams VALUES('0_0_','士事','-0.0000001','-3')") == SQLITE_OK,
            "legacy text score fixture");
    require(db->execute("INSERT INTO user_unigrams VALUES(%Q,'琦琦','-0.123456789012345','1e-12')", qi.c_str()) == SQLITE_OK,
            "legacy second custom phrase");
    require(db->execute(invalidCache ?
        "INSERT INTO user_candidate_override_cache VALUES('0_',x'FF')" :
        "INSERT INTO user_candidate_override_cache VALUES('0_','事')") == SQLITE_OK, "legacy candidate fixture");
    require(db->execute("INSERT INTO user_bigram_cache VALUES('0_ \\O','是','妳','0.0')") == SQLITE_OK, "legacy Bigram fixture");
    const auto before = bytes(source);
    require(Manjusri::BPMFUserPhraseHelper::Export(db.get(), archive.u8string()), "actual Manjusri exporter");
    require([bytes(source) isEqualToData:before], "actual exporter preserves legacy source bytes");
    require([bytes(archive) length] > 0, "actual exporter produced archive");
    return archive;
}

static void testNativeLegacyImport(const fs::path& model, const fs::path& root) {
    const auto path = legacyExport(root);
    const auto original = bytes(path);
    NSError* error = nil;
    NSDictionary* portable = GuanyinmaReadArchive(native(path), &error);
    require(portable != nil && !error, "new reader accepts real native MJSR export");
    require([[portable objectForKey:@"phrases"] count] == 2, "native phrase count preserved");
    NSDictionary* precise = [[portable objectForKey:@"phrases"] objectAtIndex:1];
    require([[precise objectForKey:@"probability"] doubleValue] == -0.123456789012345 &&
            [[precise objectForKey:@"backoff"] doubleValue] == 1e-12,
            "native numeric text preserves full precision and scientific notation");
    NSDictionary* smart = [portable objectForKey:@"smart"];
    require([[smart objectForKey:@"overrides"] count] == 1 && [[smart objectForKey:@"bigrams"] count] == 1,
            "real native embedded cache decoded completely");
    require(![portable objectForKey:@"table"] || [portable objectForKey:@"table"] == [NSNull null],
            "legacy Smart archive has no table-learning scope");
    GuanyinmaMacUserData store(model.u8string(), (root / "legacy-destination.db").u8string());
    require(store.valid(), "legacy destination Guanyinma store");
    NSMutableDictionary* seed = [copyDictionary(fullArchive()) mutableCopy];
    [[seed objectForKey:@"phrases"] objectAtIndex:0][@"probability"] = @(-9.0);
    [[seed objectForKey:@"smart"] objectForKey:@"overrides"][0][@"current"] = @"世";
    require(importData(store, seed), "seed independent phrases and method scopes");
    [seed release];
    auto before = store.data();
    require(store.importArchive(native(path), &error), "actual administration imports MJSR atomically");
    auto after = store.data();
    require([[after objectForKey:@"phrases"] count] == 2, "MJSR merges phrases");
    require([[[[after objectForKey:@"phrases"] objectAtIndex:0] objectForKey:@"probability"] doubleValue] == -9.0,
            "existing phrase score survives import collision");
    require([[after objectForKey:@"table"] isEqual:[before objectForKey:@"table"]], "MJSR preserves Cangjie and Simplex learning");
    require([[[after objectForKey:@"overrides"] objectAtIndex:0][@"current"] isEqualToString:@"事"],
            "MJSR replaces Smart preferences");
    require([[after objectForKey:@"generation"] longLongValue] > [[before objectForKey:@"generation"] longLongValue],
            "MJSR Smart replacement starts a new learning epoch");
    require([bytes(path) isEqualToData:original], "MJSR source remains unchanged");
    Session input(model, root / "legacy-destination.db");
    require([[input.type("g4") objectForKey:@"composition"] isEqualToString:@"事"], "imported preference drives a fresh input session");

    // A text-only file is a real export prefix with its database block removed.
    NSString* text = [[[NSString alloc] initWithData:original encoding:NSUTF8StringEncoding] autorelease];
    const auto crlf = root / "native-crlf.mjsr";
    write(crlf, [[text stringByReplacingOccurrencesOfString:@"\n" withString:@"\r\n"] dataUsingEncoding:NSUTF8StringEncoding]);
    error = nil;
    require([GuanyinmaReadArchive(native(crlf), &error) isEqualToDictionary:portable] && !error,
            "native archive with CRLF line endings preserves complete data");
    auto opening = [text rangeOfString:@"<database>"];
    require(opening.location != NSNotFound, "native oracle has database marker");
    const auto textOnly = root / "phrases-only.mjsr";
    write(textOnly, [[text substringToIndex:opening.location] dataUsingEncoding:NSUTF8StringEncoding]);
    auto preserve = store.data();
    require(store.importArchive(native(textOnly), &error), "text-only native phrase archive imports");
    after = store.data();
    require([[after objectForKey:@"overrides"] isEqual:[preserve objectForKey:@"overrides"]] &&
            [[after objectForKey:@"bigrams"] isEqual:[preserve objectForKey:@"bigrams"]] &&
            [[after objectForKey:@"table"] isEqual:[preserve objectForKey:@"table"]] &&
            [[after objectForKey:@"generation"] isEqual:[preserve objectForKey:@"generation"]],
            "text-only import preserves all learning domains and epoch");
}

static void testJSONRoundTrip(const fs::path& model, const fs::path& root) {
    const auto user = root / "roundtrip-source.db";
    GuanyinmaMacUserData source(model.u8string(), user.u8string());
    require(importData(source, fullArchive()), "import complete portable fixture");
    const auto path = root / "完整 備份.json";
    NSError* error = nil;
    require(source.exportArchive(native(path), &error) && !error, "export complete Guanyinma JSON");
    auto expected = source.archive();
    require(expected && [[expected objectForKey:@"smart"] isKindOfClass:[NSDictionary class]] &&
            [[expected objectForKey:@"table"] isKindOfClass:[NSArray class]], "full backup includes all scopes");
    require(![expected objectForKey:@"generation"] && ![expected objectForKey:@"revision"], "portable backup omits local epochs");
    auto read = GuanyinmaReadArchive(native(path), &error);
    require([read isEqualToDictionary:expected], "complete archive survives JSON write/read");
    GuanyinmaMacUserData destination(model.u8string(), (root / "roundtrip-destination.db").u8string());
    require(destination.importArchive(native(path), &error), "new store imports complete JSON");
    require([destination.archive() isEqualToDictionary:expected], "full JSON preserves phrases, scores, Smart and table learning");
    const auto original = bytes(path);
    require(source.exportArchive(native(path), &error), "existing JSON backup can be replaced atomically");
    require([bytes(path) isEqualToData:original], "stable data produces stable archive");
}

static void testMalformedImports(const fs::path& model, const fs::path& root) {
    GuanyinmaMacUserData store(model.u8string(), (root / "malformed-target.db").u8string());
    require(importData(store, fullArchive()), "seed malformed-import target");
    auto before = store.data();
    const auto path = root / "invalid.archive";
    auto reject = [&](NSData* data, const std::string& description) {
        write(path, data);
        auto source = bytes(path);
        NSError* error = nil;
        require(!store.importArchive(native(path), &error) && error, description + " rejected with an error");
        require([store.data() isEqualToDictionary:before], description + " leaves every data row and epoch unchanged");
        require([bytes(path) isEqualToData:source], description + " never rewrites source");
    };
    reject([@"not an archive" dataUsingEncoding:NSUTF8StringEncoding], "unknown format");
    reject([@"{\"format\":\"guanyinma_user_data\"" dataUsingEncoding:NSUTF8StringEncoding], "truncated JSON");
    for (NSDictionary* change in @[
        @{@"schema_version": @2}, @{@"unknown_field": @1},
        @{@"phrases": @[@{@"qstring": @"0_", @"current": @"事", @"probability": @"-1", @"backoff": @0}]}
    ]) {
        NSMutableDictionary* invalid = [copyDictionary(fullArchive()) mutableCopy];
        [invalid addEntriesFromDictionary:change];
        reject(encoded(invalid), "invalid portable schema");
        [invalid release];
    }
    NSMutableDictionary* duplicate = [copyDictionary(fullArchive()) mutableCopy];
    [[duplicate objectForKey:@"phrases"] addObject:[[duplicate objectForKey:@"phrases"] objectAtIndex:0]];
    reject(encoded(duplicate), "duplicate custom phrase identity");
    [duplicate release];
    NSMutableDictionary* nul = [copyDictionary(fullArchive()) mutableCopy];
    unichar nulWord[] = {0x58eb, 0};
    [[nul objectForKey:@"phrases"] objectAtIndex:0][@"current"] = [NSString stringWithCharacters:nulWord length:2];
    reject(encoded(nul), "NUL in portable phrase");
    [nul release];
    const uint8_t invalidUTF8[] = {0xff, 0xfe, 0xff};
    reject([NSData dataWithBytes:invalidUTF8 length:sizeof(invalidUTF8)], "invalid UTF-8");
    reject([@"MJSR version 1.0.0\n士事\tㄕˋ,ㄕˋ\tNaN\t-3\n" dataUsingEncoding:NSUTF8StringEncoding],
           "nonfinite legacy score");
    reject([@"MJSR version 1.0.0\n士事\tㄕˋ,ㄕˋ\t-1\t-3\n<database>\n0\n</database>\n" dataUsingEncoding:NSUTF8StringEncoding],
           "odd hex cache");
    reject([@"MJSR version 1.0.0\n士事\tㄕˋ,ㄕˋ\t-1\t-3\n<database>\nxx\n</database>\n" dataUsingEncoding:NSUTF8StringEncoding],
           "nonhex cache");
    reject([@"MJSR version 1.0.0\n士事\tㄕˋ,ㄕˋ\t-1\t-3\n<database>\n00112233\n" dataUsingEncoding:NSUTF8StringEncoding],
           "unterminated cache block");
    reject([@"MJSR version 1.0.0\n士事\tㄕˋ,ㄕˋ\t0x1p-2\t-3\n" dataUsingEncoding:NSUTF8StringEncoding],
           "legacy hexadecimal float outside archive number grammar");
    auto malformedCache = legacyExport(root, true);
    reject(bytes(malformedCache), "valid phrases followed by invalid encrypted cache");
    const auto nativePath = root / "native.mjsr";
    auto data = bytes(nativePath);
    require(data != nil, "native malformed-test oracle exists");
    NSString* text = [[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] autorelease];
    auto extra = [text stringByAppendingString:@"<database>\n00\n</database>\n"];
    reject([extra dataUsingEncoding:NSUTF8StringEncoding], "duplicate legacy cache block");
}

static void testFailuresAndAliases(const fs::path& model, const fs::path& root) {
    const auto truncated = root / "nul-prefix.db";
    const auto badPath = truncated.u8string() + std::string(1, '\0') + "suffix";
    GuanyinmaMacUserData invalid(model.u8string(), badPath);
    NSError* openError = nil;
    require(!invalid.valid() && !invalid.data(&openError) && openError && !fs::exists(truncated),
            "administration refuses NUL path before opening its valid prefix");
    // Guard regressions can only affect this disposable model copy.
    const auto copy = root / "protected-model.db";
    fs::copy_file(model, copy);
    const auto user = root / "protected-user.db";
    GuanyinmaMacUserData store(copy.u8string(), user.u8string());
    require(importData(store, fullArchive()), "seed export-failure store");
    const auto path = root / "existing-backup.json";
    const auto sentinel = [@"previous backup must survive" dataUsingEncoding:NSUTF8StringEncoding];
    write(path, sentinel);
    NSError* error = nil;
    const auto userBytes = bytes(user), modelBytes = bytes(copy);
    NSDictionary* exportSnapshot = store.archive();
    require(exportSnapshot != nil, "snapshot before any export alias");
    for (const auto& protectedPath : {copy, user}) {
        require(!store.exportArchive(native(protectedPath), &error), "refuse direct protected database export path");
        // Apple SQLite invalidates open handles on link/unlink vnode events.
        // Closed copies test destination identity without invalidating the live store.
        const auto closed = root / (protectedPath.filename().u8string() + "-closed-fixture");
        fs::copy_file(protectedPath, closed);
        NSArray* protectedPaths = @[native(closed)];
        const auto link = root / (protectedPath.filename().u8string() + "-symlink");
        fs::create_symlink(closed, link);
        require(!GuanyinmaWriteArchive(native(link), exportSnapshot, protectedPaths, &error),
                "refuse protected database symlink export path");
        const auto hard = root / (protectedPath.filename().u8string() + "-hardlink");
        fs::create_hard_link(closed, hard);
        require(!GuanyinmaWriteArchive(native(hard), exportSnapshot, protectedPaths, &error),
                "refuse protected database hardlink export path");
        require([bytes(closed) isEqualToData:bytes(protectedPath)], "closed aliased database remains byte-identical");
        fs::remove(hard);
        fs::remove(link);
        require(store.data() != nil, "live store remains readable after isolated alias checks");
    }
    require([bytes(user) isEqualToData:userBytes] && [bytes(copy) isEqualToData:modelBytes],
            "protected database contents survive direct and aliased export attempts");
    require(store.data() != nil, "snapshot after alias export attempts");
    const auto directory = root / "export-directory";
    fs::create_directory(directory);
    require(!store.exportArchive(native(directory), &error) && fs::is_directory(directory),
            "export refuses directory destination");
    require(!store.exportArchive(native(root / "absent-parent" / "backup.json"), &error),
            "unwritable missing parent produces export failure");
    NSMutableDictionary* partial = [copyDictionary(fullArchive()) mutableCopy];
    [partial setObject:@"unknown_format" forKey:@"format"];
    require(!GuanyinmaWriteArchive(native(path), partial, @[], &error),
            "writer rejects invalid portable schema before replacing destination");
    require([bytes(path) isEqualToData:sentinel], "serialization validation failure preserves previous export");
    [partial setObject:@"guanyinma_user_data" forKey:@"format"];
    [partial setObject:[NSNull null] forKey:@"table"];
    require(!GuanyinmaWriteArchive(native(path), partial, @[], &error) && [bytes(path) isEqualToData:sentinel],
            "full backup writer refuses an omitted method scope without replacing old export");
    [partial release];

    require(store.data() != nil, "snapshot before child write failure");
    std::set<fs::path> filesBefore;
    for (const auto& entry : fs::directory_iterator(root)) filesBefore.insert(entry.path());
    std::string destination = path.u8string();
    char* arguments[] = {const_cast<char*>(executable.c_str()), const_cast<char*>("--limited-export"),
                         const_cast<char*>(destination.c_str()), NULL};
    pid_t child = 0;
    require(posix_spawn(&child, executable.c_str(), NULL, NULL, arguments, environ) == 0,
            "spawn isolated partial-write failure process");
    int status = 0;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "actual archive write reports child-only file-size failure");
    require([bytes(path) isEqualToData:sentinel], "partial-write failure preserves previous export");
    std::set<fs::path> filesAfter;
    for (const auto& entry : fs::directory_iterator(root)) filesAfter.insert(entry.path());
    require(filesAfter == filesBefore, "partial-write failure removes temporary export");

    require(store.data() != nil, "snapshot after child write failure");
    sqlite3* blocker = NULL;
    require(sqlite3_open(user.u8string().c_str(), &blocker) == SQLITE_OK, "open isolated destination blocker");
    const auto good = root / "valid-import.json";
    require(GuanyinmaWriteArchive(native(good), fullArchive(), @[], &error), "write valid lock-test import");
    auto before = store.data(&error);
    require(before != nil, "valid snapshot before destination lock");
    sql(blocker, "BEGIN IMMEDIATE");
    require(!store.importArchive(native(good), &error), "locked destination rejects whole import");
    sql(blocker, "ROLLBACK");
    auto afterFailure = store.data();
    require([afterFailure isEqualToDictionary:before], "failed import leaves phrases, learning and epoch unchanged");
    sql(blocker, "BEGIN EXCLUSIVE");
    require(!store.exportArchive(native(path), &error), "unreadable snapshot rejects export");
    sql(blocker, "ROLLBACK");
    require([bytes(path) isEqualToData:sentinel], "snapshot read failure preserves previous export file");
    sqlite3_close(blocker);
    require(!store.importArchive(native(user), &error) && !store.importArchive(native(copy), &error),
            "database files cannot masquerade as archives");
    require([store.data() isEqualToDictionary:before], "wrong source format never changes user store");
}

static void testActiveSessions(const fs::path& model, const fs::path& root) {
    const auto user = root / "active-import.db";
    GuanyinmaMacUserData administration(model.u8string(), user.u8string());
    Session active(model, user);
    active.type("g4");
    auto panel = active.apply(@{@"type": @"open_candidates", @"index": @0});
    require([[[panel objectForKey:@"candidates"] objectAtIndex:0] isEqualToString:@"是"], "active panel starts in model order");
    const auto path = root / "active-import.json";
    NSError* error = nil;
    require(GuanyinmaWriteArchive(native(path), fullArchive(), @[], &error), "write external import archive");
    require(administration.importArchive(native(path), &error), "other administration session imports replacement");
    auto stale = active.apply(@{@"type": @"select", @"index": @1});
    NSDictionary* effects = [stale objectForKey:@"effects"];
    require([[effects objectForKey:@"beep"] boolValue] && ![[effects objectForKey:@"commit"] length] &&
            [[stale objectForKey:@"candidates"] count] == 0, "old candidate action is consumed after archive reorder");
    active.apply(@{@"type": @"reset"});
    require([[active.type("g4") objectForKey:@"composition"] isEqualToString:@"事"],
            "existing input session synchronizes imported preference");
    require(administration.apply(@{@"type": @"reset_learning"}), "other session resets imported learning");
    active.apply(@{@"type": @"save_learning"});
    active.apply(@{@"type": @"key", @"key": @"return"});
    require([[active.type("g4") objectForKey:@"composition"] isEqualToString:@"是"], "old session never revives reset preferences");
    require([[administration.phrases() objectAtIndex:0][@"current"] isEqualToString:@"士事"] &&
            [[administration.data() objectForKey:@"overrides"] count] == 0 &&
            [[administration.data() objectForKey:@"table"] count] == 0,
            "reset clears all imported learning and preserves custom words");
}

static void testLegacyDestinationGuards(const fs::path& model, const fs::path& root) {
    GuanyinmaMacUserData store(model.u8string(), (root / "legacy-guards-user.db").u8string());
    require(importData(store, fullArchive()), "seed legacy destination guard store");
    NSError* error = nil;
    for (const std::string name : {"SmartMandarinUserData.db", "UserPhrase.db",
             "Generic-cj-cin-DynamicCandidateOrder.sqlite3", "Generic-simplex-cin-DynamicCandidateOrder.sqlite3"}) {
        const auto path = root / name;
        NSData* content = [@"encrypted legacy profile without SQLite magic" dataUsingEncoding:NSUTF8StringEncoding];
        write(path, content);
        require(!store.exportArchive(native(path), &error) && [bytes(path) isEqualToData:content],
                "legacy encrypted profile name stays protected");
        for (const std::string suffix : {"", "-journal", "-wal", "-shm"}) {
            const auto protectedPath = root / (name + suffix);
            if (!suffix.empty()) {
                require(!store.exportArchive(native(protectedPath), &error) && !fs::exists(protectedPath),
                        "missing legacy sidecar name cannot become an archive");
                write(protectedPath, content);
            }
            const auto alias = root / (name + suffix + "-alias");
            fs::create_hard_link(protectedPath, alias);
            require(!store.exportArchive(native(alias), &error) && [bytes(alias) isEqualToData:content] &&
                    [bytes(protectedPath) isEqualToData:content], "legacy profile/sidecar hardlink alias stays unchanged");
            fs::remove(alias);
        }
    }
}

static void testNonregularInput(const fs::path& root) {
    const auto pipe = root / "archive.fifo";
    require(mkfifo(pipe.u8string().c_str(), 0600) == 0, "create isolated FIFO");
    std::string filename = pipe.u8string();
    char* arguments[] = {const_cast<char*>(executable.c_str()), const_cast<char*>("--fifo-read"),
                         const_cast<char*>(filename.c_str()), NULL};
    pid_t child = 0;
    require(posix_spawn(&child, executable.c_str(), NULL, NULL, arguments, environ) == 0,
            "spawn FIFO read deadline check");
    int status = 0;
    require(waitpid(child, &status, 0) == child && WIFEXITED(status) && WEXITSTATUS(status) == 0,
            "FIFO input fails promptly instead of waiting for a writer");
}

int main(int argc, char** argv) {
    @autoreleasepool {
        @try {
          try {
            if (argc == 3 && std::strcmp(argv[1], "--fifo-read") == 0) {
                alarm(3);
                NSError* error = nil;
                return !GuanyinmaReadArchive([NSString stringWithUTF8String:argv[2]], &error) && error ? 0 : 3;
            }
            if (argc == 3 && std::strcmp(argv[1], "--limited-export") == 0) {
                signal(SIGXFSZ, SIG_IGN);
                struct rlimit limit = {64, 64};
                if (setrlimit(RLIMIT_FSIZE, &limit) != 0) return 2;
                NSError* error = nil;
                bool success = GuanyinmaWriteArchive([NSString stringWithUTF8String:argv[2]], fullArchive(), @[], &error);
                return !success && error ? 0 : 3;
            }
            executable = argv[0];
            require(argc == 3, "usage: GuanyinmaMacArchiveTests MODEL TEMP_PROFILE_DIRECTORY");
            fs::path model(argv[1]), root(argv[2]);
            require(fs::is_directory(root), "isolated archive test root exists");
            testNativeLegacyImport(model, root);
            testJSONRoundTrip(model, root);
            testMalformedImports(model, root);
            testFailuresAndAliases(model, root);
            testActiveSessions(model, root);
            testLegacyDestinationGuards(model, root);
            testNonregularInput(root);
            std::cout << "Guanyinma macOS archive: " << checks << " checks passed.\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "Guanyinma macOS archive test failed: " << error.what() << '\n';
            return 1;
          }
        } @catch (NSException* exception) {
            std::cerr << "Guanyinma macOS archive threw: " << [[exception reason] UTF8String] << '\n';
            return 1;
        }
    }
}

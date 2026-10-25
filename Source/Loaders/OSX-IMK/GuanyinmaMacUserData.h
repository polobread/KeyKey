/*
 * macOS user-data administration through the Guanyinma C ABI.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#ifndef GUANYINMA_MAC_USER_DATA_H
#define GUANYINMA_MAC_USER_DATA_H

#import <Foundation/Foundation.h>
#include "../../Guanyinma/include/guanyinma.h"
#include "GuanyinmaMacArchive.h"
#include <string>
#include <vector>

// Short-lived administration sessions share only the explicitly selected store.
// They never emit host effects or open a native Manjusri user profile.
class GuanyinmaMacUserData {
public:
    GuanyinmaMacUserData(const std::string& modelPath, const std::string& userPath)
        : session_(NULL), modelPath_(nil), userPath_(nil), openError_(nil)
    {
        if (modelPath.empty() || userPath.empty() ||
            modelPath.find('\0') != std::string::npos || userPath.find('\0') != std::string::npos) {
            openError_ = [errorWithMessage(@"Model and user paths must be nonempty and contain no NUL",
                GUANYINMA_INVALID_ARGUMENT) retain];
            return;
        }
        modelPath_ = [[NSString alloc] initWithBytes:modelPath.data() length:modelPath.size()
            encoding:NSUTF8StringEncoding];
        userPath_ = [[NSString alloc] initWithBytes:userPath.data() length:userPath.size()
            encoding:NSUTF8StringEncoding];
        if (!modelPath_ || !userPath_) {
            openError_ = [errorWithMessage(@"Model and user paths must be valid UTF-8",
                GUANYINMA_INVALID_UTF8) retain];
            return;
        }
        NSData* config = [NSJSONSerialization dataWithJSONObject:
            @{@"method": @"smart", @"user_database": userPath_} options:0 error:NULL];
        if (!config) {
            openError_ = [errorWithMessage(@"Could not encode user-data settings",
                GUANYINMA_INVALID_ARGUMENT) retain];
            return;
        }
        const int32_t status = guanyinma_session_open(
            reinterpret_cast<const uint8_t*>(modelPath.data()), modelPath.size(),
            static_cast<const uint8_t*>([config bytes]), [config length], &session_);
        if (status != GUANYINMA_OK)
            openError_ = [lastError(status) retain];
    }

    ~GuanyinmaMacUserData()
    {
        guanyinma_session_close(&session_);
        [modelPath_ release];
        [userPath_ release];
        [openError_ release];
    }
    bool valid() const { return session_ != NULL; }

    NSDictionary* data(NSError** error = NULL) const
    {
        if (error) *error = nil;
        if (!session_) {
            reportOpenError(error);
            return nil;
        }
        GuanyinmaResult* result = NULL;
        const int32_t status = guanyinma_session_user_data(session_, &result);
        if (status != GUANYINMA_OK) {
            if (error) *error = lastError(status);
            return nil;
        }
        size_t required = 0;
        NSDictionary* decoded = nil;
        int32_t copied = guanyinma_result_json(result, NULL, 0, &required);
        if (copied == GUANYINMA_BUFFER_TOO_SMALL && required > 1) {
            std::vector<uint8_t> bytes(required);
            copied = guanyinma_result_json(result, bytes.data(), bytes.size(), &required);
            if (copied == GUANYINMA_OK) {
                id object = [NSJSONSerialization JSONObjectWithData:
                    [NSData dataWithBytes:bytes.data() length:required - 1] options:0 error:error];
                if ([object isKindOfClass:[NSDictionary class]] &&
                    [[object objectForKey:@"kind"] isEqual:@"user_data"] &&
                    [[object objectForKey:@"schema_version"] unsignedIntegerValue] == 1 &&
                    [[object objectForKey:@"data"] isKindOfClass:[NSDictionary class]])
                    decoded = [object objectForKey:@"data"];
            }
        }
        if (!decoded && error && !*error)
            *error = copied == GUANYINMA_OK ? errorWithMessage(@"Invalid user-data result",
                GUANYINMA_SCHEMA_ERROR) : lastError(copied);
        // Capture diagnostics before close clears the thread-local ABI error.
        guanyinma_result_close(&result);
        return decoded;
    }

    NSArray* phrases() const { return [data() objectForKey:@"phrases"]; }

    bool apply(NSDictionary* operation, NSError** error = NULL)
    {
        if (error) *error = nil;
        if (!session_) return reportOpenError(error);
        NSData* json = [NSJSONSerialization dataWithJSONObject:operation options:0 error:error];
        if (!json) return false;
        GuanyinmaResult* result = NULL;
        const int32_t status = guanyinma_session_apply(session_,
            static_cast<const uint8_t*>([json bytes]), [json length], &result);
        if (status != GUANYINMA_OK && error) *error = lastError(status);
        guanyinma_result_close(&result);
        return status == GUANYINMA_OK;
    }

    NSDictionary* archive(NSError** error = NULL) const
    {
        NSDictionary* snapshot = data(error);
        if (!snapshot) return nil;
        for (NSString* key in @[@"phrases", @"overrides", @"bigrams", @"table"]) {
            if (![[snapshot objectForKey:key] isKindOfClass:[NSArray class]]) {
                if (error) *error = errorWithMessage(@"Incomplete user-data result", GUANYINMA_SCHEMA_ERROR);
                return nil;
            }
        }
        // Concurrency metadata belongs to the destination and is not a backup.
        return @{@"format": @"guanyinma_user_data", @"schema_version": @1,
            @"phrases": [snapshot objectForKey:@"phrases"],
            @"smart": @{@"overrides": [snapshot objectForKey:@"overrides"],
                @"bigrams": [snapshot objectForKey:@"bigrams"]},
            @"table": [snapshot objectForKey:@"table"]};
    }

    bool exportArchive(NSString* path, NSError** error = NULL) const
    {
        NSDictionary* snapshot = archive(error);
        if (!snapshot) return false;
        // Legacy Mac Smart profiles may be encrypted and have no SQLite magic.
        // Protect their known sibling paths by identity without opening them.
        NSString* directory = [userPath_ stringByDeletingLastPathComponent];
        NSMutableArray* protectedPaths = [NSMutableArray arrayWithObjects:modelPath_, userPath_, nil];
        for (NSString* name in @[@"SmartMandarinUserData.db", @"UserPhrase.db",
            @"Generic-cj-cin-DynamicCandidateOrder.sqlite3",
            @"Generic-simplex-cin-DynamicCandidateOrder.sqlite3"])
            [protectedPaths addObject:[directory stringByAppendingPathComponent:name]];
        return GuanyinmaWriteArchive(path, snapshot, protectedPaths, error);
    }

    bool importArchive(NSString* path, NSError** error = NULL)
    {
        if (error) *error = nil;
        if (!session_) return reportOpenError(error);
        NSDictionary* imported = GuanyinmaReadArchive(path, error);
        return imported && apply(@{@"type": @"import_user_data", @"archive": imported}, error);
    }

private:
    static NSError* errorWithMessage(NSString* message, NSInteger code)
    {
        return [NSError errorWithDomain:@"io.github.polobread.Guanyinma.UserData" code:code
            userInfo:@{NSLocalizedDescriptionKey: message}];
    }
    static NSError* lastError(int32_t code)
    {
        size_t required = 0;
        NSString* message = nil;
        if (guanyinma_last_error(NULL, 0, &required) == GUANYINMA_BUFFER_TOO_SMALL && required > 1) {
            std::vector<uint8_t> bytes(required);
            if (guanyinma_last_error(bytes.data(), bytes.size(), &required) == GUANYINMA_OK)
                message = [[[NSString alloc] initWithBytes:bytes.data() length:required - 1
                    encoding:NSUTF8StringEncoding] autorelease];
        }
        return errorWithMessage(message ?: @"Guanyinma user-data operation failed", code);
    }
    bool reportOpenError(NSError** error) const
    {
        if (error) *error = openError_ ? [[openError_ retain] autorelease] :
            errorWithMessage(@"Guanyinma user store is unavailable", GUANYINMA_DATABASE_ERROR);
        return false;
    }
    GuanyinmaMacUserData(const GuanyinmaMacUserData&) = delete;
    GuanyinmaMacUserData& operator=(const GuanyinmaMacUserData&) = delete;
    GuanyinmaSession* session_;
    NSString* modelPath_;
    NSString* userPath_;
    NSError* openError_;
};

#endif

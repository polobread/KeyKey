// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// Ordinary codec contract tests use the actual Formosa and Manjusri sources.
// No input-method host, preferences, model, user store or migration trace is used.
#import <Foundation/Foundation.h>
#include "GuanyinmaMacReadingCodec.h"
#include "BPMFUserPhraseHelper.h"
#include "Mandarin.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using Formosa::Mandarin::BPMF;
using Manjusri::BPMFUserPhraseHelper;
static size_t checks;

static void require(bool value, const std::string& message)
{
    ++checks;
    if (!value) throw std::runtime_error(message);
}

static NSString* native(const std::string& value)
{
    return [[[NSString alloc] initWithBytes:value.data() length:value.size()
        encoding:NSUTF8StringEncoding] autorelease];
}

static std::string text(NSString* value)
{
    return value ? std::string([value UTF8String]) : std::string();
}

static NSDictionary* codec(NSDictionary* request, bool rejected = false)
{
    NSData* data = [NSJSONSerialization dataWithJSONObject:request options:0 error:NULL];
    require(data != nil, "serialize codec request");
    GuanyinmaResult* result = NULL;
    const int32_t status = guanyinma_reading_codec(static_cast<const uint8_t*>(data.bytes),
        data.length, &result);
    if (rejected) {
        require(status == GUANYINMA_INVALID_ARGUMENT && result == NULL,
            "invalid query/reading must fail safely without an owned result");
        return nil;
    }
    require(status == GUANYINMA_OK && result != NULL, "convert reading without a database");
    struct Close { GuanyinmaResult* value; ~Close() { guanyinma_result_close(&value); } } close{result};
    size_t size = 0;
    require(guanyinma_result_json(result, NULL, 0, &size) == GUANYINMA_BUFFER_TOO_SMALL,
        "probe owned codec result");
    std::vector<uint8_t> bytes(size);
    require(guanyinma_result_json(result, bytes.data(), bytes.size(), &size) == GUANYINMA_OK,
        "copy owned codec result");
    id decoded = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithBytes:bytes.data() length:size - 1] options:0 error:NULL];
    require([decoded isKindOfClass:[NSDictionary class]], "decode owned codec result");
    return decoded;
}

static void compareEncode(const std::string& reading, const std::string& label)
{
    const auto expected = BPMFUserPhraseHelper::QString(reading);
    std::string actual;
    size_t count = 0;
    require(GuanyinmaMacEncodeReading(reading, actual, count), "encode " + label);
    require(actual == expected.first, "Manjusri query bytes: " + label);
    require(count == expected.second, "Manjusri syllable count: " + label);
}

static void testAllSyllables()
{
    for (short order = 0; order < 6160; ++order) {
        @autoreleasepool {
            const auto reading = BPMF::FromAbsoluteOrder(order).composedString();
            compareEncode(reading, "absolute order " + std::to_string(order));
        }
    }
}

static void testEveryPrintableQuery()
{
    for (size_t order = 0; order < 79 * 79; ++order) {
        @autoreleasepool {
            std::string query(2, '0');
            query[0] += static_cast<char>(order % 79);
            query[1] += static_cast<char>(order / 79);
            require(GuanyinmaMacDecodeReading(query) == BPMFUserPhraseHelper::BPMFString(query),
                "Manjusri printable query order " + std::to_string(order));
        }
    }
}

static void testComposedSyntax()
{
    const std::vector<std::string> readings = {
        "", ",", ",,", "unknown", "ㄋㄧˇ,ㄏㄠˇ", ",ㄋㄧˇ,,ㄏㄠˇ,",
        "ㄅㄆㄧㄨˊˇ", "ㄋㄋ", "ㄧㄨ", "ㄚㄛ", "ˊˇ", "ˇㄧㄋ", "ˇ", "ㄧ˙",
        "ㄋ?ㄧˇ", "ㄋㄧˇ ㄏㄠˇ", "ㄋㄧˇ，ㄏㄠˇ", " \tㄋㄧˇ\r\n, ㄏㄠˇ ", "😀ㄋ",
    };
    for (const auto& reading : readings) {
        @autoreleasepool {
            compareEncode(reading, reading);
            const auto query = BPMFUserPhraseHelper::QString(reading).first;
            require(GuanyinmaMacDecodeReading(query) == BPMFUserPhraseHelper::BPMFString(query),
                "canonical display after composed parsing: " + reading);
        }
    }
    for (const auto& query : std::vector<std::string>{"x", "000", "\\O?", "\\O:W?"}) {
        require(BPMFUserPhraseHelper::BPMFString(query).empty(), "legacy odd query is empty");
        require(GuanyinmaMacDecodeReading(query).empty(), "bridge keeps legacy odd-query display");
    }
    for (const auto& query : std::vector<std::string>{"0000", "00\\O", "\\O00:W", "\\O00"}) {
        require(GuanyinmaMacDecodeReading(query) == BPMFUserPhraseHelper::BPMFString(query),
            "empty query positions retain comma separators");
    }
}

static void testUnsafeInputRejection()
{
    // Never pass these bytes to the legacy decoder: negative component orders
    // can invoke undefined shifts or invalid character-map lookups in old C++.
    const std::vector<std::string> queries = {
        "/0", "0/", std::string(1, '\x7f') + "0", "0" + std::string(1, '\x7f'),
        "é", "😀", std::string("\\O\0", 3),
    };
    for (const auto& query : queries) {
        codec(@{@"operation": @"decode", @"qstring": native(query)}, true);
        require(GuanyinmaMacDecodeReading(query).empty(), "bridge safely rejects malformed query");
    }
    std::string query = "prior";
    size_t count = 99;
    require(!GuanyinmaMacEncodeReading(std::string("ㄋ\0", 4), query, count),
        "bridge rejects embedded NUL reading");
    require(query.empty() && count == 0, "rejected encode clears caller outputs");
}

static bool roundtripReading(const std::string& current, const std::string& reading, bool shared)
{
    std::pair<std::string, size_t> query;
    if (shared) {
        if (!GuanyinmaMacEncodeReading(reading, query.first, query.second)) return false;
    } else {
        query = BPMFUserPhraseHelper::QString(reading);
    }
    const auto decoded = shared ? GuanyinmaMacDecodeReading(query.first) :
        BPMFUserPhraseHelper::BPMFString(query.first);
    const size_t textLength = [native(current)
        lengthOfBytesUsingEncoding:NSUTF32LittleEndianStringEncoding] / 4;
    return query.second && decoded == reading && query.second == textLength;
}

static void testArchiveReadingRoundtrip()
{
    // These are the codec predicates used by MJSR import. Actual container
    // parsing and database import have their own isolated archive tests.
    struct Row { std::string current; std::string reading; bool accepted; };
    const std::vector<Row> rows = {
        {"你好", "ㄋㄧˇ,ㄏㄠˇ", true}, {"士", "ˇ", true},
        {"你", "ㄋㄋ", false}, {"你", "ㄋ?ㄧˇ", false},
        {"你", "ˇㄧㄋ", false}, {"你", ",ㄋㄧˇ", false},
        {"你好", "ㄋㄧˇ", false}, {"你", "", false},
    };
    for (const auto& row : rows) {
        const bool original = roundtripReading(row.current, row.reading, false);
        require(original == row.accepted, "actual legacy archive reading predicate");
        require(roundtripReading(row.current, row.reading, true) == original,
            "shared codec preserves archive reading acceptance");
    }
}

// Pure text reference for the pre-migration required-comma behavior. These
// examples verify an option contract; they do not exercise a Windows host.
static std::string requiredCommaQuery(const std::string& reading)
{
    std::string query;
    for (size_t pos = 0; pos <= reading.size();) {
        const auto end = reading.find(',', pos);
        const auto part = reading.substr(pos, end - pos);
        const auto first = part.find_first_not_of(" \t\r\n");
        const auto last = part.find_last_not_of(" \t\r\n");
        if (first == std::string::npos) return {};
        const auto syllable = BPMF::FromComposedString(part.substr(first, last - first + 1));
        if (syllable.isEmpty()) return {};
        query += syllable.absoluteOrderString();
        if (end == std::string::npos) break;
        pos = end + 1;
    }
    return query;
}

static void testExplicitBehaviorOptions()
{
    NSDictionary* encodeOptions = @{@"separator": @"comma", @"components": @"replace_known",
        @"empty": @"reject", @"require_phonetic": @NO};
    for (const auto& reading : std::vector<std::string>{
        " \tㄋㄧˇ\r\n, ㄏㄠˇ ", "ˇ", "ㄋ?ㄧˇ", "ㄅㄆ", "", ",ㄋ", "ㄋ,", "unknown"}) {
        const auto original = requiredCommaQuery(reading);
        NSDictionary* result = codec(@{@"operation": @"encode", @"reading": native(reading),
            @"options": encodeOptions}, original.empty());
        if (!original.empty()) {
            require(text(result[@"qstring"]) == original, "required-comma behavior uses real Formosa");
        }
    }
    NSDictionary* decodeOptions = @{@"odd_tail": @"ignore"};
    for (const auto& query : std::vector<std::string>{"x", "\\O?", "\\O:W?", "000", "~~?"}) {
        const auto complete = query.substr(0, query.size() / 2 * 2);
        NSDictionary* result = codec(@{@"operation": @"decode", @"qstring": native(query),
            @"options": decodeOptions});
        require(text(result[@"reading"]) == BPMFUserPhraseHelper::BPMFString(complete),
            "explicit odd-tail ignore preserves complete query pairs");
        require(text(result[@"qstring"]) == query, "decode retains original query bytes");
    }
}

int main()
{
    @autoreleasepool {
        try {
            testAllSyllables();
            testEveryPrintableQuery();
            testComposedSyntax();
            testUnsafeInputRejection();
            testArchiveReadingRoundtrip();
            testExplicitBehaviorOptions();
            std::cout << "{\"checks\":" << checks << ",\"canonical_syllables\":6160,"
                "\"printable_query_pairs\":6241,\"database_opened\":false,\"ui_used\":false}\n";
            return 0;
        } catch (const std::exception& error) {
            std::cerr << "Native reading codec verification failed: " << error.what() << '\n';
            return 1;
        }
    }
}

/* Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 * Stateless Foundation bridge; phonetic parsing/validation lives in Guanyinma.
 */
#ifndef GUANYINMA_MAC_READING_CODEC_H
#define GUANYINMA_MAC_READING_CODEC_H
#import <Foundation/Foundation.h>
#include "../../Guanyinma/include/guanyinma.h"
#include <string>
#include <vector>

inline NSDictionary* GuanyinmaMacReadingCodec(const char* operation, const std::string& text)
{
    NSString* input = [[[NSString alloc] initWithBytes:text.data() length:text.size()
        encoding:NSUTF8StringEncoding] autorelease];
    if (!input) return nil;
    NSString* kind = [NSString stringWithUTF8String:operation];
    NSDictionary* request = @{@"operation": kind,
        [kind isEqualToString:@"encode"] ? @"reading" : @"qstring": input};
    NSData* encoded = [NSJSONSerialization dataWithJSONObject:request options:0 error:NULL];
    if (!encoded) return nil;
    GuanyinmaResult* result = NULL;
    if (guanyinma_reading_codec(static_cast<const uint8_t*>([encoded bytes]),
        [encoded length], &result) != GUANYINMA_OK) return nil;
    struct Close { GuanyinmaResult* value; ~Close() { guanyinma_result_close(&value); } } close{result};
    size_t size = 0;
    if (guanyinma_result_json(result, NULL, 0, &size) != GUANYINMA_BUFFER_TOO_SMALL || size < 2)
        return nil;
    std::vector<uint8_t> bytes(size);
    if (guanyinma_result_json(result, bytes.data(), bytes.size(), &size) != GUANYINMA_OK)
        return nil;
    id value = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithBytes:bytes.data() length:size - 1] options:0 error:NULL];
    if (![value isKindOfClass:[NSDictionary class]] ||
        ![value[@"kind"] isEqualToString:@"reading_codec"] ||
        [value[@"schema_version"] unsignedIntegerValue] != 1 ||
        ![value[@"qstring"] isKindOfClass:[NSString class]] ||
        ![value[@"reading"] isKindOfClass:[NSString class]] ||
        ![value[@"syllable_count"] isKindOfClass:[NSNumber class]]) return nil;
    return value;
}

inline bool GuanyinmaMacEncodeReading(const std::string& reading, std::string& query, size_t& count)
{
    query.clear(); count = 0;
    NSDictionary* result = GuanyinmaMacReadingCodec("encode", reading);
    if (!result) return false;
    query = [result[@"qstring"] UTF8String];
    count = [result[@"syllable_count"] unsignedIntegerValue];
    return true;
}

inline std::string GuanyinmaMacDecodeReading(const std::string& query)
{
    NSDictionary* result = GuanyinmaMacReadingCodec("decode", query);
    return result ? std::string([result[@"reading"] UTF8String]) : std::string();
}
#endif

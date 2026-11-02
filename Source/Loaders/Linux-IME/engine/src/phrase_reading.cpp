// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "keykey/linux_ime/phrase_reading.h"
#include "guanyinma.h"
#include <json-c/json.h>
#include <climits>
#include <memory>
#include <vector>

namespace keykey::linux_ime {
namespace {
struct JsonDelete {
    void operator()(json_object *value) const {
        if (value) json_object_put(value);
    }
};
using Json = std::unique_ptr<json_object, JsonDelete>;
struct ResultDelete {
    void operator()(GuanyinmaResult *value) const { guanyinma_result_close(&value); }
};
using Result = std::unique_ptr<GuanyinmaResult, ResultDelete>;

std::string convert(const char *operation, const char *inputName,
                    const std::string &input, const char *optionsJson,
                    const char *outputName) {
    if (input.size() > static_cast<std::size_t>(INT_MAX)) return {};
    Json request(json_object_new_object());
    Json options(json_tokener_parse(optionsJson));
    if (!request || !options) return {};
    json_object_object_add(request.get(), "operation", json_object_new_string(operation));
    json_object_object_add(request.get(), inputName,
        json_object_new_string_len(input.data(), static_cast<int>(input.size())));
    json_object_object_add(request.get(), "options", options.release());
    const char *bytes = json_object_to_json_string_ext(request.get(), JSON_C_TO_STRING_PLAIN);
    // Keep the serialized representation owned by request through this ABI call.
    const std::string encoded = bytes ? bytes : "";
    if (encoded.empty()) return {};
    GuanyinmaResult *raw = nullptr;
    if (guanyinma_reading_codec(reinterpret_cast<const uint8_t *>(encoded.data()),
            encoded.size(), &raw) != GUANYINMA_OK) return {};
    Result result(raw);
    std::size_t required = 0;
    if (guanyinma_result_json(result.get(), nullptr, 0, &required) != GUANYINMA_BUFFER_TOO_SMALL ||
        required < 2 || required > static_cast<std::size_t>(INT_MAX)) return {};
    std::vector<uint8_t> output(required);
    if (guanyinma_result_json(result.get(), output.data(), output.size(), &required) != GUANYINMA_OK ||
        required != output.size() || output.back() != 0) return {};
    auto *tokener = json_tokener_new();
    if (!tokener) return {};
    Json response(json_tokener_parse_ex(tokener, reinterpret_cast<const char *>(output.data()),
                                     static_cast<int>(output.size() - 1)));
    const auto parseError = json_tokener_get_error(tokener);
    const auto end = json_tokener_get_parse_end(tokener);
    json_tokener_free(tokener);
    if (!response || parseError != json_tokener_success || end != output.size() - 1) return {};
    json_object *value = nullptr;
    if (!json_object_object_get_ex(response.get(), outputName, &value) ||
        !json_object_is_type(value, json_type_string)) return {};
    return std::string(json_object_get_string(value),
                       static_cast<std::size_t>(json_object_get_string_len(value)));
}
} // namespace

std::string readingToQuery(const std::string &reading) {
    return convert("encode", "reading", reading,
        R"({"separator":"whitespace","components":"unique_known","empty":"skip","require_phonetic":true})",
        "qstring");
}

std::string queryToReading(const std::string &query) {
    return convert("decode", "qstring", query,
        R"({"separator":"space","query":"canonical","odd_tail":"reject","omit_leading_empty":true})",
        "reading");
}
} // namespace keykey::linux_ime

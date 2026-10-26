// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include <Windows.h>
#include <roapi.h>
#include <coroutine>
#include <winrt/Windows.Foundation.Collections.h>
#include <winrt/Windows.Data.Json.h>
#include <stdexcept>
#include "../../Guanyinma/include/guanyinma.h"

namespace KeyKey::WindowsTsf::Guanyinma {
using Json = winrt::Windows::Data::Json::JsonObject;
using Array = winrt::Windows::Data::Json::JsonArray;
using Value = winrt::Windows::Data::Json::JsonValue;

// TSF usually supplies an STA; standalone consumers may have no apartment.
struct Apartment {
    HRESULT status = RoInitialize(RO_INIT_SINGLETHREADED);
    Apartment() { if (FAILED(status) && status != RPC_E_CHANGED_MODE) winrt::throw_hresult(status); }
    ~Apartment() { if (SUCCEEDED(status)) { winrt::clear_factory_cache(); RoUninitialize(); } }
};
inline void Set(Json const& json, const wchar_t* key, bool value) { json.SetNamedValue(key, Value::CreateBooleanValue(value)); }
inline void Set(Json const& json, const wchar_t* key, int value) { json.SetNamedValue(key, Value::CreateNumberValue(value)); }
inline void Set(Json const& json, const wchar_t* key, const std::string& value) { json.SetNamedValue(key, Value::CreateStringValue(winrt::to_hstring(value))); }
inline void Set(Json const& json, const wchar_t* key, const char* value) { Set(json, key, std::string(value)); }
inline std::string String(Json const& json, const wchar_t* key) { return winrt::to_string(json.GetNamedString(key)); }
inline Json Operation(const char* type) { Json value; Set(value, L"type", type); return value; }
inline std::string LastError() {
    size_t size = 0;
    guanyinma_last_error(nullptr, 0, &size);
    std::string text(size ? size : 1, '\0');
    guanyinma_last_error(reinterpret_cast<uint8_t*>(text.data()), text.size(), &size);
    if (size) text.resize(size - 1);
    return text;
}
inline Json ReadResult(GuanyinmaResult* result) {
    struct Close { GuanyinmaResult* result; ~Close() { guanyinma_result_close(&result); } } close{result};
    size_t size = 0;
    if (guanyinma_result_json(result, nullptr, 0, &size) != GUANYINMA_BUFFER_TOO_SMALL || !size)
        throw std::runtime_error(LastError());
    std::string text(size, '\0');
    if (guanyinma_result_json(result, reinterpret_cast<uint8_t*>(text.data()), text.size(), &size) != GUANYINMA_OK)
        throw std::runtime_error(LastError());
    text.resize(size - 1);
    return Json::Parse(winrt::to_hstring(text));
}
inline Json Apply(GuanyinmaSession* session, Json const& operation) {
    const auto text = winrt::to_string(operation.Stringify());
    GuanyinmaResult* result = nullptr;
    if (guanyinma_session_apply(session, reinterpret_cast<const uint8_t*>(text.data()), text.size(), &result) != GUANYINMA_OK)
        throw std::runtime_error(LastError());
    return ReadResult(result);
}
} // namespace KeyKey::WindowsTsf::Guanyinma

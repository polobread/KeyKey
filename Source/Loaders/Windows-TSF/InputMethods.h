#pragma once

#include <string_view>

namespace KeyKey::WindowsTsf {

struct InputMethodDefinition {
    const char* identifier;
    const wchar_t* name;
    const wchar_t* indicator;
    unsigned int menuId;
};

inline constexpr InputMethodDefinition kInputMethods[] = {
    {"SmartMandarin", L"好打注音", L"ㄅ", 11},
    {"TraditionalMandarin", L"傳統注音", L"ㄅ", 12},
    {"Generic-cj-cin", L"倉頡", L"倉", 13},
    {"Generic-simplex-cin", L"簡易", L"簡", 14},
};

inline const InputMethodDefinition* FindInputMethod(std::string_view identifier) {
    for (const auto& method : kInputMethods) {
        if (identifier == method.identifier) return &method;
    }
    return nullptr;
}

inline bool IsTableInputMethod(std::string_view identifier) {
    return identifier == "Generic-cj-cin" || identifier == "Generic-simplex-cin";
}

}  // namespace KeyKey::WindowsTsf

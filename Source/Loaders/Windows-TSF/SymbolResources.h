#pragma once
#include <string>
#include <vector>
namespace KeyKey::WindowsTsf {
struct SymbolItem { std::wstring label; std::wstring text; };
enum class SymbolLayout { Grid, List };
struct SymbolCategory {
    std::wstring name;
    SymbolLayout layout;
    std::vector<SymbolItem> items;
    bool emoji = false;
};
const std::vector<SymbolCategory>& BuiltinSymbolCategories();
} // namespace KeyKey::WindowsTsf

#pragma once
#include <string>
#include <vector>
namespace KeyKey::WindowsTsf {
struct SymbolItem { std::wstring label; std::wstring text; };
struct SymbolCategory { std::wstring name; std::vector<SymbolItem> items; };
const std::vector<SymbolCategory>& BuiltinSymbolCategories();
} // namespace KeyKey::WindowsTsf

#pragma once
#include <string>

namespace KeyKey::WindowsTsf {
// The same character table used by the macOS OVOFHanConvert output filter.
// Call only at a document commit boundary; composition and learning stay traditional.
std::wstring ConvertOutput(const std::wstring& text, bool simplified);
}

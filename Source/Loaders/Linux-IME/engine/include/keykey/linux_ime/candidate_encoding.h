#pragma once

#include <string>
#include <vector>

namespace keykey::linux_ime {

bool isBig5HkscsRepresentable(const std::string &text);
std::vector<std::string>
filterBig5HkscsCandidates(const std::vector<std::string> &candidates);

} // namespace keykey::linux_ime

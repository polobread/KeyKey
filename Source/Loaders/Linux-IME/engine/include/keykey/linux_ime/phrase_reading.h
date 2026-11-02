// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include <string>
namespace keykey::linux_ime {
std::string readingToQuery(const std::string &reading);
std::string queryToReading(const std::string &query);
}

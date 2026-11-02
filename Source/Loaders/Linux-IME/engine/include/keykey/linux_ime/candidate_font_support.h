// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once

#include <memory>
#include <string>

namespace keykey::linux_ime {

// Native font fallback without a GTK/Qt application or display connection.
// One provider is owned by one session and used on that session's thread.
class CandidateFontSupport {
public:
    CandidateFontSupport();
    ~CandidateFontSupport();
    CandidateFontSupport(const CandidateFontSupport &) = delete;
    CandidateFontSupport &operator=(const CandidateFontSupport &) = delete;
    bool accepts(const std::string &text) const;

private:
    class Impl;
    std::unique_ptr<Impl> impl_;
};

} // namespace keykey::linux_ime

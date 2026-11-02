// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include "UserDataStore.h"
#include <memory>

namespace KeyKey::WindowsTsf {
// One settings window owns one backend, fixed at open. Row IDs belong only to
// that snapshot and resolve to phrase identity, never to another core's rows.
class GuanyinmaWindowsUserData final {
public:
    explicit GuanyinmaWindowsUserData(const std::wstring& model);
    ~GuanyinmaWindowsUserData();
    std::vector<UserPhrase> load();
    bool save(const UserPhrase& phrase);
    bool remove(std::int64_t row);
    bool resetLearning();
    bool importData(const std::wstring& path);
    bool exportData(const std::wstring& path);
private:
    struct Impl;
    std::unique_ptr<Impl> impl_;
};
}

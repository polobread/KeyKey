#pragma once

#include <cstdint>
#include <string>
#include <vector>

namespace KeyKey::WindowsTsf {

struct UserPhrase {
    std::int64_t rowid = 0;
    std::wstring text;
    std::wstring reading;
};

std::vector<UserPhrase> LoadUserPhrases();
bool SaveUserPhrase(const UserPhrase& phrase);
bool DeleteUserPhrase(std::int64_t rowid);
bool ResetUserLearning();
bool ImportUserData(const std::wstring& databasePath);
bool ExportUserData(const std::wstring& databasePath);

}  // namespace KeyKey::WindowsTsf

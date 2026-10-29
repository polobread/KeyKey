#pragma once
#include "UserDataStore.h"

// Only test fixtures create or change historical Windows databases.
namespace KeyKey::WindowsTsf {
std::vector<UserPhrase> LoadUserPhrases();
bool SaveUserPhrase(const UserPhrase& phrase);
bool DeleteUserPhrase(std::int64_t rowid);
bool ResetUserLearning();
bool ImportUserData(const std::wstring& databasePath);
bool ExportUserData(const std::wstring& databasePath);

}

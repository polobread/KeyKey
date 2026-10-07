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

enum class ReadingLookupStatus { Success = 1, NoReadings = 0, InvalidPhrase = -1, DatabaseError = -2 };
struct CharacterReadings {
    std::wstring text;
    std::vector<std::wstring> readings;
};
struct ReadingLookup {
    ReadingLookupStatus status = ReadingLookupStatus::InvalidPhrase;
    std::vector<std::wstring> wholePhraseReadings;
    std::vector<CharacterReadings> characters;
};
// Canonical database only, opened read-only. At most 64 Unicode code points and
// 32 ranked alternatives per query; never expands a Cartesian product.
ReadingLookup LookupPhraseReadings(const std::wstring& databasePath, const std::wstring& phrase);

std::vector<UserPhrase> LoadUserPhrases();
bool SaveUserPhrase(const UserPhrase& phrase);
bool DeleteUserPhrase(std::int64_t rowid);
bool ResetUserLearning();
bool ImportUserData(const std::wstring& databasePath);
bool ExportUserData(const std::wstring& databasePath);

}  // namespace KeyKey::WindowsTsf

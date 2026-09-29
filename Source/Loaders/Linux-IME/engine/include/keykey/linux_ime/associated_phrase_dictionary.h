#pragma once

#include <cstddef>
#include <istream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>

namespace keykey::linux_ime {

class AssociatedPhraseDictionary {
public:
    using CandidateMap =
        std::unordered_map<std::string, std::vector<std::string>>;

    struct Collection {
        std::string source;
        std::string displayName;
        std::size_t phraseCount = 0;
    };

    static AssociatedPhraseDictionary loadDirectory(
        const std::string &directoryPath);
    static CandidateMap parseCollection(
        std::istream &input,
        const std::unordered_set<std::string> &exclusions = {});

    std::vector<std::string> candidates(
        const std::string &headCharacter,
        const std::vector<std::string> &enabledSources) const;
    const std::vector<Collection> &collections() const noexcept;
    std::size_t entryCount() const noexcept;

private:
    struct CollectionData {
        CandidateMap entries;
    };

    std::vector<CollectionData> collectionData_;
    std::vector<Collection> collections_;
    std::unordered_map<std::string, std::size_t> collectionIndexes_;
    std::size_t entryCount_ = 0;
};

} // namespace keykey::linux_ime

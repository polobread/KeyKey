#include "keykey/linux_ime/candidate_encoding.h"

#include <cerrno>
#include <iconv.h>

namespace keykey::linux_ime {
namespace {

class IconvHandle {
public:
    IconvHandle() : value_(iconv_open("BIG5-HKSCS", "UTF-8")) {}
    ~IconvHandle() {
        if (valid()) {
            iconv_close(value_);
        }
    }

    IconvHandle(const IconvHandle &) = delete;
    IconvHandle &operator=(const IconvHandle &) = delete;

    bool valid() const noexcept { return value_ != invalidHandle(); }
    iconv_t value() const noexcept { return value_; }

private:
    static iconv_t invalidHandle() noexcept {
        return reinterpret_cast<iconv_t>(-1);
    }

    iconv_t value_;
};

bool canConvert(iconv_t converter, const std::string &text) {
    static_cast<void>(iconv(converter, nullptr, nullptr, nullptr, nullptr));
    char *input = const_cast<char *>(text.data());
    std::size_t inputBytes = text.size();
    while (inputBytes != 0U) {
        char output[256];
        char *outputPosition = output;
        std::size_t outputBytes = sizeof(output);
        errno = 0;
        if (iconv(converter, &input, &inputBytes, &outputPosition,
                  &outputBytes) != static_cast<std::size_t>(-1)) {
            continue;
        }
        if (errno != E2BIG) {
            return false;
        }
    }
    return true;
}

} // namespace

bool isBig5HkscsRepresentable(const std::string &text) {
    IconvHandle converter;
    return converter.valid() && canConvert(converter.value(), text);
}

std::vector<std::string>
filterBig5HkscsCandidates(const std::vector<std::string> &candidates) {
    IconvHandle converter;
    if (!converter.valid()) {
        return {};
    }
    std::vector<std::string> result;
    result.reserve(candidates.size());
    for (const std::string &candidate : candidates) {
        if (canConvert(converter.value(), candidate)) {
            result.push_back(candidate);
        }
    }
    return result;
}

} // namespace keykey::linux_ime

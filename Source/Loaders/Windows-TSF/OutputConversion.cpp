#include "OutputConversion.h"

extern unsigned short VXUCS2TradToSimpChinese(unsigned short);

namespace KeyKey::WindowsTsf {
std::wstring ConvertOutput(const std::wstring& text, bool simplified) {
    if (!simplified) return text;
    auto result = text;
    for (auto& character : result) {
        if (!((character >= 0x3400 && character <= 0x9fff) ||
              (character >= 0xf900 && character <= 0xfaff))) continue;
        const auto converted = VXUCS2TradToSimpChinese(static_cast<unsigned short>(character));
        if (converted) character = converted;
    }
    return result;
}
}

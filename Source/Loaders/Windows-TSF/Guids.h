#pragma once

#include <Windows.h>

namespace KeyKey::WindowsTsf {

// {828E3CF0-11E9-45FC-A5DB-394991AD0093}
inline constexpr CLSID kTextServiceClsid = {
    0x828e3cf0, 0x11e9, 0x45fc, {0xa5, 0xdb, 0x39, 0x49, 0x91, 0xad, 0x00, 0x93}};

// {BED5C2CB-27F6-455D-AB13-CD2BB19B670B}
inline constexpr GUID kTraditionalChineseProfileGuid = {
    0xbed5c2cb, 0x27f6, 0x455d, {0xab, 0x13, 0xcd, 0x2b, 0xb1, 0x9b, 0x67, 0x0b}};

inline constexpr LANGID kTraditionalChineseLangId = 0x0404;
inline constexpr wchar_t kTextServiceDescription[] = L"琦琦輸入法";
inline constexpr wchar_t kThreadingModel[] = L"Apartment";

}  // namespace KeyKey::WindowsTsf

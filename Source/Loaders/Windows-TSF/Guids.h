#pragma once

#include <Windows.h>

namespace KeyKey::WindowsTsf {

// {828E3CF0-11E9-45FC-A5DB-394991AD0093}
inline constexpr CLSID kTextServiceClsid = {
    0x828e3cf0, 0x11e9, 0x45fc, {0xa5, 0xdb, 0x39, 0x49, 0x91, 0xad, 0x00, 0x93}};

// {BED5C2CB-27F6-455D-AB13-CD2BB19B670B}
inline constexpr GUID kTraditionalChineseProfileGuid = {
    0xbed5c2cb, 0x27f6, 0x455d, {0xab, 0x13, 0xcd, 0x2b, 0xb1, 0x9b, 0x67, 0x0b}};

// Keep the Taiwan profile GUID stable for existing installations.
inline constexpr GUID kHongKongProfileGuid = {
    0xba8f9f0a, 0x28ab, 0x4153, {0x91, 0x6f, 0x14, 0xdd, 0x65, 0xe7, 0x39, 0xd4}};
inline constexpr GUID kMacaoProfileGuid = {
    0xf5a64310, 0x9a9b, 0x48d4, {0x9f, 0x0e, 0x8b, 0x8c, 0x28, 0xf8, 0xc5, 0xbd}};

// The active composition uses an explicit underline display attribute.
inline constexpr GUID kCompositionDisplayAttributeGuid = {
    0xd6a94965, 0x4202, 0x4da7, {0x8d, 0x62, 0x1e, 0x4a, 0xcf, 0x48, 0x2d, 0x3d}};

inline constexpr LANGID kTraditionalChineseLangId = 0x0404;
inline constexpr LANGID kHongKongLangId = 0x0c04;
inline constexpr LANGID kMacaoLangId = 0x1404;
inline constexpr wchar_t kTextServiceDescription[] = L"琦琦輸入法";
inline constexpr wchar_t kThreadingModel[] = L"Apartment";

}  // namespace KeyKey::WindowsTsf

#include <Windows.h>
#include <ctffunc.h>
#include <msctf.h>

#include <iostream>
#include <string>

#include "Guids.h"

namespace {

std::wstring ModuleDirectory() {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                            static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    const size_t separator = path.find_last_of(L"\\/");
    return separator == std::wstring::npos ? std::wstring()
                                           : path.substr(0, separator);
}

}  // namespace

int wmain() {
    const std::wstring dllPath = ModuleDirectory() + L"\\KeyKeyTsf.dll";
    HMODULE module = LoadLibraryW(dllPath.c_str());
    if (!module) {
        std::cerr << "Unable to load KeyKeyTsf.dll\n";
        return 1;
    }
    using GetClassObject = HRESULT(__stdcall*)(REFCLSID, REFIID, void**);
    const auto getClassObject = reinterpret_cast<GetClassObject>(
        GetProcAddress(module, "DllGetClassObject"));
    if (!getClassObject) return 2;
    using QueryState = HRESULT(__stdcall*)(DWORD*);
    const auto queryState = reinterpret_cast<QueryState>(
        GetProcAddress(module, "KeyKeyQueryTsfState"));
    if (!queryState || !GetProcAddress(module, "KeyKeyRestoreTsfState") ||
        !GetProcAddress(module, "KeyKeyRegisterTsfState")) return 13;
    DWORD registrationState = 0;
    // Query only: this smoke test never registers, activates or removes an IME.
    if (FAILED(queryState(&registrationState))) return 14;
    // Existing machine definitions must remain visible even to an account
    // with no Traditional Chinese language installed (including the sandbox).
    using namespace KeyKey::WindowsTsf;
    const LANGID languages[] = { kTraditionalChineseLangId, kHongKongLangId, kMacaoLangId };
    const GUID profileGuids[] = { kTraditionalChineseProfileGuid, kHongKongProfileGuid, kMacaoProfileGuid };
    wchar_t clsid[40]{};
    StringFromGUID2(kTextServiceClsid, clsid, 40);
    for (unsigned int i = 0; i < 3; ++i) {
        wchar_t language[16]{}, profile[40]{};
        swprintf_s(language, L"0x%08x", static_cast<unsigned int>(languages[i]));
        StringFromGUID2(profileGuids[i], profile, 40);
        const auto key = std::wstring(L"Software\\Microsoft\\CTF\\TIP\\") + clsid +
            L"\\LanguageProfile\\" + language + L"\\" + profile;
        HKEY definition = nullptr;
        const LONG opened = RegOpenKeyExW(HKEY_LOCAL_MACHINE, key.c_str(), 0, KEY_READ, &definition);
        if (definition) RegCloseKey(definition);
        if (opened == ERROR_SUCCESS && !(registrationState & (1u << i))) return 15;
        if (opened != ERROR_SUCCESS && opened != ERROR_FILE_NOT_FOUND && opened != ERROR_PATH_NOT_FOUND) return 16;
    }

    IClassFactory* factory = nullptr;
    HRESULT result = getClassObject(KeyKey::WindowsTsf::kTextServiceClsid,
                                    IID_IClassFactory,
                                    reinterpret_cast<void**>(&factory));
    if (FAILED(result) || !factory) return 3;

    ITfFnConfigure* configure = nullptr;
    result = factory->CreateInstance(nullptr, IID_ITfFnConfigure,
                                     reinterpret_cast<void**>(&configure));
    factory->Release();
    if (FAILED(result) || !configure) return 4;

    BSTR displayName = nullptr;
    result = configure->GetDisplayName(&displayName);
    if (FAILED(result) || !displayName || !SysStringLen(displayName)) return 5;
    SysFreeString(displayName);

    ITfTextEditSink* textEditSink = nullptr;
    result = configure->QueryInterface(IID_ITfTextEditSink,
                                       reinterpret_cast<void**>(&textEditSink));
    if (FAILED(result) || !textEditSink) return 6;
    textEditSink->Release();

    ITfDisplayAttributeProvider* displayProvider = nullptr;
    result = configure->QueryInterface(IID_ITfDisplayAttributeProvider,
                                       reinterpret_cast<void**>(&displayProvider));
    if (FAILED(result) || !displayProvider) return 9;
    IEnumTfDisplayAttributeInfo* attributes = nullptr;
    result = displayProvider->EnumDisplayAttributeInfo(&attributes);
    if (FAILED(result) || !attributes) return 10;
    ITfDisplayAttributeInfo* attributeInfo = nullptr;
    ULONG fetched = 0;
    result = attributes->Next(1, &attributeInfo, &fetched);
    attributes->Release();
    displayProvider->Release();
    if (FAILED(result) || fetched != 1 || !attributeInfo) return 11;
    GUID attributeGuid{};
    TF_DISPLAYATTRIBUTE attribute{};
    result = attributeInfo->GetGUID(&attributeGuid);
    if (SUCCEEDED(result)) result = attributeInfo->GetAttributeInfo(&attribute);
    attributeInfo->Release();
    if (FAILED(result) ||
        attributeGuid != KeyKey::WindowsTsf::kCompositionDisplayAttributeGuid ||
        attribute.lsStyle != TF_LS_SOLID || attribute.bAttr != TF_ATTR_INPUT) {
        return 12;
    }

    ITfFunctionProvider* provider = nullptr;
    result = configure->QueryInterface(IID_ITfFunctionProvider,
                                       reinterpret_cast<void**>(&provider));
    if (FAILED(result) || !provider) return 7;
    IUnknown* function = nullptr;
    result = provider->GetFunction(GUID_NULL, IID_ITfFnConfigure, &function);
    provider->Release();
    configure->Release();
    if (FAILED(result) || !function) return 8;
    function->Release();
    FreeLibrary(module);
    std::cout << "TSF configure and display attribute interfaces passed.\n";
    return 0;
}

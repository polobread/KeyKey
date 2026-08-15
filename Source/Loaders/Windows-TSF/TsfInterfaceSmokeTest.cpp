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

    ITfFunctionProvider* provider = nullptr;
    result = configure->QueryInterface(IID_ITfFunctionProvider,
                                       reinterpret_cast<void**>(&provider));
    if (FAILED(result) || !provider) return 6;
    IUnknown* function = nullptr;
    result = provider->GetFunction(GUID_NULL, IID_ITfFnConfigure, &function);
    provider->Release();
    configure->Release();
    if (FAILED(result) || !function) return 7;
    function->Release();
    FreeLibrary(module);
    std::cout << "TSF configure interface smoke test passed.\n";
    return 0;
}

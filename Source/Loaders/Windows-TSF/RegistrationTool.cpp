#include <Windows.h>
#include <iostream>
#include <string>

// Architecture bridge used by the deployment transaction, never a user IME
// activation entrypoint. The caller verifies the packaged DLL before loading.
int wmain(int argc, wchar_t** argv) {
    if (argc < 3) return 2;
    const std::wstring operation = argv[1];
    if (operation != L"query" && operation != L"restore" && operation != L"register" && operation != L"retire") return 2;
    HMODULE module = LoadLibraryExW(argv[2], nullptr,
        LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!module) return 3;
    HRESULT result = E_FAIL;
    if (operation == L"query") {
        using Query = HRESULT(__stdcall*)(DWORD*);
        const auto query = reinterpret_cast<Query>(GetProcAddress(module, "KeyKeyQueryTsfState"));
        DWORD mask = 0;
        if (query) result = query(&mask);
        if (SUCCEEDED(result)) std::cout << mask << '\n';
    } else if (operation == L"register") {
        using Register = HRESULT(__stdcall*)(DWORD*);
        const auto registration = reinterpret_cast<Register>(GetProcAddress(module, "KeyKeyRegisterTsfState"));
        DWORD stage = 0;
        if (registration) result = registration(&stage);
        if (FAILED(result)) std::cerr << "registration stage " << stage << ": ";
    } else if (operation == L"retire" && argc == 3) {
        using Retire = HRESULT(__stdcall*)(DWORD*);
        const auto retire = reinterpret_cast<Retire>(GetProcAddress(module, "KeyKeyRetireLegacyProfiles"));
        DWORD remaining = 0;
        if (retire) result = retire(&remaining);
        if (SUCCEEDED(result)) std::cout << remaining << '\n';
    } else if (operation == L"restore" && argc == 4) {
        using Restore = HRESULT(__stdcall*)(DWORD);
        const auto restore = reinterpret_cast<Restore>(GetProcAddress(module, "KeyKeyRestoreTsfState"));
        try {
            std::size_t end = 0;
            const auto mask = std::stoul(argv[3], &end);
            if (end == std::wstring(argv[3]).size()) {
                if (restore) result = restore(static_cast<DWORD>(mask));
            }
        } catch (...) { result = E_INVALIDARG; }
    }
    FreeLibrary(module);
    if (FAILED(result)) std::cerr << "TSF transaction failed: 0x" << std::hex << result << '\n';
    return SUCCEEDED(result) ? 0 : 1;
}

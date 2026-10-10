#include <Windows.h>
#include <msctf.h>
#include <cstddef>
#include <iterator>
#include <new>
#include <mutex>
#include <string>

#include "Guids.h"
#include "ModuleState.h"
#include "TextService.h"

using namespace KeyKey::WindowsTsf;

HMODULE KeyKey::WindowsTsf::g_module = nullptr;
std::atomic<long> KeyKey::WindowsTsf::g_objectCount{0};
std::atomic<long> KeyKey::WindowsTsf::g_serverLocks{0};

namespace {

thread_local DWORD g_registrationStage = 0;
// Serialize an idle cleanup with new class-factory acquisition. Existing
// factories/services keep g_objectCount nonzero throughout member destruction.
std::mutex g_unloadMutex;

class ClassFactory final : public IClassFactory {
public:
    ClassFactory() { ++g_objectCount; }

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_INVALIDARG;
        *object = nullptr;
        if (iid == IID_IUnknown || iid == IID_IClassFactory) {
            *object = static_cast<IClassFactory*>(this);
            AddRef();
            return S_OK;
        }
        return E_NOINTERFACE;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override {
        const ULONG remaining = --references_;
        if (!remaining) delete this;
        return remaining;
    }
    STDMETHODIMP CreateInstance(IUnknown* outer, REFIID iid, void** object) override {
        return TextService::CreateInstance(outer, iid, object);
    }
    STDMETHODIMP LockServer(BOOL lock) override {
        lock ? ++g_serverLocks : --g_serverLocks;
        return S_OK;
    }

private:
    ~ClassFactory() { --g_objectCount; }
    std::atomic<ULONG> references_{1};
};

std::wstring GuidString(REFGUID guid) {
    wchar_t text[40]{};
    return StringFromGUID2(guid, text, static_cast<int>(std::size(text))) ? text
                                                                          : L"";
}

HRESULT SetRegistryString(HKEY root, const std::wstring& keyPath,
                          const wchar_t* valueName, const std::wstring& value) {
    HKEY key = nullptr;
    const LONG opened = RegCreateKeyExW(root, keyPath.c_str(), 0, nullptr, 0,
                                        KEY_WRITE, nullptr, &key, nullptr);
    if (opened != ERROR_SUCCESS) return HRESULT_FROM_WIN32(opened);
    const LONG written = RegSetValueExW(
        key, valueName, 0, REG_SZ, reinterpret_cast<const BYTE*>(value.c_str()),
        static_cast<DWORD>((value.size() + 1) * sizeof(wchar_t)));
    RegCloseKey(key);
    return HRESULT_FROM_WIN32(written);
}

HRESULT RegisterComServer() {
    wchar_t modulePath[32768]{};
    const DWORD length = GetModuleFileNameW(g_module, modulePath,
                                            static_cast<DWORD>(std::size(modulePath)));
    if (!length || length >= std::size(modulePath)) return HRESULT_FROM_WIN32(GetLastError());

    const std::wstring classKey = L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid);
    HRESULT result = SetRegistryString(HKEY_LOCAL_MACHINE, classKey, nullptr,
                                       kTextServiceDescription);
    if (FAILED(result)) return result;
    result = SetRegistryString(HKEY_LOCAL_MACHINE, classKey + L"\\InprocServer32",
                               nullptr, modulePath);
    if (FAILED(result)) return result;
    return SetRegistryString(HKEY_LOCAL_MACHINE, classKey + L"\\InprocServer32",
                             L"ThreadingModel", kThreadingModel);
}

HRESULT UnregisterComServer() {
    const std::wstring classKey = L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid);
    const LONG result = RegDeleteTreeW(HKEY_LOCAL_MACHINE, classKey.c_str());
    return result == ERROR_FILE_NOT_FOUND ? S_OK : HRESULT_FROM_WIN32(result);
}

struct LanguageProfile {
    LANGID languageId;
    GUID profileGuid;
};

// All regions share the Taiwan profile. The old regional GUIDs are retained
// here only to identify exactly which obsolete definitions to unregister.
constexpr LanguageProfile kLanguageProfiles[] = {
    {kTraditionalChineseLangId, kTraditionalChineseProfileGuid},
    {kHongKongLangId, kHongKongProfileGuid},
    {kMacaoLangId, kMacaoProfileGuid},
};

HRESULT ProfileExists(ITfInputProcessorProfileMgr* manager,
                      const LanguageProfile& profile, bool* exists) {
    *exists = false;
    // Definitions are machine-wide. TSF can retain a removed definition in its
    // process cache; a surviving HKCU Enable value is not a registration.
    wchar_t language[16]{};
    swprintf_s(language, L"0x%08x", static_cast<unsigned int>(profile.languageId));
    const auto key = L"Software\\Microsoft\\CTF\\TIP\\" + GuidString(kTextServiceClsid) +
        L"\\LanguageProfile\\" + language + L"\\" + GuidString(profile.profileGuid);
    HKEY definition = nullptr;
    const LONG opened = RegOpenKeyExW(HKEY_LOCAL_MACHINE, key.c_str(), 0, KEY_READ, &definition);
    if (definition) RegCloseKey(definition);
    if (opened == ERROR_FILE_NOT_FOUND || opened == ERROR_PATH_NOT_FOUND) return S_OK;
    if (opened != ERROR_SUCCESS) return HRESULT_FROM_WIN32(opened);
    ITfInputProcessorProfiles* definitions = nullptr;
    HRESULT result = manager->QueryInterface(IID_PPV_ARGS(&definitions));
    if (FAILED(result)) return result;
    // Description queries find disabled profiles even without that language
    // installed for the current (possibly different UAC) account.
    BSTR description = nullptr;
    result = definitions->GetLanguageProfileDescription(kTextServiceClsid,
        profile.languageId, profile.profileGuid, &description);
    SysFreeString(description);
    definitions->Release();
    if (result == S_OK) { *exists = true; return S_OK; }
    return FAILED(result) ? result : E_UNEXPECTED;
}

HRESULT RegisterProfile() {
    wchar_t modulePath[32768]{};
    const DWORD length = GetModuleFileNameW(g_module, modulePath,
                                            static_cast<DWORD>(std::size(modulePath)));
    if (!length || length >= std::size(modulePath)) return HRESULT_FROM_WIN32(GetLastError());

    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (FAILED(result)) return result;
    bool created[std::size(kLanguageProfiles)]{};
    std::size_t index = 0;
    for (const auto& profile : kLanguageProfiles) {
        g_registrationStage = static_cast<DWORD>(10 + index);
        bool existing = false;
        result = ProfileExists(profiles, profile, &existing);
        if (FAILED(result)) break;
        if (existing) {
            ++index;
            continue;
        }
        if (index != 0) { ++index; continue; }
        result = profiles->RegisterProfile(
            kTextServiceClsid, profile.languageId, profile.profileGuid,
            kTextServiceDescription, static_cast<ULONG>(wcslen(kTextServiceDescription)),
            modulePath, length, 0, nullptr, 0,
            FALSE, 0);
        if (FAILED(result)) break;
        created[index++] = true;
    }
    if (FAILED(result)) {
        for (std::size_t i = 0; i < std::size(kLanguageProfiles); ++i) {
            if (created[i]) {
                const auto& profile = kLanguageProfiles[i];
                profiles->UnregisterProfile(kTextServiceClsid, profile.languageId,
                                            profile.profileGuid, 0);
            }
        }
    }
    profiles->Release();
    return result;
}

HRESULT UnregisterProfile() {
    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (SUCCEEDED(result)) {
        for (const auto& profile : kLanguageProfiles) {
            bool existing = false;
            const HRESULT queried = ProfileExists(profiles, profile, &existing);
            if (FAILED(queried)) { if (SUCCEEDED(result)) result = queried; continue; }
            if (existing) {
                const HRESULT removed = profiles->UnregisterProfile(
                    kTextServiceClsid, profile.languageId, profile.profileGuid, 0);
                if (FAILED(removed) && SUCCEEDED(result)) result = removed;
            }
        }
        profiles->Release();
    }
    return result;
}

// The input-mode compartment lets Windows and the TIP share the visible
// Chinese/English state. System-tray support surfaces the language-bar state
// buttons, while immersive support makes the TIP available to modern Windows
// text hosts such as Start/Search and Store apps.
const GUID kCategories[] = {
    GUID_TFCAT_TIP_KEYBOARD,
    GUID_TFCAT_DISPLAYATTRIBUTEPROVIDER,
    GUID_TFCAT_TIPCAP_INPUTMODECOMPARTMENT,
    GUID_TFCAT_TIPCAP_SYSTRAYSUPPORT,
    GUID_TFCAT_TIPCAP_IMMERSIVESUPPORT,
};

HRESULT RegisterCategories() {
    ITfCategoryMgr* manager = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager));
    if (FAILED(result)) return result;
    for (const GUID& category : kCategories) {
        result = manager->RegisterCategory(kTextServiceClsid, category,
                                           kTextServiceClsid);
        if (FAILED(result)) break;
    }
    manager->Release();
    return result;
}

HRESULT UnregisterCategories() {
    ITfCategoryMgr* manager = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                   CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager));
    if (SUCCEEDED(result)) {
        for (const GUID& category : kCategories) {
            const HRESULT removed = manager->UnregisterCategory(
                kTextServiceClsid, category, kTextServiceClsid);
            if (FAILED(removed) && SUCCEEDED(result)) result = removed;
        }
        manager->Release();
    }
    return result;
}

std::wstring RegisteredModule() {
    const std::wstring key = L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid) + L"\\InprocServer32";
    wchar_t value[32768]{};
    DWORD size = sizeof(value);
    if (RegGetValueW(HKEY_LOCAL_MACHINE, key.c_str(), nullptr, RRF_RT_REG_SZ,
                    nullptr, value, &size) != ERROR_SUCCESS) return L"";
    return value;
}

HRESULT QueryTsfState(DWORD* mask, DWORD* failureStage = nullptr) {
    if (!mask) return E_POINTER;
    *mask = 0;
    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (FAILED(result)) return result;
    for (std::size_t i = 0; i < std::size(kLanguageProfiles); ++i) {
        bool existing = false;
        const auto& profile = kLanguageProfiles[i];
        const HRESULT queried = ProfileExists(profiles, profile, &existing);
        if (FAILED(queried)) {
            if (failureStage) *failureStage = static_cast<DWORD>(100 + i);
            profiles->Release();
            return queried;
        }
        if (existing) {
            *mask |= (1u << i);
        }
    }
    profiles->Release();
    // EnumCategoriesInItem caches the initially empty list in an STA apartment.
    // After registration and DLL reload it may still enumerate zero categories,
    // despite all five machine definitions existing. Deployment snapshots must
    // inspect the persisted definitions, independent of apartment/user caches.
    // Only read our exact product keys; all registration/removal uses TSF APIs.
    for (std::size_t i = 0; i < std::size(kCategories); ++i) {
        const auto key = L"Software\\Microsoft\\CTF\\TIP\\" + GuidString(kTextServiceClsid) +
            L"\\Category\\Item\\" + GuidString(kTextServiceClsid) + L"\\" + GuidString(kCategories[i]);
        HKEY definition = nullptr;
        const LONG opened = RegOpenKeyExW(HKEY_LOCAL_MACHINE, key.c_str(), 0, KEY_READ, &definition);
        if (definition) RegCloseKey(definition);
        if (opened == ERROR_SUCCESS) *mask |= (1u << (8 + i));
        else if (opened != ERROR_FILE_NOT_FOUND && opened != ERROR_PATH_NOT_FOUND) {
            if (failureStage) *failureStage = static_cast<DWORD>(200 + i);
            return HRESULT_FROM_WIN32(opened);
        }
    }
    return S_OK;
}

// Remove transaction additions without changing existing keyboard choices.
HRESULT RestoreTsfState(DWORD mask) {
    DWORD current = 0;
    HRESULT result = QueryTsfState(&current);
    if (FAILED(result)) return result;
    ITfInputProcessorProfileMgr* profiles = nullptr;
    result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                              CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (FAILED(result)) return result;
    for (std::size_t i = 0; i < std::size(kLanguageProfiles); ++i) {
        if ((current & (1u << i)) && !(mask & (1u << i))) {
            const auto& p = kLanguageProfiles[i];
            const HRESULT removed = profiles->UnregisterProfile(
                kTextServiceClsid, p.languageId, p.profileGuid, 0);
            if (FAILED(removed) && SUCCEEDED(result)) result = removed;
        }
    }
    profiles->Release();
    ITfCategoryMgr* manager = nullptr;
    const HRESULT opened = CoCreateInstance(CLSID_TF_CategoryMgr, nullptr,
                                            CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager));
    if (FAILED(opened)) return opened;
    for (std::size_t i = 0; i < std::size(kCategories); ++i) {
        const DWORD bit = 1u << (8 + i);
        if ((current & bit) && !(mask & bit)) {
            const HRESULT removed = manager->UnregisterCategory(
                kTextServiceClsid, kCategories[i], kTextServiceClsid);
            if (FAILED(removed) && SUCCEEDED(result)) result = removed;
        }
    }
    manager->Release();
    return result;
}

class ComScope final {
public:
    ComScope() : result_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
    ~ComScope() {
        if (SUCCEEDED(result_)) CoUninitialize();
    }
    HRESULT result() const {
        return result_ == RPC_E_CHANGED_MODE ? S_OK : result_;
    }

private:
    HRESULT result_;
};

}  // namespace

BOOL APIENTRY DllMain(HMODULE module, DWORD reason, LPVOID) {
    if (reason == DLL_PROCESS_ATTACH) {
        g_module = module;
        DisableThreadLibraryCalls(module);
    }
    return TRUE;
}

extern "C" HRESULT __stdcall DllCanUnloadNow() {
    std::lock_guard<std::mutex> lock(g_unloadMutex);
    if (g_objectCount.load() || g_serverLocks.load()) return S_FALSE;
    // COM calls this outside DllMain. Do not move User32 or engine teardown
    // into DLL_PROCESS_DETACH, where the loader lock would be held.
    if (!CandidateWindow::releaseWindowClass() || !SymbolPanel::releaseWindowClasses())
        return S_FALSE;
    return ShutdownEngineRuntime() ? S_OK : S_FALSE;
}

extern "C" HRESULT __stdcall DllGetClassObject(REFCLSID clsid, REFIID iid,
                                                void** object) {
    std::lock_guard<std::mutex> lock(g_unloadMutex);
    if (!object) return E_INVALIDARG;
    *object = nullptr;
    if (clsid != kTextServiceClsid) return CLASS_E_CLASSNOTAVAILABLE;
    auto* factory = new (std::nothrow) ClassFactory();
    if (!factory) return E_OUTOFMEMORY;
    const HRESULT result = factory->QueryInterface(iid, object);
    factory->Release();
    return result;
}

extern "C" HRESULT __stdcall DllRegisterServer() {
    g_registrationStage = 1;
    ComScope com;
    HRESULT result = com.result();
    if (FAILED(result)) return result;
    const std::wstring previousModule = RegisteredModule();
    DWORD previousState = 0;
    result = QueryTsfState(&previousState, &g_registrationStage);
    if (FAILED(result)) return result;
    g_registrationStage = 2;
    result = RegisterComServer();
    if (FAILED(result)) {
        if (previousModule.empty()) UnregisterComServer();
        else SetRegistryString(HKEY_LOCAL_MACHINE,
            L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid) + L"\\InprocServer32",
            nullptr, previousModule);
        return result;
    }
    result = RegisterProfile();
    if (FAILED(result)) {
        RestoreTsfState(previousState);
        if (previousModule.empty()) UnregisterComServer();
        else SetRegistryString(HKEY_LOCAL_MACHINE,
            L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid) + L"\\InprocServer32",
            nullptr, previousModule);
        return result;
    }
    g_registrationStage = 20;
    result = RegisterCategories();
    if (FAILED(result)) {
        RestoreTsfState(previousState);
        if (previousModule.empty()) UnregisterComServer();
        else SetRegistryString(HKEY_LOCAL_MACHINE,
            L"Software\\Classes\\CLSID\\" + GuidString(kTextServiceClsid) + L"\\InprocServer32",
            nullptr, previousModule);
    }
    return result;
}

// Return the actual HRESULT and phase instead of regsvr32's generic exit 5.
extern "C" HRESULT __stdcall KeyKeyRegisterTsfState(DWORD* stage) {
    if (!stage) return E_POINTER;
    const HRESULT result = DllRegisterServer();
    *stage = g_registrationStage;
    return result;
}

extern "C" HRESULT __stdcall DllUnregisterServer() {
    ComScope com;
    if (FAILED(com.result())) return com.result();
    wchar_t modulePath[32768]{};
    GetModuleFileNameW(g_module, modulePath, static_cast<DWORD>(std::size(modulePath)));
    const auto registered = RegisteredModule();
    if (registered.empty()) return S_FALSE;
    if (!registered.empty() && _wcsicmp(registered.c_str(), modulePath) != 0)
        return HRESULT_FROM_WIN32(ERROR_REVISION_MISMATCH);
    HRESULT result = UnregisterProfile();
    if (FAILED(result)) return result;
    result = UnregisterCategories();
    if (FAILED(result)) return result;
    return UnregisterComServer();
}

// Used only by the deployment transaction. Neither function enables a profile.
extern "C" HRESULT __stdcall KeyKeyQueryTsfState(DWORD* mask) {
    ComScope com;
    return FAILED(com.result()) ? com.result() : QueryTsfState(mask);
}

extern "C" HRESULT __stdcall KeyKeyRestoreTsfState(DWORD mask) {
    ComScope com;
    return FAILED(com.result()) ? com.result() : RestoreTsfState(mask);
}

// Runs only after the installation commits. Retire our two obsolete regional
// definitions; preserve the shared profile and let users select it in Settings.
extern "C" HRESULT __stdcall KeyKeyRetireLegacyProfiles(DWORD* remaining) {
    if (!remaining) return E_INVALIDARG;
    ComScope com;
    if (FAILED(com.result())) return com.result();
    ITfInputProcessorProfileMgr* profiles = nullptr;
    HRESULT result = CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                                      CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&profiles));
    if (FAILED(result)) return result;
    for (std::size_t i = 1; i < std::size(kLanguageProfiles); ++i) {
        const auto& profile = kLanguageProfiles[i];
        bool existing = false;
        result = ProfileExists(profiles, profile, &existing);
        if (FAILED(result)) break;
        if (!existing) continue;
        result = profiles->UnregisterProfile(kTextServiceClsid, profile.languageId, profile.profileGuid, 0);
        if (FAILED(result)) break;
    }
    profiles->Release();
    return FAILED(result) ? result : QueryTsfState(remaining);
}

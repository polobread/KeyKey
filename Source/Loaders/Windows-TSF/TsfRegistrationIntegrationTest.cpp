#include <Windows.h>
#include <msctf.h>
#include <iostream>
#include <stdexcept>
#include <string>
#include "Guids.h"

using namespace KeyKey::WindowsTsf;

namespace {
void Check(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Success(HRESULT value, const char* message) {
    if (FAILED(value)) { std::cerr << message << ": HRESULT 0x" << std::hex << value << '\n'; throw std::runtime_error(message); }
}
std::wstring GuidText(REFGUID guid) { wchar_t text[40]{}; StringFromGUID2(guid,text,40); return text; }
struct Isolation {
    HKEY root = nullptr, machine = nullptr, user = nullptr;
    std::wstring path;
    bool owner = true;
    explicit Isolation(const wchar_t* existing = nullptr) {
        try {
        GUID id{};
        if (existing) {
            Check(wcslen(existing)==38,"isolation GUID length");
            Success(CLSIDFromString(existing,&id),"isolation GUID");
            owner=false;
        } else Success(CoCreateGuid(&id), "GUID");
        path = L"Software\\KeyKeyDeploymentIsolation\\" + GuidText(id);
        Check(RegCreateKeyExW(HKEY_CURRENT_USER,path.c_str(),0,nullptr,0,KEY_ALL_ACCESS,nullptr,&root,nullptr)==ERROR_SUCCESS,"isolation create");
        Check(RegCreateKeyExW(root,L"Machine",0,nullptr,0,KEY_ALL_ACCESS,nullptr,&machine,nullptr)==ERROR_SUCCESS,"machine hive");
        Check(RegCreateKeyExW(root,L"User",0,nullptr,0,KEY_ALL_ACCESS,nullptr,&user,nullptr)==ERROR_SUCCESS,"user hive");
        Check(RegOverridePredefKey(HKEY_LOCAL_MACHINE,machine)==ERROR_SUCCESS,"machine override");
        Check(RegOverridePredefKey(HKEY_CURRENT_USER,user)==ERROR_SUCCESS,"user override");
        } catch (...) { Reset(); throw; }
    }
    void Reset() {
        RegOverridePredefKey(HKEY_LOCAL_MACHINE,nullptr);
        RegOverridePredefKey(HKEY_CURRENT_USER,nullptr);
        if(user)RegCloseKey(user);
        if(machine)RegCloseKey(machine);
        if(root)RegCloseKey(root);
        user=machine=root=nullptr;
        if(owner && !path.empty())RegDeleteTreeW(HKEY_CURRENT_USER,path.c_str());
        path.clear();
    }
    ~Isolation() { Reset(); }
};
std::wstring ProfilePath(LANGID language, REFGUID guid) {
    wchar_t text[16]{}; swprintf_s(text,L"0x%08x",static_cast<unsigned>(language));
    return L"Software\\Microsoft\\CTF\\TIP\\"+GuidText(kTextServiceClsid)+L"\\LanguageProfile\\"+text+L"\\"+GuidText(guid);
}
DWORD Number(HKEY root, const std::wstring& path, const wchar_t* name) {
    DWORD value=0,size=sizeof(value);
    Check(RegGetValueW(root,path.c_str(),name,RRF_RT_REG_DWORD,nullptr,&value,&size)==ERROR_SUCCESS,"read number"); return value;
}
void UserSelection(const std::wstring& path) {
    HKEY key=nullptr; Check(RegCreateKeyExW(HKEY_CURRENT_USER,path.c_str(),0,nullptr,0,KEY_WRITE,nullptr,&key,nullptr)==ERROR_SUCCESS,"seed user selection");
    const DWORD value=1; const LONG result=RegSetValueExW(key,L"Enable",0,REG_DWORD,reinterpret_cast<const BYTE*>(&value),sizeof(value)); RegCloseKey(key); Check(result==ERROR_SUCCESS,"write user selection");
}
}

int wmain(int argc, wchar_t** argv) {
    if (argc==3) {
        try {
            wchar_t executable[32768]{}; GetModuleFileNameW(nullptr,executable,32768);
            std::wstring dll=executable; dll.resize(dll.find_last_of(L"\\/")); dll+=L"\\KeyKeyTsf.dll";
            HMODULE module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
            Check(module!=nullptr,"worker DLL");
            using Query=HRESULT(__stdcall*)(DWORD*);
            using Restore=HRESULT(__stdcall*)(DWORD);
            auto registration=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyRegisterTsfState"));
            auto query=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyQueryTsfState"));
            auto restore=reinterpret_cast<Restore>(GetProcAddress(module,"KeyKeyRestoreTsfState"));
            Isolation isolated(argv[2]);
            DWORD value=0;
            const std::wstring operation=argv[1];
            if(operation==L"transaction") {
                Success(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"installer apartment");
                Success(query(&value),"child transaction snapshot");
                Check(value==0,"transaction initial state");
                FreeLibrary(module);
                module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
                registration=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyRegisterTsfState"));
                Success(registration(&value),"child transaction register");
                FreeLibrary(module);
                module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
                query=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyQueryTsfState"));
                Success(query(&value),"child transaction verification");
                if (value!=0x1f01) return static_cast<int>(0x10000u | value);
                CoUninitialize();
            }
            else if(operation==L"register") Success(registration(&value),"child register");
            else if(operation==L"remove") Success(restore(0),"child remove");
            else {
                Success(query(&value),"child query");
                std::wcerr<<L"child "<<operation<<L" mask=0x"<<std::hex<<value<<L'\n';
                Check(value==(operation==L"verify"?0x1f01u:0u),"fresh process registration state");
            }
            FreeLibrary(module);
            return 0;
        } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
    }
    Success(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED),"COM");
    ITfInputProcessorProfileMgr* profiles=nullptr;
    ITfCategoryMgr* categories=nullptr;
    Success(CoCreateInstance(CLSID_TF_InputProcessorProfiles,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&profiles)),"profile manager");
    Success(CoCreateInstance(CLSID_TF_CategoryMgr,nullptr,CLSCTX_INPROC_SERVER,IID_PPV_ARGS(&categories)),"category manager");
    wchar_t executable[32768]{}; GetModuleFileNameW(nullptr,executable,32768);
    std::wstring directory=executable; directory.resize(directory.find_last_of(L"\\/"));
    const auto dll=directory+L"\\KeyKeyTsf.dll";
    HMODULE module=LoadLibraryExW(dll.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_SYSTEM32);
    Check(module!=nullptr,"load test DLL");
    using Query=HRESULT(__stdcall*)(DWORD*);
    using Retire=HRESULT(__stdcall*)(DWORD*);
    using Restore=HRESULT(__stdcall*)(DWORD);
    auto registration=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyRegisterTsfState"));
    auto query=reinterpret_cast<Query>(GetProcAddress(module,"KeyKeyQueryTsfState"));
    auto retire=reinterpret_cast<Retire>(GetProcAddress(module,"KeyKeyRetireLegacyProfiles"));
    auto restore=reinterpret_cast<Restore>(GetProcAddress(module,"KeyKeyRestoreTsfState"));
    Check(registration && query && retire && restore,"exports");
    int result=0;
    try {
        Isolation isolated;
        DWORD stage=0,mask=0;
        const HRESULT registered = registration(&stage);
        if (FAILED(registered)) std::cerr << "stage=" << stage << '\n';
        Success(registered,"fresh native registration");
        Success(query(&mask),"query fresh"); Check(mask==0x1f01,"fresh must create only Taiwan");
        std::cout<<"PASS fresh native registration creates only Taiwan\n";
        for (auto language : {kHongKongLangId,kMacaoLangId}) {
            const GUID& guid=language==kHongKongLangId?kHongKongProfileGuid:kMacaoProfileGuid;
            Success(profiles->RegisterProfile(kTextServiceClsid,language,guid,L"琦琦輸入法",5,dll.c_str(),static_cast<ULONG>(dll.size()),0,nullptr,0,FALSE,0),"seed legacy");
        }
        Success(registration(&stage),"upgrade native registration");
        Success(retire(&mask),"remove unused regional profiles"); Check(mask==0x1f01,"unused regional profiles must disappear");
        std::cout<<"PASS native upgrade and unused regional removal\n";
        const auto shared=ProfilePath(kTraditionalChineseLangId,kTraditionalChineseProfileGuid);
        UserSelection(shared);
        for (auto language : {kHongKongLangId,kMacaoLangId}) {
            const GUID& guid=language==kHongKongLangId?kHongKongProfileGuid:kMacaoProfileGuid;
            Success(profiles->RegisterProfile(kTextServiceClsid,language,guid,L"琦琦輸入法",5,dll.c_str(),static_cast<ULONG>(dll.size()),0,nullptr,0,TRUE,0),"seed enabled legacy");
            UserSelection(ProfilePath(language,guid));
        }
        Success(retire(&mask),"retire selected regional entries"); Check(mask==0x1f01,"only the shared entry must remain");
        Check(Number(HKEY_CURRENT_USER,shared,L"Enable")==1 && Number(HKEY_LOCAL_MACHINE,shared,L"Enable")==0,"retirement changed shared selection or machine default");
        std::cout<<"PASS selected regional entries retire while shared selection survives\n";
        Success(registration(&stage),"repeat registration"); Success(retire(&mask),"repeat cleanup");
        Check(mask==0x1f01 && Number(HKEY_CURRENT_USER,shared,L"Enable")==1,"rerun changed shared selection");
        std::cout<<"PASS native rerun preserves one shared entry\n";
        Success(restore(0),"native uninstall");
        Success(query(&mask),"query after uninstall"); Check(mask==0,"uninstall left registered profiles or categories");
        Success(registration(&stage),"native reinstall");
        Success(query(&mask),"query after reinstall"); Check(mask==0x1f01,"reinstall must create only Taiwan");
        std::cout<<"PASS native uninstall and reinstall\n";
    } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; result=1; }
    // Deployment calls Query/Register/Query through separate COM lifetimes.
    // A permanently initialized COM apartment masks registry-cache problems.
    categories->Release(); profiles->Release(); CoUninitialize();
    try {
        Isolation isolated;
        const auto shared=ProfilePath(kTraditionalChineseLangId,kTraditionalChineseProfileGuid);
        UserSelection(shared); // user selection survives an earlier uninstall
        DWORD stage=0,mask=0;
        Success(query(&mask),"deployment snapshot"); Check(mask==0,"snapshot must be empty");
        Success(registration(&stage),"deployment register");
        Success(query(&mask),"deployment verify");
        std::cerr<<"separate COM lifetime mask=0x"<<std::hex<<mask<<'\n';
        Check(mask==0x1f01,"deployment verify after separate COM lifetimes");
        Success(restore(0),"deployment remove");
        Success(query(&mask),"deployment removed snapshot"); Check(mask==0,"removed snapshot must be empty");
        Success(registration(&stage),"deployment reinstall");
        Success(query(&mask),"deployment reinstall verify"); Check(mask==0x1f01,"deployment reinstall must register main profile and categories");
        std::cout<<"PASS deployment COM lifetime boundaries and surviving user selection\n";
    } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; result=1; }
    try {
        Isolation isolated;
        UserSelection(ProfilePath(kTraditionalChineseLangId,kTraditionalChineseProfileGuid));
        const auto categoryRoot=L"Software\\Microsoft\\CTF\\TIP\\"+GuidText(kTextServiceClsid)+L"\\Category\\";
        // Unregister leaves empty parent keys. Reboot preserves them and HKCU
        // Enable even though the machine no longer defines the keyboard.
        for (const auto* suffix : {L"Item\\{828E3CF0-11E9-45FC-A5DB-394991AD0093}",
                L"Category\\{34745C63-B2F0-4784-8B67-5E12C8701A31}",
                L"Category\\{046B8C80-1647-40F7-9B21-B93B81AABC1B}",
                L"Category\\{CCF05DD7-4A87-11D7-A6E2-00065B84435C}",
                L"Category\\{13A016DF-560B-46CD-947A-4C3AF1E0E35D}",
                L"Category\\{25504FB4-7BAB-4BC1-9C69-CF81890F0EF5}"}) {
            HKEY key=nullptr;
            Check(RegCreateKeyExW(HKEY_LOCAL_MACHINE,(categoryRoot+suffix).c_str(),0,nullptr,0,KEY_WRITE,nullptr,&key,nullptr)==ERROR_SUCCESS,"seed empty category parent");
            RegCloseKey(key);
        }
        const auto id=isolated.path.substr(isolated.path.find_last_of(L"\\")+1);
        // Child processes must see the real HKCU root containing the sandbox,
        // not the parent's overridden User root. Keep handles for later cleanup.
        RegOverridePredefKey(HKEY_LOCAL_MACHINE,nullptr);
        RegOverridePredefKey(HKEY_CURRENT_USER,nullptr);
        for(const auto* operation : {L"empty",L"transaction",L"verify",L"remove",L"empty",L"transaction",L"verify"}) {
            std::wstring command=L"\""+std::wstring(executable)+L"\" "+operation+L" "+id;
            STARTUPINFOW start{sizeof(start)}; PROCESS_INFORMATION child{};
            Check(CreateProcessW(executable,command.data(),nullptr,nullptr,FALSE,CREATE_NO_WINDOW,nullptr,nullptr,&start,&child)!=FALSE,"start isolated child");
            const DWORD waited=WaitForSingleObject(child.hProcess,30000);
            if(waited!=WAIT_OBJECT_0) { TerminateProcess(child.hProcess,2); WaitForSingleObject(child.hProcess,5000); }
            DWORD status=1; GetExitCodeProcess(child.hProcess,&status);
            CloseHandle(child.hThread); CloseHandle(child.hProcess);
            if(status) std::wcerr<<L"isolated child "<<operation<<L" status=0x"<<std::hex<<status<<L'\n';
            Check(waited==WAIT_OBJECT_0 && status==0,"separate-process install/remove/reinstall");
        }
        std::cout<<"PASS independent processes install, verify, remove and reinstall\n";
    } catch(const std::exception& error) { std::cerr<<error.what()<<'\n'; result=1; }
    FreeLibrary(module);
    return result;
}

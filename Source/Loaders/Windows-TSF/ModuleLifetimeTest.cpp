#include <Windows.h>
#include <msctf.h>
#include <psapi.h>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include "Guids.h"

namespace {
void Check(bool ok, const char* message) { if (!ok) throw std::runtime_error(message); }
SIZE_T PrivateBytes() {
    PROCESS_MEMORY_COUNTERS_EX info{};
    info.cb=sizeof(info);
    GetProcessMemoryInfo(GetCurrentProcess(),reinterpret_cast<PROCESS_MEMORY_COUNTERS*>(&info),sizeof(info));
    return info.PrivateUsage;
}
}
int wmain() {
    try {
        wchar_t path[32768]{};
        Check(GetModuleFileNameW(nullptr,path,32768)!=0,"Executable path");
        const auto directory=std::filesystem::path(path).parent_path();
        const auto profile=directory/(L"lifetime-profile-"+std::to_wstring(GetCurrentProcessId()));
        std::filesystem::create_directories(profile);
        SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
        Check(SUCCEEDED(CoInitializeEx(nullptr,COINIT_APARTMENTTHREADED)),"COM initialization");
        HWND owner=CreateWindowExW(0,L"STATIC",L"",WS_POPUP,0,0,100,100,nullptr,nullptr,GetModuleHandleW(nullptr),nullptr);
        Check(owner!=nullptr,"Owner window");
        const wchar_t* classes[]={L"chichi77.KeyKey.TSF.CandidateWindow",L"chichi77.KeyKey.TSF.SymbolPanel",L"chichi77.KeyKey.TSF.SymbolContent"};
        for (int cycle=0;cycle<10;++cycle) {
            HMODULE module=LoadLibraryW((directory/L"KeyKeyTsfLifetimeProbe.dll").c_str());
            Check(module!=nullptr,"Load probe DLL");
            const auto warm=reinterpret_cast<int(__cdecl*)(HWND)>(GetProcAddress(module,"ProbeWarm"));
            const auto unload=reinterpret_cast<HRESULT(__stdcall*)()>(GetProcAddress(module,"DllCanUnloadNow"));
            const auto factoryEntry=reinterpret_cast<HRESULT(__stdcall*)(REFCLSID,REFIID,void**)>(GetProcAddress(module,"DllGetClassObject"));
            Check(warm && unload && factoryEntry,"Production COM exports and test warmup");
            Check(unload()==S_OK,"Unused module cleanup does not initialize engine");
            for (int reuse=0;reuse<2;++reuse) {
                IClassFactory* factory=nullptr;
                Check(SUCCEEDED(factoryEntry(KeyKey::WindowsTsf::kTextServiceClsid,IID_IClassFactory,reinterpret_cast<void**>(&factory))),"Create factory");
                Check(unload()==S_FALSE,"Factory prevents unload");
                factory->LockServer(TRUE);
                ITfTextInputProcessorEx* service=nullptr;
                Check(SUCCEEDED(factory->CreateInstance(nullptr,IID_ITfTextInputProcessorEx,reinterpret_cast<void**>(&service))),"Create service without TIP activation");
                Check(unload()==S_FALSE,"Service prevents unload");
                service->Release();
                factory->Release();
                Check(unload()==S_FALSE,"Server lock prevents unload");
                Check(SUCCEEDED(factoryEntry(KeyKey::WindowsTsf::kTextServiceClsid,IID_IClassFactory,reinterpret_cast<void**>(&factory))),"Reacquire factory");
                factory->LockServer(FALSE); factory->Release();
                const int result=warm(owner);
                if (result) std::cerr<<"Warmup failure "<<result<<'\n';
                Check(result==0,"Live engine, ordered input and HWND unload guards");
                Check(unload()==S_OK && unload()==S_OK,"Idle cleanup is repeatable");
                for (const auto* name : classes) {
                    WNDCLASSEXW wc{sizeof(wc)};
                    Check(!GetClassInfoExW(module,name,&wc),"No class retained before unload");
                }
                // Exclusive access proves the runtime's database connection was closed.
                HANDLE db=CreateFileW((directory/L"Databases"/L"KeyKey.db").c_str(),GENERIC_READ,0,nullptr,OPEN_EXISTING,FILE_ATTRIBUTE_NORMAL,nullptr);
                Check(db!=INVALID_HANDLE_VALUE,"Runtime releases database handles");
                CloseHandle(db);
            }
            Check(FreeLibrary(module)!=FALSE,"Unload DLL");
            Check(!GetModuleHandleW(L"KeyKeyTsfLifetimeProbe.dll"),"DLL is actually unmapped");
            for (const auto* name : classes) {
                WNDCLASSEXW wc{sizeof(wc)};
                Check(!GetClassInfoExW(module,name,&wc),"No stale class after unload");
            }
            std::cout<<"cycle="<<cycle<<" private_after="<<PrivateBytes()<<'\n';
        }
        DestroyWindow(owner); CoUninitialize();
        std::cout<<"10 DLL reloads and 20 runtime/class retire-and-recreate cycles passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}

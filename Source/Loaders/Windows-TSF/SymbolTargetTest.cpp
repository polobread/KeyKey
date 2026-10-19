// Isolated native/AppContainer IPC hosts; no TIP registration or user text.
#include "SymbolTarget.h"
#include <aclapi.h>
#include <userenv.h>
#include <cstring>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

using namespace KeyKey::WindowsTsf;
constexpr wchar_t kDispatch[] = L"KeyKey isolated symbol target test";
constexpr UINT kQuery = WM_APP+72;
constexpr ULONG_PTR kTag = 0x4B535931;
constexpr wchar_t kSymbol[] = L"\x203B";
HWND rootWindow=nullptr;
unsigned received=0;

void Check(bool value,const char* message) { if (!value) throw std::runtime_error(message); }
void Pump() {
    MSG message{};
    while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
    }
}

struct Container {
    std::wstring name;
    std::filesystem::path stage;
    PSID sid=nullptr;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes=nullptr;
    std::vector<unsigned char> storage;
    SECURITY_CAPABILITIES capabilities{};
    ~Container() {
        if (attributes) DeleteProcThreadAttributeList(attributes);
        if (sid) FreeSid(sid);
        if (!name.empty()) DeleteAppContainerProfile(name.c_str());
        // Remove only the staged executable and its now-empty test directory.
        if (!stage.empty()) {
            std::error_code ignored;
            std::filesystem::remove(stage/L"SymbolTargetTest.exe",ignored);
            std::filesystem::remove(stage,ignored);
        }
    }
    std::wstring prepare(const wchar_t* executable) {
        name=L"KeyKey.SymbolTargetTest."+std::to_wstring(GetCurrentProcessId())+L"."+std::to_wstring(GetTickCount64());
        Check(SUCCEEDED(CreateAppContainerProfile(name.c_str(),name.c_str(),L"Temporary symbol routing test",nullptr,0,&sid)),
            "Create isolated AppContainer");
        stage=std::filesystem::temp_directory_path()/name;
        std::filesystem::create_directory(stage);
        EXPLICIT_ACCESSW access{};
        access.grfAccessPermissions=GENERIC_READ|GENERIC_EXECUTE;
        access.grfAccessMode=GRANT_ACCESS;
        access.grfInheritance=SUB_CONTAINERS_AND_OBJECTS_INHERIT;
        access.Trustee.TrusteeForm=TRUSTEE_IS_SID;
        access.Trustee.ptstrName=static_cast<LPWSTR>(sid);
        PACL oldAcl=nullptr,newAcl=nullptr;
        PSECURITY_DESCRIPTOR descriptor=nullptr;
        Check(GetNamedSecurityInfoW(stage.c_str(),SE_FILE_OBJECT,DACL_SECURITY_INFORMATION,
            nullptr,nullptr,&oldAcl,nullptr,&descriptor)==ERROR_SUCCESS,"Read staged test ACL");
        const auto aclBuilt=SetEntriesInAclW(1,&access,oldAcl,&newAcl);
        const auto aclApplied=aclBuilt==ERROR_SUCCESS ? SetNamedSecurityInfoW(
            const_cast<wchar_t*>(stage.c_str()),SE_FILE_OBJECT,DACL_SECURITY_INFORMATION,
            nullptr,nullptr,newAcl,nullptr) : aclBuilt;
        LocalFree(newAcl); LocalFree(descriptor);
        Check(aclApplied==ERROR_SUCCESS,"Grant container read/execute only on staged test");
        const auto staged=stage/L"SymbolTargetTest.exe";
        std::filesystem::copy_file(executable,staged);
        SIZE_T bytes=0;
        InitializeProcThreadAttributeList(nullptr,1,0,&bytes);
        storage.resize(bytes);
        attributes=reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
        Check(InitializeProcThreadAttributeList(attributes,1,0,&bytes)!=FALSE,"Initialize container attributes");
        capabilities.AppContainerSid=sid;
        Check(UpdateProcThreadAttribute(attributes,0,PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
            &capabilities,sizeof(capabilities),nullptr,nullptr)!=FALSE,"Apply container capabilities");
        return staged.wstring();
    }
};

LRESULT CALLBACK Receiver(HWND window,UINT message,WPARAM wp,LPARAM lp) {
    if (message==kQuery) return GetFocus()==rootWindow;
    if (message==WM_COPYDATA) {
        const auto* data=reinterpret_cast<COPYDATASTRUCT*>(lp);
        if (GetFocus()!=rootWindow || !data || data->dwData!=kTag || data->cbData!=sizeof(kSymbol) ||
            !data->lpData || memcmp(data->lpData,kSymbol,sizeof(kSymbol))) return FALSE;
        if (++received==3) PostMessageW(rootWindow,WM_CLOSE,0,0);
        return TRUE;
    }
    if (message==WM_ACTIVATE && LOWORD(wp)!=WA_INACTIVE && window==rootWindow) SetFocus(rootWindow);
    if (message==WM_CLOSE && window==rootWindow) { DestroyWindow(window); PostQuitMessage(0); return 0; }
    return DefWindowProcW(window,message,wp,lp);
}

int Child(const wchar_t* title) {
    HANDLE token=nullptr; DWORD restricted=0,bytes=0;
    Check(OpenProcessToken(GetCurrentProcess(),TOKEN_QUERY,&token)!=FALSE,"Child token");
    const bool queried=GetTokenInformation(token,TokenIsAppContainer,&restricted,sizeof(restricted),&bytes)!=FALSE;
    CloseHandle(token);
    Check(queried && restricted,"Child must run inside a real AppContainer");
    rootWindow=CreateWindowExW(0,L"STATIC",title,WS_OVERLAPPEDWINDOW,100,100,300,100,nullptr,nullptr,nullptr,nullptr);
    Check(rootWindow!=nullptr,"Create AppContainer input host");
    SetWindowLongPtrW(rootWindow,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(Receiver));
    const HWND dispatch=CreateWindowExW(WS_EX_NOACTIVATE|WS_EX_TOOLWINDOW,L"STATIC",kDispatch,
        WS_POPUP,0,0,0,0,nullptr,nullptr,nullptr,nullptr);
    Check(dispatch!=nullptr,"Create AppContainer symbol endpoint");
    SetWindowLongPtrW(dispatch,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(Receiver));
    ShowWindow(rootWindow,SW_SHOWNOACTIVATE);
    const auto deadline=GetTickCount64()+15000;
    while (IsWindow(rootWindow) && GetTickCount64()<deadline) {
        Pump(); Sleep(1);
    }
    DestroyWindow(dispatch);
    if (IsWindow(rootWindow)) DestroyWindow(rootWindow);
    Check(received==3,"AppContainer must receive exactly three ordered symbols");
    return 0;
}

int Parent() {
    wchar_t executable[32768]{};
    Check(GetModuleFileNameW(nullptr,executable,32768)!=0,"Executable path");
    Container container;
    const auto childExecutable=container.prepare(executable);
    const auto title=L"KeyKey isolated symbol input "+std::to_wstring(GetCurrentProcessId());
    auto command=L"\""+childExecutable+L"\" --child \""+title+L"\"";
    STARTUPINFOEXW startup{};
    startup.StartupInfo.cb=sizeof(startup); startup.lpAttributeList=container.attributes;
    PROCESS_INFORMATION child{};
    Check(CreateProcessW(childExecutable.c_str(),command.data(),nullptr,nullptr,FALSE,
        CREATE_NO_WINDOW|EXTENDED_STARTUPINFO_PRESENT,nullptr,nullptr,&startup.StartupInfo,&child)!=FALSE,
        "Start AppContainer input host");
    CloseHandle(child.hThread);
    struct Cleanup {
        HANDLE process;
        ~Cleanup() {
            if (WaitForSingleObject(process,0)==WAIT_TIMEOUT) { TerminateProcess(process,2); WaitForSingleObject(process,2000); }
            CloseHandle(process);
        }
    } cleanup{child.hProcess};
    HWND host=nullptr;
    const auto readyDeadline=GetTickCount64()+5000;
    while (!(host=FindWindowExW(nullptr,nullptr,L"STATIC",title.c_str())) && GetTickCount64()<readyDeadline &&
        WaitForSingleObject(child.hProcess,0)==WAIT_TIMEOUT) { Pump(); Sleep(10); }
    Check(host!=nullptr,"AppContainer host did not start");
    const auto focusDeadline=GetTickCount64()+2000;
    while (GetForegroundWindow()!=host && GetTickCount64()<focusDeadline) {
        SetForegroundWindow(host); Pump(); Sleep(10);
    }
    if (GetForegroundWindow()!=host) {
        std::cout<<"Interactive foreground desktop unavailable\n"; return 77;
    }
    auto targets=SymbolTargets(host,kDispatch);
    Check(targets.size()==1,"Discover the focused AppContainer symbol endpoint");
    DWORD process=0;
    Check(GetWindowThreadProcessId(targets.front(),&process)==SymbolInputThread(host) && process==child.dwProcessId,
        "Endpoint must belong to the focused AppContainer process/thread");
    Check(SymbolTargets(host,L"Unknown isolated endpoint").empty(),"Unknown endpoint must not match");
    Check(SymbolTargets(nullptr,kDispatch).empty(),"Missing foreground must not match");
    DWORD_PTR available=0;
    Check(SendMessageTimeoutW(targets.front(),kQuery,0,0,SMTO_ABORTIFHUNG|SMTO_BLOCK,80,&available)!=0 && available,
        "Focused AppContainer must enable symbols");
    COPYDATASTRUCT data{kTag,sizeof(kSymbol),const_cast<wchar_t*>(kSymbol)};
    for (unsigned i=0;i<3;++i) {
        DWORD_PTR accepted=0;
        Check(SendMessageTimeoutW(targets.front(),WM_COPYDATA,0,reinterpret_cast<LPARAM>(&data),
            SMTO_ABORTIFHUNG|SMTO_BLOCK,500,&accepted)!=0 && accepted,"Send symbol to AppContainer");
    }
    Check(WaitForSingleObject(child.hProcess,3000)==WAIT_OBJECT_0,"Container receiver exit");
    DWORD result=1; GetExitCodeProcess(child.hProcess,&result);
    Check(result==0,"Container receiver rejected or duplicated symbols");
    Check(SymbolTargets(host,kDispatch).empty(),"Exited host must not remain a target");
    std::cout<<"AppContainer discovery, availability and three symbol transfers passed\n";
    return 0;
}

int wmain(int argc,wchar_t** argv) {
    try { return argc==3 && std::wstring(argv[1])==L"--child" ? Child(argv[2]) : Parent(); }
    catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}

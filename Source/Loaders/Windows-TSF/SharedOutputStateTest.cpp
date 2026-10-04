#include "SharedOutputState.h"
#include <iostream>
#include <stdexcept>
#include <string>
#include <filesystem>
#include <userenv.h>
#include <aclapi.h>
#include <sddl.h>
#include <vector>
using namespace KeyKey::WindowsTsf;
using Microsoft::WRL::ComPtr;
void Check(bool value, const char* label) { if (!value) throw std::runtime_error(label); }
void Success(HRESULT value, const char* label) {
    if (FAILED(value)) std::cerr << label << " HRESULT=" << std::hex << value << '\n';
    Check(SUCCEEDED(value), label);
}
struct Container {
    std::wstring name;
    std::filesystem::path stage;
    PSID sid = nullptr;
    LPPROC_THREAD_ATTRIBUTE_LIST attributes = nullptr;
    std::vector<unsigned char> storage;
    SECURITY_CAPABILITIES capabilities{};
    ~Container() {
        if (attributes) DeleteProcThreadAttributeList(attributes);
        if (sid) FreeSid(sid);
        if (!name.empty()) DeleteAppContainerProfile(name.c_str());
    }
    std::wstring prepare(const wchar_t* executable) {
        name = L"KeyKey.OutputTest." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetTickCount64());
        Success(CreateAppContainerProfile(name.c_str(), name.c_str(), L"Temporary KeyKey output test", nullptr, 0, &sid), "Create test AppContainer");
        stage = std::filesystem::temp_directory_path() / name;
        std::filesystem::create_directories(stage);
        EXPLICIT_ACCESSW access{};
        access.grfAccessPermissions = GENERIC_READ | GENERIC_EXECUTE;
        access.grfAccessMode = GRANT_ACCESS;
        access.grfInheritance = SUB_CONTAINERS_AND_OBJECTS_INHERIT;
        access.Trustee.TrusteeForm = TRUSTEE_IS_SID;
        access.Trustee.ptstrName = static_cast<LPWSTR>(sid);
        PACL oldAcl = nullptr, newAcl = nullptr;
        PSECURITY_DESCRIPTOR descriptor = nullptr;
        Check(GetNamedSecurityInfoW(stage.c_str(), SE_FILE_OBJECT, DACL_SECURITY_INFORMATION,
            nullptr, nullptr, &oldAcl, nullptr, &descriptor) == ERROR_SUCCESS, "Read test directory ACL");
        Check(SetEntriesInAclW(1, &access, oldAcl, &newAcl) == ERROR_SUCCESS, "Build test directory ACL");
        const DWORD aclResult = SetNamedSecurityInfoW(const_cast<wchar_t*>(stage.c_str()), SE_FILE_OBJECT,
            DACL_SECURITY_INFORMATION, nullptr, nullptr, newAcl, nullptr);
        LocalFree(newAcl);
        LocalFree(descriptor);
        Check(aclResult == ERROR_SUCCESS, "Apply read-only test directory ACL");
        const auto source = std::filesystem::path(executable);
        std::filesystem::copy_file(source, stage / source.filename());
        LPWSTR sidText = nullptr, containerPath = nullptr;
        Check(ConvertSidToStringSidW(sid, &sidText), "Format container SID");
        const HRESULT pathResult = GetAppContainerFolderPath(sidText, &containerPath);
        LocalFree(sidText);
        Success(pathResult, "Container profile path");
        const auto temporary = std::filesystem::path(containerPath) / L"LocalState";
        CoTaskMemFree(containerPath);
        std::filesystem::create_directories(temporary);
        Check(SetEnvironmentVariableW(L"TEMP", temporary.c_str()) &&
              SetEnvironmentVariableW(L"TMP", temporary.c_str()), "Container temporary environment");
        SIZE_T bytes = 0;
        InitializeProcThreadAttributeList(nullptr, 1, 0, &bytes);
        storage.resize(bytes);
        attributes = reinterpret_cast<LPPROC_THREAD_ATTRIBUTE_LIST>(storage.data());
        Check(InitializeProcThreadAttributeList(attributes, 1, 0, &bytes), "Container attributes");
        capabilities.AppContainerSid = sid;
        Check(UpdateProcThreadAttribute(attributes, 0, PROC_THREAD_ATTRIBUTE_SECURITY_CAPABILITIES,
            &capabilities, sizeof(capabilities), nullptr, nullptr), "Container capabilities");
        return (stage / source.filename()).wstring();
    }
};

int wmain(int argc, wchar_t** argv) {
    try {
        Success(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "COM");
        ComPtr<ITfThreadMgrEx> manager;
        Success(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
            IID_PPV_ARGS(&manager)), "Thread manager");
        TfClientId client = TF_CLIENTID_NULL;
        Success(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT), "Activate");
        GUID guid{};
        bool child = argc == 3 && std::wstring(argv[1]) == L"--child";
        if (child) Success(CLSIDFromString(argv[2], &guid), "Isolated GUID parse");
        else Success(CoCreateGuid(&guid), "Isolated GUID creation");
        SharedOutputState state;
        Check(!state.read().has_value() && state.write(client,true) == E_UNEXPECTED, "Disconnected state");
        Success(state.connect(manager.Get(), guid), "Connect");
        if (child) {
            Check(state.read() == std::optional<bool>(true), "Cross-process enabled state");
            Success(state.write(client,false), "Child disable");
        } else {
            Check(!state.read().has_value(), "New isolated compartment must be unset");
            Success(state.write(client,true), "Enable");
            Check(state.read() == std::optional<bool>(true), "Enabled read");
            wchar_t executable[32768]{};
            Check(GetModuleFileNameW(nullptr,executable,32768) != 0, "Executable path");
            wchar_t guidText[40]{}; StringFromGUID2(guid,guidText,40);
            const bool restricted = argc == 2 && std::wstring(argv[1]) == L"--container";
            Container container;
            const std::wstring childExecutable = restricted ? container.prepare(executable) : argc == 2 ? argv[1] : executable;
            std::wstring command = L"\"" + childExecutable + L"\" --child " + guidText;
            STARTUPINFOEXW startup{};
            startup.StartupInfo.cb = restricted ? sizeof(startup) : sizeof(STARTUPINFOW);
            startup.lpAttributeList = container.attributes;
            PROCESS_INFORMATION process{};
            Check(CreateProcessW(childExecutable.c_str(),command.data(),nullptr,nullptr,FALSE,
                CREATE_NO_WINDOW | (restricted ? EXTENDED_STARTUPINFO_PRESENT : 0),
                nullptr,nullptr,&startup.StartupInfo,&process), "Child process");
            CloseHandle(process.hThread);
            DWORD wait = WAIT_TIMEOUT, result = 1;
            const ULONGLONG deadline = GetTickCount64() + 30000;
            while (GetTickCount64() < deadline) {
                wait = MsgWaitForMultipleObjects(1, &process.hProcess, FALSE, 100, QS_ALLINPUT);
                if (wait == WAIT_OBJECT_0 || wait == WAIT_FAILED) break;
                MSG message;
                while (PeekMessageW(&message,nullptr,0,0,PM_REMOVE)) {
                    TranslateMessage(&message); DispatchMessageW(&message);
                }
            }
            if (wait == WAIT_OBJECT_0) GetExitCodeProcess(process.hProcess,&result);
            else TerminateProcess(process.hProcess,1);
            CloseHandle(process.hProcess);
            Check(wait == WAIT_OBJECT_0 && result == 0, "Child result");
            Check(state.read() == std::optional<bool>(false), "Cross-process disabled state");
            ComPtr<ITfCompartmentMgr> global;
            Success(manager->GetGlobalCompartment(&global), "Cleanup global manager");
            Success(global->ClearCompartment(client,guid), "Cleanup isolated compartment");
        }
        state.reset();
        Check(!state.read().has_value(), "Reset state");
        manager->Deactivate(); manager.Reset(); CoUninitialize();
        std::cout << "Shared output state tests passed\n"; return 0;
    } catch (const std::exception& error) { std::cerr << error.what() << '\n'; return 1; }
}

#include "SharedInputMethod.h"
#include "KeyKeyEngine.h"
#include "ModuleState.h"
#include <atomic>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <userenv.h>
#include <aclapi.h>
#include <sddl.h>
#include <vector>

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
}
using namespace KeyKey::WindowsTsf;
using Microsoft::WRL::ComPtr;

static void Check(bool result, const char* message) {
    if (!result) throw std::runtime_error(message);
}
static void Success(HRESULT result, const char* message) {
    if (FAILED(result)) std::cerr << message << " hr=" << std::hex << result << '\n';
    Check(SUCCEEDED(result), message);
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
        name = L"KeyKey.ModeTest." + std::to_wstring(GetCurrentProcessId()) + L"." + std::to_wstring(GetTickCount64());
        Success(CreateAppContainerProfile(name.c_str(), name.c_str(), L"Temporary KeyKey mode test", nullptr, 0, &sid), "Create test AppContainer");
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
        std::filesystem::create_directory(stage / L"Databases");
        std::filesystem::copy_file(source.parent_path() / L"Databases/KeyKey.db", stage / L"Databases/KeyKey.db");
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
        Success(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "COM initialization");
        ComPtr<ITfThreadMgrEx> manager;
        Success(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER,
                                 IID_PPV_ARGS(&manager)), "TSF creation");
        TfClientId client = TF_CLIENTID_NULL;
        Success(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP |
            TF_TMAE_NOACTIVATEKEYBOARDLAYOUT), "TSF activation");
        GUID guid{};
        const bool child = argc == 4 && std::wstring(argv[1]) == L"--child";
        if (child) Success(CLSIDFromString(argv[2], &guid), "Test GUID parse");
        else Success(CoCreateGuid(&guid), "Test GUID creation");
        SharedInputMethod shared;
        Success(shared.connect(manager.Get(), guid), "Global compartment connection");
        if (child) {
            const int index = _wtoi(argv[3]);
            Check(index >= 0 && index < 4, "Invalid child method index");
            // A different profile reproduces Search retaining Traditional
            // Mandarin while the desktop has selected another method.
            auto profile = std::filesystem::temp_directory_path() /
                (L"keykey-shared-test-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
            std::filesystem::create_directories(profile);
            Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str()), "Isolated profile");
            auto engine = KeyKeyEngineSession::Create();
            Check(engine && engine->ready(), "Child engine creation");
            Check(SelectInputMethod("TraditionalMandarin"), "Stale local selection");
            const auto* selected = shared.read();
            Check(selected && selected->menuId == kInputMethods[index].menuId, "Cross-process selection was lost");
            Check(SelectInputMethod(selected->identifier), "Shared selection unavailable in child");
            Check(CurrentInputMethod() == selected->identifier, "Settings reload reverted shared selection");
            KeyEvent key;
            key.virtualKey = index >= 2 ? 'A' : 'S';
            key.text = index >= 2 ? L"a" : L"s";
            const auto result = engine->handleKey(key);
            Check(result.handled && result.compositionText == (index >= 2 ? L"日" : L"ㄋ"),
                  "Child engine did not compose with the selected method");
            Success(shared.write(client, kInputMethods[(index + 1) % 4].identifier), "Child publish");
        } else {
            Check(!shared.read(), "New test compartment was not empty");
            wchar_t self[32768]{}, guidText[40]{};
            Check(GetModuleFileNameW(nullptr, self, 32768) != 0, "Executable path");
            Check(StringFromGUID2(guid, guidText, 40) != 0, "GUID formatting");
            Container container;
            const bool restricted = argc == 2 && std::wstring(argv[1]) == L"--container";
            const std::wstring executable = restricted ? container.prepare(self) : argc == 2 ? argv[1] : self;
            const wchar_t* childExecutable = executable.c_str();
            for (int index = 0; index < 4; ++index) {
                Success(shared.write(client, kInputMethods[index].identifier), "Parent publish");
                std::wstring command = L"\"" + std::wstring(childExecutable) + L"\" --child " +
                    guidText + L" " + std::to_wstring(index);
                STARTUPINFOEXW startup{};
                startup.StartupInfo.cb = restricted ? sizeof(startup) : sizeof(STARTUPINFOW);
                startup.lpAttributeList = container.attributes;
                PROCESS_INFORMATION process{};
                Check(CreateProcessW(childExecutable, command.data(), nullptr, nullptr, FALSE,
                    CREATE_NO_WINDOW | (restricted ? EXTENDED_STARTUPINFO_PRESENT : 0),
                    nullptr, nullptr, &startup.StartupInfo, &process), "Child process creation");
                const ULONGLONG deadline = GetTickCount64() + 30000;
                DWORD wait = WAIT_TIMEOUT;
                while (GetTickCount64() < deadline) {
                    wait = MsgWaitForMultipleObjects(1, &process.hProcess, FALSE, 100, QS_ALLINPUT);
                    if (wait == WAIT_OBJECT_0) break;
                    MSG message;
                    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
                        TranslateMessage(&message);
                        DispatchMessageW(&message);
                    }
                }
                DWORD exitCode = 1;
                GetExitCodeProcess(process.hProcess, &exitCode);
                if (exitCode) std::cerr << "Child exit code: " << std::hex << exitCode << '\n';
                if (wait != WAIT_OBJECT_0) TerminateProcess(process.hProcess, 1);
                CloseHandle(process.hThread);
                CloseHandle(process.hProcess);
                Check(wait == WAIT_OBJECT_0 && exitCode == 0, "Cross-process child failed");
                const auto* returned = shared.read();
                Check(returned && returned->menuId == kInputMethods[(index + 1) % 4].menuId,
                      "Child selection did not propagate back to parent");
            }
            ComPtr<ITfCompartmentMgr> global;
            Success(manager->GetGlobalCompartment(&global), "Global manager cleanup");
            Success(global->ClearCompartment(client, guid), "Test compartment cleanup");
            std::cout << "Four methods shared across processes, composed with isolated profiles, and returned successfully.\n";
        }
        shared.reset();
        manager->Deactivate();
        manager.Reset();
        CoUninitialize();
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

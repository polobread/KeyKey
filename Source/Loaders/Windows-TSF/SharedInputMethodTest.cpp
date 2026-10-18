#include "SharedInputMethod.h"
#include "KeyKeyEngine.h"
#include "ModuleState.h"
#include "FrontendSettings.h"
#include "Mandarin.h"
#include <atomic>
#include <fstream>
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
        const bool child = argc == 5 && std::wstring(argv[1]) == L"--child";
        if (child) Success(CLSIDFromString(argv[2], &guid), "Test GUID parse");
        else Success(CoCreateGuid(&guid), "Test GUID creation");
        SharedInputMethod shared;
        Success(shared.connect(manager.Get(), guid), "Global compartment connection");
        GUID previewGuid = guid;
        previewGuid.Data1 ^= 0x7734ac21;
        SharedTableSettings preview;
        Success(preview.connect(manager.Get(), previewGuid), "Cangjie settings connection");
        GUID simplexGuid = previewGuid;
        simplexGuid.Data1 ^= 0x6921138f;
        SharedTableSettings simplexPreview;
        Success(simplexPreview.connect(manager.Get(), simplexGuid), "Simplex settings connection");
        GUID preferencesGuid = guid;
        preferencesGuid.Data1 ^= 0xb8103ef6;
        SharedRuntimePreferences preferences;
        Success(preferences.connect(manager.Get(), preferencesGuid), "Runtime preferences connection");
        if (child) {
            const int index = _wtoi(argv[3]);
            Check(index >= 0 && index < 4, "Invalid child method index");
            // A different profile reproduces Search retaining Traditional
            // Mandarin while the desktop has selected another method.
            auto profile = std::filesystem::temp_directory_path() /
                (L"keykey-shared-test-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
            std::filesystem::create_directories(profile);
            Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str()), "Isolated profile");
            const int previewFlags = _wtoi(argv[4]);
            const bool simplex = index == 3;
            auto& tablePreview = simplex ? simplexPreview : preview;
            const TablePreviewSettings expected{(previewFlags & 1) != 0,
                !simplex && (previewFlags & 2) != 0, (previewFlags & 1) == 0};
            if (index >= 2) {
                std::ofstream config(profile / (simplex
                    ? L"com.polobread.chichi77-keykey.windows.Generic-simplex-cin.plist"
                    : L"com.polobread.chichi77-keykey.windows.Generic-cj-cin.plist"));
                config << "<plist><dict><key>ComposeWhenTyping</key><string>"
                    << (expected.composeWhileTyping ? "false" : "true")
                    << "</string><key>PrefixCandidates</key><string>"
                    << (expected.prefixCandidates ? "false" : "true")
                    << "</string><key>RetainedText</key><string>private</string></dict></plist>";
            }
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
            if (index >= 2) {
                const auto otherMethod = simplex ? "Generic-cj-cin" : "Generic-simplex-cin";
                const auto otherRevision = EngineSettingsSignature(otherMethod);
                Check(SyncTablePreviewSettings(tablePreview, client, true, simplex), "Restricted settings synchronization");
                Check(LoadTablePreviewSettings(simplex).encoded() == expected.encoded(), "Private settings kept stale defaults");
                Check(tablePreview.read() && tablePreview.read()->encoded() == expected.encoded(), "Restricted host overwrote desktop preferences");
                Check(EngineSettingsSignature(otherMethod) == otherRevision, "Table sync contaminated the other method");
                const auto revision = EngineSettingsSignature(selected->identifier);
                Check(revision.find("private") != std::string::npos, "Sync lost unrelated private settings");
                Check(SyncTablePreviewSettings(tablePreview, client, true, simplex) &&
                    EngineSettingsSignature(selected->identifier) == revision, "Unchanged settings were rewritten");
                engine->reset();
                KeyEvent h; h.virtualKey = simplex ? 'A' : 'H'; h.text = simplex ? L"a" : L"h";
                KeyEvent k; k.virtualKey = 'K'; k.text = L"k";
                auto hk = engine->handleKey(h);
                if (!simplex) hk = engine->handleKey(k);
                bool qiao = false;
                for (const auto& candidate : hk.candidates) qiao |= candidate.text == L"喬";
                Check(hk.handled && hk.committedText.empty() && hk.compositionText == (simplex ? L"日" : L"竹大"),
                    "Restricted table radicals were lost or committed");
                Check(hk.candidatesVisible == expected.composeWhileTyping,
                    "Restricted host did not apply realtime candidates");
                Check(qiao == (expected.composeWhileTyping && expected.prefixCandidates),
                    "Restricted host did not apply prefix candidates");
            }
            engine->reset();
            const auto sourceSnapshot = preferences.read();
            if (!sourceSnapshot) {
                ComPtr<ITfCompartmentMgr> global;
                Success(manager->GetGlobalCompartment(&global), "Inspect preferences manager");
                ComPtr<ITfCompartment> raw;
                Success(global->GetCompartment(preferencesGuid, &raw), "Inspect preferences compartment");
                VARIANT value{};
                const auto status = raw->GetValue(&value);
                const auto size = value.vt == VT_BSTR && value.bstrVal ? SysStringLen(value.bstrVal) : 0;
                const auto message = "Missing shared runtime preferences: hr=" + std::to_string(status) +
                    " type=" + std::to_string(value.vt) + " length=" + std::to_string(size);
                VariantClear(&value);
                Check(false, message.c_str());
            }
            Check(preferences.write(client, std::wstring(SharedRuntimePreferences::maximumLength + 1, L'x')) == E_INVALIDARG,
                "Unbounded settings snapshot accepted");
            const auto beforeInvalid = EngineSettingsSignature(selected->identifier);
            Success(preferences.write(client, L"<plist><dict><key>Version</key><string>2</string></dict></plist>"), "Publish invalid test snapshot");
            Check(!SyncRuntimePreferences(preferences, client, true) &&
                EngineSettingsSignature(selected->identifier) == beforeInvalid, "Invalid snapshot changed settings");
            Success(preferences.write(client, *sourceSnapshot), "Restore valid preferences snapshot");
            Check(SyncRuntimePreferences(preferences, client, true), "Apply cross-process input preferences");
            const auto frontend = LoadFrontendSettings();
            Check(frontend.candidateLayout == CandidateLayout::Horizontal && frontend.candidateScalePercent == 150 &&
                frontend.highlightColor == L"Green" && !frontend.symbolPanelShortcutEnabled &&
                !frontend.toggleWithControlBackslash && !frontend.playSoundOnTypingError,
                "Restricted frontend retained stale appearance/shortcut/sound preferences");
            Check(!IsInputMethodVisible("TraditionalMandarin") && IsInputMethodVisible("Generic-cj-cin"),
                "Restricted method visibility diverged from desktop");
            const auto afterSnapshot = RuntimePreferencesSnapshot();
            Check(afterSnapshot == *sourceSnapshot && SyncRuntimePreferences(preferences, client, true) &&
                RuntimePreferencesSnapshot() == afterSnapshot, "Preference groups diverged or unchanged sync rewrote values");
            if (index < 2) {
                const auto* layout = Formosa::Mandarin::BopomofoKeyboardLayout::LayoutForName("Hsu");
                const auto syllable = Formosa::Mandarin::BopomofoSyllable::FromComposedString("ㄋㄧˇ");
                for (char c : layout->keySequenceFromSyllable(syllable)) {
                    KeyEvent event; event.virtualKey = static_cast<UINT>(c >= 'a' && c <= 'z' ? c - 'a' + 'A' : c);
                    event.text.assign(1, static_cast<wchar_t>(c));
                    Check(engine->handleKey(event).handled, "Shared phonetic layout did not handle a key");
                }
                if (index == 0) {
                    KeyEvent space; space.virtualKey = VK_SPACE; space.text = L" ";
                    const auto candidates = engine->handleKey(space);
                    Check(candidates.candidatesVisible && candidates.candidates.size() == 8 &&
                        candidates.candidates[0].selectionKey == L"q", "Shared Smart Mandarin layout/space/candidate keys not applied");
                    KeyEvent escape; escape.virtualKey = VK_ESCAPE; escape.text = L"\x1b";
                    engine->handleKey(escape);
                    const auto cleared = engine->handleKey(escape);
                    Check(cleared.compositionText.empty(), "Shared Esc clear preference not applied");
                }
            }
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
            const auto parentProfile = std::filesystem::temp_directory_path() /
                (L"keykey-preferences-parent-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(GetTickCount64()));
            std::filesystem::create_directories(parentProfile);
            Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", parentProfile.c_str()), "Parent isolated preferences");
            const auto seed = [&](const wchar_t* module, const char* values) {
                std::ofstream file(parentProfile / (std::wstring(L"com.polobread.chichi77-keykey.windows") + module + L".plist"));
                file << "<plist><dict>" << values << "</dict></plist>";
            };
            seed(L"", "<key>OneDimensionalCandidatePanelStyle</key><string>horizontal</string>"
                "<key>CandidateWindowScalePercent</key><string>150</string><key>HighlightColor</key><string>Green</string>"
                "<key>SymbolPanelShortcutEnabled</key><string>false</string>"
                "<key>ToggleInputMethodWithControlBackslash</key><string>false</string>"
                "<key>ShouldPlaySoundOnTypingError</key><string>false</string>"
                "<key>ModulesSuppressedFromUI</key><array><string>TraditionalMandarin</string></array>"
                "<key>Secret</key><string>do-not-publish</string>");
            seed(L".SmartMandarin", "<key>KeyboardLayout</key><string>Hsu</string>"
                "<key>ShowCandidateListWithSpace</key><string>true</string>"
                "<key>CandidateCursorAtEndOfTargetBlock</key><string>true</string>"
                "<key>CandidateSelectionKeys</key><string>qwertyui</string>"
                "<key>ComposingTextBufferSize</key><string>15</string>"
                "<key>ClearComposingTextWithEscUserChoice</key><string>true</string>"
                "<key>ClearComposingTextWithEsc</key><string>true</string>");
            seed(L".TraditionalMandarin", "<key>KeyboardLayout</key><string>Hsu</string>"
                "<key>UseCharactersSupportedByEncoding</key><string>UTF-8</string>");
            seed(L".Generic-cj-cin", "<key>ShouldCommitAtMaximumRadicalLength</key><string>true</string>"
                "<key>UseDynamicFrequency</key><string>true</string>"
                "<key>UseCharactersSupportedByEncoding</key><string>BIG-5</string>"
                "<key>UseOverrideTable</key><string>Punctuations-cj-halfwidth-cin</string>");
            seed(L".Generic-simplex-cin", "<key>ShouldCommitAtMaximumRadicalLength</key><string>true</string>"
                "<key>UseCharactersSupportedByEncoding</key><string>BIG-5</string>");
            seed(L".AssociatedPhrase", "<key>EnabledCollections</key><string></string>");
            const auto snapshot = RuntimePreferencesSnapshot();
            Check(!snapshot.empty() && snapshot.find(L"Secret") == std::wstring::npos &&
                snapshot.find(L"do-not-publish") == std::wstring::npos, "Private keys leaked into shared preferences");
            Success(preferences.write(client, snapshot), "Seed complete settings publication");
            ComPtr<ITfCompartmentMgr> publicationManager;
            Success(manager->GetGlobalCompartment(&publicationManager), "Publication test manager");
            ComPtr<ITfCompartment> publication;
            Success(publicationManager->GetCompartment(preferencesGuid, &publication), "Publication revision");
            VARIANT interrupted{};
            Success(publication->GetValue(&interrupted), "Read complete revision");
            Check(interrupted.vt == VT_I4, "Unexpected publication revision type");
            interrupted.lVal |= 1;
            Success(publication->SetValue(client, &interrupted), "Simulate interrupted publisher");
            VariantClear(&interrupted);
            Check(!preferences.read(), "Incomplete publication returned cached/partial settings");
            Success(preferences.write(client, snapshot), "Recover interrupted publisher");
            Check(preferences.read() == std::optional<std::wstring>(snapshot), "Recovered publication differs");
            const int methods[] = {0, 1, 2, 2, 2, 2, 3, 3};
            for (int test = 0; test < 8; ++test) {
                const int index = methods[test];
                const int flags = index == 2 ? test - 2 : index == 3 ? test - 6 : 0;
                Success(preview.write(client, {(flags & 1) != 0, (flags & 2) != 0,
                    (flags & 1) == 0}), "Parent Cangjie settings publish");
                Success(simplexPreview.write(client, {(flags & 1) != 0, false,
                    (flags & 1) == 0}), "Parent Simplex settings publish");
                Success(preferences.write(client, snapshot), "Parent runtime preferences publish");
                Check(preferences.read() == std::optional<std::wstring>(snapshot), "Parent preferences readback");
                Success(shared.write(client, kInputMethods[index].identifier), "Parent publish");
                const auto childError = std::filesystem::temp_directory_path() /
                    (L"keykey-shared-error-" + std::to_wstring(GetCurrentProcessId()) + L"-" + std::to_wstring(test) + L".txt");
                Check(SetEnvironmentVariableW(L"KEYKEY_TEST_CHILD_ERROR_PATH", childError.c_str()), "Child error path");
                std::wstring command = L"\"" + std::wstring(childExecutable) + L"\" --child " +
                    guidText + L" " + std::to_wstring(index) + L" " + std::to_wstring(flags);
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
                if (exitCode) {
                    std::cerr << "Child exit code: " << std::hex << exitCode << '\n';
                    std::ifstream details(childError);
                    std::cerr << details.rdbuf();
                }
                if (wait != WAIT_OBJECT_0) TerminateProcess(process.hProcess, 1);
                CloseHandle(process.hThread);
                CloseHandle(process.hProcess);
                std::error_code cleanupError;
                std::filesystem::remove(childError, cleanupError);
                Check(wait == WAIT_OBJECT_0 && exitCode == 0, "Cross-process child failed");
                const auto* returned = shared.read();
                Check(returned && returned->menuId == kInputMethods[(index + 1) % 4].menuId,
                      "Child selection did not propagate back to parent");
            }
            ComPtr<ITfCompartmentMgr> global;
            Success(manager->GetGlobalCompartment(&global), "Global manager cleanup");
            Success(global->ClearCompartment(client, guid), "Test compartment cleanup");
            Success(global->ClearCompartment(client, previewGuid), "Cangjie compartment cleanup");
            Success(global->ClearCompartment(client, simplexGuid), "Simplex compartment cleanup");
            Success(preferences.clear(client), "Runtime preferences cleanup");
            std::cout << "Four methods, four Cangjie preview combinations and Simplex on/off passed across isolated profiles.\n";
        }
        shared.reset();
        preview.reset();
        simplexPreview.reset();
        preferences.reset();
        manager->Deactivate();
        manager.Reset();
        CoUninitialize();
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        wchar_t path[32768]{};
        const auto size = GetEnvironmentVariableW(L"KEYKEY_TEST_CHILD_ERROR_PATH", path, 32768);
        if (size && size < 32768) {
            std::ofstream details(path);
            details << error.what() << '\n';
        }
        return 1;
    }
}

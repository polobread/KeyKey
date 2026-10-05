#include <Windows.h>
#include <ctffunc.h>
#include <ctfutb.h>
#include <msctf.h>
#include <wrl/client.h>

#include <algorithm>
#include <filesystem>
#include <fstream>
#include <chrono>
#include <iostream>
#include <stdexcept>
#include <string>
#include <vector>

#include "Guids.h"
#include "InputMethods.h"
#include "InputModeState.h"
#include "StartupInputMode.h"
#include "FrontendSettings.h"
#include "LangBarButton.h"
#include "TextService.h"
#include "ModuleState.h"

namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
struct TextServiceTestAccess {
    static void start(TextService& service, ITfThreadMgr* manager, TfClientId client) {
        // Exercise the activation's mode initialization with real compartments.
        // An application client cannot register a TIP key sink, so this test
        // deliberately does not claim to exercise full ActivateEx registration.
        service.threadManager_ = manager;
        service.clientId_ = client;
        service.engine_ = KeyKeyEngineSession::Create();
        service.applyStartupInputMode();
    }
};
struct LangBarButtonTestAccess {
    static HMENU popup(LangBarButton& button) { return button.createPopupMenu(); }
};
}

namespace {
using namespace KeyKey::WindowsTsf;
using Microsoft::WRL::ComPtr;

void Check(bool value, const char* message) {
    if (!value) throw std::runtime_error(message);
}
void Success(HRESULT result, const char* message) { Check(SUCCEEDED(result), message); }

class Menu final : public ITfMenu {
public:
    STDMETHODIMP QueryInterface(REFIID iid, void** object) override {
        if (!object) return E_POINTER;
        *object = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfMenu) return E_NOINTERFACE;
        *object = static_cast<ITfMenu*>(this);
        AddRef();
        return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++references_; }
    STDMETHODIMP_(ULONG) Release() override { return --references_; }
    STDMETHODIMP AddMenuItem(UINT id, DWORD flags, HBITMAP, HBITMAP,
                            const WCHAR*, ULONG, ITfMenu** submenu) override {
        if (submenu) *submenu = nullptr;
        if (!(flags & (TF_LBMENUF_SEPARATOR | TF_LBMENUF_GRAYED))) ids.push_back(id);
        entries.push_back({id, flags});
        return S_OK;
    }
    std::vector<UINT> ids;
    std::vector<std::pair<UINT,DWORD>> entries;
private:
    ULONG references_ = 1;
};

struct ComApartment {
    ComApartment() { Success(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED), "COM initialization failed."); }
    ~ComApartment() { CoUninitialize(); }
};
std::wstring Text(ITfLangBarItemButton* button) {
    BSTR value = nullptr;
    Success(button->GetText(&value), "Mode text unavailable.");
    const std::wstring result(value, SysStringLen(value));
    SysFreeString(value);
    return result;
}
}

int wmain() {
    try {
        const auto profile = std::filesystem::temp_directory_path() /
            (L"keykey-tray-test-" + std::to_wstring(GetCurrentProcessId()) + L"-" +
             std::to_wstring(GetTickCount64()));
        std::filesystem::create_directories(profile);
        Check(SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", profile.c_str()), "Test profile isolation failed.");
        ComApartment apartment;
        auto* service = new TextService;
        ComPtr<ITfLangBarItemButton> mode;
        mode.Attach(LangBarButton::CreateInputMode(service));
        service->Release();
        Check(mode != nullptr, "Mode item allocation failed.");
        ComPtr<ITfThreadMgrEx> manager;
        Success(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager)), "TSF manager unavailable.");
        TfClientId client = TF_CLIENTID_NULL;
        // Exercise the TSF manager without registering or activating an IME
        // or changing the user's keyboard layout as part of this test.
        Success(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT), "TSF manager activation failed.");
        ComPtr<ITfCompartmentMgr> compartments;
        Success(manager.As(&compartments), "Input-mode compartments unavailable.");
        ComPtr<ITfCompartment> conversion, openClose;
        Success(compartments->GetCompartment(GUID_COMPARTMENT_KEYBOARD_INPUTMODE_CONVERSION, &conversion), "Conversion compartment unavailable.");
        Success(compartments->GetCompartment(GUID_COMPARTMENT_KEYBOARD_OPENCLOSE, &openClose), "Open/close compartment unavailable.");
        VARIANT value;
        VariantInit(&value);
        value.vt = VT_I4;
        value.lVal = TF_CONVERSIONMODE_FULLSHAPE | TF_CONVERSIONMODE_ROMAN;
        Success(conversion->SetValue(client, &value), "Initial conversion mode failed.");
        for (const bool chinese : {true, false, true}) {
            Success(WriteChineseMode(compartments.Get(), client, chinese), "Input-mode synchronization failed.");
            Success(conversion->GetValue(&value), "Conversion mode read failed.");
            Check(value.vt == VT_I4 &&
                  value.lVal == (TF_CONVERSIONMODE_FULLSHAPE | TF_CONVERSIONMODE_ROMAN |
                                 (chinese ? TF_CONVERSIONMODE_NATIVE : 0)),
                  "Native-mode toggle lost width/other flags or failed to restore Chinese mode.");
            VariantClear(&value);
            Success(openClose->GetValue(&value), "Open/close read failed.");
            Check(value.vt == VT_I4 && value.lVal == (chinese ? 1 : 0), "IME open/close and native mode disagree.");
            VariantClear(&value);
        }
        ComPtr<ITfLangBarItemMgr> items;
        Success(manager.As(&items), "Language-bar manager unavailable.");
        Success(items->AddItem(mode.Get()), "Mode item registration failed.");
        ComPtr<ITfLangBarItem> item;
        Success(items->GetItem(GUID_LBI_INPUTMODE, &item), "System tray cannot find the standard IME mode item.");
        ComPtr<ITfLangBarItemButton> button;
        Success(item.As(&button), "Mode item is not a button.");
        TF_LANGBARITEMINFO info{};
        Success(button->GetInfo(&info), "Mode metadata unavailable.");
        Check(info.guidItem == GUID_LBI_INPUTMODE && (info.dwStyle & TF_LBI_STYLE_SHOWNINTRAY), "Mode item is not exposed to the system tray.");
        Check((info.dwStyle & TF_LBI_STYLE_BTN_MENU) && !(info.dwStyle & TF_LBI_STYLE_BTN_BUTTON),
              "System tray mode item must expose the whole button as a native menu.");
        Menu menu;
        Success(button->InitMenu(&menu), "System tray menu unavailable.");
        const std::vector<UINT> tail{2,3,6,0,5,4};
        Check(menu.entries.size() >= tail.size(), "Tray menu tail missing");
        for (size_t i=0; i<tail.size(); ++i) {
            const auto& entry=menu.entries[menu.entries.size()-tail.size()+i];
            Check(entry.first==tail[i], "Tray menu order must be width, simplified, separator, symbols, settings");
            Check(((entry.second & TF_LBMENUF_SEPARATOR)!=0)==(i==3), "Tray menu separator misplaced");
        }
        auto* nativeButton=static_cast<LangBarButton*>(mode.Get());
        HMENU popup=LangBarButtonTestAccess::popup(*nativeButton);
        Check(popup!=nullptr, "Fallback popup unavailable");
        const int count=GetMenuItemCount(popup);
        Check(count>=static_cast<int>(tail.size()), "Fallback menu tail missing");
        for (size_t i=0; i<tail.size(); ++i) {
            MENUITEMINFOW entry{sizeof(entry)}; entry.fMask=MIIM_ID | MIIM_FTYPE;
            Check(GetMenuItemInfoW(popup,count-static_cast<int>(tail.size())+static_cast<int>(i),TRUE,&entry)!=FALSE,
                  "Fallback menu item unavailable");
            Check(entry.wID==tail[i], "Fallback menu order differs from tray menu");
            Check(((entry.fType & MFT_SEPARATOR)!=0)==(i==3), "Fallback separator misplaced");
        }
        DestroyMenu(popup);
        for (const auto& method : kInputMethods) {
            Check(std::find(menu.ids.begin(), menu.ids.end(), method.menuId) != menu.ids.end(), "System tray menu omitted an input method.");
            Success(button->OnMenuSelect(method.menuId), "Input method menu selection failed.");
            Check(Text(button.Get()) == method.indicator, "Mode indicator did not follow input method selection.");
        }
        Success(button->OnMenuSelect(1), "English mode toggle failed.");
        Check(Text(button.Get()) == L"英", "English mode indicator failed.");
        Success(button->OnMenuSelect(kInputMethods[0].menuId), "Chinese mode restore failed.");
        Check(Text(button.Get()) == L"ㄅ", "Chinese mode indicator failed.");
        Success(items->RemoveItem(mode.Get()), "Mode item removal failed.");
        item.Reset();
        const HRESULT removed = items->GetItem(GUID_LBI_INPUTMODE, &item);
        Check(FAILED(removed) || !item, "Removal left a stale mode item.");
        // Use real TSF compartments with an isolated profile, without installing
        // or switching the user's active keyboard layout.
        for (const auto& method : kInputMethods) {
            for (const bool startChinese : {true, false}) {
                const auto loader = LoaderPreferencesPath();
                const auto previousTime = std::filesystem::last_write_time(loader);
                { std::ofstream out(loader); out << "<plist><dict><key>PrimaryInputMethod</key><string>"
                    << method.identifier << "</string><key>DefaultInputMode</key><string>"
                    << (startChinese ? "Chinese" : "English") << "</string></dict></plist>"; }
                std::filesystem::last_write_time(loader, previousTime + std::chrono::seconds(2));
                ComPtr<TextService> startup; startup.Attach(new TextService);
                TextServiceTestAccess::start(*startup.Get(), manager.Get(), client);
                Check(startup->isChineseMode()==startChinese && CurrentInputMethod()==method.identifier,
                      "Startup preference lost mode or selected Chinese input method");
                Success(openClose->GetValue(&value), "Startup compartment read failed");
                Check(value.vt==VT_I4 && value.lVal==(startChinese ? 1 : 0), "Startup state was not published to Windows");
                VariantClear(&value);
                startup->toggleChineseMode();
                Success(startup->OnSetFocus(TRUE), "Focus after manual toggle failed");
                Check(startup->isChineseMode()!=startChinese && LoadFrontendSettings().defaultChineseMode==startChinese,
                      "Focus reset live mode or toggle changed startup preference");
                Success(startup->Deactivate(), "Startup deactivation failed");
                TextServiceTestAccess::start(*startup.Get(), manager.Get(), client);
                Check(startup->isChineseMode()==startChinese, "Reactivation did not reapply startup preference");
                Success(startup->Deactivate(), "Startup cleanup failed");
            }
        }
        Check(!ResolveStartupChineseMode(manager.Get(),client,false,false), "Desktop English preference failed");
        Check(!ResolveStartupChineseMode(manager.Get(),client,true,true), "Immersive host ignored desktop English preference");
        Check(ResolveStartupChineseMode(manager.Get(),client,false,true), "Desktop Chinese preference failed");
        Check(ResolveStartupChineseMode(manager.Get(),client,true,false), "Immersive host ignored desktop Chinese preference");
        Success(manager->Deactivate(), "TSF manager deactivation failed.");
        std::cout << "TSF system tray mode item and four input method selections passed.\n";
        return 0;
    } catch (const std::exception& error) {
        std::cerr << error.what() << '\n';
        return 1;
    }
}

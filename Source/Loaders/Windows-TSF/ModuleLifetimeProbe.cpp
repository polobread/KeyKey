// Test-only exports linked with the production COM server and frontend sources.
// Never registered as a TIP; the host uses an isolated settings directory.
#include "CandidateWindow.h"
#include "SymbolPanel.h"
#include "KeyKeyEngine.h"
#include "ModuleState.h"
#include <thread>
#include <vector>
#include <atomic>

using namespace KeyKey::WindowsTsf;
extern "C" HRESULT __stdcall DllCanUnloadNow();

extern "C" __declspec(dllexport) int __cdecl ProbeWarm(HWND owner) {
    // Race first use on several threads: only one runtime may be constructed.
    std::atomic<bool> ready{true};
    std::vector<std::thread> workers;
    for (int i=0;i<4;++i) workers.emplace_back([&] {
        if (!IsInputMethodAvailable("SmartMandarin")) ready=false;
    });
    for (auto& worker : workers) worker.join();
    if (!ready) return 1;
    {
        auto engine=KeyKeyEngineSession::CreateControlled("SmartMandarin");
        if (!engine || !engine->ready() || ShutdownEngineRuntime()) return 2;
        if (DllCanUnloadNow()!=S_FALSE) return 3;
    }
    BeginOrderedEngineInput();
    if (ShutdownEngineRuntime() || DllCanUnloadNow()!=S_FALSE) return 4;
    EndOrderedEngineInput();
    {
        // A partial registration must be cleanable, and ALREADY_EXISTS must
        // never silently adopt a different callback under our class name.
        WNDCLASSEXW foreign{sizeof(foreign)};
        foreign.hInstance=g_module; foreign.lpfnWndProc=DefWindowProcW;
        foreign.lpszClassName=L"chichi77.KeyKey.TSF.SymbolContent";
        if (!RegisterClassExW(&foreign)) return 8;
        SymbolPanel symbols;
        if (symbols.show(owner,RECT{0,0,50,30},[](const std::wstring&){})) return 9;
        if (!SymbolPanel::releaseWindowClasses()) return 10;
        if (!UnregisterClassW(foreign.lpszClassName,g_module)) return 11;
    }
    {
        CandidateWindow candidate;
        candidate.show(owner,RECT{0,0,50,30},{{L"1",L"test"}},0);
        if (CandidateWindow::releaseWindowClass() || DllCanUnloadNow()!=S_FALSE) return 5;
        SymbolPanel symbols;
        if (!symbols.show(owner,RECT{0,0,50,30},[](const std::wstring&){})) return 6;
        candidate.hide();
        if (SymbolPanel::releaseWindowClasses() || DllCanUnloadNow()!=S_FALSE) return 7;
    }
    return 0;
}

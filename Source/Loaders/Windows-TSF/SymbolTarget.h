#pragma once

#include <Windows.h>
#include <vector>

namespace KeyKey::WindowsTsf {

inline DWORD SymbolInputThread(HWND foreground) {
    DWORD process=0;
    const DWORD rootThread=GetWindowThreadProcessId(foreground,&process);
    GUITHREADINFO info{sizeof(info)};
    if (!rootThread || !GetGUIThreadInfo(rootThread,&info) || !info.hwndFocus) return 0;
    DWORD focusedProcess=0;
    const DWORD thread=GetWindowThreadProcessId(info.hwndFocus,&focusedProcess);
    return focusedProcess==process && GetForegroundWindow()==foreground ? thread : 0;
}

inline std::vector<HWND> SymbolTargets(HWND foreground,const wchar_t* dispatchTitle) {
    std::vector<HWND> targets;
    // The editor can be on a different thread from its foreground frame.
    const DWORD thread=SymbolInputThread(foreground);
    if (!thread) return targets;
    DWORD process=0;
    GetWindowThreadProcessId(foreground,&process);
    // EnumThreadWindows omits SearchHost's immersive windows on Windows 11.
    // Find only our known STATIC endpoint, then enforce the same focused
    // process/thread boundary before querying or sending any symbol.
    HWND window=nullptr;
    while ((window=FindWindowExW(nullptr,window,L"STATIC",dispatchTitle))) {
        DWORD owner=0;
        if (GetWindowThreadProcessId(window,&owner)==thread && owner==process)
            targets.push_back(window);
        if (targets.size()==8) break;
    }
    return targets;
}

} // namespace KeyKey::WindowsTsf

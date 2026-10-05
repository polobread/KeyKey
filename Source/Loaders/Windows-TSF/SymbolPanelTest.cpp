#include "SymbolPanel.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include <filesystem>
#include <fstream>
#include <iostream>
#include <set>
#include <stdexcept>
namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0};
std::atomic<long> g_serverLocks{0};
struct SymbolPanelTestAccess {
    static HWND window(SymbolPanel& panel) { return panel.window_; }
    static size_t category(SymbolPanel& panel) { return panel.category_; }
    static size_t capacity(SymbolPanel& panel) { return panel.capacity_; }
    static size_t page(SymbolPanel& panel) { return panel.page_; }
    static void category(SymbolPanel& panel,size_t index) {
        panel.category_=index; panel.page_=0;
        RECT rect{}; GetWindowRect(panel.window_,&rect);
        rect.bottom=rect.top+panel.scaled(BuiltinSymbolCategories()[index].layout==SymbolLayout::List ? 430 : 310);
        panel.position(rect); panel.rebuild();
    }
    static void dragBy(SymbolPanel& panel,int x,int y) {
        panel.dragStart_.x-=x; panel.dragStart_.y-=y;
    }
    static void small(SymbolPanel& panel) {
        RECT rect{}; GetWindowRect(panel.window_,&rect);
        rect.right=rect.left+240; rect.bottom=rect.top+220;
        panel.position(rect); panel.rebuild();
    }
    static void palette(SymbolPanel& panel,COLORREF foreground,COLORREF background) {
        panel.foreground_=foreground; panel.backgroundColor_=background;
        if (panel.background_) DeleteObject(panel.background_);
        panel.background_=CreateSolidBrush(background); panel.rebuild();
    }
    static bool unavailable(SymbolPanel& panel) {
        RECT bounds{0,0,32,32};
        return !panel.drawColorEmoji(nullptr,bounds,L"\xD83D\xDE00",RGB(255,255,255),RGB(0,0,0));
    }
    static void contrast(SymbolPanel& panel,bool enabled) { panel.highContrast_=enabled; }
};
}
using namespace KeyKey::WindowsTsf;
void Check(bool ok,const char* message) { if (!ok) throw std::runtime_error(message); }
void Click(HWND panel,UINT id) {
    HWND item=GetDlgItem(panel,id);
    Check(item && IsWindowEnabled(item),"Clickable control missing");
    SendMessageW(item,WM_LBUTTONDOWN,MK_LBUTTON,MAKELPARAM(5,5));
    SendMessageW(item,WM_LBUTTONUP,0,MAKELPARAM(5,5));
}
std::wstring Label(HWND hwnd) {
    const int length=GetWindowTextLengthW(hwnd);
    std::wstring text(static_cast<size_t>(length)+1,L'\0');
    GetWindowTextW(hwnd,text.data(),length+1); text.resize(length); return text;
}
void CheckBounds(HWND panel) {
    RECT client{}; GetClientRect(panel,&client);
    for (HWND child=GetWindow(panel,GW_CHILD);child;child=GetWindow(child,GW_HWNDNEXT)) {
        RECT rect{}; GetWindowRect(child,&rect); MapWindowPoints(nullptr,panel,reinterpret_cast<POINT*>(&rect),2);
        Check(rect.left>=0 && rect.top>=0 && rect.right<=client.right && rect.bottom<=client.bottom &&
              rect.right>rect.left && rect.bottom>rect.top,"Control exceeds panel bounds");
    }
}
void Render(HWND panel,const std::filesystem::path& file,bool requireColor=false,bool requireMonochromeGlyph=false) {
    RECT rect{}; GetClientRect(panel,&rect);
    HDC screen=GetDC(panel), dc=CreateCompatibleDC(screen);
    HBITMAP bitmap=CreateCompatibleBitmap(screen,rect.right,rect.bottom);
    auto old=SelectObject(dc,bitmap);
    Check(PrintWindow(panel,dc,PW_CLIENTONLY)!=FALSE,"Native panel render failed");
    SelectObject(dc,old);
    BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth=rect.right; info.bmiHeader.biHeight=-rect.bottom;
    info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
    std::vector<unsigned char> pixels(static_cast<size_t>(rect.right)*rect.bottom*4);
    Check(GetDIBits(dc,bitmap,0,rect.bottom,pixels.data(),&info,DIB_RGB_COLORS)!=0,"Bitmap read failed");
    if (requireColor || requireMonochromeGlyph) {
        RECT emoji{}; GetWindowRect(GetDlgItem(panel,100),&emoji);
        MapWindowPoints(nullptr,panel,reinterpret_cast<POINT*>(&emoji),2);
        size_t colored=0,ink=0;
        for (int y=emoji.top+2;y<emoji.bottom-2;++y) for (int x=emoji.left+2;x<emoji.right-2;++x) {
            const auto* pixel=&pixels[(static_cast<size_t>(y)*rect.right+x)*4];
            const int maximum=std::max({pixel[0],pixel[1],pixel[2]});
            const int minimum=std::min({pixel[0],pixel[1],pixel[2]});
            if (maximum-minimum>100) ++colored;
            if (maximum<220) ++ink;
        }
        if (requireColor) Check(colored>100,"Emoji native render must contain substantial color glyph pixels");
        if (requireMonochromeGlyph) Check(ink>100,"Monochrome emoji fallback must still render the glyph");
    }
    BITMAPFILEHEADER header{}; header.bfType=0x4D42;
    header.bfOffBits=sizeof(header)+sizeof(info.bmiHeader);
    header.bfSize=header.bfOffBits+static_cast<DWORD>(pixels.size());
    std::ofstream out(file,std::ios::binary);
    out.write(reinterpret_cast<const char*>(&header),sizeof(header));
    out.write(reinterpret_cast<const char*>(&info.bmiHeader),sizeof(info.bmiHeader));
    out.write(reinterpret_cast<const char*>(pixels.data()),static_cast<std::streamsize>(pixels.size()));
    Check(out.good(),"Native render artifact write failed");
    DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(panel,screen);
}
void CheckDrawState(HWND panel,UINT id) {
    HWND item=GetDlgItem(panel,id);
    RECT bounds{}; GetClientRect(item,&bounds);
    HDC screen=GetDC(item),dc=CreateCompatibleDC(screen);
    HBITMAP bitmap=CreateCompatibleBitmap(screen,bounds.right,bounds.bottom);
    auto oldBitmap=SelectObject(dc,bitmap);
    auto font=GetStockObject(SYSTEM_FIXED_FONT); SelectObject(dc,font);
    SetTextColor(dc,RGB(21,42,63)); SetBkColor(dc,RGB(71,82,93)); SetBkMode(dc,OPAQUE);
    for (UINT state : {0U,static_cast<UINT>(ODS_SELECTED),0U}) {
        DRAWITEMSTRUCT draw{ODT_BUTTON,id,0,ODA_DRAWENTIRE,state,item,dc,bounds,0};
        Check(SendMessageW(panel,WM_DRAWITEM,id,reinterpret_cast<LPARAM>(&draw))!=0,"Owner draw failed");
        Check(GetCurrentObject(dc,OBJ_FONT)==font && GetTextColor(dc)==RGB(21,42,63) &&
              GetBkColor(dc)==RGB(71,82,93) && GetBkMode(dc)==OPAQUE,"Owner draw leaked caller DC state");
        Check(!Label(item).empty(),"Selected/unselected redraw lost control text");
    }
    SelectObject(dc,oldBitmap); DeleteObject(bitmap); DeleteDC(dc); ReleaseDC(item,screen);
}
namespace {
HWND popupHost=nullptr, popupOwner=nullptr;
SymbolPanel* popupPanel=nullptr;
int popupAction=0, timerTicks=0;
bool popupSeen=false,popupFocus=true;
bool popupTimeout=false;
bool popupHighlight=true;
std::filesystem::path popupArtifact;
void CALLBACK PopupTimer(HWND,UINT,UINT_PTR timer,DWORD) {
    ++timerTicks;
    if (timerTicks>=20) { popupTimeout=true; KillTimer(nullptr,timer); EndMenu(); return; }
    HWND menu=nullptr;
    while ((menu=FindWindowExW(nullptr,menu,L"#32768",nullptr))) {
        if (IsWindowVisible(menu) && GetWindowThreadProcessId(menu,nullptr)==GetCurrentThreadId()) break;
    }
    if (menu) {
        popupSeen=true; popupFocus=popupFocus && GetFocus()==popupHost;
        if (popupAction==0) { KillTimer(nullptr,timer); EndMenu(); }
        else if (popupAction==1) {
            // Native menu type-to-select chooses its unique English "Emoji" item.
            // Post messages only to our own menu; preserve desktop keyboard/mouse state.
            PostMessageW(menu,WM_CHAR,L'E',1);
            PostMessageW(menu,WM_KEYDOWN,VK_RETURN,1);
            popupAction=-1;
        } else if (popupAction==2) { KillTimer(nullptr,timer); popupPanel->hide(); }
        else if (popupAction==3) { KillTimer(nullptr,timer); DestroyWindow(popupOwner); }
        else if (popupAction==4) { KillTimer(nullptr,timer); delete popupPanel; popupPanel=nullptr; }
        else if (popupAction==5) {
            MENUBARINFO info{sizeof(info)};
            if (!GetMenuBarInfo(menu,OBJID_CLIENT,0,&info) || !info.hMenu) {
                popupHighlight=false; KillTimer(nullptr,timer); EndMenu(); return;
            }
            // Exercise native highlight drawing without changing desktop mouse state.
            const UINT index=timerTicks==1 ? 0 : timerTicks==2 ? 5 : 17;
            wchar_t before[128]{},after[128]{};
            GetMenuStringW(info.hMenu,index,before,128,MF_BYPOSITION);
            popupHighlight=popupHighlight && HiliteMenuItem(SymbolPanelTestAccess::window(*popupPanel),info.hMenu,
                index,MF_BYPOSITION|MF_HILITE)!=FALSE;
            RedrawWindow(menu,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW);
            GetMenuStringW(info.hMenu,index,after,128,MF_BYPOSITION);
            popupHighlight=popupHighlight && before[0] && std::wstring(before)==after;
            if (timerTicks==2 && !popupArtifact.empty()) {
                try { Render(menu,popupArtifact); } catch (...) { popupHighlight=false; }
            }
            if (timerTicks>=3) { KillTimer(nullptr,timer); EndMenu(); }
        }
    }
}
void Popup(SymbolPanel& panel,HWND host,int action) {
    popupHost=host; popupOwner=host; popupPanel=&panel; popupAction=action;
    timerTicks=0; popupSeen=false; popupFocus=true; popupTimeout=false; popupHighlight=true;
    const UINT_PTR timer=SetTimer(nullptr,0,50,PopupTimer);
    Check(timer!=0,"Popup test timer failed");
    Click(SymbolPanelTestAccess::window(panel),1);
    KillTimer(nullptr,timer);
    Check(popupSeen,"Native category popup did not open");
    Check(!popupTimeout,"Native category popup test timed out");
    Check(popupFocus,"Native category popup changed host focus");
    Check(popupHighlight,"Native category highlight redraw failed/lost label");
}
}
int wmain(int argc,wchar_t** argv) {
    try {
        SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        g_module=GetModuleHandleW(nullptr);
        const auto& categories=BuiltinSymbolCategories();
        Check(categories.size()==18,"All plist categories plus Emoji must be embedded");
        size_t count=0,grid=0,list=0,listIndex=0;
        bool longMessage=false;
        for (size_t i=0;i<17;++i) {
            const auto& category=categories[i];
            Check(!category.name.empty() && !category.items.empty(),"Empty category");
            if (category.layout==SymbolLayout::Grid) ++grid; else { ++list; listIndex=i; }
            for (const auto& item : category.items) {
                Check(!item.label.empty() && !item.text.empty(),"Empty item"); ++count;
                if (item.text==L"v(\xFFE3\xFE36\xFFE3)y \x5F97\x610F\x3001YA~") longMessage=true;
            }
        }
        Check(count==807 && grid==16 && list==1,"All original 733 Buttons and 74 Messages/layouts must be embedded");
        Check(longMessage,"Full message text must survive generation");
        const auto& emojis=categories.back();
        Check(emojis.layout==SymbolLayout::Grid && emojis.emoji && emojis.items.size()==200,"Mobile and Windows emoji grid missing");
        std::set<std::wstring> unique;
        for (const auto& item : emojis.items) { unique.insert(item.text); Check(item.text==item.label,"Emoji string split"); }
        Check(unique.size()==200,"Mobile and Windows emojis must be unique");
        Check(emojis.items[0].text==L"\xD83D\xDE00" && emojis.items[30].text==L"\x270C\xFE0F" &&
              emojis.items[36].text==L"\x2764\xFE0F","Emoji surrogate pairs/variation selectors changed");
        HWND host=CreateWindowExW(0,L"EDIT",L"",WS_POPUP | WS_VISIBLE,0,0,100,100,nullptr,nullptr,g_module,nullptr);
        Check(host!=nullptr,"Host creation"); SetFocus(host);
        Check(GetFocus()==host,"Test requires real host focus");
        SymbolPanel panel; RECT anchor{20,20,30,40}; int calls=0; std::wstring chosen;
        auto show=[&] { Check(panel.show(host,anchor,[&](const std::wstring& text) { ++calls; chosen=text; }),"Panel creation"); };
        show(); HWND hwnd=SymbolPanelTestAccess::window(panel);
        Check(panel.visible() && (GetWindowLongPtrW(hwnd,GWL_EXSTYLE)&WS_EX_NOACTIVATE),"Noactivate panel missing");
        Check(GetFocus()==host,"Showing panel changed host focus");
        RECT first{},tenth{}; GetWindowRect(GetDlgItem(hwnd,100),&first); GetWindowRect(GetDlgItem(hwnd,109),&tenth);
        Check(first.top==tenth.top && first.right<tenth.left,"Symbols must use ten columns");
        CheckBounds(hwnd);
        if (argc>1) { std::filesystem::create_directories(argv[1]); Render(hwnd,std::filesystem::path(argv[1])/L"symbols-light.bmp"); }
        Popup(panel,host,0);
        Check(GetFocus()==host && panel.visible() && calls==0,"Cancel dropdown changed selection/focus");
        for (int iteration=0;iteration<20;++iteration) {
            popupArtifact=(argc>1 && iteration==0) ? std::filesystem::path(argv[1])/L"category-native-highlight.bmp" : std::filesystem::path{};
            Popup(panel,host,5);
            Check(GetFocus()==host && panel.visible() && calls==0,"Repeated category redraw changed focus/selection");
        }
        popupArtifact.clear(); CheckDrawState(hwnd,1); CheckDrawState(hwnd,100);
        Popup(panel,host,1);
        Check(GetFocus()==host && SymbolPanelTestAccess::category(panel)==17 &&
              SymbolPanelTestAccess::page(panel)==0 && calls==0,"Dropdown did not select Emoji safely");
        Check(SymbolPanelTestAccess::capacity(panel)==40,"Default emoji grid must show five pages of forty");
        Check(SymbolPanelTestAccess::unavailable(panel),"Invalid color render DC must fail safely");
        CheckDrawState(hwnd,100);
        if (argc>1) {
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-page1.bmp",true);
            for (int page=2;page<=5;++page) {
                Click(hwnd,5);
                Render(hwnd,std::filesystem::path(argv[1])/(L"emoji-color-page"+std::to_wstring(page)+L".bmp"),true);
            }
            for (int page=5;page>1;--page) Click(hwnd,4);
            SymbolPanelTestAccess::palette(panel,RGB(245,245,245),RGB(32,32,32));
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-dark.bmp",true);
            SymbolPanelTestAccess::palette(panel,RGB(0,0,0),RGB(255,255,255));
            SymbolPanelTestAccess::contrast(panel,true);
            CheckDrawState(hwnd,100);
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-high-contrast-fallback.bmp",false,true);
            SymbolPanelTestAccess::contrast(panel,false);
        }
        // Visit every emoji through the rendered pages, including the partial last page.
        size_t seen=0;
        do {
            for (UINT id=100;GetDlgItem(hwnd,id);++id) {
                Check(Label(GetDlgItem(hwnd,id))==emojis.items[seen].label,"Emoji paging repeats or loses entries");
                ++seen;
            }
            if (!IsWindowEnabled(GetDlgItem(hwnd,5))) break;
            Click(hwnd,5);
        } while (true);
        Check(seen==200,"Emoji paging omitted entries");
        SendMessageW(hwnd,WM_COMMAND,MAKEWPARAM(100,BN_CLICKED),reinterpret_cast<LPARAM>(GetDlgItem(hwnd,1)));
        Check(calls==0,"Unrelated/stale control command accepted");
        Popup(panel,host,1);
        Check(SymbolPanelTestAccess::page(panel)==0,"Category selection must reset page");
        Click(hwnd,100);
        Check(calls==1 && chosen==emojis.items[0].text && !panel.visible() && GetFocus()==host,"Emoji click must insert once and close");
        Click(hwnd,100); Check(calls==1,"Stale click ignored");
        {
            SymbolPanel fallback; std::wstring fallbackText;
            Check(fallback.show(host,anchor,[&](const std::wstring& text) { fallbackText=text; }),"Fallback panel show");
            SymbolPanelTestAccess::category(fallback,17); SymbolPanelTestAccess::contrast(fallback,true);
            HWND fallbackWindow=SymbolPanelTestAccess::window(fallback);
            CheckDrawState(fallbackWindow,136); Click(fallbackWindow,136);
            Check(fallbackText==emojis.items[36].text && !fallback.visible() && GetFocus()==host,
                  "Monochrome fallback must preserve full variation-selector string and host focus");
        }
        show(); SymbolPanelTestAccess::category(panel,listIndex);
        CheckBounds(hwnd);
        if (argc>1) Render(hwnd,std::filesystem::path(argv[1])/L"kaomoji-light.bmp");
        Click(hwnd,100);
        Check(calls==2 && chosen==categories[listIndex].items[0].text,"Kaomoji insertion must use full text");
        show(); SymbolPanelTestAccess::category(panel,0);
        SendMessageW(hwnd,WM_LBUTTONDOWN,MK_LBUTTON,MAKELPARAM(12,12));
        Check(GetCapture()==hwnd && GetFocus()==host,"Dragging must keep host focus");
        SymbolPanelTestAccess::dragBy(panel,-120,-80);
        SendMessageW(hwnd,WM_MOUSEMOVE,MK_LBUTTON,MAKELPARAM(12,12));
        SendMessageW(hwnd,WM_LBUTTONUP,0,MAKELPARAM(12,12));
        RECT moved{},reopened{}; GetWindowRect(hwnd,&moved); panel.hide(); show(); GetWindowRect(hwnd,&reopened);
        Check(moved.left==reopened.left && moved.top==reopened.top,"Reopen lost dragged position");
        Check(GetFocus()==host,"Drag/reopen changed host focus");
        SendMessageW(hwnd,WM_LBUTTONDOWN,MK_LBUTTON,MAKELPARAM(12,12));
        SymbolPanelTestAccess::dragBy(panel,100000,100000);
        SendMessageW(hwnd,WM_MOUSEMOVE,MK_LBUTTON,0); SendMessageW(hwnd,WM_LBUTTONUP,0,0);
        RECT clamped{}; GetWindowRect(hwnd,&clamped); MONITORINFO monitor{sizeof(monitor)};
        GetMonitorInfoW(MonitorFromWindow(hwnd,MONITOR_DEFAULTTONEAREST),&monitor);
        Check(clamped.left>=monitor.rcWork.left && clamped.top>=monitor.rcWork.top &&
              clamped.right<=monitor.rcWork.right && clamped.bottom<=monitor.rcWork.bottom,"Dragged position escapes work area");
        SymbolPanelTestAccess::small(panel); CheckBounds(hwnd);
        RECT dpiRect{100,100,730,565};
        SendMessageW(hwnd,WM_DPICHANGED,MAKEWPARAM(144,144),reinterpret_cast<LPARAM>(&dpiRect)); CheckBounds(hwnd);
        if (argc>1) Render(hwnd,std::filesystem::path(argv[1])/L"symbols-150dpi.bmp");
        SymbolPanelTestAccess::category(panel,17);
        if (argc>1) Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-150dpi.bmp",true);
        SymbolPanelTestAccess::category(panel,0);
        SendMessageW(hwnd,WM_THEMECHANGED,0,0); CheckBounds(hwnd);
        if (argc>1) {
            SymbolPanelTestAccess::palette(panel,RGB(245,245,245),RGB(32,32,32));
            Render(hwnd,std::filesystem::path(argv[1])/L"symbols-dark-palette.bmp");
            SymbolPanelTestAccess::palette(panel,RGB(255,255,255),RGB(0,0,0));
            Render(hwnd,std::filesystem::path(argv[1])/L"symbols-contrast-palette.bmp");
        }
        Popup(panel,host,2);
        Check(!panel.visible() && calls==2,"Hide during category popup applied stale selection");
        show(); SendMessageW(hwnd,WM_KEYDOWN,VK_ESCAPE,0);
        Check(calls==2 && !panel.visible(),"Escape cancels");
        show(); SendMessageW(hwnd,WM_CLOSE,0,0);
        Check(calls==2 && !panel.visible(),"Close cancels");
        show(); Popup(panel,host,3);
        Check(!panel.visible() && calls==2,"Owner destruction during popup left stale panel");
        Check(panel.show(nullptr,anchor,[&](const std::wstring&) { ++calls; }),"Reopen after owner destruction");
        Check(panel.visible(),"Recreated ownerless panel visible"); panel.hide();
        host=CreateWindowExW(0,L"EDIT",L"",WS_POPUP | WS_VISIBLE,0,0,100,100,nullptr,nullptr,g_module,nullptr);
        SetFocus(host); Check(GetFocus()==host,"Destruction test requires host focus");
        auto* disposable=new SymbolPanel;
        Check(disposable->show(host,anchor,[&](const std::wstring&) { ++calls; }),"Disposable panel show");
        Popup(*disposable,host,4);
        Check(!popupPanel && calls==2 && GetFocus()==host,"Panel destruction during nested popup was unsafe");
        DestroyWindow(host);
        std::cout<<"Symbol resources, native category popup, paging, focus, drag, DPI and cancellation tests passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}

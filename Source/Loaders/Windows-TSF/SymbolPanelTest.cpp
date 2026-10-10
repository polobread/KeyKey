#include "SymbolPanel.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include "FrontendSettings.h"
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
    static int offset(SymbolPanel& panel) { return panel.scrollOffset_; }
    static unsigned renders(SymbolPanel& panel) { return panel.emojiRasterizations_; }
    static UINT dpi(SymbolPanel& panel) { return panel.dpi_; }
    static UINT hostDpi(SymbolPanel& panel) { return panel.hostDpi_; }
    static void category(SymbolPanel& panel,size_t index) {
        panel.category_=index; panel.scrollOffset_=0;
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
HWND PanelControl(HWND panel,UINT id) {
    return GetDlgItem(id>=100 ? GetDlgItem(GetDlgItem(panel,10),11) : panel,id);
}
HWND ScrollControl(HWND panel) { return GetDlgItem(PanelControl(panel,10),12); }
void Scroll(HWND panel,UINT request) {
    SendMessageW(PanelControl(panel,10),WM_VSCROLL,request,reinterpret_cast<LPARAM>(ScrollControl(panel)));
}
void Check(bool ok,const char* message) { if (!ok) throw std::runtime_error(message); }
void Click(HWND panel,UINT id) {
    HWND item=PanelControl(panel,id);
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
std::vector<unsigned char> Render(HWND panel,const std::filesystem::path& file,bool requireColor=false,bool requireMonochromeGlyph=false) {
    RECT rect{}; GetClientRect(panel,&rect);
    HDC screen=GetDC(panel), dc=CreateCompatibleDC(screen);
    HBITMAP bitmap=CreateCompatibleBitmap(screen,rect.right,rect.bottom);
    auto old=SelectObject(dc,bitmap);
    FillRect(dc,&rect,GetSysColorBrush(COLOR_WINDOW));
    wchar_t windowClass[32]{}; GetClassNameW(panel,windowClass,32);
    if (_wcsicmp(windowClass,L"ScrollBar")==0)
        SendMessageW(panel,WM_PAINT,reinterpret_cast<WPARAM>(dc),0);
    else Check(PrintWindow(panel,dc,PW_CLIENTONLY)!=FALSE,"Native panel render failed");
    // ScrollBar paints into a supplied WM_PAINT DC rather than WM_PRINTCLIENT.
    // Composite its drawing into the panel artifact.
    if (const HWND scrollbar=ScrollControl(panel)) {
        RECT bounds{}; GetWindowRect(scrollbar,&bounds);
        MapWindowPoints(nullptr,panel,reinterpret_cast<POINT*>(&bounds),2);
        const int width=bounds.right-bounds.left,height=bounds.bottom-bounds.top;
        HDC scrollDC=CreateCompatibleDC(screen);
        HBITMAP scrollBitmap=CreateCompatibleBitmap(screen,width,height);
        const auto previous=SelectObject(scrollDC,scrollBitmap);
        RECT local{0,0,width,height}; FillRect(scrollDC,&local,GetSysColorBrush(COLOR_WINDOW));
        SendMessageW(scrollbar,WM_PAINT,reinterpret_cast<WPARAM>(scrollDC),0);
        BitBlt(dc,bounds.left,bounds.top,width,height,scrollDC,0,0,SRCCOPY);
        SelectObject(scrollDC,previous); DeleteObject(scrollBitmap); DeleteDC(scrollDC);
    }
    SelectObject(dc,old);
    BITMAPINFO info{}; info.bmiHeader.biSize=sizeof(BITMAPINFOHEADER);
    info.bmiHeader.biWidth=rect.right; info.bmiHeader.biHeight=-rect.bottom;
    info.bmiHeader.biPlanes=1; info.bmiHeader.biBitCount=32; info.bmiHeader.biCompression=BI_RGB;
    std::vector<unsigned char> pixels(static_cast<size_t>(rect.right)*rect.bottom*4);
    Check(GetDIBits(dc,bitmap,0,rect.bottom,pixels.data(),&info,DIB_RGB_COLORS)!=0,"Bitmap read failed");
    if (requireColor || requireMonochromeGlyph) {
        RECT viewport{}; GetWindowRect(PanelControl(panel,10),&viewport);
        RECT emoji{};
        for (UINT id=100;PanelControl(panel,id);++id) {
            GetWindowRect(PanelControl(panel,id),&emoji);
            if (emoji.top>=viewport.top && emoji.bottom<=viewport.bottom) break;
        }
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
    return pixels;
}
void CheckDrawState(HWND panel,UINT id) {
    HWND item=PanelControl(panel,id);
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
HWND nativeScroll=nullptr,nativeScrollHost=nullptr;
bool nativeScrollFocus=true;
int nativeScrollTarget=0;
void CALLBACK NativeScrollRelease(HWND,UINT,UINT_PTR timer,DWORD) {
    nativeScrollFocus=nativeScrollFocus && GetFocus()==nativeScrollHost;
    KillTimer(nullptr,timer);
    PostMessageW(nativeScroll,WM_LBUTTONUP,0,MAKELPARAM(5,nativeScrollTarget));
}
void ScrollArrow(HWND scrollbar,HWND host,int y) {
    nativeScroll=scrollbar; nativeScrollHost=host;
    nativeScrollFocus=true; nativeScrollTarget=y;
    const UINT_PTR timer=SetTimer(nullptr,0,50,NativeScrollRelease);
    Check(timer!=0,"Native scrollbar test timer failed");
    SendMessageW(scrollbar,WM_LBUTTONDOWN,MK_LBUTTON,MAKELPARAM(5,y));
    KillTimer(nullptr,timer);
    Check(nativeScrollFocus && GetFocus()==host,"Native scrollbar mouse operation stole host focus");
}
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
    wchar_t temp[MAX_PATH]{}; GetTempPathW(MAX_PATH,temp);
    const auto profile=std::filesystem::path(temp)/(L"keykey-symbols-"+std::to_wstring(GetCurrentProcessId()));
    std::filesystem::create_directories(profile);
    SetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR",profile.c_str());
    struct Cleanup { std::filesystem::path path; ~Cleanup() { std::error_code error; std::filesystem::remove_all(path,error); } } cleanup{profile};
    try {
        const auto manifest=profile/L"controls.manifest";
        { std::ofstream out(manifest); out<<"<assembly xmlns=\"urn:schemas-microsoft-com:asm.v1\" manifestVersion=\"1.0\">"
            "<assemblyIdentity version=\"1.0.0.0\" processorArchitecture=\"*\" name=\"KeyKey.SymbolPanel.Test\" type=\"win32\"/>"
            "<dependency><dependentAssembly><assemblyIdentity type=\"win32\" name=\"Microsoft.Windows.Common-Controls\" "
            "version=\"6.0.0.0\" processorArchitecture=\"*\" publicKeyToken=\"6595b64144ccf1df\" language=\"*\"/>"
            "</dependentAssembly></dependency></assembly>"; }
        ACTCTXW context{sizeof(context)}; context.lpSource=manifest.c_str();
        const HANDLE activation=CreateActCtxW(&context);
        Check(activation!=INVALID_HANDLE_VALUE,"Cannot create themed host activation context");
        ULONG_PTR cookie=0;
        Check(ActivateActCtx(activation,&cookie)!=FALSE,"Cannot activate themed host controls");
        struct ThemeCleanup { HANDLE activation; ULONG_PTR cookie; ~ThemeCleanup() { DeactivateActCtx(0,cookie); ReleaseActCtx(activation); } } themeCleanup{activation,cookie};
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
        RECT first{},tenth{}; GetWindowRect(PanelControl(hwnd,100),&first); GetWindowRect(PanelControl(hwnd,109),&tenth);
        Check(first.top==tenth.top && first.right<tenth.left,"Symbols must use ten columns");
        CheckBounds(hwnd);
        if (argc>1) { std::filesystem::create_directories(argv[1]); Render(hwnd,std::filesystem::path(argv[1])/L"symbols-light.bmp"); }
        const auto setScale=[&](int scale) {
            std::ofstream out(LoaderPreferencesPath());
            out<<"<plist><dict><key>CandidateWindowScalePercent</key><string>"<<scale<<"</string></dict></plist>";
            Check(out.good(),"Test scale preference write failed");
        };
        RECT normal{}; GetWindowRect(hwnd,&normal);
        setScale(125); panel.hide(); show();
        RECT enlarged{}; GetWindowRect(hwnd,&enlarged);
        const UINT expected=ContentDpiForScale(SymbolPanelTestAccess::hostDpi(panel),
            MonitorFromWindow(hwnd,MONITOR_DEFAULTTONEAREST),125);
        Check(SymbolPanelTestAccess::dpi(panel)==expected && enlarged.right-enlarged.left==MulDiv(440,expected,96),
            "Symbol panel must use candidate window scale for window and font sizes");
        GetWindowRect(PanelControl(hwnd,100),&first);
        Check(first.bottom-first.top==MulDiv(34,expected,96),"Symbol cells must use candidate window scale");
        CheckBounds(hwnd);
        if (argc>1) Render(hwnd,std::filesystem::path(argv[1])/L"symbols-125percent.bmp");
        SymbolPanelTestAccess::category(panel,17);
        if (argc>1) Render(hwnd,std::filesystem::path(argv[1])/L"emoji-125percent.bmp",true);
        setScale(0); SendMessageW(hwnd,WM_SETTINGCHANGE,0,0);
        Check(SymbolPanelTestAccess::dpi(panel)==SymbolPanelTestAccess::hostDpi(panel),
            "Follow Windows scale must restore host DPI on settings change");
        SymbolPanelTestAccess::category(panel,0);
        for (size_t category=0;category<categories.size();++category) {
            SymbolPanelTestAccess::category(panel,category);
            for (size_t item=0;item<categories[category].items.size();++item)
                Check(Label(PanelControl(hwnd,100+static_cast<UINT>(item)))==categories[category].items[item].label,
                    "A category must expose all entries in original order");
            Check(!PanelControl(hwnd,100+static_cast<UINT>(categories[category].items.size())),
                "Category change left stale entries");
        }
        SymbolPanelTestAccess::category(panel,0);
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
              SymbolPanelTestAccess::offset(panel)==0 && calls==0,"Dropdown did not select Emoji safely");
        Check(!PanelControl(hwnd,4) && !PanelControl(hwnd,5),"Paging controls must be removed");
        Check(PanelControl(hwnd,299) && !PanelControl(hwnd,300),"All 200 emoji must exist in one scrollable list");
        Check(SymbolPanelTestAccess::unavailable(panel),"Invalid color render DC must fail safely");
        CheckDrawState(hwnd,100);
        if (argc>1) {
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-page1.bmp",true);
            Scroll(hwnd,SB_BOTTOM);
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-bottom.bmp",true);
            Scroll(hwnd,SB_TOP);
            SymbolPanelTestAccess::palette(panel,RGB(245,245,245),RGB(32,32,32));
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-color-dark.bmp",true);
            SymbolPanelTestAccess::palette(panel,RGB(0,0,0),RGB(255,255,255));
            SymbolPanelTestAccess::contrast(panel,true);
            CheckDrawState(hwnd,100);
            Render(hwnd,std::filesystem::path(argv[1])/L"emoji-high-contrast-fallback.bmp",false,true);
            SymbolPanelTestAccess::contrast(panel,false);
        }
        // All entries exist at once; scrolling reuses HWNDs and does not paginate.
        size_t seen=0;
        for (UINT id=100;PanelControl(hwnd,id);++id) {
            Check(Label(PanelControl(hwnd,id))==emojis.items[seen].label,"Emoji list repeats or loses entries"); ++seen;
        }
        Check(seen==200,"Emoji scroll list omitted entries");
        const HWND firstEmoji=PanelControl(hwnd,100), lastEmoji=PanelControl(hwnd,299);
        SendMessageW(firstEmoji,WM_MOUSEWHEEL,MAKEWPARAM(0,static_cast<WORD>(-WHEEL_DELTA)),0);
        Check(SymbolPanelTestAccess::offset(panel)>0 && GetFocus()==host,"Wheel over an emoji must scroll without moving focus");
        Scroll(hwnd,SB_BOTTOM);
        RECT last{},viewport{}; GetWindowRect(lastEmoji,&last); GetWindowRect(PanelControl(hwnd,10),&viewport);
        Check(last.top>=viewport.top && last.bottom<=viewport.bottom &&
            PanelControl(hwnd,100)==firstEmoji && PanelControl(hwnd,299)==lastEmoji,"Scroll bottom lost items or rebuilt HWNDs");
        Scroll(hwnd,SB_TOP);
        SCROLLBARINFO topBar{sizeof(topBar)};
        Check(GetScrollBarInfo(ScrollControl(hwnd),OBJID_CLIENT,&topBar)!=FALSE,"Cannot read native scrollbar geometry");
        const auto topPixels=Render(ScrollControl(hwnd),(argc>1 ? std::filesystem::path(argv[1]) : profile)/L"scroll-top.bmp");
        Scroll(hwnd,SB_BOTTOM);
        SCROLLBARINFO bottomBar{sizeof(bottomBar)};
        Check(GetScrollBarInfo(ScrollControl(hwnd),OBJID_CLIENT,&bottomBar)!=FALSE &&
            bottomBar.xyThumbTop>topBar.xyThumbTop,"Native scrollbar thumb must follow content scrolling");
        const auto bottomPixels=Render(ScrollControl(hwnd),(argc>1 ? std::filesystem::path(argv[1]) : profile)/L"scroll-bottom.bmp");
        Check(topPixels!=bottomPixels,"Scrollbar painting must visibly move its thumb with content");
        RECT scrollRect{}; GetClientRect(ScrollControl(hwnd),&scrollRect);
        const int width=scrollRect.right,height=scrollRect.bottom,arrow=topBar.dxyLineButton;
        for (const auto& pixels : {topPixels,bottomPixels}) for (int start : {0,height-arrow}) {
            size_t nonBlack=0;
            for (int y=start;y<start+arrow;++y) for (int x=0;x<width;++x) {
                const auto index=(static_cast<size_t>(y)*width+x)*4;
                if (std::max({pixels[index],pixels[index+1],pixels[index+2]})>100) ++nonBlack;
            }
            Check(nonBlack>static_cast<size_t>(width*arrow/4),"Scrollbar arrows must not render as black blocks");
        }
        Scroll(hwnd,SB_TOP);
        ScrollArrow(ScrollControl(hwnd),host,height-5);
        Check(SymbolPanelTestAccess::offset(panel)>0,"Native scrollbar arrow click must scroll content");
        Scroll(hwnd,SB_TOP);
        Scroll(hwnd,SB_PAGEDOWN);
        Check(SymbolPanelTestAccess::offset(panel)>0,"Native scrollbar page request must scroll content");
        SCROLLINFO nativeInfo{sizeof(nativeInfo),SIF_POS};
        Check(GetScrollInfo(ScrollControl(hwnd),SB_CTL,&nativeInfo)!=FALSE &&
            nativeInfo.nPos==SymbolPanelTestAccess::offset(panel),"Native thumb and content offsets differ");
        Scroll(hwnd,SB_TOP);
        RedrawWindow(hwnd,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN);
        const unsigned renders=SymbolPanelTestAccess::renders(panel);
        Check(renders>0,"Emoji cache must have rasterized visible glyphs");
        RedrawWindow(hwnd,nullptr,nullptr,RDW_INVALIDATE|RDW_UPDATENOW|RDW_ALLCHILDREN);
        Check(SymbolPanelTestAccess::renders(panel)==renders,"Warm repaint rerasterized emoji");
        SendMessageW(hwnd,WM_COMMAND,MAKEWPARAM(100,BN_CLICKED),reinterpret_cast<LPARAM>(PanelControl(hwnd,1)));
        Check(calls==0,"Unrelated/stale control command accepted");
        Popup(panel,host,1);
        Check(SymbolPanelTestAccess::offset(panel)==0,"Category selection must reset scroll position");
        Click(hwnd,100);
        Check(calls==1 && chosen==emojis.items[0].text && !panel.visible() && GetFocus()==host,"Emoji click must insert once and close");
        Click(hwnd,100); Check(calls==1,"Stale click ignored");
        {
            SymbolPanel lastPanel; std::wstring lastText;
            Check(lastPanel.show(host,anchor,[&](const std::wstring& text) { lastText=text; }),"Last emoji panel show");
            SymbolPanelTestAccess::category(lastPanel,17);
            const HWND lastWindow=SymbolPanelTestAccess::window(lastPanel);
            Scroll(lastWindow,SB_BOTTOM);
            Click(lastWindow,299);
            Check(lastText==emojis.items.back().text && !lastPanel.visible() && GetFocus()==host,
                "Scroll-bottom selection lost the last emoji or host focus");
        }
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
        Check(!panel.show(nullptr,anchor,[&](const std::wstring&) { ++calls; }) && !panel.visible(),
              "Owner destruction must not allow an unowned symbol popup");
        host=CreateWindowExW(0,L"EDIT",L"",WS_POPUP | WS_VISIBLE,0,0,100,100,nullptr,nullptr,g_module,nullptr);
        SetFocus(host); Check(GetFocus()==host,"Destruction test requires host focus");
        Check(panel.show(host,anchor,[&](const std::wstring&) { ++calls; }),"Reopen with replacement owner");
        Check(panel.visible(),"Recreated owned panel not visible"); panel.hide();
        auto* disposable=new SymbolPanel;
        Check(disposable->show(host,anchor,[&](const std::wstring&) { ++calls; }),"Disposable panel show");
        Popup(*disposable,host,4);
        Check(!popupPanel && calls==2 && GetFocus()==host,"Panel destruction during nested popup was unsafe");
        DestroyWindow(host);
        std::cout<<"Symbol resources, scroll inventory, emoji cache, focus, drag, DPI and cancellation tests passed\n";
        return 0;
    } catch (const std::exception& error) { std::cerr<<error.what()<<'\n'; return 1; }
}

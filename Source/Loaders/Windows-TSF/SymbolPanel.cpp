#include "SymbolPanel.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include <algorithm>
#include <mutex>
#include <windowsx.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wrl/client.h>

namespace KeyKey::WindowsTsf {
namespace {
constexpr wchar_t kClass[] = L"chichi77.KeyKey.TSF.SymbolPanel";
constexpr UINT kCategory = 1, kClose = 3, kPreviousPage = 4, kNextPage = 5, kFirstItem = 100;
constexpr int kTitleHeight = 30, kGap = 6, kToolbarHeight = 34, kCellSize = 34;
std::once_flag registration;
bool registered = false;
struct ScopedDC {
    HDC dc;
    int state;
    explicit ScopedDC(HDC value) : dc(value), state(SaveDC(value)) {}
    ~ScopedDC() { if (state) RestoreDC(dc, state); }
};
// Keep standard BUTTON names/accessibility, but bypass its mouse SetFocus path.
LRESULT CALLBACK PassiveButtonProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    auto original = reinterpret_cast<WNDPROC>(GetWindowLongPtrW(hwnd, GWLP_USERDATA));
    if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg == WM_LBUTTONDOWN) {
        if (!IsWindowEnabled(hwnd)) return 0;
        SetCapture(hwnd); SendMessageW(hwnd, BM_SETSTATE, TRUE, 0); return 0;
    }
    if (msg == WM_LBUTTONUP && GetCapture() == hwnd) {
        ReleaseCapture(); SendMessageW(hwnd, BM_SETSTATE, FALSE, 0);
        RECT rect{}; GetClientRect(hwnd, &rect);
        POINT point{GET_X_LPARAM(lp), GET_Y_LPARAM(lp)};
        if (PtInRect(&rect, point) && IsWindowEnabled(hwnd))
            SendMessageW(GetParent(hwnd), WM_COMMAND,
                MAKEWPARAM(GetDlgCtrlID(hwnd), BN_CLICKED), reinterpret_cast<LPARAM>(hwnd));
        return 0;
    }
    if (msg == WM_CAPTURECHANGED) SendMessageW(hwnd, BM_SETSTATE, FALSE, 0);
    return CallWindowProcW(original, hwnd, msg, wp, lp);
}
bool DarkAppearance() {
    DWORD light = 1, bytes = sizeof(light);
    RegGetValueW(HKEY_CURRENT_USER,
        L"Software\\Microsoft\\Windows\\CurrentVersion\\Themes\\Personalize",
        L"AppsUseLightTheme", RRF_RT_REG_DWORD, nullptr, &light, &bytes);
    HIGHCONTRASTW contrast{sizeof(contrast)};
    SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0);
    return !light && !(contrast.dwFlags & HCF_HIGHCONTRASTON);
}
bool HighContrast() {
    HIGHCONTRASTW contrast{sizeof(contrast)};
    return SystemParametersInfoW(SPI_GETHIGHCONTRAST, sizeof(contrast), &contrast, 0) &&
        (contrast.dwFlags & HCF_HIGHCONTRASTON);
}
}
struct SymbolPanel::ColorEmojiRenderer {
    Microsoft::WRL::ComPtr<ID2D1Factory> factory;
    Microsoft::WRL::ComPtr<IDWriteFactory> writeFactory;
    Microsoft::WRL::ComPtr<IDWriteTextFormat> format;
    Microsoft::WRL::ComPtr<ID2D1DCRenderTarget> target;
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
    bool unavailable = false;
    unsigned recreations = 0;

    void retry() {
        if (unavailable) { brush.Reset(); target.Reset(); }
        unavailable = false;
        recreations = 0;
    }

    bool draw(HDC dc, const RECT& bounds, const std::wstring& text, UINT dpi,
              COLORREF background, COLORREF foreground) {
        if (unavailable || !dc || bounds.right <= bounds.left || bounds.bottom <= bounds.top) return false;
        auto fail = [&] { unavailable = true; return false; };
        if (!factory && FAILED(D2D1CreateFactory(D2D1_FACTORY_TYPE_SINGLE_THREADED,
            __uuidof(ID2D1Factory), nullptr, reinterpret_cast<void**>(factory.GetAddressOf())))) return fail();
        if (!writeFactory && FAILED(DWriteCreateFactory(DWRITE_FACTORY_TYPE_SHARED,
            __uuidof(IDWriteFactory), reinterpret_cast<IUnknown**>(writeFactory.GetAddressOf())))) return fail();
        if (!format) {
            if (FAILED(writeFactory->CreateTextFormat(L"Segoe UI Emoji", nullptr, DWRITE_FONT_WEIGHT_NORMAL,
                DWRITE_FONT_STYLE_NORMAL, DWRITE_FONT_STRETCH_NORMAL, 25.0f, L"zh-TW", &format))) return fail();
            format->SetTextAlignment(DWRITE_TEXT_ALIGNMENT_CENTER);
            format->SetParagraphAlignment(DWRITE_PARAGRAPH_ALIGNMENT_CENTER);
            format->SetWordWrapping(DWRITE_WORD_WRAPPING_NO_WRAP);
        }
        if (!target) {
            const auto properties = D2D1::RenderTargetProperties(D2D1_RENDER_TARGET_TYPE_SOFTWARE,
                D2D1::PixelFormat(DXGI_FORMAT_B8G8R8A8_UNORM, D2D1_ALPHA_MODE_IGNORE));
            if (FAILED(factory->CreateDCRenderTarget(&properties, &target))) return fail();
        }
        if (!brush && FAILED(target->CreateSolidColorBrush(D2D1::ColorF(D2D1::ColorF::Black), &brush))) return fail();
        if (FAILED(target->BindDC(dc, &bounds))) return fail();
        target->SetDpi(static_cast<float>(dpi), static_cast<float>(dpi));
        target->SetTransform(D2D1::Matrix3x2F::Identity());
        target->SetTextAntialiasMode(D2D1_TEXT_ANTIALIAS_MODE_GRAYSCALE);
        auto color = [](COLORREF value) {
            return D2D1::ColorF(GetRValue(value)/255.0f, GetGValue(value)/255.0f, GetBValue(value)/255.0f);
        };
        brush->SetColor(color(foreground));
        // BindDC establishes a local origin. Convert pixels to DIPs exactly once.
        const auto layout = D2D1::RectF(0, 0, (bounds.right-bounds.left)*96.0f/dpi,
                                             (bounds.bottom-bounds.top)*96.0f/dpi);
        target->BeginDraw();
        target->Clear(color(background));
        target->DrawText(text.data(), static_cast<UINT32>(text.size()), format.Get(), layout, brush.Get(),
            static_cast<D2D1_DRAW_TEXT_OPTIONS>(D2D1_DRAW_TEXT_OPTIONS_ENABLE_COLOR_FONT | D2D1_DRAW_TEXT_OPTIONS_CLIP));
        const HRESULT result = target->EndDraw();
        if (result == D2DERR_RECREATE_TARGET) {
            brush.Reset(); target.Reset();
            if (++recreations >= 2) unavailable = true;
            return false;
        }
        if (FAILED(result)) return fail();
        recreations = 0;
        return true;
    }
};

SymbolPanel::SymbolPanel() = default;
bool SymbolPanel::drawColorEmoji(HDC dc, const RECT& bounds, const std::wstring& text,
                                 COLORREF background, COLORREF foreground) {
    if (highContrast_) return false;
    if (!colorEmoji_) colorEmoji_ = std::make_unique<ColorEmojiRenderer>();
    return colorEmoji_->draw(dc, bounds, text, dpi_, background, foreground);
}
SymbolPanel::~SymbolPanel() {
    *alive_ = false;
    hide();
    if (window_) DestroyWindow(window_);
    if (font_) DeleteObject(font_);
    if (symbolFont_) DeleteObject(symbolFont_);
    if (emojiFont_) DeleteObject(emojiFont_);
    if (background_) DeleteObject(background_);
}
int SymbolPanel::scaled(int value) const { return MulDiv(value, dpi_, 96); }
size_t SymbolPanel::pageSize() const { return capacity_; }
void SymbolPanel::updateFonts() {
    auto font = [&](HFONT& target, int size, const wchar_t* face) {
        if (target) DeleteObject(target);
        target = CreateFontW(-scaled(size), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH, face);
    };
    font(font_, 16, L"Segoe UI");
    font(symbolFont_, 22, L"Segoe UI");
    font(emojiFont_, 25, L"Segoe UI Emoji");
}
void SymbolPanel::position(const RECT& desired) {
    MONITORINFO monitor{sizeof(monitor)};
    if (!GetMonitorInfoW(MonitorFromRect(&desired, MONITOR_DEFAULTTONEAREST), &monitor)) return;
    const int width = std::min(static_cast<int>(desired.right-desired.left),
                              static_cast<int>(monitor.rcWork.right-monitor.rcWork.left));
    const int height = std::min(static_cast<int>(desired.bottom-desired.top),
                               static_cast<int>(monitor.rcWork.bottom-monitor.rcWork.top));
    const int x = std::clamp(static_cast<int>(desired.left), static_cast<int>(monitor.rcWork.left),
                             static_cast<int>(monitor.rcWork.right)-width);
    const int y = std::clamp(static_cast<int>(desired.top), static_cast<int>(monitor.rcWork.top),
                             static_cast<int>(monitor.rcWork.bottom)-height);
    SetWindowPos(window_, HWND_TOPMOST, x, y, width, height, SWP_NOACTIVATE);
}
bool SymbolPanel::show(HWND owner, const RECT& anchor, Selection selection) {
    hide();
    if (!selection || BuiltinSymbolCategories().empty()) return false;
    std::call_once(registration, [] {
        WNDCLASSEXW wc{sizeof(wc)};
        wc.hInstance = g_module; wc.lpfnWndProc = WindowProc;
        wc.hCursor = LoadCursorW(nullptr, IDC_ARROW); wc.lpszClassName = kClass;
        registered = RegisterClassExW(&wc) || GetLastError() == ERROR_CLASS_ALREADY_EXISTS;
    });
    if (!registered) return false;
    if (!window_) window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        kClass, L"\x7B26\x865F\x8868", WS_POPUP | WS_BORDER,
        0, 0, 1, 1, owner, nullptr, g_module, this);
    if (!window_) return false;
    SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
    MONITORINFO monitor{sizeof(monitor)};
    RECT reference = anchor;
    if (hasPosition_) reference = {position_.x,position_.y,position_.x+1,position_.y+1};
    if (!GetMonitorInfoW(MonitorFromRect(&reference, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
    const UINT targetDpi = hasPosition_ ? dpi_ :
        owner ? GetDpiForWindow(owner) : GetDpiForWindow(window_);
    dpi_ = targetDpi ? targetDpi : 96;
    updateFonts();
    if (colorEmoji_) colorEmoji_->retry();
    foreground_ = DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
    highContrast_ = HighContrast();
    backgroundColor_ = DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
    if (background_) DeleteObject(background_);
    background_ = CreateSolidBrush(backgroundColor_);
    const int width = std::min(scaled(420), static_cast<int>(monitor.rcWork.right-monitor.rcWork.left));
    const bool list = BuiltinSymbolCategories()[category_].layout == SymbolLayout::List;
    const int height = std::min(scaled(list ? 430 : 310), static_cast<int>(monitor.rcWork.bottom-monitor.rcWork.top));
    const int x = hasPosition_ ? position_.x : monitor.rcWork.right-width-scaled(12);
    const int y = hasPosition_ ? position_.y : monitor.rcWork.bottom-height-scaled(200);
    position({x,y,x+width,y+height});
    page_ = 0; selection_ = std::move(selection);
    rebuild(); ShowWindow(window_, SW_SHOWNOACTIVATE); return true;
}
void SymbolPanel::hide() {
    // A host-suppressed owned popup has a pending ShowOwnedPopups restore;
    // hiding its already hidden HWND does not cancel that restore.
    const bool suppressed = window_ && selection_ && !IsWindowVisible(window_);
    ++generation_; selection_ = {};
    if (menuOpen_) { menuOpen_=false; EndMenu(); }
    dragging_ = false;
    if (window_ && GetCapture() == window_) ReleaseCapture();
    if (window_) {
        if (suppressed) DestroyWindow(window_);
        else ShowWindow(window_, SW_HIDE);
    }
}
void SymbolPanel::page(int delta) {
    const size_t count = BuiltinSymbolCategories()[category_].items.size();
    const size_t pages = std::max<size_t>(1,(count+pageSize()-1)/pageSize());
    if (delta<0 && page_>0) --page_;
    if (delta>0 && page_+1<pages) ++page_;
    rebuild();
}
void SymbolPanel::chooseCategory() {
    HMENU menu = CreatePopupMenu();
    if (!menu) return;
    const auto& categories = BuiltinSymbolCategories();
    for (size_t i=0; i<categories.size(); ++i)
        AppendMenuW(menu, MF_STRING | (i==category_ ? MF_CHECKED : 0),
                    static_cast<UINT_PTR>(i+1), categories[i].name.c_str());
    RECT rect{}; GetWindowRect(GetDlgItem(window_,kCategory), &rect);
    TPMPARAMS params{sizeof(params)}; params.rcExclude = rect;
    const auto generation = generation_; HWND current = window_;
    const auto alive = alive_;
    menuOpen_ = true;
    const UINT selected = TrackPopupMenuEx(menu,TPM_RETURNCMD | TPM_NONOTIFY | TPM_LEFTALIGN,
                                           rect.left,rect.bottom,current,&params);
    DestroyMenu(menu);
    // Deactivation may destroy the entire service during the nested popup loop.
    if (!*alive) return;
    menuOpen_ = false;
    // TrackPopupMenu runs a nested message loop: focus/context may have been cancelled.
    if (current!=window_ || !IsWindow(current) || !visible() || !selection_ ||
        generation!=generation_ || !selected || selected>categories.size()) return;
    category_ = selected-1; page_ = 0;
    RECT panel{}; GetWindowRect(window_,&panel);
    panel.bottom = panel.top+scaled(categories[category_].layout==SymbolLayout::List ? 430 : 310);
    position(panel); rebuild();
}
void SymbolPanel::rebuild() {
    for (HWND control : controls_) DestroyWindow(control);
    controls_.clear();
    RECT rect{}; GetClientRect(window_,&rect);
    const int gap=scaled(kGap), toolbar=scaled(kToolbarHeight), title=scaled(kTitleHeight);
    auto button = [&](UINT id,const std::wstring& label,int x,int y,int w,int h) {
        HWND control=CreateWindowExW(WS_EX_NOACTIVATE,L"BUTTON",label.c_str(),
            WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,x,y,std::max(1,w),std::max(1,h),window_,
            reinterpret_cast<HMENU>(static_cast<UINT_PTR>(id)),g_module,nullptr);
        SendMessageW(control,WM_SETFONT,reinterpret_cast<WPARAM>(font_),FALSE);
        auto original=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(control,GWLP_WNDPROC,
            reinterpret_cast<LONG_PTR>(PassiveButtonProc)));
        SetWindowLongPtrW(control,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(original));
        controls_.push_back(control);
    };
    const auto& category=BuiltinSymbolCategories()[category_];
    button(kClose,L"\x00D7",rect.right-title-gap,gap/2,title,title-gap);
    button(kCategory,category.name+L"  \x25BE",gap,title+gap,rect.right-2*gap,toolbar);
    const int top=title+toolbar+2*gap, footer=rect.bottom-toolbar-gap;
    const int contentHeight=std::max(1,footer-top-gap), contentWidth=std::max(1,static_cast<int>(rect.right)-2*gap);
    const bool list=category.layout==SymbolLayout::List;
    columns_=list ? 1 : std::max<size_t>(1,std::min<size_t>(10,(contentWidth+gap)/(scaled(kCellSize)+gap)));
    const size_t rows=std::max<size_t>(1,std::min<size_t>(list ? 8 : 5,(contentHeight+gap)/(scaled(list ? 32 : kCellSize)+gap)));
    capacity_=columns_*rows;
    const size_t pages=std::max<size_t>(1,(category.items.size()+capacity_-1)/capacity_);
    page_=std::min(page_,pages-1);
    const int cellWidth=(contentWidth-gap*static_cast<int>(columns_-1))/static_cast<int>(columns_);
    const int cellHeight=list ? (contentHeight-gap*static_cast<int>(rows-1))/static_cast<int>(rows) :
        std::min(cellWidth,(contentHeight-gap*static_cast<int>(rows-1))/static_cast<int>(rows));
    for (size_t i=0; i<capacity_ && page_*capacity_+i<category.items.size(); ++i)
        button(kFirstItem+static_cast<UINT>(i),category.items[page_*capacity_+i].label,
            gap+static_cast<int>(i%columns_)*(cellWidth+gap),
            top+static_cast<int>(i/columns_)*(cellHeight+gap),cellWidth,cellHeight);
    const int pageButton=std::min(scaled(72),std::max(1,(contentWidth-scaled(80))/2));
    button(kPreviousPage,L"\x4E0A\x4E00\x9801",gap,footer,pageButton,toolbar);
    button(kNextPage,L"\x4E0B\x4E00\x9801",rect.right-pageButton-gap,footer,pageButton,toolbar);
    EnableWindow(controls_[controls_.size()-2],page_>0);
    EnableWindow(controls_.back(),page_+1<pages);
    InvalidateRect(window_,nullptr,TRUE);
}
LRESULT CALLBACK SymbolPanel::WindowProc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    auto self=reinterpret_cast<SymbolPanel*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    if (msg==WM_NCCREATE) {
        self=static_cast<SymbolPanel*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
        self->window_=hwnd;
        SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));
    }
    return self ? self->message(msg,wp,lp) : DefWindowProcW(hwnd,msg,wp,lp);
}
LRESULT SymbolPanel::message(UINT msg,WPARAM wp,LPARAM lp) {
    switch (msg) {
    case WM_NCDESTROY: {
        HWND destroyed=window_;
        ++generation_; selection_ = {}; dragging_=false; controls_.clear();
        if (menuOpen_) { menuOpen_=false; EndMenu(); }
        window_=nullptr;
        SetWindowLongPtrW(destroyed,GWLP_USERDATA,0);
        return DefWindowProcW(destroyed,msg,wp,lp);
    }
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_CLOSE: hide(); return 0;
    case WM_LBUTTONDOWN:
        if (GET_Y_LPARAM(lp)<scaled(kTitleHeight) && visible()) {
            dragging_=true; GetCursorPos(&dragStart_);
            RECT rect{}; GetWindowRect(window_,&rect);
            dragOrigin_={rect.left,rect.top}; SetCapture(window_);
        }
        return 0;
    case WM_MOUSEMOVE:
        if (dragging_ && GetCapture()==window_) {
            POINT cursor{}; GetCursorPos(&cursor);
            RECT rect{}; GetWindowRect(window_,&rect);
            const int x=dragOrigin_.x+cursor.x-dragStart_.x, y=dragOrigin_.y+cursor.y-dragStart_.y;
            position({x,y,x+rect.right-rect.left,y+rect.bottom-rect.top});
        }
        return 0;
    case WM_LBUTTONUP:
        if (dragging_) {
            dragging_=false; if (GetCapture()==window_) ReleaseCapture();
            RECT rect{}; GetWindowRect(window_,&rect);
            position_={rect.left,rect.top}; hasPosition_=true;
        }
        return 0;
    case WM_CAPTURECHANGED: dragging_=false; return 0;
    case WM_DPICHANGED:
        if (colorEmoji_) colorEmoji_->retry();
        dpi_=HIWORD(wp); updateFonts(); position(*reinterpret_cast<RECT*>(lp));
        if (hasPosition_) { RECT rect{}; GetWindowRect(window_,&rect); position_={rect.left,rect.top}; }
        if (selection_) rebuild();
        return 0;
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
        if (colorEmoji_) colorEmoji_->retry();
        highContrast_ = HighContrast();
        foreground_=DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
        backgroundColor_=DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
        if (background_) DeleteObject(background_);
        background_=CreateSolidBrush(backgroundColor_);
        if (font_) rebuild();
        return 0;
    case WM_KEYDOWN: if (wp==VK_ESCAPE) { hide(); return 0; } break;
    case WM_MOUSEWHEEL: if (visible() && selection_) page(GET_WHEEL_DELTA_WPARAM(wp)>0 ? -1 : 1); return 0;
    case WM_COMMAND: {
        if (!visible() || !selection_ || HIWORD(wp)!=BN_CLICKED) return 0;
        const UINT id=LOWORD(wp); HWND control=reinterpret_cast<HWND>(lp);
        if (!control || control!=GetDlgItem(window_,id) || !IsWindowEnabled(control)) return 0;
        if (id==kClose) hide();
        else if (id==kCategory) chooseCategory();
        else if (id==kPreviousPage || id==kNextPage) page(id==kPreviousPage ? -1 : 1);
        else if (id>=kFirstItem && id<kFirstItem+pageSize()) {
            const size_t index=page_*pageSize()+id-kFirstItem;
            const auto& items=BuiltinSymbolCategories()[category_].items;
            if (index<items.size()) {
                std::wstring text=items[index].text; auto callback=std::move(selection_);
                hide(); callback(text);
            }
        }
        return 0;
    }
    case WM_ERASEBKGND: {
        RECT rect{}; GetClientRect(window_,&rect);
        if (background_) FillRect(reinterpret_cast<HDC>(wp),&rect,background_);
        return 1;
    }
    case WM_PAINT: {
        PAINTSTRUCT ps{}; HDC dc=BeginPaint(window_,&ps);
        const int saved=SaveDC(dc);
        SelectObject(dc,font_); SetBkMode(dc,TRANSPARENT); SetTextColor(dc,foreground_);
        RECT rect{}; GetClientRect(window_,&rect);
        rect.left=scaled(12); rect.right-=scaled(44); rect.top=0; rect.bottom=scaled(kTitleHeight);
        DrawTextW(dc,L"\x7B26\x865F\x8868",-1,&rect,DT_LEFT | DT_VCENTER | DT_SINGLELINE);
        const auto& category=BuiltinSymbolCategories()[category_];
        GetClientRect(window_,&rect);
        rect.left=scaled(86); rect.right-=scaled(86); rect.top=rect.bottom-scaled(kToolbarHeight+kGap);
        const std::wstring label=std::to_wstring(page_+1)+L" / "+
            std::to_wstring(std::max<size_t>(1,(category.items.size()+pageSize()-1)/pageSize()));
        DrawTextW(dc,label.c_str(),-1,&rect,DT_CENTER | DT_VCENTER | DT_SINGLELINE);
        if (saved) RestoreDC(dc,saved);
        EndPaint(window_,&ps); return 0;
    }
    case WM_DRAWITEM: {
        auto draw=reinterpret_cast<DRAWITEMSTRUCT*>(lp);
        if (!draw || draw->CtlType != ODT_BUTTON || GetParent(draw->hwndItem) != window_) break;
        ScopedDC saved(draw->hDC);
        const auto& category=BuiltinSymbolCategories()[category_];
        const bool item=draw->CtlID>=kFirstItem;
        const COLORREF background=draw->itemState & ODS_SELECTED ? GetSysColor(COLOR_HIGHLIGHT) : backgroundColor_;
        const COLORREF foreground=draw->itemState & ODS_DISABLED ? GetSysColor(COLOR_GRAYTEXT) :
            draw->itemState & ODS_SELECTED ? GetSysColor(COLOR_HIGHLIGHTTEXT) : foreground_;
        HBRUSH brush=CreateSolidBrush(background);
        FillRect(draw->hDC,&draw->rcItem,brush); DeleteObject(brush);
        FrameRect(draw->hDC,&draw->rcItem,GetSysColorBrush(COLOR_GRAYTEXT));
        SelectObject(draw->hDC,item && category.layout==SymbolLayout::Grid ?
            (category.emoji ? emojiFont_ : symbolFont_) : font_);
        SetBkMode(draw->hDC,TRANSPARENT);
        SetTextColor(draw->hDC,foreground);
        int length=GetWindowTextLengthW(draw->hwndItem);
        std::wstring label(static_cast<size_t>(length)+1,L'\0');
        GetWindowTextW(draw->hwndItem,label.data(),length+1);
        label.resize(static_cast<size_t>(length));
        RECT text=draw->rcItem; InflateRect(&text,-scaled(4),-scaled(2));
        if (item && category.emoji && drawColorEmoji(draw->hDC,text,label,background,foreground)) return TRUE;
        // A failed D2D draw may have cleared its interior before EndDraw failed.
        brush=CreateSolidBrush(background); FillRect(draw->hDC,&text,brush); DeleteObject(brush);
        DrawTextW(draw->hDC,label.c_str(),length,&text,DT_VCENTER | DT_SINGLELINE | DT_NOPREFIX |
            (item && category.layout==SymbolLayout::List ? DT_LEFT : DT_CENTER));
        return TRUE;
    }
    }
    return DefWindowProcW(window_,msg,wp,lp);
}
} // namespace KeyKey::WindowsTsf

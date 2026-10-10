#include "SymbolPanel.h"
#include "TsfHost.h"
#include "WindowClass.h"
#include <SymbolResources.generated.h>
#include "ModuleState.h"
#include "FrontendSettings.h"
#include "Diagnostics.h"
#include <algorithm>
#include <map>
#include <tuple>
#include <windowsx.h>
#include <d2d1.h>
#include <dwrite.h>
#include <wrl/client.h>
#include <uxtheme.h>

namespace KeyKey::WindowsTsf {
namespace {
constexpr wchar_t kClass[] = L"chichi77.KeyKey.TSF.SymbolPanel";
constexpr wchar_t kContentClass[] = L"chichi77.KeyKey.TSF.SymbolContent";
constexpr UINT kCategory = 1, kClose = 3, kFirstItem = 100;
constexpr int kTitleHeight = 30, kGap = 6, kToolbarHeight = 34, kCellSize = 34;
WindowClass panelClass, contentClass;
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
    if (msg == WM_MOUSEWHEEL) return SendMessageW(GetParent(hwnd), msg, wp, lp);
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
LRESULT CALLBACK PassiveScrollProc(HWND hwnd, UINT msg, WPARAM wp, LPARAM lp) {
    if (msg == WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg == WM_MOUSEWHEEL) return SendMessageW(GetParent(hwnd),msg,wp,lp);
    const auto original=reinterpret_cast<WNDPROC>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    return CallWindowProcW(original,hwnd,msg,wp,lp);
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
    using Key = std::tuple<std::wstring, int, int, UINT, COLORREF, COLORREF>;
    std::map<Key, HBITMAP> cache;
    HDC cacheDC = nullptr;
    Microsoft::WRL::ComPtr<ID2D1Factory> factory;
    Microsoft::WRL::ComPtr<IDWriteFactory> writeFactory;
    Microsoft::WRL::ComPtr<IDWriteTextFormat> format;
    Microsoft::WRL::ComPtr<ID2D1DCRenderTarget> target;
    Microsoft::WRL::ComPtr<ID2D1SolidColorBrush> brush;
    bool unavailable = false;
    unsigned recreations = 0;
    unsigned rasterizations = 0;

    void clearCache() {
        for (const auto& entry : cache) DeleteObject(entry.second);
        cache.clear();
    }
    ~ColorEmojiRenderer() { clearCache(); if (cacheDC) DeleteDC(cacheDC); }

    void retry() {
        if (unavailable) { brush.Reset(); target.Reset(); clearCache(); }
        unavailable = false;
        recreations = 0;
    }

    bool rasterize(HDC dc, const RECT& bounds, const std::wstring& text, UINT dpi,
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

    bool draw(HDC dc, const RECT& bounds, const std::wstring& text, UINT dpi,
              COLORREF background, COLORREF foreground) {
        const int width = bounds.right - bounds.left, height = bounds.bottom - bounds.top;
        if (unavailable || !dc || width <= 0 || height <= 0) return false;
        if (!cacheDC) cacheDC = CreateCompatibleDC(dc);
        if (!cacheDC) return false;
        const Key key{text, width, height, dpi, background, foreground};
        auto found = cache.find(key);
        if (found == cache.end() && cache.size() >= 256) { clearCache(); found = cache.end(); }
        HBITMAP bitmap = found == cache.end() ? nullptr : found->second;
        const bool fresh = !bitmap;
        if (fresh) {
            BITMAPINFO info{}; info.bmiHeader.biSize = sizeof(BITMAPINFOHEADER);
            info.bmiHeader.biWidth = width; info.bmiHeader.biHeight = -height;
            info.bmiHeader.biPlanes = 1; info.bmiHeader.biBitCount = 32;
            info.bmiHeader.biCompression = BI_RGB;
            void* pixels = nullptr;
            bitmap = CreateDIBSection(dc, &info, DIB_RGB_COLORS, &pixels, nullptr, 0);
            if (!bitmap) return false;
        }
        const auto previous = SelectObject(cacheDC, bitmap);
        RECT local{0, 0, width, height};
        const bool rendered = !fresh || rasterize(cacheDC, local, text, dpi, background, foreground);
        const bool copied = rendered && BitBlt(dc, bounds.left, bounds.top, width, height, cacheDC, 0, 0, SRCCOPY);
        SelectObject(cacheDC, previous);
        if (fresh) {
            if (rendered) { cache.emplace(key, bitmap); ++rasterizations; }
            else DeleteObject(bitmap);
        }
        return copied;
    }
};

SymbolPanel::SymbolPanel() = default;
bool SymbolPanel::releaseWindowClasses() {
    const bool contentReleased = contentClass.retire();
    const bool panelReleased = panelClass.retire();
    return contentReleased && panelReleased;
}
bool SymbolPanel::drawColorEmoji(HDC dc, const RECT& bounds, const std::wstring& text,
                                 COLORREF background, COLORREF foreground) {
    if (highContrast_) return false;
    if (!colorEmoji_) colorEmoji_ = std::make_unique<ColorEmojiRenderer>();
    const bool drawn = colorEmoji_->draw(dc, bounds, text, dpi_, background, foreground);
    emojiRasterizations_ = colorEmoji_->rasterizations;
    return drawn;
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
void SymbolPanel::updateFonts() {
    if (fontDpi_ == dpi_ && font_ && symbolFont_ && emojiFont_) return;
    if (colorEmoji_) colorEmoji_->clearCache();
    auto font = [&](HFONT& target, int size, const wchar_t* face) {
        if (target) DeleteObject(target);
        target = CreateFontW(-scaled(size), 0, 0, 0, FW_NORMAL, FALSE, FALSE, FALSE,
            DEFAULT_CHARSET, OUT_DEFAULT_PRECIS, CLIP_DEFAULT_PRECIS, CLEARTYPE_QUALITY,
            DEFAULT_PITCH, face);
    };
    font(font_, 16, L"Segoe UI");
    font(symbolFont_, 22, L"Segoe UI");
    font(emojiFont_, 25, L"Segoe UI Emoji");
    fontDpi_ = dpi_;
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
    if (!IsPopupOwner(owner) || !selection || BuiltinSymbolCategories().empty()) return false;
    WNDCLASSEXW wc{sizeof(wc)};
    wc.hInstance = g_module; wc.lpfnWndProc = WindowProc;
    wc.hCursor = LoadCursorW(nullptr, IDC_ARROW); wc.lpszClassName = kClass;
    if (!panelClass.ensure(wc)) return false;
    wc.lpfnWndProc = ContentProc; wc.lpszClassName = kContentClass;
    if (!contentClass.ensure(wc)) return false;
    if (!window_) window_ = CreateWindowExW(WS_EX_NOACTIVATE | WS_EX_TOOLWINDOW,
        kClass, L"\x7B26\x865F\x8868", WS_POPUP | WS_BORDER | WS_CLIPCHILDREN,
        0, 0, 1, 1, owner, nullptr, g_module, this);
    if (!window_) return false;
    traceState("create");
    SetWindowLongPtrW(window_, GWLP_HWNDPARENT, reinterpret_cast<LONG_PTR>(owner));
    MONITORINFO monitor{sizeof(monitor)};
    RECT reference = anchor;
    if (hasPosition_) reference = {position_.x,position_.y,position_.x+1,position_.y+1};
    if (!GetMonitorInfoW(MonitorFromRect(&reference, MONITOR_DEFAULTTONEAREST), &monitor)) return false;
    const UINT targetDpi = hasPosition_ ? hostDpi_ :
        owner ? GetDpiForWindow(owner) : GetDpiForWindow(window_);
    hostDpi_ = targetDpi ? targetDpi : 96;
    scalePercent_ = LoadFrontendSettings().candidateScalePercent;
    dpi_ = ContentDpiForScale(hostDpi_,MonitorFromRect(&reference,MONITOR_DEFAULTTONEAREST),scalePercent_);
    updateFonts();
    if (colorEmoji_) colorEmoji_->retry();
    foreground_ = DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
    highContrast_ = HighContrast();
    backgroundColor_ = DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
    if (background_) DeleteObject(background_);
    background_ = CreateSolidBrush(backgroundColor_);
    const int width = std::min(scaled(440), static_cast<int>(monitor.rcWork.right-monitor.rcWork.left));
    const bool list = BuiltinSymbolCategories()[category_].layout == SymbolLayout::List;
    const int height = std::min(scaled(list ? 430 : 310), static_cast<int>(monitor.rcWork.bottom-monitor.rcWork.top));
    const int x = hasPosition_ ? position_.x : monitor.rcWork.right-width-scaled(12);
    const int y = hasPosition_ ? position_.y : monitor.rcWork.bottom-height-scaled(200);
    position({x,y,x+width,y+height});
    scrollOffset_ = 0; wheelRemainder_ = 0; selection_ = std::move(selection);
    rebuild(); ShowWindow(window_, SW_SHOWNOACTIVATE); notifyVisibility(true);
    traceState("show"); return true;
}
void SymbolPanel::notifyVisibility(bool visible) {
    if (shown_==visible) return;
    shown_=visible;
    if (window_) NotifyWinEvent(visible ? EVENT_OBJECT_IME_SHOW : EVENT_OBJECT_IME_HIDE,
        window_,OBJID_CLIENT,CHILDID_SELF);
}
void SymbolPanel::hide() {
    if (window_) traceState("hide-begin");
    ++generation_; selection_ = {};
    if (menuOpen_) { menuOpen_=false; EndMenu(); }
    dragging_ = false;
    if (window_ && GetCapture() == window_) ReleaseCapture();
    if (window_) {
        notifyVisibility(false);
        // Cancellation ends this native surface's lifetime, including a
        // normally hidden panel that a host/compositor might restore later.
        // Fonts, emoji bitmaps, category and remembered position remain reusable.
        if (!DestroyWindow(window_)) {
            const DWORD error=GetLastError();
            SetWindowPos(window_,HWND_NOTOPMOST,0,0,0,0,
                SWP_NOACTIVATE|SWP_NOMOVE|SWP_NOSIZE|SWP_HIDEWINDOW);
            Trace("SymbolPanel destroy-failed hwnd=%p error=%lu",window_,error);
        }
    }
}
void SymbolPanel::traceState(const char* event) const {
    if (!DiagnosticsEnabled()) return;
    RECT bounds{}; if (window_) GetWindowRect(window_,&bounds);
    Trace("SymbolPanel %s object=%p hwnd=%p owner=%p foreground=%p logical=%d visible=%d category=%zu controls=%zu generation=%lu rect=(%ld,%ld,%ld,%ld)",
        event,this,window_,window_ ? GetWindow(window_,GW_OWNER) : nullptr,GetForegroundWindow(),
        static_cast<bool>(selection_),window_ && IsWindowVisible(window_),category_,controls_.size(),generation_,
        bounds.left,bounds.top,bounds.right,bounds.bottom);
}
void SymbolPanel::scrollTo(int offset) {
    if (!content_ || !viewport_) return;
    scrollOffset_ = std::clamp(offset, 0, std::max(0, contentHeight_ - viewportHeight_));
    SetWindowPos(content_, nullptr, 0, -scrollOffset_, 0, 0,
        SWP_NOACTIVATE | SWP_NOZORDER | SWP_NOSIZE);
    SCROLLINFO info{sizeof(info), SIF_POS}; info.nPos = scrollOffset_;
    SetScrollInfo(scrollbar_, SB_CTL, &info, TRUE);
}
void SymbolPanel::scrollWheel(int delta) {
    UINT lines = 3; SystemParametersInfoW(SPI_GETWHEELSCROLLLINES, 0, &lines, 0);
    wheelRemainder_ += delta;
    const int steps = wheelRemainder_ / WHEEL_DELTA;
    wheelRemainder_ %= WHEEL_DELTA;
    const int distance = lines == WHEEL_PAGESCROLL ? viewportHeight_ : rowStep_ * static_cast<int>(lines);
    scrollTo(scrollOffset_ - steps * distance);
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
    category_ = selected-1; scrollOffset_ = 0; wheelRemainder_ = 0;
    RECT panel{}; GetWindowRect(window_,&panel);
    panel.bottom = panel.top+scaled(categories[category_].layout==SymbolLayout::List ? 430 : 310);
    position(panel); rebuild();
}
void SymbolPanel::rebuild() {
    RECT rect{}; GetClientRect(window_,&rect);
    const int gap=scaled(kGap), toolbar=scaled(kToolbarHeight), title=scaled(kTitleHeight);
    auto button = [&](HWND parent,UINT id,const std::wstring& label,int x,int y,int w,int h) {
        HWND control=GetDlgItem(parent,id);
        if (!control) {
            control=CreateWindowExW(WS_EX_NOACTIVATE,L"BUTTON",label.c_str(),
                WS_CHILD | WS_VISIBLE | BS_OWNERDRAW,x,y,std::max(1,w),std::max(1,h),parent,
                reinterpret_cast<HMENU>(static_cast<UINT_PTR>(id)),g_module,nullptr);
            if (!control) return;
            auto original=reinterpret_cast<WNDPROC>(SetWindowLongPtrW(control,GWLP_WNDPROC,
                reinterpret_cast<LONG_PTR>(PassiveButtonProc)));
            SetWindowLongPtrW(control,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(original));
            controls_.push_back(control);
        } else {
            SetWindowTextW(control,label.c_str());
            SetWindowPos(control,nullptr,x,y,std::max(1,w),std::max(1,h),SWP_NOACTIVATE|SWP_NOZORDER);
        }
        SendMessageW(control,WM_SETFONT,reinterpret_cast<WPARAM>(font_),FALSE);
    };
    const auto& category=BuiltinSymbolCategories()[category_];
    button(window_,kClose,L"\x00D7",rect.right-title-gap,gap/2,title,title-gap);
    button(window_,kCategory,category.name+L"  \x25BE",gap,title+gap,rect.right-2*gap,toolbar);
    const int top=title+toolbar+2*gap;
    viewportHeight_=std::max(1,static_cast<int>(rect.bottom)-top-gap);
    if (!viewport_) viewport_=CreateWindowExW(WS_EX_NOACTIVATE,kContentClass,L"",
        WS_CHILD|WS_VISIBLE|WS_CLIPCHILDREN,gap,top,std::max(1,static_cast<int>(rect.right)-2*gap),
        viewportHeight_,window_,reinterpret_cast<HMENU>(10),g_module,this);
    if (!viewport_) return;
    SetWindowPos(viewport_,nullptr,gap,top,std::max(1,static_cast<int>(rect.right)-2*gap),
        viewportHeight_,SWP_NOACTIVATE|SWP_NOZORDER);
    if (!content_) content_=CreateWindowExW(WS_EX_NOACTIVATE,kContentClass,L"",
        WS_CHILD|WS_VISIBLE|WS_CLIPCHILDREN,0,0,1,1,viewport_,reinterpret_cast<HMENU>(11),g_module,this);
    if (!content_) return;
    if (!scrollbar_) {
        // A client-area control owns its painting; the host's themed nonclient
        // scrollbar can leave invisible thumbs or black arrow rectangles here.
        scrollbar_=CreateWindowExW(WS_EX_NOACTIVATE,L"SCROLLBAR",L"",WS_CHILD|WS_VISIBLE|SBS_VERT,
            0,0,1,1,viewport_,reinterpret_cast<HMENU>(12),g_module,nullptr);
        if (!scrollbar_) return;
        // Keep a full, visible thumb and arrows even when the host uses thin
        // overlay scrollbars. System colors still follow high-contrast settings.
        SetWindowTheme(scrollbar_,L"",L"");
        const auto original=SetWindowLongPtrW(scrollbar_,GWLP_WNDPROC,reinterpret_cast<LONG_PTR>(PassiveScrollProc));
        SetWindowLongPtrW(scrollbar_,GWLP_USERDATA,original);
    }
    // Keep the scrollbar present even when a small category fits, so columns
    // do not shift when changing categories.
    RECT viewport{}; GetClientRect(viewport_,&viewport);
    const int scrollbarWidth=std::min(static_cast<int>(viewport.right)-1,
        GetSystemMetricsForDpi(SM_CXVSCROLL,hostDpi_));
    const int contentWidth=std::max(1,static_cast<int>(viewport.right)-scrollbarWidth);
    SetWindowPos(scrollbar_,nullptr,contentWidth,0,std::max(1,scrollbarWidth),viewportHeight_,SWP_NOACTIVATE|SWP_NOZORDER);
    const bool list=category.layout==SymbolLayout::List;
    columns_=list ? 1 : std::max<size_t>(1,std::min<size_t>(10,(contentWidth+gap)/(scaled(kCellSize)+gap)));
    const size_t rows=std::max<size_t>(1,(category.items.size()+columns_-1)/columns_);
    const int cellWidth=(contentWidth-gap*static_cast<int>(columns_-1))/static_cast<int>(columns_);
    const int cellHeight=list ? scaled(32) : std::max(1,std::min(cellWidth,scaled(kCellSize)));
    rowStep_=cellHeight+gap;
    contentHeight_=static_cast<int>(rows)*rowStep_-gap;
    if (renderedCategory_!=category_) {
        for (HWND control : controls_) if (GetParent(control)==content_) DestroyWindow(control);
        controls_.erase(std::remove_if(controls_.begin(),controls_.end(),
            [](HWND control){ return !IsWindow(control); }),controls_.end());
        renderedCategory_=category_;
    }
    SetWindowPos(content_,nullptr,0,0,contentWidth,contentHeight_,SWP_NOACTIVATE|SWP_NOZORDER);
    for (size_t i=0; i<category.items.size(); ++i)
        button(content_,kFirstItem+static_cast<UINT>(i),category.items[i].label,
            static_cast<int>(i%columns_)*(cellWidth+gap),
            static_cast<int>(i/columns_)*rowStep_,cellWidth,cellHeight);
    SCROLLINFO info{sizeof(info),SIF_RANGE|SIF_PAGE|SIF_DISABLENOSCROLL};
    info.nMax=std::max(0,contentHeight_-1); info.nPage=viewportHeight_;
    SetScrollInfo(scrollbar_,SB_CTL,&info,TRUE);
    scrollTo(scrollOffset_);
    InvalidateRect(window_,nullptr,TRUE);
}
LRESULT CALLBACK SymbolPanel::ContentProc(HWND hwnd,UINT msg,WPARAM wp,LPARAM lp) {
    auto self=reinterpret_cast<SymbolPanel*>(GetWindowLongPtrW(hwnd,GWLP_USERDATA));
    if (msg==WM_NCCREATE) {
        self=static_cast<SymbolPanel*>(reinterpret_cast<CREATESTRUCTW*>(lp)->lpCreateParams);
        SetWindowLongPtrW(hwnd,GWLP_USERDATA,reinterpret_cast<LONG_PTR>(self));
    }
    if (!self) return DefWindowProcW(hwnd,msg,wp,lp);
    if (msg==WM_MOUSEACTIVATE) return MA_NOACTIVATE;
    if (msg==WM_COMMAND || msg==WM_DRAWITEM) return SendMessageW(self->window_,msg,wp,lp);
    if (msg==WM_MOUSEWHEEL) { if (self->visible() && self->selection_) self->scrollWheel(GET_WHEEL_DELTA_WPARAM(wp)); return 0; }
    if (msg==WM_VSCROLL && hwnd==self->viewport_ && reinterpret_cast<HWND>(lp)==self->scrollbar_ &&
        self->visible() && self->selection_) {
        int offset=self->scrollOffset_;
        switch (LOWORD(wp)) {
        case SB_LINEUP: offset-=self->rowStep_; break;
        case SB_LINEDOWN: offset+=self->rowStep_; break;
        case SB_PAGEUP: offset-=self->viewportHeight_; break;
        case SB_PAGEDOWN: offset+=self->viewportHeight_; break;
        case SB_TOP: offset=0; break;
        case SB_BOTTOM: offset=self->contentHeight_; break;
        case SB_THUMBPOSITION:
        case SB_THUMBTRACK: {
            SCROLLINFO info{sizeof(info),SIF_TRACKPOS}; GetScrollInfo(self->scrollbar_,SB_CTL,&info);
            offset=info.nTrackPos; break;
        }
        default: return 0;
        }
        self->scrollTo(offset); return 0;
    }
    if (msg==WM_ERASEBKGND) {
        RECT rect{}; GetClientRect(hwnd,&rect);
        if (self->background_) FillRect(reinterpret_cast<HDC>(wp),&rect,self->background_);
        return 1;
    }
    if (msg==WM_PAINT) {
        PAINTSTRUCT paint{}; HDC dc=BeginPaint(hwnd,&paint);
        if (self->background_) FillRect(dc,&paint.rcPaint,self->background_);
        EndPaint(hwnd,&paint); return 0;
    }
    return DefWindowProcW(hwnd,msg,wp,lp);
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
        traceState("destroy");
        HWND destroyed=window_;
        notifyVisibility(false);
        ++generation_; selection_ = {}; dragging_=false; controls_.clear();
        viewport_=content_=scrollbar_=nullptr; renderedCategory_=static_cast<size_t>(-1);
        if (menuOpen_) { menuOpen_=false; EndMenu(); }
        window_=nullptr;
        SetWindowLongPtrW(destroyed,GWLP_USERDATA,0);
        return DefWindowProcW(destroyed,msg,wp,lp);
    }
    case WM_MOUSEACTIVATE: return MA_NOACTIVATE;
    case WM_SHOWWINDOW:
        traceState("visibility");
        notifyVisibility(wp!=0 && static_cast<bool>(selection_));
        return DefWindowProcW(window_,msg,wp,lp);
    case WM_WINDOWPOSCHANGED: {
        const auto* pos=reinterpret_cast<const WINDOWPOS*>(lp);
        if (shown_ && !(pos->flags & SWP_HIDEWINDOW) &&
            (!(pos->flags & SWP_NOMOVE) || !(pos->flags & SWP_NOSIZE)))
            NotifyWinEvent(EVENT_OBJECT_IME_CHANGE,window_,OBJID_CLIENT,CHILDID_SELF);
        return DefWindowProcW(window_,msg,wp,lp);
    }
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
        hostDpi_=HIWORD(wp);
        dpi_=ContentDpiForScale(hostDpi_,MonitorFromRect(reinterpret_cast<RECT*>(lp),MONITOR_DEFAULTTONEAREST),scalePercent_);
        updateFonts();
        {
            RECT desired=*reinterpret_cast<RECT*>(lp);
            desired.right=desired.left+scaled(440);
            desired.bottom=desired.top+scaled(BuiltinSymbolCategories()[category_].layout==SymbolLayout::List ? 430 : 310);
            position(desired);
        }
        if (hasPosition_) { RECT rect{}; GetWindowRect(window_,&rect); position_={rect.left,rect.top}; }
        if (selection_) rebuild();
        return 0;
    case WM_SETTINGCHANGE:
    case WM_THEMECHANGED:
        if (colorEmoji_) colorEmoji_->retry();
        if (colorEmoji_) colorEmoji_->clearCache();
        scalePercent_=LoadFrontendSettings().candidateScalePercent;
        {
            RECT rect{}; GetWindowRect(window_,&rect);
            dpi_=ContentDpiForScale(hostDpi_,MonitorFromRect(&rect,MONITOR_DEFAULTTONEAREST),scalePercent_);
            updateFonts();
            rect.right=rect.left+scaled(440);
            rect.bottom=rect.top+scaled(BuiltinSymbolCategories()[category_].layout==SymbolLayout::List ? 430 : 310);
            position(rect);
        }
        highContrast_ = HighContrast();
        foreground_=DarkAppearance() ? RGB(245,245,245) : GetSysColor(COLOR_WINDOWTEXT);
        backgroundColor_=DarkAppearance() ? RGB(32,32,32) : GetSysColor(COLOR_WINDOW);
        if (background_) DeleteObject(background_);
        background_=CreateSolidBrush(backgroundColor_);
        if (font_) rebuild();
        return 0;
    case WM_KEYDOWN: if (wp==VK_ESCAPE) { hide(); return 0; } break;
    case WM_MOUSEWHEEL: if (visible() && selection_) scrollWheel(GET_WHEEL_DELTA_WPARAM(wp)); return 0;
    case WM_COMMAND: {
        if (!visible() || !selection_ || HIWORD(wp)!=BN_CLICKED) return 0;
        const UINT id=LOWORD(wp); HWND control=reinterpret_cast<HWND>(lp);
        const HWND parent=id>=kFirstItem ? content_ : window_;
        if (!control || control!=GetDlgItem(parent,id) || !IsWindowEnabled(control)) return 0;
        if (id==kClose) hide();
        else if (id==kCategory) chooseCategory();
        else if (id>=kFirstItem) {
            const size_t index=id-kFirstItem;
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
        traceState("paint");
        PAINTSTRUCT ps{}; HDC dc=BeginPaint(window_,&ps);
        const int saved=SaveDC(dc);
        SelectObject(dc,font_); SetBkMode(dc,TRANSPARENT); SetTextColor(dc,foreground_);
        RECT rect{}; GetClientRect(window_,&rect);
        rect.left=scaled(12); rect.right-=scaled(44); rect.top=0; rect.bottom=scaled(kTitleHeight);
        DrawTextW(dc,L"\x7B26\x865F\x8868",-1,&rect,DT_LEFT | DT_VCENTER | DT_SINGLELINE);
        if (saved) RestoreDC(dc,saved);
        EndPaint(window_,&ps); return 0;
    }
    case WM_DRAWITEM: {
        auto draw=reinterpret_cast<DRAWITEMSTRUCT*>(lp);
        if (!draw || draw->CtlType != ODT_BUTTON ||
            (GetParent(draw->hwndItem) != window_ && GetParent(draw->hwndItem) != content_)) break;
        ScopedDC saved(draw->hDC);
        const auto& category=BuiltinSymbolCategories()[category_];
        const bool item=draw->CtlID>=kFirstItem;
        if (item) {
            RECT visible{}; GetWindowRect(draw->hwndItem,&visible);
            MapWindowPoints(nullptr,viewport_,reinterpret_cast<POINT*>(&visible),2);
            if (visible.bottom<=0 || visible.top>=viewportHeight_) return TRUE;
        }
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

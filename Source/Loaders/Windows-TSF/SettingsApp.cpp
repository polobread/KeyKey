#include <Windows.h>
#include <CommCtrl.h>

#include <fstream>
#include <iterator>
#include <set>
#include <string>
#include <vector>

#include "FrontendSettings.h"
#include "sqlite3.h"

namespace {

using KeyKey::WindowsTsf::AssociatedPhrasePreferencesPath;
using KeyKey::WindowsTsf::LoaderPreferencesPath;
using KeyKey::WindowsTsf::TraditionalMandarinPreferencesPath;

constexpr wchar_t kWindowClass[] = L"KeyKeySettingsWindow";
constexpr wchar_t kWindowTitle[] = L"琦琦輸入法 — 設定";
constexpr int kTabId = 100;
constexpr int kSaveId = IDOK;
constexpr int kCloseId = IDCANCEL;
constexpr int kGeneralKeyboardLayoutId = 201;
constexpr int kGeneralResetKeyboardId = 202;
constexpr int kGeneralVerticalId = 203;
constexpr int kGeneralHorizontalId = 204;
constexpr int kGeneralHighlightId = 205;
constexpr int kGeneralControlBackslashId = 206;
constexpr int kGeneralBeepId = 207;
constexpr int kGeneralCandidateScaleId = 208;
constexpr int kPhoneticKeyboardLayoutId = 301;
constexpr int kPhoneticRareCharactersId = 302;
constexpr int kPhraseListId = 401;
constexpr int kPhraseSelectAllId = 402;
constexpr int kPhraseBaseOnlyId = 403;

struct Collection {
    std::wstring source;
    std::wstring display;
};

struct WindowState {
    HWND tab = nullptr;
    HWND phraseList = nullptr;
    HWND status = nullptr;
    std::vector<HWND> generalControls;
    std::vector<HWND> phoneticControls;
    std::vector<HWND> phraseControls;
};

std::wstring Utf8ToWide(const std::string& text) {
    if (text.empty()) return {};
    const int length = MultiByteToWideChar(
        CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
        static_cast<int>(text.size()), nullptr, 0);
    if (length <= 0) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text.data(),
                        static_cast<int>(text.size()), result.data(), length);
    return result;
}

std::string WideToUtf8(const std::wstring& text) {
    if (text.empty()) return {};
    const int length = WideCharToMultiByte(
        CP_UTF8, 0, text.data(), static_cast<int>(text.size()), nullptr, 0,
        nullptr, nullptr);
    if (length <= 0) return {};
    std::string result(static_cast<size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(),
                        static_cast<int>(text.size()), result.data(), length,
                        nullptr, nullptr);
    return result;
}

std::string ReadFile(const std::wstring& path) {
    std::ifstream input(path, std::ios::binary);
    if (!input) return {};
    return std::string(std::istreambuf_iterator<char>(input),
                       std::istreambuf_iterator<char>());
}

std::string EmptyPlist() {
    return "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n"
           "<!DOCTYPE plist PUBLIC \"-//Apple//DTD PLIST 1.0//EN\" "
           "\"http://www.apple.com/DTDs/PropertyList-1.0.dtd\">\r\n"
           "<plist version=\"1.0\">\r\n<dict>\r\n</dict>\r\n</plist>\r\n";
}

std::string PlistString(const std::string& xml, const std::string& key,
                        const std::string& defaultValue) {
    const std::string keyTag = "<key>" + key + "</key>";
    size_t position = xml.find(keyTag);
    if (position == std::string::npos) return defaultValue;
    position = xml.find("<string>", position + keyTag.size());
    if (position == std::string::npos) return defaultValue;
    position += 8;
    const size_t end = xml.find("</string>", position);
    return end == std::string::npos ? defaultValue
                                    : xml.substr(position, end - position);
}

bool PlistBool(const std::string& xml, const std::string& key,
               bool defaultValue) {
    const std::string value =
        PlistString(xml, key, defaultValue ? "true" : "false");
    return value == "true" || value == "1" || value == "YES";
}

void SetPlistString(std::string& xml, const std::string& key,
                    const std::string& value) {
    if (xml.empty()) xml = EmptyPlist();
    const std::string keyTag = "<key>" + key + "</key>";
    const size_t keyPosition = xml.find(keyTag);
    if (keyPosition != std::string::npos) {
        const size_t stringTag = xml.find("<string>", keyPosition + keyTag.size());
        if (stringTag != std::string::npos) {
            const size_t valueStart = stringTag + 8;
            const size_t valueEnd = xml.find("</string>", valueStart);
            if (valueEnd != std::string::npos) {
                xml.replace(valueStart, valueEnd - valueStart, value);
                return;
            }
        }
    }
    const size_t dictionaryEnd = xml.rfind("</dict>");
    if (dictionaryEnd == std::string::npos) {
        xml = EmptyPlist();
        SetPlistString(xml, key, value);
        return;
    }
    const std::string entry = "\t<key>" + key + "</key>\r\n\t<string>" +
                              value + "</string>\r\n";
    xml.insert(dictionaryEnd, entry);
}

bool WriteFile(const std::wstring& path, const std::string& contents) {
    if (path.empty()) return false;
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) return false;
    output.write(contents.data(), static_cast<std::streamsize>(contents.size()));
    output.close();
    return output.good();
}

std::wstring ExecutableDirectory() {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(
        nullptr, path.data(), static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    const size_t separator = path.find_last_of(L"\\/");
    return separator == std::wstring::npos ? std::wstring()
                                           : path.substr(0, separator);
}

std::vector<Collection> LoadCollections() {
    std::vector<Collection> collections;
    const std::wstring databasePath =
        ExecutableDirectory() + L"\\Databases\\KeyKey.db";
    sqlite3* database = nullptr;
    if (sqlite3_open16(databasePath.c_str(), &database) != SQLITE_OK) {
        if (database) sqlite3_close(database);
        return collections;
    }
    sqlite3_stmt* statement = nullptr;
    if (sqlite3_prepare_v2(database,
                          "SELECT source, display FROM collection_names "
                          "ORDER BY sortorder, display",
                          -1, &statement, nullptr) == SQLITE_OK) {
        while (sqlite3_step(statement) == SQLITE_ROW) {
            const char* source = reinterpret_cast<const char*>(
                sqlite3_column_text(statement, 0));
            const char* display = reinterpret_cast<const char*>(
                sqlite3_column_text(statement, 1));
            collections.push_back(
                {Utf8ToWide(source ? source : ""),
                 Utf8ToWide(display ? display : "")});
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
    return collections;
}

std::set<std::wstring> LoadEnabledCollections() {
    const std::string xml = ReadFile(AssociatedPhrasePreferencesPath());
    if (xml.empty()) return {L"McBopomofo"};
    const std::wstring value = Utf8ToWide(
        PlistString(xml, "EnabledCollections", "McBopomofo"));
    std::set<std::wstring> enabled;
    size_t start = 0;
    while (start <= value.size()) {
        const size_t comma = value.find(L',', start);
        std::wstring name = value.substr(start, comma - start);
        const size_t first = name.find_first_not_of(L" \t\r\n");
        const size_t last = name.find_last_not_of(L" \t\r\n");
        if (first != std::wstring::npos) {
            enabled.insert(name.substr(first, last - first + 1));
        }
        if (comma == std::wstring::npos) break;
        start = comma + 1;
    }
    return enabled;
}

bool SaveEnabledCollections(HWND list) {
    std::wstring joined;
    const int count = ListView_GetItemCount(list);
    for (int index = 0; index < count; ++index) {
        if (!ListView_GetCheckState(list, index)) continue;
        wchar_t source[256]{};
        ListView_GetItemText(list, index, 1, source, ARRAYSIZE(source));
        if (!joined.empty()) joined += L',';
        joined += source;
    }
    std::string xml = ReadFile(AssociatedPhrasePreferencesPath());
    SetPlistString(xml, "EnabledCollections", WideToUtf8(joined));
    return WriteFile(AssociatedPhrasePreferencesPath(), xml);
}

void SetControlFont(HWND control) {
    SendMessageW(control, WM_SETFONT,
                 reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)),
                 TRUE);
}

HWND AddControl(HWND window, std::vector<HWND>& page, DWORD extendedStyle,
                const wchar_t* className, const wchar_t* text, DWORD style,
                int x, int y, int width, int height, int id = 0) {
    HWND control = CreateWindowExW(
        extendedStyle, className, text, WS_CHILD | WS_VISIBLE | style, x, y,
        width, height, window,
        id ? reinterpret_cast<HMENU>(static_cast<INT_PTR>(id)) : nullptr,
        nullptr, nullptr);
    SetControlFont(control);
    page.push_back(control);
    return control;
}

void AddComboValues(HWND combo, const std::vector<std::wstring>& values,
                    int selectedIndex) {
    for (const std::wstring& value : values) {
        SendMessageW(combo, CB_ADDSTRING, 0,
                     reinterpret_cast<LPARAM>(value.c_str()));
    }
    SendMessageW(combo, CB_SETCURSEL, selectedIndex, 0);
}

void CreateGeneralPage(HWND window, WindowState* state) {
    auto& page = state->generalControls;
    AddControl(window, page, 0, L"BUTTON", L"鍵盤類型對應", BS_GROUPBOX,
               26, 54, 650, 84);
    AddControl(window, page, 0, L"STATIC",
               L"Windows TSF 依實體按鍵位置輸入注音：", 0, 42, 82, 250,
               22);
    HWND keyboard = AddControl(window, page, 0, WC_COMBOBOXW, L"",
                               CBS_DROPDOWNLIST | WS_VSCROLL, 292, 78, 250,
                               200, kGeneralKeyboardLayoutId);
    SendMessageW(keyboard, CB_ADDSTRING, 0,
                 reinterpret_cast<LPARAM>(L"美式鍵盤（固定）"));
    SendMessageW(keyboard, CB_SETCURSEL, 0, 0);
    EnableWindow(keyboard, FALSE);
    HWND reset = AddControl(window, page, 0, L"BUTTON", L"重設",
                            BS_PUSHBUTTON, 552, 77, 90, 26,
                            kGeneralResetKeyboardId);
    EnableWindow(reset, FALSE);

    AddControl(window, page, 0, L"BUTTON", L"輸入法模組管理", BS_GROUPBOX,
               26, 146, 650, 82);
    HWND module = AddControl(window, page, 0, L"BUTTON", L"傳統注音",
                             BS_AUTOCHECKBOX, 44, 174, 180, 24);
    SendMessageW(module, BM_SETCHECK, BST_CHECKED, 0);
    EnableWindow(module, FALSE);
    AddControl(window, page, 0, L"STATIC",
               L"Windows 版固定啟用傳統注音；本版不包含倉頡與簡易。", 0,
               238, 176, 400, 24);

    AddControl(window, page, 0, L"BUTTON", L"選字窗", BS_GROUPBOX, 26,
               236, 650, 150);
    AddControl(window, page, 0, L"STATIC", L"樣式：", 0, 44, 266, 64, 22);
    AddControl(window, page, 0, L"BUTTON", L"垂直選字窗",
               BS_AUTORADIOBUTTON | WS_GROUP, 112, 263, 125, 24,
               kGeneralVerticalId);
    AddControl(window, page, 0, L"BUTTON", L"水平選字窗",
               BS_AUTORADIOBUTTON, 246, 263, 125, 24,
               kGeneralHorizontalId);
    AddControl(window, page, 0, L"STATIC", L"比例：", 0, 44, 307, 64, 22);
    HWND candidateScale = AddControl(
        window, page, 0, WC_COMBOBOXW, L"",
        CBS_DROPDOWNLIST | WS_VSCROLL, 112, 303, 220, 240,
        kGeneralCandidateScaleId);
    AddControl(window, page, 0, L"STATIC", L"可獨立於顯示器縮放調整大小", 0,
               344, 307, 260, 22);
    AddControl(window, page, 0, L"STATIC", L"配色：", 0, 44, 347, 64, 22);
    HWND highlight = AddControl(window, page, 0, WC_COMBOBOXW, L"",
                                CBS_DROPDOWNLIST | WS_VSCROLL, 112, 343, 200,
                                180, kGeneralHighlightId);

    AddControl(window, page, 0, L"BUTTON", L"快捷鍵與提示聲", BS_GROUPBOX,
               26, 394, 650, 124);
    AddControl(window, page, 0, L"BUTTON",
               L"使用 Ctrl + \\ 切換中英文模式", BS_AUTOCHECKBOX, 44,
               420, 280, 24, kGeneralControlBackslashId);
    AddControl(window, page, 0, L"BUTTON", L"輸入錯誤時發出提示聲",
               BS_AUTOCHECKBOX, 44, 450, 280, 24, kGeneralBeepId);
    AddControl(window, page, 0, L"STATIC",
               L"固定快捷鍵：單按 Shift 或 Ctrl+Space 切換中英文；"
               L"Shift+Space 切換全半形。",
               0, 44, 482, 590, 24);

    const std::string xml = ReadFile(LoaderPreferencesPath());
    const bool horizontal =
        PlistString(xml, "OneDimensionalCandidatePanelStyle", "vertical") ==
        "horizontal";
    SendMessageW(GetDlgItem(window, horizontal ? kGeneralHorizontalId
                                               : kGeneralVerticalId),
                 BM_SETCHECK, BST_CHECKED, 0);
    const std::string color = PlistString(xml, "HighlightColor", "Default");
    const int colorIndex = color == "Green"    ? 1
                           : color == "Yellow" ? 2
                           : color == "Red"    ? 3
                                                 : 0;
    AddComboValues(highlight,
                   {L"紫色", L"綠色", L"黃色", L"紅色"}, colorIndex);
    const std::string scale =
        PlistString(xml, "CandidateWindowScalePercent", "system");
    const char* scaleValues[] = {"system", "75",  "90",  "100", "125", "150",
                                 "175",    "200", "225", "250", "300", "350"};
    int scaleIndex = 0;
    for (int index = 1; index < 12; ++index) {
        if (scale == scaleValues[index]) {
            scaleIndex = index;
            break;
        }
    }
    AddComboValues(candidateScale,
                   {L"跟隨 Windows（預設）", L"75%", L"90%", L"100%",
                    L"125%", L"150%", L"175%", L"200%", L"225%",
                    L"250%", L"300%", L"350%"},
                   scaleIndex);
    SendMessageW(GetDlgItem(window, kGeneralControlBackslashId), BM_SETCHECK,
                 PlistBool(xml, "ToggleInputMethodWithControlBackslash", true)
                     ? BST_CHECKED
                     : BST_UNCHECKED,
                 0);
    SendMessageW(GetDlgItem(window, kGeneralBeepId), BM_SETCHECK,
                 PlistBool(xml, "ShouldPlaySoundOnTypingError", true)
                     ? BST_CHECKED
                     : BST_UNCHECKED,
                 0);
}

void CreatePhoneticPage(HWND window, WindowState* state) {
    auto& page = state->phoneticControls;
    AddControl(window, page, 0, L"BUTTON", L"傳統注音輸入法", BS_GROUPBOX,
               26, 54, 650, 190);
    AddControl(window, page, 0, L"STATIC", L"鍵盤配置：", 0, 48, 90, 100,
               22);
    HWND layout = AddControl(window, page, 0, WC_COMBOBOXW, L"",
                             CBS_DROPDOWNLIST | WS_VSCROLL, 154, 85, 220, 180,
                             kPhoneticKeyboardLayoutId);
    AddControl(window, page, 0, L"BUTTON", L"使用全字庫罕用字（CNS11643）",
               BS_AUTOCHECKBOX, 48, 132, 300, 24,
               kPhoneticRareCharactersId);
    AddControl(window, page, 0, L"STATIC",
               L"關閉時僅顯示 Big-5 可表示的候選字；變更會在下一次按鍵時生效。",
               0, 48, 170, 580, 42);
    AddControl(window, page, 0, L"STATIC",
               L"注音選字鍵固定為 1–9；空白、Enter、方向鍵、Page Up／"
               L"Page Down 與 Esc 的行為和 macOS 傳統注音一致。",
               0, 34, 274, 620, 48);

    const std::string xml = ReadFile(TraditionalMandarinPreferencesPath());
    const std::string current = PlistString(xml, "KeyboardLayout", "Standard");
    const int selection = current == "ETen"           ? 1
                          : current == "ETen26"       ? 2
                          : current == "Hsu"          ? 3
                          : current == "Hanyu Pinyin" ? 4
                                                        : 0;
    AddComboValues(layout,
                   {L"標準", L"倚天", L"倚天 26 鍵", L"許氏鍵盤",
                    L"漢語拼音"},
                   selection);
    const bool useRare =
        PlistString(xml, "UseCharactersSupportedByEncoding", "BIG-5").empty();
    SendMessageW(GetDlgItem(window, kPhoneticRareCharactersId), BM_SETCHECK,
                 useRare ? BST_CHECKED : BST_UNCHECKED, 0);
}

void CreatePhrasePage(HWND window, WindowState* state) {
    auto& page = state->phraseControls;
    AddControl(window, page, 0, L"STATIC",
               L"選擇要啟用的關聯詞詞庫。變更會在下一次輸入時立即生效。",
               0, 28, 58, 620, 24);
    state->phraseList = AddControl(
        window, page, WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
        LVS_REPORT | LVS_SHOWSELALWAYS, 28, 88, 646, 400, kPhraseListId);
    ListView_SetExtendedListViewStyle(
        state->phraseList, LVS_EX_CHECKBOXES | LVS_EX_FULLROWSELECT |
                               LVS_EX_DOUBLEBUFFER);
    LVCOLUMNW column{};
    column.mask = LVCF_TEXT | LVCF_WIDTH;
    column.pszText = const_cast<wchar_t*>(L"詞庫");
    column.cx = 300;
    ListView_InsertColumn(state->phraseList, 0, &column);
    column.pszText = const_cast<wchar_t*>(L"識別碼");
    column.cx = 300;
    ListView_InsertColumn(state->phraseList, 1, &column);

    const std::set<std::wstring> enabled = LoadEnabledCollections();
    const std::vector<Collection> collections = LoadCollections();
    int row = 0;
    for (const Collection& collection : collections) {
        LVITEMW item{};
        item.mask = LVIF_TEXT;
        item.iItem = row;
        item.pszText = const_cast<wchar_t*>(collection.display.c_str());
        ListView_InsertItem(state->phraseList, &item);
        ListView_SetItemText(
            state->phraseList, row, 1,
            const_cast<wchar_t*>(collection.source.c_str()));
        ListView_SetCheckState(state->phraseList, row,
                               enabled.count(collection.source) != 0);
        ++row;
    }
    AddControl(window, page, 0, L"BUTTON", L"全部啟用", BS_PUSHBUTTON, 28,
               502, 100, 28, kPhraseSelectAllId);
    AddControl(window, page, 0, L"BUTTON", L"僅基本詞庫", BS_PUSHBUTTON,
               138, 502, 110, 28, kPhraseBaseOnlyId);
    if (collections.empty()) {
        SetWindowTextW(state->status, L"找不到 Databases\\KeyKey.db");
    }
}

void ShowSelectedPage(WindowState* state) {
    if (!state || !state->tab) return;
    const int selected = TabCtrl_GetCurSel(state->tab);
    const std::vector<HWND>* pages[] = {&state->generalControls,
                                        &state->phoneticControls,
                                        &state->phraseControls};
    for (int page = 0; page < 3; ++page) {
        for (HWND control : *pages[page]) {
            ShowWindow(control, page == selected ? SW_SHOW : SW_HIDE);
        }
    }
}

bool SaveSettings(HWND window, WindowState* state) {
    std::string general = ReadFile(LoaderPreferencesPath());
    SetPlistString(
        general, "OneDimensionalCandidatePanelStyle",
        SendMessageW(GetDlgItem(window, kGeneralHorizontalId), BM_GETCHECK, 0,
                     0) == BST_CHECKED
            ? "horizontal"
            : "vertical");
    const int colorIndex = static_cast<int>(SendMessageW(
        GetDlgItem(window, kGeneralHighlightId), CB_GETCURSEL, 0, 0));
    const char* colors[] = {"Default", "Green", "Yellow", "Red"};
    SetPlistString(general, "HighlightColor",
                   colors[colorIndex >= 0 && colorIndex < 4 ? colorIndex : 0]);
    const int scaleIndex = static_cast<int>(SendMessageW(
        GetDlgItem(window, kGeneralCandidateScaleId), CB_GETCURSEL, 0, 0));
    const char* scaleValues[] = {"system", "75",  "90",  "100", "125", "150",
                                 "175",    "200", "225", "250", "300", "350"};
    SetPlistString(
        general, "CandidateWindowScalePercent",
        scaleValues[scaleIndex >= 0 && scaleIndex < 12 ? scaleIndex : 0]);
    SetPlistString(
        general, "ToggleInputMethodWithControlBackslash",
        SendMessageW(GetDlgItem(window, kGeneralControlBackslashId),
                     BM_GETCHECK, 0, 0) == BST_CHECKED
            ? "true"
            : "false");
    SetPlistString(general, "ShouldPlaySoundOnTypingError",
                   SendMessageW(GetDlgItem(window, kGeneralBeepId),
                                BM_GETCHECK, 0, 0) == BST_CHECKED
                       ? "true"
                       : "false");

    std::string phonetic = ReadFile(TraditionalMandarinPreferencesPath());
    const int layoutIndex = static_cast<int>(SendMessageW(
        GetDlgItem(window, kPhoneticKeyboardLayoutId), CB_GETCURSEL, 0, 0));
    const char* layouts[] = {"Standard", "ETen", "ETen26", "Hsu",
                             "Hanyu Pinyin"};
    SetPlistString(
        phonetic, "KeyboardLayout",
        layouts[layoutIndex >= 0 && layoutIndex < 5 ? layoutIndex : 0]);
    SetPlistString(
        phonetic, "UseCharactersSupportedByEncoding",
        SendMessageW(GetDlgItem(window, kPhoneticRareCharactersId),
                     BM_GETCHECK, 0, 0) == BST_CHECKED
            ? ""
            : "BIG-5");

    const bool saved = WriteFile(LoaderPreferencesPath(), general) &&
                       WriteFile(TraditionalMandarinPreferencesPath(),
                                 phonetic) &&
                       SaveEnabledCollections(state->phraseList);
    if (saved) {
        SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                            reinterpret_cast<LPARAM>(L"chichi77 KeyKey"),
                            SMTO_ABORTIFHUNG, 250, nullptr);
    }
    return saved;
}

void Layout(HWND window, WindowState* state) {
    if (!state) return;
    RECT client{};
    GetClientRect(window, &client);
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    MoveWindow(state->tab, 12, 12, width - 24, height - 78, TRUE);
    MoveWindow(state->status, 22, height - 52, width - 240, 28, TRUE);
    MoveWindow(GetDlgItem(window, kSaveId), width - 206, height - 54, 86, 30,
               TRUE);
    MoveWindow(GetDlgItem(window, kCloseId), width - 110, height - 54, 86, 30,
               TRUE);
}

LRESULT CALLBACK WindowProcedure(HWND window, UINT message, WPARAM wparam,
                                 LPARAM lparam) {
    auto* state = reinterpret_cast<WindowState*>(
        GetWindowLongPtrW(window, GWLP_USERDATA));
    switch (message) {
        case WM_CREATE: {
            state = new WindowState();
            SetWindowLongPtrW(window, GWLP_USERDATA,
                              reinterpret_cast<LONG_PTR>(state));
            state->tab = CreateWindowExW(
                0, WC_TABCONTROLW, L"", WS_CHILD | WS_VISIBLE | WS_CLIPSIBLINGS,
                0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kTabId)), nullptr,
                nullptr);
            SetControlFont(state->tab);
            const wchar_t* tabs[] = {L"一般", L"注音", L"關聯詞庫"};
            for (int index = 0; index < 3; ++index) {
                TCITEMW item{};
                item.mask = TCIF_TEXT;
                item.pszText = const_cast<wchar_t*>(tabs[index]);
                TabCtrl_InsertItem(state->tab, index, &item);
            }

            state->status = CreateWindowExW(0, L"STATIC", L"",
                                             WS_CHILD | WS_VISIBLE | SS_LEFT,
                                             0, 0, 0, 0, window, nullptr,
                                             nullptr, nullptr);
            HWND save = CreateWindowExW(
                0, L"BUTTON", L"套用", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kSaveId)), nullptr,
                nullptr);
            HWND close = CreateWindowExW(
                0, L"BUTTON", L"關閉", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(static_cast<INT_PTR>(kCloseId)), nullptr,
                nullptr);
            SetControlFont(state->status);
            SetControlFont(save);
            SetControlFont(close);

            CreateGeneralPage(window, state);
            CreatePhoneticPage(window, state);
            CreatePhrasePage(window, state);
            TabCtrl_SetCurSel(state->tab, 0);
            ShowSelectedPage(state);
            Layout(window, state);
            return 0;
        }
        case WM_SIZE:
            Layout(window, state);
            return 0;
        case WM_NOTIFY:
            if (state && reinterpret_cast<NMHDR*>(lparam)->idFrom == kTabId &&
                reinterpret_cast<NMHDR*>(lparam)->code == TCN_SELCHANGE) {
                ShowSelectedPage(state);
                return 0;
            }
            break;
        case WM_COMMAND: {
            const int id = LOWORD(wparam);
            if (id == kPhraseSelectAllId && state) {
                const int count = ListView_GetItemCount(state->phraseList);
                for (int row = 0; row < count; ++row) {
                    ListView_SetCheckState(state->phraseList, row, TRUE);
                }
                return 0;
            }
            if (id == kPhraseBaseOnlyId && state) {
                const int count = ListView_GetItemCount(state->phraseList);
                for (int row = 0; row < count; ++row) {
                    wchar_t source[256]{};
                    ListView_GetItemText(state->phraseList, row, 1, source,
                                         ARRAYSIZE(source));
                    ListView_SetCheckState(
                        state->phraseList, row,
                        wcscmp(source, L"McBopomofo") == 0);
                }
                return 0;
            }
            if (id == kSaveId && state) {
                SetWindowTextW(state->status,
                               SaveSettings(window, state) ? L"設定已套用"
                                                           : L"設定儲存失敗");
                return 0;
            }
            if (id == kCloseId) {
                DestroyWindow(window);
                return 0;
            }
            break;
        }
        case WM_DESTROY:
            delete state;
            SetWindowLongPtrW(window, GWLP_USERDATA, 0);
            PostQuitMessage(0);
            return 0;
    }
    return DefWindowProcW(window, message, wparam, lparam);
}

}  // namespace

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE, PWSTR, int show) {
    INITCOMMONCONTROLSEX controls{sizeof(controls),
                                  ICC_LISTVIEW_CLASSES | ICC_TAB_CLASSES};
    InitCommonControlsEx(&controls);

    WNDCLASSEXW windowClass{sizeof(windowClass)};
    windowClass.style = CS_HREDRAW | CS_VREDRAW;
    windowClass.lpfnWndProc = WindowProcedure;
    windowClass.hInstance = instance;
    windowClass.hIcon = LoadIconW(instance, MAKEINTRESOURCEW(101));
    windowClass.hIconSm = windowClass.hIcon;
    windowClass.hCursor = LoadCursorW(nullptr, IDC_ARROW);
    windowClass.hbrBackground = reinterpret_cast<HBRUSH>(COLOR_WINDOW + 1);
    windowClass.lpszClassName = kWindowClass;
    if (!RegisterClassExW(&windowClass) &&
        GetLastError() != ERROR_CLASS_ALREADY_EXISTS) {
        return 1;
    }

    HWND window = CreateWindowExW(
        0, kWindowClass, kWindowTitle,
        WS_OVERLAPPEDWINDOW & ~(WS_MAXIMIZEBOX | WS_THICKFRAME), CW_USEDEFAULT,
        CW_USEDEFAULT, 720, 680, nullptr, nullptr, instance, nullptr);
    if (!window) return 1;
    ShowWindow(window, show);
    UpdateWindow(window);

    MSG message{};
    while (GetMessageW(&message, nullptr, 0, 0) > 0) {
        TranslateMessage(&message);
        DispatchMessageW(&message);
    }
    return static_cast<int>(message.wParam);
}

#include <Windows.h>
#include <CommCtrl.h>
#include <ShlObj.h>
#include <shellapi.h>

#include <fstream>
#include <set>
#include <string>
#include <vector>

#include "sqlite3.h"

namespace {

constexpr wchar_t kWindowClass[] = L"KeyKeySettingsWindow";
constexpr wchar_t kWindowTitle[] = L"琦琦輸入法 — 詞庫設定";
constexpr int kListId = 100;
constexpr int kSelectAllId = 101;
constexpr int kBaseOnlyId = 102;
constexpr int kSaveId = IDOK;
constexpr int kCancelId = IDCANCEL;

struct Collection {
    std::wstring source;
    std::wstring display;
};

struct WindowState {
    HWND list = nullptr;
    HWND status = nullptr;
};

std::wstring Utf8ToWide(const char* text) {
    if (!text || !*text) return {};
    const int length = MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text,
                                            -1, nullptr, 0);
    if (length <= 1) return {};
    std::wstring result(static_cast<size_t>(length), L'\0');
    MultiByteToWideChar(CP_UTF8, MB_ERR_INVALID_CHARS, text, -1, result.data(),
                        length);
    result.resize(static_cast<size_t>(length - 1));
    return result;
}

std::string WideToUtf8(const std::wstring& text) {
    if (text.empty()) return {};
    const int length = WideCharToMultiByte(CP_UTF8, 0, text.data(),
                                            static_cast<int>(text.size()), nullptr,
                                            0, nullptr, nullptr);
    std::string result(static_cast<size_t>(length), '\0');
    WideCharToMultiByte(CP_UTF8, 0, text.data(), static_cast<int>(text.size()),
                        result.data(), length, nullptr, nullptr);
    return result;
}

std::wstring ExecutableDirectory() {
    std::wstring path(32768, L'\0');
    const DWORD length = GetModuleFileNameW(nullptr, path.data(),
                                            static_cast<DWORD>(path.size()));
    if (!length || length >= path.size()) return {};
    path.resize(length);
    const size_t separator = path.find_last_of(L"\\/");
    return separator == std::wstring::npos ? std::wstring()
                                           : path.substr(0, separator);
}

std::wstring PreferencesPath() {
    wchar_t roaming[MAX_PATH]{};
    if (FAILED(SHGetFolderPathW(nullptr, CSIDL_APPDATA | CSIDL_FLAG_CREATE,
                                nullptr, SHGFP_TYPE_CURRENT, roaming))) {
        return {};
    }
    std::wstring directory = std::wstring(roaming) + L"\\chichi77 KeyKey";
    CreateDirectoryW(directory.c_str(), nullptr);
    return directory +
           L"\\org.openvanilla.chichi77-keykey.windows.AssociatedPhrase.plist";
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
            collections.push_back({Utf8ToWide(source), Utf8ToWide(display)});
        }
    }
    if (statement) sqlite3_finalize(statement);
    sqlite3_close(database);
    return collections;
}

std::set<std::wstring> LoadEnabledCollections() {
    const std::wstring path = PreferencesPath();
    std::ifstream input(path, std::ios::binary);
    if (!input) return {L"McBopomofo"};
    const std::string xml((std::istreambuf_iterator<char>(input)),
                          std::istreambuf_iterator<char>());
    const std::string key = "<key>EnabledCollections</key>";
    size_t position = xml.find(key);
    if (position == std::string::npos) return {L"McBopomofo"};
    position = xml.find("<string>", position + key.size());
    if (position == std::string::npos) return {};
    position += 8;
    const size_t end = xml.find("</string>", position);
    if (end == std::string::npos) return {};

    std::set<std::wstring> enabled;
    const std::wstring value = Utf8ToWide(xml.substr(position, end - position).c_str());
    size_t start = 0;
    while (start <= value.size()) {
        const size_t comma = value.find(L',', start);
        std::wstring name = value.substr(start, comma - start);
        const size_t first = name.find_first_not_of(L" \t\r\n");
        const size_t last = name.find_last_not_of(L" \t\r\n");
        if (first != std::wstring::npos) enabled.insert(name.substr(first, last - first + 1));
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

    const std::wstring path = PreferencesPath();
    if (path.empty()) return false;
    std::ofstream output(path, std::ios::binary | std::ios::trunc);
    if (!output) return false;
    const std::string value = WideToUtf8(joined);
    output << "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\r\n"
              "<plist version=\"1.0\">\r\n"
              "<dict>\r\n"
              "\t<key>EnabledCollections</key>\r\n"
              "\t<string>"
           << value
           << "</string>\r\n"
              "</dict>\r\n"
              "</plist>\r\n";
    output.close();
    SendMessageTimeoutW(HWND_BROADCAST, WM_SETTINGCHANGE, 0,
                        reinterpret_cast<LPARAM>(L"chichi77 KeyKey"),
                        SMTO_ABORTIFHUNG, 250, nullptr);
    return output.good();
}

void SetControlFont(HWND control) {
    SendMessageW(control, WM_SETFONT,
                 reinterpret_cast<WPARAM>(GetStockObject(DEFAULT_GUI_FONT)), TRUE);
}

void Layout(HWND window, WindowState* state) {
    if (!state) return;
    RECT client{};
    GetClientRect(window, &client);
    const int width = client.right - client.left;
    const int height = client.bottom - client.top;
    MoveWindow(GetDlgItem(window, 10), 16, 14, width - 32, 42, TRUE);
    MoveWindow(state->list, 16, 60, width - 32, height - 138, TRUE);
    MoveWindow(GetDlgItem(window, kSelectAllId), 16, height - 66, 84, 28, TRUE);
    MoveWindow(GetDlgItem(window, kBaseOnlyId), 108, height - 66, 92, 28, TRUE);
    MoveWindow(state->status, 212, height - 66, width - 408, 28, TRUE);
    MoveWindow(GetDlgItem(window, kSaveId), width - 184, height - 66, 76, 28, TRUE);
    MoveWindow(GetDlgItem(window, kCancelId), width - 100, height - 66, 76, 28, TRUE);
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
            HWND explanation = CreateWindowExW(
                0, L"STATIC",
                L"選擇要啟用的關聯詞詞庫。變更會在下一次輸入時立即生效。",
                WS_CHILD | WS_VISIBLE, 0, 0, 0, 0, window,
                reinterpret_cast<HMENU>(10), nullptr, nullptr);
            state->list = CreateWindowExW(
                WS_EX_CLIENTEDGE, WC_LISTVIEWW, L"",
                WS_CHILD | WS_VISIBLE | LVS_REPORT | LVS_SHOWSELALWAYS,
                0, 0, 0, 0, window, reinterpret_cast<HMENU>(kListId), nullptr,
                nullptr);
            ListView_SetExtendedListViewStyle(
                state->list, LVS_EX_CHECKBOXES | LVS_EX_FULLROWSELECT |
                                 LVS_EX_DOUBLEBUFFER);
            LVCOLUMNW column{};
            column.mask = LVCF_TEXT | LVCF_WIDTH;
            column.pszText = const_cast<wchar_t*>(L"詞庫");
            column.cx = 245;
            ListView_InsertColumn(state->list, 0, &column);
            column.pszText = const_cast<wchar_t*>(L"識別碼");
            column.cx = 245;
            ListView_InsertColumn(state->list, 1, &column);

            const std::set<std::wstring> enabled = LoadEnabledCollections();
            const std::vector<Collection> collections = LoadCollections();
            int row = 0;
            for (const Collection& collection : collections) {
                LVITEMW item{};
                item.mask = LVIF_TEXT;
                item.iItem = row;
                item.pszText = const_cast<wchar_t*>(collection.display.c_str());
                ListView_InsertItem(state->list, &item);
                ListView_SetItemText(state->list, row, 1,
                                     const_cast<wchar_t*>(collection.source.c_str()));
                ListView_SetCheckState(state->list, row,
                                       enabled.count(collection.source) != 0);
                ++row;
            }

            HWND selectAll = CreateWindowExW(
                0, L"BUTTON", L"全部啟用", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0, window, reinterpret_cast<HMENU>(kSelectAllId),
                nullptr, nullptr);
            HWND baseOnly = CreateWindowExW(
                0, L"BUTTON", L"僅基本詞庫", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0, window, reinterpret_cast<HMENU>(kBaseOnlyId),
                nullptr, nullptr);
            state->status = CreateWindowExW(0, L"STATIC", L"",
                                             WS_CHILD | WS_VISIBLE | SS_CENTER,
                                             0, 0, 0, 0, window, nullptr, nullptr,
                                             nullptr);
            HWND save = CreateWindowExW(
                0, L"BUTTON", L"儲存", WS_CHILD | WS_VISIBLE | BS_DEFPUSHBUTTON,
                0, 0, 0, 0, window, reinterpret_cast<HMENU>(kSaveId), nullptr,
                nullptr);
            HWND cancel = CreateWindowExW(
                0, L"BUTTON", L"關閉", WS_CHILD | WS_VISIBLE | BS_PUSHBUTTON,
                0, 0, 0, 0, window, reinterpret_cast<HMENU>(kCancelId), nullptr,
                nullptr);
            for (HWND control : {explanation, state->list, selectAll, baseOnly,
                                 state->status, save, cancel}) {
                SetControlFont(control);
            }
            if (collections.empty()) {
                SetWindowTextW(state->status, L"找不到 Databases\\KeyKey.db");
                EnableWindow(save, FALSE);
            }
            Layout(window, state);
            return 0;
        }
        case WM_SIZE:
            Layout(window, state);
            return 0;
        case WM_COMMAND: {
            const int id = LOWORD(wparam);
            if (id == kSelectAllId && state) {
                const int count = ListView_GetItemCount(state->list);
                for (int row = 0; row < count; ++row)
                    ListView_SetCheckState(state->list, row, TRUE);
                return 0;
            }
            if (id == kBaseOnlyId && state) {
                const int count = ListView_GetItemCount(state->list);
                for (int row = 0; row < count; ++row) {
                    wchar_t source[256]{};
                    ListView_GetItemText(state->list, row, 1, source,
                                         ARRAYSIZE(source));
                    ListView_SetCheckState(state->list, row,
                                           wcscmp(source, L"McBopomofo") == 0);
                }
                return 0;
            }
            if (id == kSaveId && state) {
                SetWindowTextW(state->status,
                               SaveEnabledCollections(state->list)
                                   ? L"已儲存"
                                   : L"儲存失敗");
                return 0;
            }
            if (id == kCancelId) {
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
    INITCOMMONCONTROLSEX controls{sizeof(controls), ICC_LISTVIEW_CLASSES};
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
    if (!RegisterClassExW(&windowClass) && GetLastError() != ERROR_CLASS_ALREADY_EXISTS)
        return 1;

    HWND window = CreateWindowExW(
        0, kWindowClass, kWindowTitle,
        WS_OVERLAPPEDWINDOW & ~(WS_MAXIMIZEBOX | WS_THICKFRAME),
        CW_USEDEFAULT, CW_USEDEFAULT, 650, 620, nullptr, nullptr, instance,
        nullptr);
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

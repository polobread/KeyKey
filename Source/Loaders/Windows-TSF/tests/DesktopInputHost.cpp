// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#include "TextService.h"
#include "FrontendSettings.h"
#include "GuanyinmaJson.h"
#include "DesktopTextStore.h"
#include <functional>
#include <filesystem>
#include <fstream>
#include <iostream>
#include <map>
#include <set>

using Microsoft::WRL::ComPtr;
using namespace KeyKey::WindowsTsf;
using namespace KeyKey::WindowsTsf::Guanyinma;
namespace KeyKey::WindowsTsf {
HMODULE g_module = nullptr;
std::atomic<long> g_objectCount{0}, g_serverLocks{0};
// Only construction and observation use the existing test friend. All keys
// enter through the production ITfKeyEventSink and all edits use native TSF.
struct TextServiceTestAccess {
    static void start(TextService& s, ITfThreadMgr* manager, TfClientId client, const std::string& method) {
        s.threadManager_ = manager; s.clientId_ = client;
        s.effectiveInputMethod_ = s.lastLocalInputMethod_ = method;
        s.effectiveSettingsSignature_ = EngineSettingsSignature(method);
        s.engine_ = KeyKeyEngineSession::CreateControlled(method);
        if (!s.engine_ || !s.engine_->ready()) throw std::runtime_error("Windows adapter session failed");
        s.chineseMode_ = true; s.fullWidthMode_ = false;
        s.outputSettingsInitialized_ = true; s.simplifiedOutput_ = s.lastLocalSimplifiedOutput_ = false;
        // Do not connect process-global preference channels, register/activate
        // an installed TIP, or create visible windows in this test host.
    }
    static ITfComposition* composition(TextService& s, ITfContext* context) {
        return s.compositionContext_.Get() == context ? s.composition_.Get() : nullptr;
    }
    static bool candidates(TextService& s) { return s.candidateActive_; }
    static Array rows(TextService& s) {
        Array rows;
        for (const auto& candidate : s.layoutCandidates_) {
            Json row; Set(row, L"key", winrt::to_string(candidate.selectionKey));
            Set(row, L"text", winrt::to_string(candidate.text)); rows.Append(row);
        }
        return rows;
    }
};
}
namespace {
void Require(bool value, const char* message) { if (!value) throw std::runtime_error(message); }
void Success(HRESULT hr, const char* message) {
    if (FAILED(hr)) throw std::runtime_error(std::string(message) + " HRESULT=" + std::to_string(static_cast<unsigned long>(hr)));
}
std::string Read(const std::filesystem::path& path) {
    std::ifstream stream(path, std::ios::binary);
    Require(bool(stream), "Read request");
    return {std::istreambuf_iterator<char>(stream), {}};
}
void Write(const std::filesystem::path& path, Json const& object) {
    std::ofstream stream(path, std::ios::binary);
    stream << winrt::to_string(object.Stringify()) << '\n';
    Require(bool(stream), "Write evidence");
}
class Edit final : public ITfEditSession {
public:
    std::function<HRESULT(TfEditCookie)> action;
    explicit Edit(std::function<HRESULT(TfEditCookie)> fn) : action(std::move(fn)) {}
    STDMETHODIMP QueryInterface(REFIID iid, void** out) override {
        if (!out) return E_POINTER; *out = nullptr;
        if (iid != IID_IUnknown && iid != IID_ITfEditSession) return E_NOINTERFACE;
        *out = static_cast<ITfEditSession*>(this); AddRef(); return S_OK;
    }
    STDMETHODIMP_(ULONG) AddRef() override { return ++refs_; }
    STDMETHODIMP_(ULONG) Release() override { auto n = --refs_; if (!n) delete this; return n; }
    STDMETHODIMP DoEditSession(TfEditCookie cookie) override { return action(cookie); }
private: ULONG refs_ = 1;
};
struct Document {
    ComPtr<DesktopTextStore> store;
    ComPtr<ITfDocumentMgr> manager;
    ComPtr<ITfContext> context;
    Document(ITfThreadMgr* thread, TfClientId client) {
        store.Attach(new DesktopTextStore);
        Success(thread->CreateDocumentMgr(&manager), "Create real document manager");
        TfEditCookie cookie;
        Success(manager->CreateContext(client, 0, store.Get(), &context, &cookie), "Create real ACP context");
        Success(manager->Push(context.Get()), "Push real context");
    }
    ~Document() { if (manager) manager->Pop(TF_POPF_ALL); }
};
struct ManagerCleanup {
    ITfThreadMgrEx* manager;
    ~ManagerCleanup() { if (manager) manager->Deactivate(); }
};
struct ServiceCleanup {
    TextService* service;
    ~ServiceCleanup() { if (service) service->Deactivate(); }
};
void Pump() {
    MSG message{};
    while (PeekMessageW(&message, nullptr, 0, 0, PM_REMOVE)) {
        TranslateMessage(&message); DispatchMessageW(&message);
    }
}
int Scalars(const std::wstring& text) {
    int n = 0;
    for (size_t i = 0; i < text.size(); ++i, ++n)
        if (text[i] >= 0xd800 && text[i] <= 0xdbff && i + 1 < text.size() && text[i + 1] >= 0xdc00 && text[i + 1] <= 0xdfff) ++i;
    return n;
}
Json Snapshot(Document& document, TextService& service, TfClientId client) {
    Json result;
    ComPtr<Edit> edit;
    edit.Attach(new Edit([&](TfEditCookie) {
        std::wstring committed = document.store->text, preedit;
        LONG start = 0, count = 0;
        if (auto* composition = TextServiceTestAccess::composition(service, document.context.Get())) {
            ComPtr<ITfRange> range; ComPtr<ITfRangeACP> acp;
            Success(composition->GetRange(&range), "Composition range");
            Success(range.As(&acp), "Native ACP range");
            Success(acp->GetExtent(&start, &count), "Composition extent");
            preedit = committed.substr(start, count); committed.erase(start, count);
        }
        Set(result, L"text", winrt::to_string(committed));
        Set(result, L"preedit", winrt::to_string(preedit));
        Set(result, L"caret", Scalars(document.store->text.substr(start, std::max<LONG>(0, document.store->selection.acpEnd - start))));
        Set(result, L"selection_start_utf16", static_cast<int>(document.store->selection.acpStart));
        Set(result, L"selection_end_utf16", static_cast<int>(document.store->selection.acpEnd));
        Set(result, L"composition_start_utf16", static_cast<int>(start));
        Set(result, L"composition_length_utf16", static_cast<int>(count));
        Set(result, L"candidates_open", TextServiceTestAccess::candidates(service));
        result.SetNamedValue(L"candidates", TextServiceTestAccess::rows(service));
        Set(result, L"chinese", service.isChineseMode()); Set(result, L"full_width", service.isFullWidthMode());
        Set(result, L"locks", static_cast<int>(document.store->locks)); Set(result, L"writes", static_cast<int>(document.store->writes));
        return S_OK;
    }));
    HRESULT edited = E_FAIL;
    Success(document.context->RequestEditSession(client, edit.Get(), TF_ES_SYNC | TF_ES_READ, &edited), "Snapshot request");
    Success(edited, "Snapshot edit session");
    return result;
}
struct Keyboard {
    BYTE original[256]{}, state[256]{};
    HKL originalLayout = nullptr, layout = nullptr;
    Keyboard() {
        Require(GetKeyboardState(original), "Save thread keyboard state");
        originalLayout = GetKeyboardLayout(0);
        layout = LoadKeyboardLayoutW(L"00000409", KLF_NOTELLSHELL);
        Require(layout != nullptr && ActivateKeyboardLayout(layout, 0) != nullptr, "Thread-local US keyboard layout");
        Require(SetKeyboardState(state), "Initialize thread-local key state");
    }
    ~Keyboard() { SetKeyboardState(original); if (originalLayout) ActivateKeyboardLayout(originalLayout, 0); }
    UINT prepare(std::string token) {
        const bool caps = (state[VK_CAPITAL] & 1) != 0;
        std::fill(std::begin(state), std::end(state), BYTE(0)); state[VK_CAPITAL] = caps ? 1 : 0;
        while (token.find('+') != std::string::npos) {
            auto pos = token.find('+'); auto modifier = token.substr(0, pos); token.erase(0, pos + 1);
            if (modifier == "shift") state[VK_SHIFT] = state[VK_LSHIFT] = 0x80;
            else if (modifier == "ctrl") state[VK_CONTROL] = state[VK_LCONTROL] = 0x80;
            else throw std::runtime_error("Unknown modifier: " + modifier);
        }
        static const std::map<std::string, UINT> names{
            {"Return", VK_RETURN}, {"space", VK_SPACE}, {"Escape", VK_ESCAPE}, {"BackSpace", VK_BACK},
            {"Left", VK_LEFT}, {"Right", VK_RIGHT}, {"Up", VK_UP}, {"Down", VK_DOWN},
            {"Home", VK_HOME}, {"End", VK_END}, {"Next", VK_NEXT}, {"Prior", VK_PRIOR},
            {"Page_Down", VK_NEXT}, {"Page_Up", VK_PRIOR}, {"Caps_Lock", VK_CAPITAL},
            {"backslash", VK_OEM_5}, {"grave", VK_OEM_3}};
        UINT vk;
        if (auto found = names.find(token); found != names.end()) vk = found->second;
        else {
            wchar_t ch = token == "question" ? L'?' : token == "asterisk" ? L'*' : token.size() == 1 ? token[0] : 0;
            Require(ch != 0, ("Unknown key: " + token).c_str());
            const auto translated = VkKeyScanExW(ch, layout);
            Require(translated != -1, "US virtual key mapping");
            vk = LOBYTE(translated);
            if (HIBYTE(translated) & 1) state[VK_SHIFT] = state[VK_LSHIFT] = 0x80;
        }
        if (vk == VK_CAPITAL) state[vk] ^= 1;
        state[vk] |= 0x80;
        Require(SetKeyboardState(state), "Set thread-local key state");
        return vk;
    }
    void release(UINT vk) {
        state[vk] &= 1; state[VK_SHIFT] = state[VK_LSHIFT] = state[VK_CONTROL] = state[VK_LCONTROL] = 0;
        Require(SetKeyboardState(state), "Release thread-local keys");
    }
};
void Send(Document& document, TextService& service, Keyboard& keyboard, TfClientId client,
          const std::string& token, Array const& trace, bool control) {
    Json event; Set(event, L"key", token); Set(event, L"tick_ms", static_cast<int>(GetTickCount64() & 0x7fffffff));
    trace.Append(event);
    auto vk = keyboard.prepare(token);
    Set(event, L"virtual_key", static_cast<int>(vk));
    Set(event, L"shift", (keyboard.state[VK_SHIFT] & 0x80) != 0);
    Set(event, L"control", (keyboard.state[VK_CONTROL] & 0x80) != 0);
    Set(event, L"caps_lock", (keyboard.state[VK_CAPITAL] & 1) != 0);
    const auto scan = MapVirtualKeyExW(vk, MAPVK_VK_TO_VSC, keyboard.layout);
    BOOL tested = FALSE, eaten = FALSE;
    if (!control) {
        Success(service.OnTestKeyDown(document.context.Get(), vk, 1 | (scan << 16), &tested), "OnTestKeyDown");
        if (tested) Success(service.OnKeyDown(document.context.Get(), vk, 1 | (scan << 16), &eaten), "OnKeyDown");
    }
    if (!eaten && !(keyboard.state[VK_CONTROL] & 0x80) && vk != VK_CAPITAL) {
        wchar_t text[8]{};
        const auto n = ToUnicodeEx(vk, scan, keyboard.state, text, 8, 4, keyboard.layout);
        if (n > 0 && text[0] >= L' ') document.store->insert(std::wstring(text, n));
        else if (vk != VK_RETURN && vk != VK_ESCAPE && vk != VK_CAPITAL)
            throw std::runtime_error("Unimplemented uneaten host editing key: " + token);
    }
    keyboard.release(vk);
    BOOL up = FALSE;
    if (!control) {
        Success(service.OnTestKeyUp(document.context.Get(), vk, (scan << 16) | (1ull << 31), &up), "OnTestKeyUp");
        if (up) Success(service.OnKeyUp(document.context.Get(), vk, (scan << 16) | (1ull << 31), &up), "OnKeyUp");
    }
    Set(event, L"tested", tested != FALSE); Set(event, L"eaten", eaten != FALSE);
    Pump(); event.SetNamedValue(L"actual", Snapshot(document, service, client));
}
void SelectCandidate(Document& document, TextService& service, Keyboard& keyboard, TfClientId client,
                     const std::string& target, const std::string& referenceKey, Array const& trace) {
    std::set<std::wstring> pages;
    for (;;) {
        const auto snapshot = Snapshot(document, service, client);
        const auto rows = snapshot.GetNamedArray(L"candidates");
        Json resolution; Set(resolution, L"action", "resolve_candidate"); Set(resolution, L"target", target);
        Set(resolution, L"reference_key", referenceKey); resolution.SetNamedValue(L"actual", snapshot);
        trace.Append(resolution);
        Require(snapshot.GetNamedBoolean(L"candidates_open") && rows.Size(), "Target candidate list is closed or empty");
        for (auto value : rows) {
            const auto row = value.GetObject();
            if (String(row, L"text") == target) {
                const auto key = String(row, L"key");
                Require(key.size() == 1, "Target selection label must be a printable key");
                Set(resolution, L"resolved_key", key);
                Send(document, service, keyboard, client, key, trace, false);
                return;
            }
        }
        Require(pages.insert(std::wstring(rows.Stringify())).second, "Target candidate absent after a complete page cycle");
        Send(document, service, keyboard, client, "Next", trace, false);
    }
}
}
int wmain(int argc, wchar_t** argv) {
    if (argc != 3) return 2;
    Apartment apartment;
    Json report; Array trace, checkpoints;
    int status = 0;
    try {
        g_module = GetModuleHandleW(nullptr);
        Require(GetEnvironmentVariableW(L"KEYKEY_TSF_TEST_PROFILE_DIR", nullptr, 0) > 1, "Missing isolated test profile");
        const auto request = Json::Parse(winrt::to_hstring(Read(argv[1])));
        const auto method = String(request, L"method");
        ComPtr<ITfThreadMgrEx> manager;
        Success(CoCreateInstance(CLSID_TF_ThreadMgr, nullptr, CLSCTX_INPROC_SERVER, IID_PPV_ARGS(&manager)), "Create Windows TSF manager");
        TfClientId client;
        Success(manager->ActivateEx(&client, TF_TMAE_NOACTIVATETIP | TF_TMAE_NOACTIVATEKEYBOARDLAYOUT), "Activate isolated TSF manager");
        ManagerCleanup managerCleanup{manager.Get()};
        {
            Document document(manager.Get(), client);
            Success(manager->SetFocus(document.manager.Get()), "Set test document focus");
            ComPtr<TextService> service; service.Attach(new TextService);
            ServiceCleanup serviceCleanup{service.Get()};
            TextServiceTestAccess::start(*service.Get(), manager.Get(), client, method);
            Keyboard keyboard;
            Set(report, L"input_source", "thread-local SetKeyboardState; production ITfKeyEventSink callbacks");
            Set(report, L"host", "Windows native TSF context / test-owned ITextStoreACP");
            Set(report, L"ignore_caps_lock_in_chinese", LoadFrontendSettings().ignoreCapsLockInChinese);
            const auto table = LoadTablePreviewSettings(false);
            Json tableSettings; Set(tableSettings, L"table.realtime", table.composeWhileTyping);
            Set(tableSettings, L"table.prefix", table.prefixCandidates); Set(tableSettings, L"table.clear_on_error", table.clearOnError);
            report.SetNamedValue(L"native_table_settings", tableSettings);
            const bool control = request.GetNamedBoolean(L"control", false);
            if (request.GetNamedString(L"scenario", L"") == L"focus") {
                // Separate real TSF documents within this worker. This does not
                // claim the fixture's cross-application foreground evidence.
                for (char c : std::string("su3cl3")) Send(document, *service.Get(), keyboard, client, std::string(1, c), trace, false);
                checkpoints.Append(Snapshot(document, *service.Get(), client));
                Document other(manager.Get(), client);
                Success(manager->SetFocus(other.manager.Get()), "Focus second test document");
                Success(service->OnSetFocus(other.manager.Get(), document.manager.Get()), "TSF document focus callback");
                checkpoints.Append(Snapshot(document, *service.Get(), client));
                for (auto key : {"s", "u", "3", "Return"}) Send(other, *service.Get(), keyboard, client, key, trace, false);
                checkpoints.Append(Snapshot(other, *service.Get(), client));
                Success(manager->SetFocus(document.manager.Get()), "Restore first document");
                Success(service->OnSetFocus(document.manager.Get(), other.manager.Get()), "TSF focus return callback");
                checkpoints.Append(Snapshot(document, *service.Get(), client));
            } else {
                for (auto value : request.GetNamedArray(L"steps")) {
                    auto step = value.GetObject();
                    const auto targets = step.GetNamedObject(L"candidate_targets", Json{});
                    unsigned index = 0;
                    for (auto key : step.GetNamedArray(L"keys")) {
                        const auto name = winrt::to_hstring(std::to_string(index++));
                        const auto referenceKey = winrt::to_string(key.GetString());
                        if (targets.HasKey(name))
                            SelectCandidate(document, *service.Get(), keyboard, client,
                                            winrt::to_string(targets.GetNamedString(name)), referenceKey, trace);
                        else Send(document, *service.Get(), keyboard, client, referenceKey, trace, control);
                    }
                    checkpoints.Append(Snapshot(document, *service.Get(), client));
                }
            }
            Success(service->Deactivate(), "Release service");
            serviceCleanup.service = nullptr;
            service.Reset();
            Success(manager->SetFocus(nullptr), "Release document focus");
        }
        Success(manager->Deactivate(), "Deactivate isolated TSF manager");
        managerCleanup.manager = nullptr;
        manager.Reset();
        Require(ShutdownEngineRuntime(), "Release Windows engine runtime");
        Set(report, L"status", "completed");
    } catch (const winrt::hresult_error& e) {
        Set(report, L"error", winrt::to_string(e.message())); status = 1;
    } catch (const std::exception& e) {
        Set(report, L"error", e.what()); status = 1;
    }
    report.SetNamedValue(L"automation", trace); report.SetNamedValue(L"checkpoints", checkpoints);
    Write(argv[2], report);
    return status;
}

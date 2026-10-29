// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
// The native PV sandwich owns associated-phrase UI, keys and output filters.
#include "GuanyinmaWindowsAdapter.h"
#include "GuanyinmaJson.h"
#include "FrontendSettings.h"
#include "SharedFileAccess.h"
#include "PlainVanilla.h"
#include "OVAFAssociatedPhrase.h"
#include <dwrite_2.h>
#include <wrl.h>
#include <algorithm>
#include <map>
#include <set>
#include <memory>
#include <utility>

namespace KeyKey::WindowsTsf {
namespace {
using namespace OpenVanilla;
using namespace Guanyinma;
using Microsoft::WRL::ComPtr;

struct Preferences {
    std::unique_ptr<PVPlistValue> root;
    explicit Preferences(const std::string& method) {
        std::string xml;
        const auto path = SettingsDirectory() + L"\\com.polobread.chichi77-keykey.windows." +
            OVUTF16::FromUTF8(method) + L".plist";
        ReadSharedSettingsFile(path, xml);
        root.reset(PVPropertyList::ParsePlistFromString(xml.c_str()));
        if (!root || root->type() != PVPlistValue::Dictionary) root.reset(new PVPlistValue(PVPlistValue::Dictionary));
    }
    std::string text(const char* key, const char* fallback = "") const {
        auto* value = root->valueForKey(key);
        return value && value->type() == PVPlistValue::String ? value->stringValue() : fallback;
    }
    bool boolean(const char* key, bool fallback) const {
        const auto value = text(key, fallback ? "true" : "false");
        return value == "true" || value == "1" || value == "YES";
    }
};

// Map using the same Windows font family as the candidate window, including
// system fallback and supplementary-plane characters. No HWND or desktop UI.
class TextSource final : public Microsoft::WRL::RuntimeClass<
    Microsoft::WRL::RuntimeClassFlags<Microsoft::WRL::ClassicCom>, IDWriteTextAnalysisSource> {
public:
    explicit TextSource(std::wstring text) : text_(std::move(text)) {}
    HRESULT STDMETHODCALLTYPE GetTextAtPosition(UINT32 pos, const WCHAR** text, UINT32* length) override {
        *text = pos < text_.size() ? text_.data() + pos : nullptr;
        *length = pos < text_.size() ? static_cast<UINT32>(text_.size() - pos) : 0; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetTextBeforePosition(UINT32 pos, const WCHAR** text, UINT32* length) override {
        if (pos > text_.size()) return E_INVALIDARG;
        *text = pos ? text_.data() : nullptr; *length = pos; return S_OK;
    }
    DWRITE_READING_DIRECTION STDMETHODCALLTYPE GetParagraphReadingDirection() override { return DWRITE_READING_DIRECTION_LEFT_TO_RIGHT; }
    HRESULT STDMETHODCALLTYPE GetLocaleName(UINT32 pos, UINT32* length, const WCHAR** locale) override {
        *length = pos < text_.size() ? static_cast<UINT32>(text_.size() - pos) : 0; *locale = L"zh-TW"; return S_OK;
    }
    HRESULT STDMETHODCALLTYPE GetNumberSubstitution(UINT32 pos, UINT32* length, IDWriteNumberSubstitution** value) override {
        *length = pos < text_.size() ? static_cast<UINT32>(text_.size() - pos) : 0; *value = nullptr; return S_OK;
    }
private:
    std::wstring text_;
};

class CandidatePolicy {
public:
    CandidatePolicy(OVEncodingService* service, std::string encoding) : service_(service), encoding_(std::move(encoding)) {
        winrt::check_hresult(DWriteCreateFactory(DWRITE_FACTORY_TYPE_ISOLATED, __uuidof(IDWriteFactory2),
            reinterpret_cast<IUnknown**>(factory_.GetAddressOf())));
        winrt::check_hresult(factory_->GetSystemFontFallback(&fallback_));
        winrt::check_hresult(factory_->GetSystemFontCollection(&fonts_));
    }
    static int32_t GUANYINMA_CALL Accept(void* context, const uint8_t* bytes, size_t length) noexcept {
        try { return static_cast<CandidatePolicy*>(context)->accept(std::string(reinterpret_cast<const char*>(bytes), length)); }
        catch (...) { return 0; }
    }
private:
    bool accept(const std::string& text) {
        const auto found = cache_.find(text);
        if (found != cache_.end()) return found->second;
        const bool accepted = (!service_ || encoding_.empty() || service_->stringSupportedByEncoding(text, encoding_)) && glyphs(text);
        if (cache_.size() < 8192) cache_.emplace(text, accepted);
        return accepted;
    }
    bool glyphs(const std::string& text) {
        const auto wide = OVUTF16::FromUTF8(text);
        if (wide.empty()) return false;
        auto source = Microsoft::WRL::Make<TextSource>(wide);
        for (UINT32 pos = 0; pos < wide.size();) {
            UINT32 length = 0; FLOAT scale = 1;
            ComPtr<IDWriteFont> font;
            if (FAILED(fallback_->MapCharacters(source.Get(), pos, static_cast<UINT32>(wide.size()) - pos,
                fonts_.Get(), L"Microsoft JhengHei UI", DWRITE_FONT_WEIGHT_NORMAL, DWRITE_FONT_STYLE_NORMAL,
                DWRITE_FONT_STRETCH_NORMAL, &length, &font, &scale)) || !length || !font) return false;
            const auto end = pos + length;
            if (end > wide.size()) return false;
            while (pos < end) {
                UINT32 scalar = wide[pos++];
                if (scalar >= 0xd800 && scalar <= 0xdbff) {
                    if (pos >= end || wide[pos] < 0xdc00 || wide[pos] > 0xdfff) return false;
                    scalar = 0x10000 + ((scalar - 0xd800) << 10) + wide[pos++] - 0xdc00;
                }
                if (scalar == 0x200d || (scalar >= 0xfe00 && scalar <= 0xfe0f) ||
                    (scalar >= 0xe0100 && scalar <= 0xe01ef)) continue;
                BOOL supported = FALSE;
                if (FAILED(font->HasCharacter(scalar, &supported)) || !supported) return false;
            }
        }
        return true;
    }
    OVEncodingService* service_;
    std::string encoding_;
    ComPtr<IDWriteFactory2> factory_;
    ComPtr<IDWriteFontFallback> fallback_;
    ComPtr<IDWriteFontCollection> fonts_;
    std::map<std::string, bool> cache_;
};

std::string Layout(const Preferences& prefs) {
    auto value = prefs.text("KeyboardLayout");
    std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) { return static_cast<char>(std::tolower(c)); });
    if (value == "hsu" || value == "bpmfdtnlgkhjvcjvcrzasexuyhgeiawomnklldfjs") return "hsu";
    if (value == "eten") return "eten";
    if (value == "eten26" || value == "bpmfdtnlvkhgvcgycjqwsexuaorwiqzpmntlhfjkd") return "eten26";
    if (value == "hanyu pinyin" || value == "hanyupinyin" || value == "hanyu-pinyin" || value == "pinyin") return "hanyu_pinyin";
    return "standard";
}

Json Configuration(const std::string& method, const Preferences& prefs, std::string& keys) {
    const bool smart = method == "SmartMandarin";
    const bool table = method == "Generic-cj-cin" || method == "Generic-simplex-cin";
    const bool cangjie = method == "Generic-cj-cin";
    const auto name = smart ? "smart" : table ? (cangjie ? "cangjie" : "simplex") : "traditional";
    Json config;
    Set(config, L"profile", "desktop"); Set(config, L"method", name);
    const auto layout = Layout(prefs); Set(config, L"layout", layout);
    const auto directory = SettingsDirectory();
    if (directory.empty()) throw std::runtime_error("no writable Guanyinma profile");
    Set(config, L"user_database", OVUTF8::FromUTF16(directory + L"\\GuanyinmaUserData.db"));
    // MakeKey normalizes the live Windows Caps Lock preference before this ABI.
    Json behaviors; Set(behaviors, L"ignore_caps_lock_in_chinese", false);
    Set(behaviors, L"literal_keypad", true); config.SetNamedValue(L"behaviors", behaviors);
    Json learning; Set(learning, L"user_phrases", true); Set(learning, L"candidate_overrides", smart);
    Set(learning, L"bigrams", smart); Set(learning, L"table_learning", table && prefs.boolean("UseDynamicFrequency", false));
    config.SetNamedValue(L"learning", learning);
    keys = table ? "123456789" : prefs.text("CandidateSelectionKeys");
    if (smart && keys.size() != 8) keys.clear();
    std::set<char> unique(keys.begin(), keys.end());
    if (unique.size() != keys.size() || std::any_of(keys.begin(), keys.end(), [](unsigned char c) { return c < 0x21 || c > 0x7e; })) keys.clear();
    if (keys.empty()) keys = layout == "hsu" ? "asdfzxcv" : layout == "eten26" ? "asdfjkl;" : smart ? "12345678" : "123456789";
    if (smart) {
        Json options;
        Set(options, L"space_opens_candidates", prefs.boolean("ShowCandidateListWithSpace", false));
        Set(options, L"candidate_cursor_at_end", prefs.boolean("CandidateCursorAtEndOfTargetBlock", false));
        Set(options, L"clear_composing_with_escape", prefs.boolean("ClearComposingTextWithEscUserChoice", false) &&
            prefs.boolean("ClearComposingTextWithEsc", false));
        Set(options, L"shift_always_uppercase", prefs.boolean("ShiftKeyAlwaysCommitUppercaseCharacters", false));
        const auto size = prefs.text("ComposingTextBufferSize", "10");
        char* end = nullptr; const long limit = std::strtol(size.c_str(), &end, 10);
        Set(options, L"max_completed_syllables", end && *end == 0 && limit >= 10 && limit <= 20 ? static_cast<int>(limit) : 10);
        Set(options, L"shift_at_limit", false); Set(options, L"candidate_selection_keys", keys);
        config.SetNamedValue(L"smart", options);
    } else if (!table) Set(config, L"traditional_selection_keys", keys);
    if (table) {
        Json options;
        auto preview = LoadTablePreviewSettings(!cangjie);
        Set(options, L"realtime", preview.composeWhileTyping); Set(options, L"prefix", cangjie && preview.prefixCandidates);
        Set(options, L"clear_on_error", preview.clearOnError);
        Set(options, L"query_at_maximum", prefs.boolean("ShouldCommitAtMaximumRadicalLength", !cangjie));
        Set(options, L"learn_selection", prefs.boolean("UseDynamicFrequency", false));
        Set(options, L"space_as_first_selection_key", prefs.boolean("UseSpaceAsFirstCandidateSelectionKey", false));
        Set(options, L"space_commits_first_on_single_page", prefs.boolean("SendFirstCandidateWithSpaceWithOnePageList", cangjie));
        Set(options, L"maximum_radical_length", cangjie ? 5 : 2);
        const auto punctuation = prefs.text("UseOverrideTable");
        if (!punctuation.empty() && punctuation != "Punctuations-cj-halfwidth-cin" && punctuation != "Punctuations-cj-mixedwidth-cin")
            throw std::runtime_error("unsupported punctuation override");
        Set(options, L"punctuation", punctuation == "Punctuations-cj-halfwidth-cin" ? "half" : punctuation.empty() ? "original" : "mixed");
        if (prefs.root->valueForKey("MatchOneChar") || prefs.root->valueForKey("MatchZeroOrMoreChar")) {
            Json wildcards;
            const auto one = prefs.text("MatchOneChar", cangjie ? "?" : "");
            const auto many = prefs.text("MatchZeroOrMoreChar", cangjie ? "*" : "");
            if (one.empty()) wildcards.SetNamedValue(L"one", Value::CreateNullValue()); else Set(wildcards, L"one", one.substr(0, 1));
            if (many.empty()) wildcards.SetNamedValue(L"many", Value::CreateNullValue()); else Set(wildcards, L"many", many.substr(0, 1));
            options.SetNamedValue(L"wildcards", wildcards);
        }
        config.SetNamedValue(cangjie ? L"cangjie" : L"simplex", options);
        // The core prepends Space itself; it is not a printable selection key
        // in SessionConfig. The native label must include the same slot.
        Set(config, L"table_selection_keys", keys);
        if (prefs.boolean("UseSpaceAsFirstCandidateSelectionKey", false)) keys.insert(keys.begin(), ' ');
    }
    return config;
}

class AssociatedPhraseQuery final : public OVAFAssociatedPhraseQuery {
public:
    explicit AssociatedPhraseQuery(std::string path) : path_(std::move(path)) {}
    ~AssociatedPhraseQuery() override { guanyinma_database_close(&database_); }
    bool isActive(OVCandidateService*) const override { return true; }
    bool lookup(const std::string& head, const std::vector<std::string>& collections,
        std::vector<std::string>& candidates, std::string& error) override {
        candidates.clear();
        try {
            Apartment apartment;
            if (!database_ && guanyinma_database_open(
                reinterpret_cast<const uint8_t*>(path_.data()), path_.size(), &database_) != GUANYINMA_OK)
                throw std::runtime_error(LastError());
            Json request;
            Set(request, L"head", head);
            Array names;
            for (const auto& name : collections) names.Append(Value::CreateStringValue(winrt::to_hstring(name)));
            request.SetNamedValue(L"collections", names);
            const auto text = winrt::to_string(request.Stringify());
            GuanyinmaResult* result = nullptr;
            if (guanyinma_database_associated_phrases(database_,
                reinterpret_cast<const uint8_t*>(text.data()), text.size(), &result) != GUANYINMA_OK)
                throw std::runtime_error(LastError());
            const auto value = ReadResult(result);
            if (value.GetNamedNumber(L"schema_version") != 1 ||
                String(value, L"kind") != "associated_phrases" || String(value, L"key") != head)
                throw std::runtime_error("invalid associated phrase result");
            std::vector<std::string> next;
            for (const auto& row : value.GetNamedArray(L"rows")) next.push_back(winrt::to_string(row.GetString()));
            candidates.swap(next);
            return true;
        } catch (const std::exception& exception) { error = exception.what(); }
        catch (const winrt::hresult_error& exception) { error = winrt::to_string(exception.message()); }
        catch (...) { error = "associated phrase query failed"; }
        return false;
    }
private:
    const std::string path_;
    GuanyinmaDatabase* database_ = nullptr;
};

class Context final : public OVEventHandlingContext {
public:
    Context(const std::string& method, const std::string& model, OVLoaderService* service) {
        Apartment apartment;
        Preferences prefs(method);
        const auto config = Configuration(method, prefs, keys_);
        const auto encoding = prefs.text("UseCharactersSupportedByEncoding");
        policy_ = std::make_unique<CandidatePolicy>(service->encodingService(), encoding == "BIG-5" || encoding == "UTF-8" ? encoding : "");
        model_ = model; config_ = winrt::to_string(config.Stringify());
        open();
    }
    void open() {
        if (guanyinma_abi_version() != 1 || guanyinma_session_open_with_candidate_filter(
            reinterpret_cast<const uint8_t*>(model_.data()), model_.size(),
            reinterpret_cast<const uint8_t*>(config_.data()), config_.size(), CandidatePolicy::Accept, policy_.get(), &session_) != GUANYINMA_OK)
            throw std::runtime_error(LastError());
    }
    ~Context() override { guanyinma_session_close(&session_); }
    void clear(OVLoaderService* service) override {
        // Clear is called only after TSF has preserved/discarded the old view.
        // Reset must not leave an old graph available after a storage failure.
        snapshot_.clear(); recoverView_ = false; candidateValues_.clear(); candidateSpans_.clear(); panelVisible_ = false;
        try { Apartment apartment; Apply(session_, Operation("reset")); }
        catch (...) { guanyinma_session_close(&session_); service->beep(); }
    }
    bool candidateSelected(OVCandidateService* candidates, const std::string& text, size_t index,
        OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service) override {
        try {
            Apartment apartment;
            if (index >= candidateValues_.size() || candidateValues_[index] != text ||
                !syncCandidatePosition(candidates, reading, composing, service)) { service->beep(); return true; }
            auto operation = Operation("select"); Set(operation, L"index", static_cast<int>(index % pageSize_));
            render(Apply(session_, operation), reading, composing, candidates, service);
        } catch (...) { recoverView_ = true; service->beep(); }
        return true;
    }
    void candidateCanceled(OVCandidateService* candidates, OVTextBuffer* reading,
        OVTextBuffer* composing, OVLoaderService* service) override {
        try {
            Apartment apartment;
            auto operation = Operation("key"); Set(operation, L"key", "escape");
            render(Apply(session_, operation), reading, composing, candidates, service);
        } catch (...) { recoverView_ = true; service->beep(); }
    }
    bool candidateNonPanelKeyReceived(OVCandidateService* candidates, const OVKey* key,
        OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service) override {
        try {
            Apartment apartment;
            if (!session_) { open(); snapshot_.clear(); recoverView_ = false; }
            if (recoverView_ && !snapshot_.empty()) {
                render(Json::Parse(winrt::to_hstring(snapshot_)), reading, composing, candidates, service, false);
                recoverView_ = false;
            }
            if (!syncCandidatePosition(candidates, reading, composing, service)) return true;
            OVKey copy(*key);
            return handleKey(&copy, reading, composing, candidates, service);
        } catch (...) { service->beep(); return true; }
    }
    bool handleKey(OVKey* key, OVTextBuffer* reading, OVTextBuffer* composing,
        OVCandidateService* candidates, OVLoaderService* service) override {
        if (!key) return false;
        try {
            Apartment apartment;
            if (!session_) { open(); snapshot_.clear(); recoverView_ = false; }
            if (recoverView_ && !snapshot_.empty()) {
                render(Json::Parse(winrt::to_hstring(snapshot_)), reading, composing, candidates, service, false);
                recoverView_ = false;
            }
            Json operation;
            const char* name = nullptr;
            switch (key->keyCode()) {
                case OVKeyCode::Return: name = "return"; break;
                case OVKeyCode::Space: name = "space"; break;
                case OVKeyCode::Backspace: name = "backspace"; break;
                case OVKeyCode::Delete: name = "delete"; break;
                case OVKeyCode::Esc: name = "escape"; break;
                case OVKeyCode::Tab: name = "tab"; break;
                case OVKeyCode::Left: name = "left"; break;
                case OVKeyCode::Right: name = "right"; break;
                case OVKeyCode::Up: name = "up"; break;
                case OVKeyCode::Down: name = "down"; break;
                case OVKeyCode::Home: name = "home"; break;
                case OVKeyCode::End: name = "end"; break;
                case OVKeyCode::PageUp: name = "page_up"; break;
                case OVKeyCode::PageDown: name = "page_down"; break;
            }
            Json modifiers; Set(modifiers, L"shift", key->isShiftPressed()); Set(modifiers, L"control", key->isCtrlPressed());
            Set(modifiers, L"alt", key->isAltPressed()); Set(modifiers, L"caps_lock", key->isCapsLockOn());
            Set(modifiers, L"keypad", key->isNumLockOn());
            operation.SetNamedValue(L"modifiers", modifiers);
            if (name) { Set(operation, L"type", "key"); Set(operation, L"key", name); }
            else {
                const auto text = key->receivedString();
                if (OVUTF8Helper::SplitStringByCodePoint(text).size() != 1) return false;
                Set(operation, L"type", "character"); Set(operation, L"text", text);
            }
            // Paging bindings are frontend policy, not Rust core shortcuts.
            if (panelVisible_ && key->isShiftPressed() && !key->isCombinedFunctionKey() &&
                (key->receivedString() == "<" || key->receivedString() == ">")) {
                operation = Operation("page"); Set(operation, L"delta", key->receivedString() == "<" ? -1 : 1);
            }
            return render(Apply(session_, operation), reading, composing, candidates, service);
        } catch (...) { recoverView_ = true; service->beep(); return true; } // Never replay through the other core.
    }
private:
    bool syncCandidatePosition(OVCandidateService* candidates, OVTextBuffer* reading,
        OVTextBuffer* composing, OVLoaderService* service) {
        auto* panel = candidates->useOneDimensionalCandidatePanel();
        const auto page = panel->currentPage(), highlight = panel->currentHightlightIndex();
        const auto stable = [&](Json const& snapshot) {
            std::vector<std::string> values;
            for (auto const& value : snapshot.GetNamedArray(L"candidates")) values.push_back(winrt::to_string(value.GetString()));
            if (values == candidateValues_ && winrt::to_string(snapshot.GetNamedArray(L"candidate_spans").Stringify()) == candidateSpans_) {
                snapshot_ = winrt::to_string(snapshot.Stringify()); return true;
            }
            render(snapshot, reading, composing, candidates, service); service->beep(); return false;
        };
        if (page != page_) {
            auto operation = Operation("page"); Set(operation, L"delta", static_cast<int>(page) - static_cast<int>(page_));
            if (!stable(Apply(session_, operation))) return false;
            page_ = page;
        }
        if (highlight < pageSize_ && highlight != highlight_) {
            auto operation = Operation("move_highlight"); Set(operation, L"delta", static_cast<int>(highlight) - static_cast<int>(highlight_));
            if (!stable(Apply(session_, operation))) return false;
            highlight_ = highlight;
        }
        return true;
    }
    bool render(Json const& snapshot, OVTextBuffer* reading, OVTextBuffer* composing,
        OVCandidateService* candidates, OVLoaderService* service, bool emitEffects = true) {
        const auto effects = snapshot.GetNamedObject(L"effects");
        const auto commit = String(effects, L"commit");
        if (emitEffects && !commit.empty()) composing->commitAsTextSegment(commit);
        const auto composition = String(snapshot, L"composition");
        const auto pendingReading = String(snapshot, L"reading");
        // Table/traditional composition is their reading, not duplicated text.
        const bool smart = String(snapshot, L"method") == "smart";
        reading->setText(pendingReading); composing->setText(smart ? composition : "");
        const auto cursor = static_cast<size_t>(snapshot.GetNamedNumber(L"cursor"));
        const auto readingLength = OVUTF8Helper::SplitStringByCodePoint(pendingReading).size();
        const auto compositionLength = OVUTF8Helper::SplitStringByCodePoint(smart ? composition : "").size();
        composing->setCursorPosition(std::min(compositionLength, cursor >= readingLength ? cursor - readingLength : 0));
        composing->setHighlightMark(OVTextBuffer::RangePair(0, 0));
        composing->clearToolTip();
        if (smart) {
            const auto marked = snapshot.GetNamedValue(L"marked_phrase");
            if (marked.ValueType() == winrt::Windows::Data::Json::JsonValueType::Object) {
                const auto value = marked.GetObject();
                composing->setHighlightMark({static_cast<size_t>(value.GetNamedNumber(L"text_start")),
                    static_cast<size_t>(value.GetNamedNumber(L"text_length"))});
            }
        }
        reading->updateDisplay(); composing->updateDisplay();
        auto* panel = candidates->useOneDimensionalCandidatePanel();
        panel->cancelEventHandler();
        std::vector<std::string> values;
        for (auto const& value : snapshot.GetNamedArray(L"candidates")) values.push_back(winrt::to_string(value.GetString()));
        candidateValues_ = values;
        candidateSpans_ = winrt::to_string(snapshot.GetNamedArray(L"candidate_spans").Stringify());
        panel->candidateList()->setCandidates(values);
        panelVisible_ = !values.empty();
        if (panelVisible_) {
            const auto size = static_cast<size_t>(snapshot.GetNamedNumber(L"page_size"));
            pageSize_ = size; page_ = static_cast<size_t>(snapshot.GetNamedNumber(L"page"));
            panel->setCandidateKeys(keys_, service); panel->setCandidatesPerPage(size);
            auto next = panel->defaultNextPageKeys(), previous = panel->defaultPreviousPageKeys();
            next.push_back(service->makeOVKey('>', false, false, false, true));
            previous.push_back(service->makeOVKey('<', false, false, false, true));
            const auto options = snapshot.GetNamedObject(L"table_options");
            if (!smart && String(snapshot, L"method") != "traditional" && snapshot.GetNamedNumber(L"page_count") <= 1 &&
                (options.GetNamedBoolean(L"space_as_first_selection_key") ||
                 (options.GetNamedValue(L"space_commits_first_on_single_page").ValueType() == winrt::Windows::Data::Json::JsonValueType::Boolean && options.GetNamedBoolean(L"space_commits_first_on_single_page")))) {
                const auto space = service->makeOVKey(OVKeyCode::Space);
                next.erase(std::remove(next.begin(), next.end(), space), next.end());
            }
            panel->setNextPageKeys(next); panel->setPreviousPageKeys(previous);
            // PV routes candidate ownership before around filters. Otherwise
            // the associated-phrase filter would dismiss another core's panel.
            panel->show(); panel->yieldToCandidateEventHandler(); panel->goToPage(page_);
            const auto highlight = snapshot.GetNamedValue(L"highlight");
            highlight_ = highlight.ValueType() == winrt::Windows::Data::Json::JsonValueType::Number ? static_cast<size_t>(highlight.GetNumber()) : 0;
            panel->setHighlightIndex(highlight_);
        } else panel->hide();
        panel->updateDisplay();
        snapshot_ = winrt::to_string(snapshot.Stringify());
        if (emitEffects && effects.GetNamedBoolean(L"beep")) service->beep();
        return effects.GetNamedBoolean(L"handled");
    }
    std::unique_ptr<CandidatePolicy> policy_;
    GuanyinmaSession* session_ = nullptr;
    std::string keys_;
    std::string model_, config_, snapshot_;
    bool recoverView_ = false;
    bool panelVisible_ = false;
    std::vector<std::string> candidateValues_;
    std::string candidateSpans_;
    size_t pageSize_ = 1, page_ = 0, highlight_ = 0;
};
} // namespace

OVEventHandlingContext* CreateGuanyinmaWindowsContext(const std::string& method,
    const std::string& modelPath, OVLoaderService* service) {
    try { return new Context(method, modelPath, service); }
    catch (...) { if (service) service->beep(); return nullptr; }
}

OVEventHandlingContext* CreateGuanyinmaWindowsAssociatedPhraseContext(
    OVModule* module, const std::string& modelPath) {
    auto* associated = dynamic_cast<OVAFAssociatedPhrase*>(module);
    if (!associated) return nullptr;
    return new OVAFAssociatedPhraseContext(associated,
        std::make_shared<AssociatedPhraseQuery>(modelPath));
}
} // namespace KeyKey::WindowsTsf

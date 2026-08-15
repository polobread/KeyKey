#pragma once

#include <Windows.h>
#include <msctf.h>

#include <atomic>
#include <utility>
#include <vector>

namespace KeyKey::WindowsTsf {

class TextService;

inline constexpr GUID kLangBarInputModeGuid = {
    0x2c77a81e, 0x41cc, 0x4178, {0xa3, 0xa7, 0x5f, 0x8a, 0x98, 0x75, 0x68, 0xe6}};
inline constexpr GUID kLangBarSwitchLanguageGuid = {
    0xa4ab59e7, 0x9fb0, 0x4e4b, {0x94, 0x9e, 0xa0, 0xd3, 0x15, 0xe8, 0x72, 0xb1}};
inline constexpr GUID kLangBarFullHalfGuid = {
    0x2a673c70, 0x88c0, 0x42a8, {0x90, 0x91, 0xd7, 0xcf, 0xdc, 0x9d, 0xa9, 0xc4}};
inline constexpr GUID kLangBarSettingsGuid = {
    0x5cd7b80f, 0x4214, 0x44bb, {0xa1, 0xab, 0xd6, 0x5b, 0x20, 0xc3, 0x13, 0xd7}};

class LangBarButton final : public ITfLangBarItemButton, public ITfSource {
public:
    enum class Kind { InputMode, SwitchLanguage, FullHalf, Settings };

    LangBarButton(TextService* service, REFGUID guid, Kind kind);

    STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
    STDMETHODIMP_(ULONG) AddRef() override;
    STDMETHODIMP_(ULONG) Release() override;

    STDMETHODIMP GetInfo(TF_LANGBARITEMINFO* info) override;
    STDMETHODIMP GetStatus(DWORD* status) override;
    STDMETHODIMP Show(BOOL show) override;
    STDMETHODIMP GetTooltipString(BSTR* tooltip) override;

    STDMETHODIMP OnClick(TfLBIClick click, POINT point, const RECT* area) override;
    STDMETHODIMP InitMenu(ITfMenu* menu) override;
    STDMETHODIMP OnMenuSelect(UINT id) override;
    STDMETHODIMP GetIcon(HICON* icon) override;
    STDMETHODIMP GetText(BSTR* text) override;

    STDMETHODIMP AdviseSink(REFIID iid, IUnknown* unknown, DWORD* cookie) override;
    STDMETHODIMP UnadviseSink(DWORD cookie) override;

    void update();

private:
    ~LangBarButton();
    const wchar_t* label() const;

    std::atomic<ULONG> referenceCount_{1};
    TextService* service_ = nullptr;
    GUID guid_{};
    Kind kind_;
    DWORD nextCookie_ = 1;
    std::vector<std::pair<DWORD, ITfLangBarItemSink*>> sinks_;
};

}  // namespace KeyKey::WindowsTsf

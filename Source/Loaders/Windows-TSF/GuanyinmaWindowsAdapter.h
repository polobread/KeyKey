// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include <string>
namespace OpenVanilla { class OVEventHandlingContext; class OVLoaderService; class OVModule; class OVTextBuffer; class OVCandidateService; }
namespace KeyKey::WindowsTsf {
OpenVanilla::OVEventHandlingContext* CreateGuanyinmaWindowsContext(
    const std::string& method, const std::string& modelPath,
    OpenVanilla::OVLoaderService* service);
OpenVanilla::OVEventHandlingContext* CreateGuanyinmaWindowsAssociatedPhraseContext(
    OpenVanilla::OVModule* module, const std::string& modelPath);
// Host offsets are UTF-16; the core cursor counts completed readings.
// False leaves an unsafe/unfinished view for TSF to preserve and retire.
bool SetGuanyinmaWindowsHostCursor(OpenVanilla::OVEventHandlingContext* context,
    const std::wstring& text, size_t cursor, OpenVanilla::OVTextBuffer* reading,
    OpenVanilla::OVTextBuffer* composing, OpenVanilla::OVCandidateService* candidates,
    OpenVanilla::OVLoaderService* service);
bool PrepareGuanyinmaWindowsResume(OpenVanilla::OVEventHandlingContext* context,
    OpenVanilla::OVTextBuffer* reading, OpenVanilla::OVTextBuffer* composing,
    OpenVanilla::OVCandidateService* candidates, OpenVanilla::OVLoaderService* service);
}

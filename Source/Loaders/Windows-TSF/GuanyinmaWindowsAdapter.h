// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
#pragma once
#include <string>
namespace OpenVanilla { class OVEventHandlingContext; class OVLoaderService; }
namespace KeyKey::WindowsTsf {
OpenVanilla::OVEventHandlingContext* CreateGuanyinmaWindowsContext(
    const std::string& method, const std::string& modelPath,
    OpenVanilla::OVLoaderService* service);
}

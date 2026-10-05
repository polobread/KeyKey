#pragma once
#include "SharedOutputState.h"

namespace KeyKey::WindowsTsf {
inline GUID StartupInputModeGuid() {
    // Separate from the live Chinese/English mode and simplified output.
    return OutputCompartmentGuid(
        {0x768abd6c, 0x93a1, 0x4e21, {0xa6, 0x61, 0x19, 0x9f, 0x52, 0x53, 0x79, 0x08}});
}

inline bool ResolveStartupChineseMode(ITfThreadMgr* manager, TfClientId client,
                                      bool immersive, bool configuredChinese) {
    SharedOutputState preference;
    if (FAILED(preference.connect(manager, StartupInputModeGuid()))) return configuredChinese;
    // Search/AppContainer can have a private profile. Desktop hosts and the
    // settings app publish the preference without changing anyone's live mode.
    if (immersive) return preference.read().value_or(configuredChinese);
    preference.write(client, configuredChinese);
    return configuredChinese;
}
}

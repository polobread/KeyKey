#pragma once

#include "OVIMGeneric.h"

namespace KeyKey::WindowsTsf {

// Use the shared table engine with Windows settings and per-context learning.
// The shared macOS module and its session transactions remain independent.
class WindowsTableInputMethod final : public OpenVanilla::OVIMGeneric {
public:
    WindowsTableInputMethod(const std::string& name,
                            OpenVanilla::OVDatabaseService* database);
    OpenVanilla::OVEventHandlingContext* createContext() override;
    void loadConfig(OpenVanilla::OVKeyValueMap* config,
                    OpenVanilla::OVLoaderService* service) override;
    void saveConfig(OpenVanilla::OVKeyValueMap* config,
                    OpenVanilla::OVLoaderService* service) override;
    bool dynamicFrequency() const { return dynamicFrequency_; }
    const std::string& frequencyPath() const { return m_userDatabasePath; }

private:
    bool dynamicFrequency_ = false;
};

}  // namespace KeyKey::WindowsTsf

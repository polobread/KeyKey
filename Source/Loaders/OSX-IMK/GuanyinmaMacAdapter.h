/*
 * macOS OpenVanilla frontend bridge for the Guanyinma shared core.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#ifndef GUANYINMA_MAC_ADAPTER_H
#define GUANYINMA_MAC_ADAPTER_H

#include <OpenVanilla/OpenVanilla.h>
#include <string>

// These entry points have no loader singleton or installed-profile dependency.
// The caller owns a returned context. NULL reports a Rust initialization error;
// callers must report the error rather than opening another input core.
bool GuanyinmaSupportsInputMethod(const std::string& identifier);

// Checks only the native preference mapping; it never opens a database.
bool GuanyinmaCanUseInputMethod(const std::string& identifier,
    OpenVanilla::OVKeyValueMap* moduleConfig, std::string* error = NULL);

OpenVanilla::OVEventHandlingContext* GuanyinmaCreateInputContext(
    const std::string& identifier,
    const std::string& modelPath,
    const std::string& userDatabasePath,
    OpenVanilla::OVKeyValueMap* moduleConfig,
    std::string* error = NULL);

// Call immediately before PVLoaderContext::handleKeyEvent. OV's legacy
// candidate-key matcher ignores keypad identity; allow real printable keypad
// input to reach a Rust-owned candidate session through the normal PV pipeline.
// Returns true only when it released that session's native candidate handler.
bool GuanyinmaPrepareCandidatePanelForKey(const OpenVanilla::OVKey* key,
    OpenVanilla::OVCandidateService* candidateService);

// Synchronize an FE-decided mode after the FE has finished/cleared visible
// text. This never commits or replays host text. A nonempty Rust session rejects
// the change. Unowned services are successful no-ops.
bool GuanyinmaSetEnglishModeForService(OpenVanilla::OVCandidateService* candidateService,
    bool enabled, std::string* error = NULL);

// Standalone package with the four existing input method identifiers and the
// associated-phrase frontend. It never creates Manjusri or Generic engines.
// The loader initializes/owns the package and owns every returned module.
OpenVanilla::OVModulePackage* GuanyinmaCreateModulePackage(
    const std::string& modelPath,
    const std::string& userDatabasePath);

#endif

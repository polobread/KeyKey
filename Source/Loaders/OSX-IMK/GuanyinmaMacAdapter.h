/*
 * macOS OpenVanilla frontend bridge for the Guanyinma shared core.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#ifndef GUANYINMA_MAC_ADAPTER_H
#define GUANYINMA_MAC_ADAPTER_H

#include <OpenVanilla/OpenVanilla.h>
#include <string>
#include "GuanyinmaMacCoreSelection.h"

#ifndef KEYKEY_ENABLE_GUANYINMA
#define KEYKEY_ENABLE_GUANYINMA 0
#endif

// These entry points have no loader singleton or installed-profile dependency.
// The caller owns a returned context; NULL means safe legacy fallback before
// any Guanyinma input session has started.
bool GuanyinmaSupportsInputMethod(const std::string& identifier);

// Checks only the native preference mapping; it never opens a database.
bool GuanyinmaCanUseInputMethod(const std::string& identifier,
    OpenVanilla::OVKeyValueMap* moduleConfig, std::string* error = NULL);

// True after this decorated module successfully created a Rust context.
// False for undecorated modules, before creation, or after safe legacy fallback.
// This is a diagnostic for the last factory call, not a user-data routing policy.
bool GuanyinmaModuleUsesCore(const OpenVanilla::OVModule* module);

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
// the change. Non-Rust/disabled/unowned services are successful no-ops.
bool GuanyinmaSetEnglishModeForService(OpenVanilla::OVCandidateService* candidateService,
    bool enabled, std::string* error = NULL);

// Decorates an already initialized package and assumes its ownership.
// Disabled builds/runtime settings return the original package unchanged.
// Supported modules keep their identifiers, names and the existing PV pipeline;
// associated-phrase/other modules are returned directly from the legacy package.
OpenVanilla::OVModulePackage* GuanyinmaWrapModulePackage(
    OpenVanilla::OVModulePackage* initializedPackage,
    const std::string& modelPath,
    const std::string& userDatabasePath,
    bool enabled);

// Dual-core package: always decorate supported methods, including when the
// saved selection is Manjusri. Each live input context switches independently
// at a safe native input boundary and retains the same PV sandwich.
OpenVanilla::OVModulePackage* GuanyinmaWrapModulePackage(
    OpenVanilla::OVModulePackage* initializedPackage,
    const std::string& modelPath,
    const std::string& userDatabasePath,
    const std::shared_ptr<GuanyinmaCoreSelection>& selection);

#endif

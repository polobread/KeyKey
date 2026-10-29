/*
 * Frontend core selection with stable OpenVanilla input contexts.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#ifndef GUANYINMA_MAC_CORE_SELECTION_H
#define GUANYINMA_MAC_CORE_SELECTION_H

#include <OpenVanilla/OpenVanilla.h>
#include <cstdint>
#include <functional>
#include <memory>
#include <string>

class GuanyinmaCoreSelection;

#ifdef __OBJC__
@class NSUserDefaults;
// An absent preference selects Rust; an explicit existing NO remains native.
// Reading the preference does not write or register a value in any domain.
bool GuanyinmaRequestedCoreFromDefaults(NSUserDefaults* defaults);
#endif

struct GuanyinmaCoreStatus {
    bool requested = false;
    bool active = false;
    bool pending = false;
    std::string error;
    std::uint64_t generation = 0;
    std::size_t contextCount = 0;
    std::size_t nativeCount = 0;
    std::size_t guanyinmaCount = 0;
};

struct GuanyinmaCoreDelegate {
    // Ownership transfers to the switching context. NULL preserves its current
    // delegate and records an error; the callback handles initial native fallback.
    OpenVanilla::OVEventHandlingContext* context = NULL;
    bool usesGuanyinma = false;
    std::string error;
};

using GuanyinmaCoreContextFactory = std::function<GuanyinmaCoreDelegate(bool requested)>;
using GuanyinmaCoreConfigurationGeneration = std::function<std::uint64_t()>;

std::shared_ptr<GuanyinmaCoreSelection> GuanyinmaCreateCoreSelection(bool requested = true);
// Every explicit request advances its policy generation, including a request
// for the same value, so a previous fallback can be retried once at a safe event.
void GuanyinmaRequestCore(const std::shared_ptr<GuanyinmaCoreSelection>& selection, bool requested);
// A native predispatch hook released a candidate handler only so its current
// event can reach the old delegate. Preserve that ownership for one fresh event.
void GuanyinmaPreserveCoreForCandidateEvent(
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    const OpenVanilla::OVCandidateService* service);

// Empty identifier matches all methods. NULL service matches every live context;
// otherwise only contexts last dispatched through that candidate service match.
// Active/error/pending describe the most recently dispatched matching context.
// No matching context reports active=requested. Pending means a request/config
// change awaits the next safe input boundary; it can also describe an idle
// context waiting for its next event. Counts describe actual owned delegates.
GuanyinmaCoreStatus GuanyinmaCoreSelectionStatus(
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    const std::string& identifier = std::string(),
    const OpenVanilla::OVCandidateService* service = NULL);
GuanyinmaCoreStatus GuanyinmaSwitchingContextStatus(
    const OpenVanilla::OVEventHandlingContext* context);

// The proxy owns every successful delegate. It never clears or commits native
// buffers itself, reloads the PV sandwich, or replays an event. Factory/config
// callbacks and delegate events run on the frontend event thread. Selection
// requests/status queries are synchronized and do not dereference PV services.
OpenVanilla::OVEventHandlingContext* GuanyinmaCreateSwitchingContext(
    const std::string& identifier,
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    GuanyinmaCoreContextFactory factory,
    GuanyinmaCoreConfigurationGeneration configurationGeneration = GuanyinmaCoreConfigurationGeneration());

#endif

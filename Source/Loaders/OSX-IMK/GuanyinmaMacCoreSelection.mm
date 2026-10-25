/*
 * Frontend core selection with stable OpenVanilla input contexts.
 * Copyright (c) 2026 Chui-Ping Cheng. MIT License.
 */
#include "GuanyinmaMacCoreSelection.h"
#include "PVCandidate.h"
#include "PVTextBuffer.h"
#include <exception>
#include <mutex>
#include <utility>
#include <vector>

using namespace OpenVanilla;

namespace {
struct ContextState {
    std::string identifier;
    bool alive = true;
    bool hasDelegate = false;
    bool active = false;
    bool configurationPending = false;
    bool holdNextEvent = false;
    std::uint64_t attemptedGeneration = 0;
    std::uint64_t attemptedConfiguration = 0;
    std::uint64_t activity = 0;
    const OVCandidateService* service = NULL;
    std::string error;
};
}

class GuanyinmaCoreSelection {
public:
    explicit GuanyinmaCoreSelection(bool value) : requested(value) {}
    std::mutex mutex;
    bool requested;
    std::uint64_t generation = 1;
    std::uint64_t activity = 0;
    std::vector<std::weak_ptr<ContextState>> contexts;
};

namespace {
static GuanyinmaCoreStatus StateStatus(const GuanyinmaCoreSelection& selection,
    const ContextState& state)
{
    GuanyinmaCoreStatus result;
    result.requested = selection.requested;
    result.active = state.active;
    result.generation = selection.generation;
    const bool changed = selection.generation != state.attemptedGeneration;
    result.pending = state.configurationPending ||
        (changed && (!state.hasDelegate || state.active != selection.requested));
    // Returning to the already active core cancels an untried request, without
    // constructing a context or retaining a previous fallback diagnostic.
    result.error = changed && state.hasDelegate && state.active == selection.requested ?
        std::string() : state.error;
    result.contextCount = 1;
    result.nativeCount = state.hasDelegate && !state.active ? 1 : 0;
    result.guanyinmaCount = state.hasDelegate && state.active ? 1 : 0;
    return result;
}

static bool BufferQuiet(OVTextBuffer* buffer)
{
    if (!buffer || !buffer->isEmpty()) return false;
    // OV does not expose a pending-commit flag. Unknown implementations cannot
    // prove that the host consumed a commit, so retain their current delegate.
    PVTextBuffer* native = dynamic_cast<PVTextBuffer*>(buffer);
    return native && !native->isCommitted();
}

static bool NativeBoundaryQuiet(OVTextBuffer* reading, OVTextBuffer* composing,
    OVCandidateService* candidates)
{
    if (!BufferQuiet(reading) || !BufferQuiet(composing)) return false;
    PVCandidateService* native = dynamic_cast<PVCandidateService*>(candidates);
    if (!native) return false;
    PVVerticalCandidatePanel* vertical = native->accessVerticalCandidatePanel();
    PVHorizontalCandidatePanel* horizontal = native->accessHorizontalCandidatePanel();
    PVPlainTextCandidatePanel* plain = native->accessPlainTextCandidatePanel();
    return vertical && horizontal && plain &&
        !vertical->isVisible() && !vertical->isInControl() &&
        !horizontal->isVisible() && !horizontal->isInControl() && !plain->isVisible();
}

class SwitchingContext : public OVEventHandlingContext {
public:
    SwitchingContext(const std::string& identifier,
        std::shared_ptr<GuanyinmaCoreSelection> selection,
        GuanyinmaCoreContextFactory factory,
        GuanyinmaCoreConfigurationGeneration configuration)
        : selection_(std::move(selection)), factory_(std::move(factory)),
          configuration_(std::move(configuration)), state_(new ContextState)
    {
        state_->identifier = identifier;
        {
            std::lock_guard<std::mutex> lock(selection_->mutex);
            selection_->contexts.push_back(state_);
        }
        std::string error;
        std::uint64_t version = configurationVersion(&error);
        attempt(version, NULL, error);
    }

    ~SwitchingContext() override
    {
        // PV destroys its buffers/services before its sandwich contexts. Only
        // release owned objects here; never call lifecycle methods with a saved
        // loader service or inspect previously borrowed native buffers.
        std::lock_guard<std::mutex> lock(selection_->mutex);
        state_->alive = false;
        state_->service = NULL;
    }

    GuanyinmaCoreStatus status() const
    {
        std::lock_guard<std::mutex> lock(selection_->mutex);
        return StateStatus(*selection_, *state_);
    }

    void startSession(OVLoaderService* service) override
    {
        if (started_) return;
        started_ = true;
        if (delegate_) delegate_->startSession(service);
    }

    void stopSession(OVLoaderService* service) override
    {
        if (started_) {
            started_ = false;
            if (delegate_) delegate_->stopSession(service);
        }
        std::lock_guard<std::mutex> lock(selection_->mutex);
        state_->service = NULL;
        state_->holdNextEvent = false;
    }

    void clear(OVLoaderService* service) override
    {
        if (delegate_) delegate_->clear(service);
        {
            std::lock_guard<std::mutex> lock(selection_->mutex);
            state_->holdNextEvent = false;
        }
        // The caller owns PV buffers and candidate cleanup. Apply a pending
        // selection on the next fresh event after that cleanup is observable.
    }

    bool handleKey(OVKey* key, OVTextBuffer* reading, OVTextBuffer* composing,
        OVCandidateService* candidates, OVLoaderService* service) override
    {
        prepare(reading, composing, candidates, service);
        return delegate_ && delegate_->handleKey(key, reading, composing, candidates, service);
    }

    bool handleDirectText(const std::string& text, OVTextBuffer* reading,
        OVTextBuffer* composing, OVCandidateService* candidates, OVLoaderService* service) override
    {
        prepare(reading, composing, candidates, service);
        return delegate_ && delegate_->handleDirectText(text, reading, composing, candidates, service);
    }

    bool handleDirectText(const std::vector<std::string>& segments, OVTextBuffer* reading,
        OVTextBuffer* composing, OVCandidateService* candidates, OVLoaderService* service) override
    {
        prepare(reading, composing, candidates, service);
        return delegate_ && delegate_->handleDirectText(segments, reading, composing, candidates, service);
    }

    void candidateCanceled(OVCandidateService* candidates, OVTextBuffer* reading,
        OVTextBuffer* composing, OVLoaderService* service) override
    {
        touch(candidates);
        if (delegate_) delegate_->candidateCanceled(candidates, reading, composing, service);
    }

    bool candidateSelected(OVCandidateService* candidates, const std::string& text,
        size_t index, OVTextBuffer* reading, OVTextBuffer* composing,
        OVLoaderService* service) override
    {
        touch(candidates);
        return delegate_ && delegate_->candidateSelected(candidates, text, index, reading, composing, service);
    }

    bool candidateNonPanelKeyReceived(OVCandidateService* candidates, const OVKey* key,
        OVTextBuffer* reading, OVTextBuffer* composing, OVLoaderService* service) override
    {
        touch(candidates);
        return delegate_ && delegate_->candidateNonPanelKeyReceived(candidates, key, reading, composing, service);
    }

    const std::string filterText(const std::string& text, OVLoaderService* service) override
    {
        return delegate_ ? delegate_->filterText(text, service) : text;
    }

private:
    std::uint64_t configurationVersion(std::string* error) const
    {
        if (!configuration_) return 0;
        try { return configuration_(); }
        catch (const std::exception& exception) { *error = exception.what(); }
        catch (...) { *error = "Cannot read the input-core configuration generation"; }
        return 0;
    }

    void touch(OVCandidateService* candidates)
    {
        std::lock_guard<std::mutex> lock(selection_->mutex);
        state_->service = candidates;
        state_->activity = ++selection_->activity;
    }

    void prepare(OVTextBuffer* reading, OVTextBuffer* composing,
        OVCandidateService* candidates, OVLoaderService* service)
    {
        touch(candidates);
        std::string error;
        const std::uint64_t version = configurationVersion(&error);
        bool needed, preserve;
        {
            std::lock_guard<std::mutex> lock(selection_->mutex);
            preserve = state_->holdNextEvent;
            state_->holdNextEvent = false;
            state_->configurationPending = version != state_->attemptedConfiguration;
            needed = state_->configurationPending ||
                selection_->generation != state_->attemptedGeneration;
        }
        if (needed && !preserve && NativeBoundaryQuiet(reading, composing, candidates))
            attempt(version, service, error);
    }

    void attempt(std::uint64_t configuration, OVLoaderService* service,
        const std::string& configurationError)
    {
        bool requested;
        std::uint64_t generation;
        {
            std::lock_guard<std::mutex> lock(selection_->mutex);
            requested = selection_->requested;
            generation = selection_->generation;
            if (delegate_ && requested == state_->active &&
                configuration == state_->attemptedConfiguration && configurationError.empty()) {
                state_->attemptedGeneration = generation;
                state_->configurationPending = false;
                state_->error.clear();
                return;
            }
        }
        GuanyinmaCoreDelegate next;
        next.error = configurationError;
        if (configurationError.empty()) {
            try { next = factory_(requested); }
            catch (const std::exception& exception) { next.error = exception.what(); }
            catch (...) { next.error = "Cannot construct the requested input core"; }
        }
        std::unique_ptr<OVEventHandlingContext> replacement(next.context);
        if (replacement) {
            if (started_ && delegate_) delegate_->stopSession(service);
            delegate_ = std::move(replacement);
            if (started_) delegate_->startSession(service);
        } else if (next.error.empty()) {
            next.error = "Cannot construct the requested input core";
        }
        std::lock_guard<std::mutex> lock(selection_->mutex);
        state_->hasDelegate = delegate_.get() != NULL;
        if (next.context) state_->active = next.usesGuanyinma;
        state_->attemptedGeneration = generation;
        state_->attemptedConfiguration = configuration;
        state_->configurationPending = false;
        state_->error = next.error;
    }

    std::shared_ptr<GuanyinmaCoreSelection> selection_;
    GuanyinmaCoreContextFactory factory_;
    GuanyinmaCoreConfigurationGeneration configuration_;
    std::shared_ptr<ContextState> state_;
    std::unique_ptr<OVEventHandlingContext> delegate_;
    bool started_ = false;
};
}

std::shared_ptr<GuanyinmaCoreSelection> GuanyinmaCreateCoreSelection(bool requested)
{
    return std::make_shared<GuanyinmaCoreSelection>(requested);
}

void GuanyinmaRequestCore(const std::shared_ptr<GuanyinmaCoreSelection>& selection, bool requested)
{
    if (!selection) return;
    std::lock_guard<std::mutex> lock(selection->mutex);
    // An explicit request is also a bounded retry after a failed factory.
    // Matching active delegates still avoid reconstruction in attempt().
    selection->requested = requested;
    ++selection->generation;
}

void GuanyinmaPreserveCoreForCandidateEvent(
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    const OVCandidateService* service)
{
    if (!selection || !service) return;
    std::lock_guard<std::mutex> lock(selection->mutex);
    for (const auto& weak : selection->contexts) {
        auto state = weak.lock();
        if (state && state->alive && state->service == service)
            state->holdNextEvent = true;
    }
}

GuanyinmaCoreStatus GuanyinmaCoreSelectionStatus(
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    const std::string& identifier, const OVCandidateService* service)
{
    GuanyinmaCoreStatus result;
    if (!selection) return result;
    std::lock_guard<std::mutex> lock(selection->mutex);
    result.requested = result.active = selection->requested;
    result.generation = selection->generation;
    bool chosen = false;
    std::uint64_t chosenActivity = 0;
    auto& contexts = selection->contexts;
    for (auto iterator = contexts.begin(); iterator != contexts.end();) {
        auto state = iterator->lock();
        if (!state || !state->alive) { iterator = contexts.erase(iterator); continue; }
        ++iterator;
        if ((!identifier.empty() && state->identifier != identifier) ||
            (service && state->service != service)) continue;
        GuanyinmaCoreStatus status = StateStatus(*selection, *state);
        ++result.contextCount;
        result.nativeCount += status.nativeCount;
        result.guanyinmaCount += status.guanyinmaCount;
        if (!chosen || state->activity >= chosenActivity) {
            result.active = status.active;
            result.pending = status.pending;
            result.error = status.error;
            chosen = true;
            chosenActivity = state->activity;
        }
    }
    return result;
}

GuanyinmaCoreStatus GuanyinmaSwitchingContextStatus(const OVEventHandlingContext* context)
{
    const SwitchingContext* switching = dynamic_cast<const SwitchingContext*>(context);
    return switching ? switching->status() : GuanyinmaCoreStatus();
}

OVEventHandlingContext* GuanyinmaCreateSwitchingContext(const std::string& identifier,
    const std::shared_ptr<GuanyinmaCoreSelection>& selection,
    GuanyinmaCoreContextFactory factory, GuanyinmaCoreConfigurationGeneration configurationGeneration)
{
    if (!selection || !factory) return NULL;
    return new SwitchingContext(identifier, selection, std::move(factory), std::move(configurationGeneration));
}

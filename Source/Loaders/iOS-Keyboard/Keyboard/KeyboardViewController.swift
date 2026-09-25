import KeyKeyEngine
import UIKit

/// The extension's entry point. It owns the engine, renders through
/// `KeyboardView`, and is the only place that touches the document.
///
/// Touch Smart Mandarin mirrors completed characters as ordinary host text so
/// the document keeps them if iOS dismisses the keyboard without a callback.
/// Other Bopomofo modes use marked text in the host field.
final class KeyboardViewController: UIInputViewController {
    private var engine: BopomofoEngine?
    private var loadFailure: String?
    private var keyboardView: KeyboardView?
    private var statusOverride: String?
    private var heightConstraint: NSLayoutConstraint?
    private var phraseStore: AssociatedPhraseStore?
    private var smartUserData: SmartMandarinUserData?
    private var collections: [AssociatedPhraseStore.Collection] = []
    private let sharedDefaults = UserDefaults(
        suiteName: KeyboardPreferenceStore.appGroupIdentifier
    )
    private lazy var phraseSettings = PhraseSettings(sharedDefaults: sharedDefaults)
    private lazy var candidateColorSettings = CandidateColorSettings(sharedDefaults: sharedDefaults)
    private lazy var compositionModeSettings = BopomofoCompositionModeSettings(
        sharedDefaults: sharedDefaults
    )
    private lazy var clickSettings = KeyboardClickSettings(sharedDefaults: sharedDefaults)
    private lazy var learningResetRequest = KeyboardLearningResetRequest(
        sharedDefaults: sharedDefaults
    )
    private let supporterState = SupporterState()
    private var settingsPanel: SettingsPanel?
    private var documentMutationGuard = DocumentMutationGuard()
    private var markedReadingUpdateGeneration: UInt = 0
    private var activeDocumentIdentifier: UUID?
    private var hasMarkedText = false
    private var touchHostText = TouchSmartHostTextState()
    private var fieldPolicy = InputFieldPolicy.default
    private var fieldPolicyUnlocked = false
    private var returnKeyPolicy = ReturnKeyPolicy(hint: .default)
    private var candidateColor: CandidateColor = .purple
    private var inputClicksEnabled = true

    override func viewDidLoad() {
        super.viewDidLoad()
        supporterState.recordFirstUse()
        loadEngine()
        candidateColor = candidateColorSettings.color
        inputClicksEnabled = clickSettings.enabled
        _ = learningResetRequest.applyIfNeeded(to: smartUserData)

        // iPad draws no globe row of its own, so the keyboard has to carry the
        // key or there is no way to leave it.
        let keyboard = KeyboardView(needsInputModeSwitch: needsInputModeSwitchKey)
        keyboard.delegate = self
        keyboard.inputModeSwitchButton?.addTarget(
            self, action: #selector(commitBeforeInputModeSwitch), for: .touchDown
        )
        keyboard.inputModeSwitchButton?.addTarget(
            self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents
        )
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboard.topAnchor.constraint(equalTo: view.topAnchor),
            keyboard.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        self.keyboardView = keyboard

        let height = view.heightAnchor.constraint(
            equalToConstant: KeyboardMetrics.portrait.contentHeight
        )
        // Candidate content must not win over our requested keyboard height;
        // leave only the host's required constraints above this one.
        height.priority = UILayoutPriority(999)
        height.isActive = true
        heightConstraint = height

        // iPhone landscape reports compact height and uses the short scale.
        // iPad remains full-height but receives a centred maximum content width.
        registerForTraitChanges([UITraitVerticalSizeClass.self]) {
            (self: Self, _) in self.applyMetrics()
        }
        applyMetrics()
        activeDocumentIdentifier = currentDocumentIdentifier()
        updateFieldPolicy()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        supporterState.recordFirstUse()
        if updateDocumentIdentifier() {
            fieldPolicyUnlocked = false
            abandonDocumentComposition()
        }
        refreshAppSettings()
        updateFieldPolicy()
    }

    private func refreshAppSettings() {
        candidateColor = candidateColorSettings.color
        inputClicksEnabled = clickSettings.enabled
        let mode = compositionModeSettings.mode
        if engine?.bopomofoCompositionMode != mode {
            if let engine { apply(engine.setCompositionMode(mode)) }
        }
        applyPhraseSelection(phraseSettings.enabledCollections)
        if learningResetRequest.applyIfNeeded(to: smartUserData) {
            discardMarkedText()
            engine?.reset()
            touchHostText.reset()
        }
        refresh()
    }

    private func applyMetrics() {
        let metrics = KeyboardMetrics.forCompactHeight(
            traitCollection.verticalSizeClass == .compact,
            isPad: traitCollection.userInterfaceIdiom == .pad
        )
        keyboardView?.setMetrics(metrics)
        applyHeight(metrics)
    }

    /// The settings list needs more room than the keyboard, but landscape has
    /// none to give, so it only grows where there is height to spare.
    private func applyHeight(_ metrics: KeyboardMetrics) {
        let wantsTallPanel = settingsPanel != nil && !metrics.isCompactHeight
        heightConstraint?.constant = wantsTallPanel
            ? max(metrics.contentHeight, 360) : metrics.contentHeight
    }

    private var currentMetrics: KeyboardMetrics {
        KeyboardMetrics.forCompactHeight(
            traitCollection.verticalSizeClass == .compact,
            isPad: traitCollection.userInterfaceIdiom == .pad
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        commitPendingTouchSmartComposition()
        super.viewWillDisappear(animated)
        keyboardView?.cancelBackspaceRepeat()
        resetInputState()
        settingsPanel?.removeFromSuperview()
        settingsPanel = nil
    }

    override func textWillChange(_ textInput: UITextInput?) {
        if !documentMutationGuard.isActive { commitPendingTouchSmartComposition() }
        super.textWillChange(textInput)
    }

    override func selectionWillChange(_ textInput: UITextInput?) {
        if !documentMutationGuard.isActive { commitPendingTouchSmartComposition() }
        super.selectionWillChange(textInput)
    }

    @objc private func commitBeforeInputModeSwitch() {
        commitPendingTouchSmartComposition()
    }

    private func commitPendingTouchSmartComposition() {
        guard let engine, engine.isTouchSmartComposition, engine.hasComposition else { return }
        apply(engine.finishCompositionForInputHandoff())
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        handleDocumentChange()
    }

    override func selectionDidChange(_ textInput: UITextInput?) {
        super.selectionDidChange(textInput)
        handleDocumentChange()
    }

    private func handleDocumentChange() {
        let documentChanged = updateDocumentIdentifier()
        if documentChanged { fieldPolicyUnlocked = false }
        updateFieldPolicy()
        // If the host changes the document or selection, its old marked range
        // is no longer trustworthy. Mutations initiated below are ignored so a
        // committed character can still leave its associated phrases up.
        guard documentChanged || !documentMutationGuard.isActive else { return }
        abandonDocumentComposition()
    }

    /// A new document must never inherit the previous proxy's mutation guard.
    /// Returning true also lets a field switch win over a callback that happens
    /// during the short internal-mutation suppression window.
    private func updateDocumentIdentifier() -> Bool {
        // The proxy can start with Objective-C nil and publish its UUID only
        // after the first document callback. That nil -> UUID transition is
        // initialisation, not a field switch: treating it as a new document
        // would clear associated phrases immediately after the first commit.
        guard let identifier = currentDocumentIdentifier() else { return false }
        defer { activeDocumentIdentifier = identifier }
        guard let activeDocumentIdentifier else { return false }
        return activeDocumentIdentifier != identifier
    }

    /// UIKit declares this property as a non-optional UUID, but an iOS 26.6
    /// keyboard host can return Objective-C nil while the proxy is starting.
    /// Access through KVC preserves that nil instead of trapping in Swift's
    /// unconditional UUID bridge.
    private func currentDocumentIdentifier() -> UUID? {
        (textDocumentProxy as AnyObject).value(forKey: "documentIdentifier") as? UUID
    }

    private func abandonDocumentComposition() {
        cancelScheduledMarkedReadingUpdate()
        documentMutationGuard.invalidate()
        hasMarkedText = false
        resetInputState(discardDocumentComposition: false)
    }

    private func loadEngine() {
        guard let url = Bundle.main.url(forResource: "KeyKey", withExtension: "db") else {
            loadFailure = "字庫不在 extension bundle 內"
            return
        }
        do {
            let database = try Database(url: url)
            let localDirectory = FileManager.default.urls(
                for: .applicationSupportDirectory, in: .userDomainMask
            )[0]
            let groupDirectory = FileManager.default.containerURL(
                forSecurityApplicationGroupIdentifier: "group.io.github.polobread.inputmethod.chichi77.ios"
            )
            smartUserData = try? SmartMandarinUserData(
                phrasesURL: (groupDirectory ?? localDirectory).appendingPathComponent("UserPhrase.db"),
                learningURL: localDirectory.appendingPathComponent("SmartMandarinLearning.db"),
                writablePhrases: false
            )
            let phrases = AssociatedPhraseStore(database: database)
            collections = (try? phrases.collections()) ?? []
            phraseStore = phrases
            applyPhraseSelection(phraseSettings.enabledCollections)
            engine = BopomofoEngine(
                dictionary: try CandidateStore(database: database),
                associatedPhrases: phrases,
                smartSource: try SmartMandarinStore(database: database, userData: smartUserData),
                compositionMode: compositionModeSettings.mode
            )
        } catch {
            loadFailure = String(describing: error)
        }
    }

    /// Only sources the database actually has are passed down, so a stale
    /// stored selection cannot silently widen the query.
    private func applyPhraseSelection(_ selection: Set<String>) {
        let enabledInPriorityOrder = collections
            .filter { selection.contains($0.source) }
            .map(\.source)
        phraseStore?.setEnabledSources(enabledInPriorityOrder)
    }

    private func showSettingsPanel() {
        guard settingsPanel == nil, !collections.isEmpty else { return }
        let panel = SettingsPanel(
            collections: collections, enabled: phraseSettings.enabledCollections,
            inputClicksEnabled: inputClicksEnabled, candidateColor: candidateColor,
            compositionMode: engine?.bopomofoCompositionMode ?? .smart
        )
        panel.delegate = self
        panel.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(panel)
        NSLayoutConstraint.activate([
            panel.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            panel.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            panel.topAnchor.constraint(equalTo: view.topAnchor),
            panel.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        settingsPanel = panel
        applyHeight(currentMetrics)
    }

    private func refresh() {
        guard let keyboardView else { return }
        guard let engine else {
            var state = KeyboardView.State()
            state.statusOverride = loadFailure ?? "字庫載入失敗"
            keyboardView.apply(state)
            return
        }
        var state = KeyboardView.State()
        state.reading = engine.composingText
        state.smartMode = engine.bopomofoCompositionMode == .smart
            && engine.inputMode == .bopomofo
        state.smartCells = engine.touchSmartCells
        state.smartEditableCount = engine.smartCompositionReadingCount
        state.candidates = engine.displayedCandidates
        state.highlightedIndex = engine.isShowingAssociatedPhrases
            ? -1 : engine.highlightedIndex
        state.pageCount = engine.pageCount
        state.mode = engine.inputMode
        state.shifted = engine.isShifted
        state.temporaryEnglish = engine.isTemporaryEnglish
        state.statusOverride = statusOverride
        state.fieldPolicy = fieldPolicy
        state.returnKeyPolicy = returnKeyPolicy
        state.inputClicksEnabled = inputClicksEnabled
        state.candidateColor = candidateColor
        state.supportPromptVisible = supporterState.shouldShowSupportPrompt()
        keyboardView.apply(state)
    }

    private func updateFieldPolicy() {
        var nextPolicy = InputFieldPolicy(hint: keyboardTypeHint(textDocumentProxy.keyboardType))
        if fieldPolicyUnlocked { nextPolicy = nextPolicy.unrestricted() }
        let layoutChanged = nextPolicy != fieldPolicy
        fieldPolicy = nextPolicy
        engine?.setAllowedInputModes(
            fieldPolicy.allowedModes, preferred: fieldPolicy.preferredMode,
            selectPreferred: layoutChanged
        )
        returnKeyPolicy = ReturnKeyPolicy(
            hint: returnKeyHint(textDocumentProxy.returnKeyType ?? .default)
        )
        refresh()
    }

    private func keyboardTypeHint(_ type: UIKeyboardType?) -> KeyboardTypeHint {
        switch type ?? .default {
        case .asciiCapable: return .asciiCapable
        case .numbersAndPunctuation: return .numbersAndPunctuation
        case .URL: return .url
        case .numberPad: return .numberPad
        case .phonePad: return .phonePad
        case .namePhonePad: return .namePhonePad
        case .emailAddress: return .emailAddress
        case .decimalPad: return .decimalPad
        case .webSearch: return .webSearch
        case .asciiCapableNumberPad: return .asciiCapableNumberPad
        default: return .default
        }
    }

    private func returnKeyHint(_ type: UIReturnKeyType) -> ReturnKeyHint {
        switch type {
        case .done: return .done
        case .go: return .go
        case .next: return .next
        case .search: return .search
        case .send: return .send
        case .join: return .join
        case .route: return .route
        case .continue: return .continue
        case .emergencyCall: return .emergencyCall
        case .google: return .google
        case .yahoo: return .yahoo
        default: return .default
        }
    }

    private func resetInputState(discardDocumentComposition: Bool = true) {
        if discardDocumentComposition { discardMarkedText() }
        engine?.reset()
        touchHostText.reset()
        statusOverride = nil
        refresh()
    }

    private func apply(_ result: BopomofoEngine.Result) {
        if engine?.isTouchSmartComposition == true || !touchHostText.editableText.isEmpty {
            applyTouchSmart(result)
            return
        }
        if result.deletesBackward {
            discardMarkedText()
            mutateDocument { textDocumentProxy.deleteBackward() }
        }
        if !result.text.isEmpty {
            commitMarkedOrInsertedText(result.text)
        }
        if engine?.hasComposition == true {
            // Candidate buttons are extension-local UIKit. Give them the
            // current run-loop turn before crossing into the host app through
            // UITextDocumentProxy, which can be slower on real devices.
            if result.text.isEmpty, !result.deletesBackward, !result.sendsReturn,
               engine?.displayedCandidates.isEmpty == false {
                refresh()
                scheduleMarkedReadingUpdate()
                return
            }
            updateMarkedReading()
        } else if result.text.isEmpty, !result.deletesBackward {
            discardMarkedText()
        }
        if result.sendsReturn { mutateDocument { textDocumentProxy.insertText("\n") } }
        refresh()
    }

    private func applyTouchSmart(_ result: BopomofoEngine.Result) {
        if hasMarkedText { discardMarkedText() }
        let edit: TouchSmartHostTextState.Edit
        if engine?.isTouchSmartComposition == true, engine?.hasComposition == true {
            edit = touchHostText.update(
                to: engine?.completedSmartText ?? "", evictedPrefix: result.text
            )
        } else if engine?.isTouchSmartComposition == true, result.text.isEmpty,
                  !result.deletesBackward, !result.sendsReturn {
            edit = touchHostText.cancel()
        } else {
            edit = touchHostText.finish(with: result.text)
        }
        if !edit.isEmpty {
            mutateDocument {
                for _ in 0..<edit.deleteCount { textDocumentProxy.deleteBackward() }
                if !edit.insertion.isEmpty { textDocumentProxy.insertText(edit.insertion) }
            }
        }
        if result.deletesBackward { mutateDocument { textDocumentProxy.deleteBackward() } }
        if result.sendsReturn { mutateDocument { textDocumentProxy.insertText("\n") } }
        refresh()
    }

    /// Replaces the current reading rather than appending to it. This is the
    /// crucial ordering: committing `你` must replace marked `ㄋㄧˇ`, not make
    /// the host document read `ㄋㄧˇ你`.
    private func commitMarkedOrInsertedText(_ text: String) {
        cancelScheduledMarkedReadingUpdate()
        mutateDocument {
            if hasMarkedText {
                textDocumentProxy.setMarkedText(
                    text, selectedRange: NSRange(location: text.utf16.count, length: 0)
                )
                textDocumentProxy.unmarkText()
                hasMarkedText = false
            } else {
                textDocumentProxy.insertText(text)
            }
        }
    }

    private func updateMarkedReading() {
        guard let reading = engine?.composingText, !reading.isEmpty else { return }
        mutateDocument {
            textDocumentProxy.setMarkedText(
                reading, selectedRange: NSRange(location: reading.utf16.count, length: 0)
            )
            hasMarkedText = true
        }
    }

    /// Coalescing protects rapid typing from applying an older reading after a
    /// newer engine state. The small dispatch boundary also lets the candidate
    /// strip become visible before the host field mirrors its final tone mark.
    private func scheduleMarkedReadingUpdate() {
        guard let reading = engine?.composingText, !reading.isEmpty else { return }
        markedReadingUpdateGeneration &+= 1
        let generation = markedReadingUpdateGeneration
        DispatchQueue.main.async { [weak self] in
            guard let self,
                  self.markedReadingUpdateGeneration == generation,
                  self.engine?.composingText == reading
            else { return }
            self.updateMarkedReading()
        }
    }

    private func cancelScheduledMarkedReadingUpdate() {
        markedReadingUpdateGeneration &+= 1
    }

    /// Replacing a marked range with an empty string cancels it. `unmarkText`
    /// would do the opposite: it would accept the raw Bopomofo reading.
    private func discardMarkedText() {
        cancelScheduledMarkedReadingUpdate()
        guard hasMarkedText else { return }
        mutateDocument {
            textDocumentProxy.setMarkedText("", selectedRange: NSRange(location: 0, length: 0))
            hasMarkedText = false
        }
    }

    private func mutateDocument(_ mutation: () -> Void) {
        let generation = documentMutationGuard.begin()
        mutation()
        // UIKit can report the callbacks for a setMarkedText + unmarkText
        // commit after the next main-loop turn on a physical iPhone. Keep the
        // classification guard alive briefly so that late callback does not
        // erase the associated phrases we have already rendered. This does
        // not delay the mutation or UI; it only classifies callbacks.
        DispatchQueue.main.asyncAfter(deadline: .now() + .milliseconds(250)) { [weak self] in
            self?.documentMutationGuard.end(ifCurrent: generation)
        }
    }

}

extension KeyboardViewController: KeyboardViewDelegate {
    func keyboardView(_ view: KeyboardView, didPress key: String) {
        statusOverride = nil
        guard let engine else { return }
        if key == "SETTINGS" {
            showSettingsPanel()
            return
        }
        if key == "MODE", fieldPolicy.isRestricted {
            fieldPolicyUnlocked = true
            fieldPolicy = fieldPolicy.unrestricted()
            engine.setAllowedInputModes(
                fieldPolicy.allowedModes, preferred: fieldPolicy.preferredMode,
                selectPreferred: false
            )
        }
        guard fieldPolicy.isKeyEnabled(
            key, mode: engine.inputMode, shifted: engine.isShifted
        ) else { return }
        apply(engine.handleSoftKey(key))
    }

    func keyboardView(_ view: KeyboardView, didSelectCandidateAt index: Int) {
        statusOverride = nil
        guard let engine else { return }
        apply(engine.selectDisplayedCandidate(index))
    }

    func keyboardView(_ view: KeyboardView, didSelectSmartCellAt index: Int) {
        guard let engine, engine.selectTouchSmartCell(index) else { return }
        refresh()
    }

    func keyboardView(_ view: KeyboardView, didChangePageBy delta: Int) {
        statusOverride = nil
        guard let engine else { return }
        engine.changePage(by: delta)
        refresh()
    }
}

extension KeyboardViewController: SettingsPanelDelegate {
    func settingsPanelResetLearning(_ panel: SettingsPanel) -> Bool {
        guard let smartUserData else { return false }
        do {
            try smartUserData.resetLearning()
            discardMarkedText()
            engine?.reset()
            touchHostText.reset()
            refresh()
            return true
        } catch {
            return false
        }
    }

    func settingsPanel(_ panel: SettingsPanel, didChange enabled: Set<String>) {
        phraseSettings.setEnabledCollections(enabled)
        applyPhraseSelection(enabled)
        // A phrase list already on screen belongs to the old selection.
        engine?.setAssociatedPhraseSource(phraseStore)
        refresh()
    }

    func settingsPanel(
        _ panel: SettingsPanel, didChangeCompositionMode mode: BopomofoCompositionMode
    ) {
        if let engine { apply(engine.setCompositionMode(mode)) }
        compositionModeSettings.setMode(mode)
        refresh()
    }

    func settingsPanelDidClose(_ panel: SettingsPanel) {
        panel.removeFromSuperview()
        settingsPanel = nil
        applyHeight(currentMetrics)
        refresh()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeInputClicksEnabled enabled: Bool) {
        inputClicksEnabled = enabled
        clickSettings.setEnabled(enabled)
        refresh()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeCandidateColor color: CandidateColor) {
        candidateColor = color
        candidateColorSettings.setColor(color)
        refresh()
    }
}

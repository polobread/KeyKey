import KeyKeyEngine
import UIKit

/// The extension's entry point. It owns the engine, renders through
/// `KeyboardView`, and is the only place that touches the document.
///
/// iOS gives an extension no marked-text API -- `UITextDocumentProxy` can only
/// insert and delete -- so the reading lives in the keyboard's own status line
/// and only finished text reaches the host app. That also means the Android
/// ordering hazard (finishing composition before committing, which produced
/// `ㄋㄧˇ你`) cannot arise here.
final class KeyboardViewController: UIInputViewController {
    private var engine: BopomofoEngine?
    private var loadFailure: String?
    private var keyboardView: KeyboardView?
    private var statusOverride: String?
    private var heightConstraint: NSLayoutConstraint?
    private var phraseStore: AssociatedPhraseStore?
    private var collections: [AssociatedPhraseStore.Collection] = []
    private let phraseSettings = PhraseSettings()
    private var settingsPanel: SettingsPanel?
    private var isMutatingDocument = false
    private var fieldPolicy = InputFieldPolicy.default

    override func viewDidLoad() {
        super.viewDidLoad()
        loadEngine()

        // iPad draws no globe row of its own, so the keyboard has to carry the
        // key or there is no way to leave it.
        let keyboard = KeyboardView(needsInputModeSwitch: needsInputModeSwitchKey)
        keyboard.delegate = self
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
        height.priority = .defaultHigh
        height.isActive = true
        heightConstraint = height

        // iPhone landscape reports compact height and uses the short scale.
        // iPad remains full-height but receives a centred maximum content width.
        registerForTraitChanges([UITraitVerticalSizeClass.self]) {
            (self: Self, _) in self.applyMetrics()
        }
        applyMetrics()
        updateFieldPolicy()
        refresh()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        updateFieldPolicy()
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
        super.viewWillDisappear(animated)
        resetInputState()
        settingsPanel?.removeFromSuperview()
        settingsPanel = nil
    }

    override func textDidChange(_ textInput: UITextInput?) {
        super.textDidChange(textInput)
        updateFieldPolicy()
        // The reading is not mirrored into the document. If the host changes
        // the document or selection, keeping it would carry a stale reading or
        // phrase list into another field. Mutations initiated below are ignored
        // so committing a character can still leave its associated phrases up.
        if !isMutatingDocument {
            resetInputState()
        }
    }

    private func loadEngine() {
        guard let url = Bundle.main.url(forResource: "KeyKey", withExtension: "db") else {
            loadFailure = "字庫不在 extension bundle 內"
            return
        }
        do {
            let database = try Database(url: url)
            let phrases = AssociatedPhraseStore(database: database)
            collections = (try? phrases.collections()) ?? []
            phraseStore = phrases
            applyPhraseSelection(phraseSettings.enabledCollections)
            engine = BopomofoEngine(
                dictionary: try CandidateStore(database: database),
                associatedPhrases: phrases
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
            collections: collections, enabled: phraseSettings.enabledCollections
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
        state.reading = engine.readingText
        state.candidates = engine.displayedCandidates
        state.highlightedIndex = engine.isShowingAssociatedPhrases
            ? -1 : engine.highlightedIndex
        state.pageCount = engine.pageCount
        state.mode = engine.inputMode
        state.shifted = engine.isShifted
        state.temporaryEnglish = engine.isTemporaryEnglish
        state.statusOverride = statusOverride
        state.fieldPolicy = fieldPolicy
        keyboardView.apply(state)
    }

    private func updateFieldPolicy() {
        let nextPolicy = InputFieldPolicy(hint: keyboardTypeHint(textDocumentProxy.keyboardType))
        let layoutChanged = nextPolicy != fieldPolicy
        fieldPolicy = nextPolicy
        engine?.setAllowedInputModes(
            fieldPolicy.allowedModes, preferred: fieldPolicy.preferredMode,
            selectPreferred: layoutChanged
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

    private func resetInputState() {
        engine?.reset()
        statusOverride = nil
        refresh()
    }

    private func apply(_ result: BopomofoEngine.Result) {
        let mutatesDocument = result.deletesBackward
            || !result.text.isEmpty || result.sendsReturn
        if mutatesDocument {
            isMutatingDocument = true
        }
        if result.deletesBackward {
            textDocumentProxy.deleteBackward()
        }
        if !result.text.isEmpty {
            textDocumentProxy.insertText(result.text)
        }
        if result.sendsReturn {
            textDocumentProxy.insertText("\n")
        }
        refresh()
        if mutatesDocument {
            DispatchQueue.main.async { [weak self] in
                self?.isMutatingDocument = false
            }
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

    func keyboardView(_ view: KeyboardView, didChangePageBy delta: Int) {
        statusOverride = nil
        guard let engine else { return }
        engine.changePage(by: delta)
        refresh()
    }
}

extension KeyboardViewController: SettingsPanelDelegate {
    func settingsPanel(_ panel: SettingsPanel, didChange enabled: Set<String>) {
        phraseSettings.setEnabledCollections(enabled)
        applyPhraseSelection(enabled)
        // A phrase list already on screen belongs to the old selection.
        engine?.setAssociatedPhraseSource(phraseStore)
        refresh()
    }

    func settingsPanelDidClose(_ panel: SettingsPanel) {
        panel.removeFromSuperview()
        settingsPanel = nil
        applyHeight(currentMetrics)
        refresh()
    }
}

import KeyKeyEngine
import UIKit

/// The extension's entry point. It owns the engine, renders through
/// `KeyboardView`, and is the only place that touches the document.
///
/// Touch Smart Mandarin mirrors completed characters as ordinary host text so
/// the document keeps them if iOS dismisses the keyboard without a callback.
/// Tone-omission readings and other Bopomofo modes use marked host text.
final class KeyboardViewController: UIInputViewController {
    #if DEBUG && targetEnvironment(simulator) && compiler(>=6.4)
    private var geometryProbe: AnyObject?
    #endif
    private var engine: KeyboardInputEngine?
    private var loadFailure: String?
    private var keyboardView: KeyboardView?
    private var statusOverride: String?
    private var heightConstraint: NSLayoutConstraint?
    private var keyboardTopConstraint: NSLayoutConstraint?
    private var settlingHeightPreview = false
    private var keyboardOrientation = KeyboardLayoutProfile.Orientation.portrait
    private let heightSettings = KeyboardHeightSettings()
    private var heightEditor: KeyboardHeightEditor?
    private var heightDraft: [KeyboardLayoutProfile.Orientation: KeyboardEdgeGeometry] = [:]
    private struct HeightDrag {
        let edge: KeyboardEdgeGeometry.Edge
        let startY: CGFloat
        let start: KeyboardEdgeGeometry
    }
    private var heightDrag: HeightDrag?
    private var phraseStore: AssociatedPhraseStore?
    private var guanyinmaPhraseData: SharedPhrasePublication?
    private var collections: [AssociatedPhraseStore.Collection] = []
    private let sharedDefaults = UserDefaults(
        suiteName: KeyboardPreferenceStore.appGroupIdentifier
    )
    private lazy var phraseSettings = PhraseSettings(sharedDefaults: sharedDefaults)
    private lazy var candidateColorSettings = CandidateColorSettings(sharedDefaults: sharedDefaults)
    private lazy var methodSettings = ChineseInputMethodSettings(sharedDefaults: sharedDefaults)
    private lazy var compositionModeSettings = BopomofoCompositionModeSettings(
        sharedDefaults: sharedDefaults
    )
    private lazy var clickSettings = KeyboardClickSettings(sharedDefaults: sharedDefaults)
    private lazy var layoutSettings = BopomofoKeyboardLayoutSettings(sharedDefaults: sharedDefaults)
    private lazy var spaceSettings = SmartMandarinSpaceSettings(sharedDefaults: sharedDefaults)
    private lazy var toneOmissionSettings = SmartMandarinToneOmissionSettings(sharedDefaults: sharedDefaults)
    private var pendingToneOmission: Bool?
    private lazy var learningResetRequest = KeyboardLearningResetRequest(
        sharedDefaults: sharedDefaults
    )
    private lazy var profileSettings = KeyboardLayoutProfileSettings(sharedDefaults: sharedDefaults)
    private let supporterState = SupporterState()
    private var settingsPanel: SettingsPanel?
    private var documentMutationGuard = DocumentMutationGuard()
    private var markedReadingUpdateGeneration: UInt = 0
    private var activeDocumentIdentifier: UUID?
    private var hasMarkedText = false
    private var markedTouchReading = ""
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
        applyLearningResetRequests()

        // Query the host after connection; keep the same globe control alive
        // through visibility changes so its system picker targets stay attached.
        let keyboard = KeyboardView(needsInputModeSwitch: false, layoutProfile: profileSettings.profile,
            keycapArea: profileSettings.keycapArea, fontSize: profileSettings.fontSize,
            deleteShiftPosition: profileSettings.deleteShiftPosition)
        keyboard.delegate = self
        keyboard.inputModeSwitchButton?.addTarget(
            self, action: #selector(commitBeforeInputModeSwitch), for: .touchDown
        )
        keyboard.inputModeSwitchButton?.addTarget(
            self, action: #selector(handleInputModeList(from:with:)), for: .allTouchEvents
        )
        keyboard.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(keyboard)
        let keyboardTop = keyboard.topAnchor.constraint(equalTo: view.topAnchor)
        keyboardTopConstraint = keyboardTop
        NSLayoutConstraint.activate([
            keyboard.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            keyboard.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            keyboardTop,
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

        // The inner display of a folding iPhone is regular in both dimensions.
        registerForTraitChanges([UITraitVerticalSizeClass.self, UITraitHorizontalSizeClass.self]) {
            (self: Self, _) in self.applyMetrics()
        }
        applyMetrics()
        #if DEBUG && targetEnvironment(simulator) && compiler(>=6.4)
        if #available(iOS 27.1, *),
           sharedDefaults?.bool(forKey: SimulatorGeometryProbe.preferenceKey) == true {
            geometryProbe = SimulatorGeometryProbe(view: view, scope: "extension")
        }
        #endif
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
        applyHeight(currentMetrics)
        updateFieldPolicy()
        refreshSystemKeyboardControls()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        if let orientation = view.window?.windowScene?.interfaceOrientation, orientation != .unknown {
            let next: KeyboardLayoutProfile.Orientation = orientation.isLandscape ? .landscape : .portrait
            if keyboardOrientation != next {
                keyboardOrientation = next
                endKeyboardHeightDrag()
                keyboardView?.setLayoutOrientation(next)
                applyHeight(currentMetrics)
            }
        }
        layoutHeightPreview(currentMetrics, geometry: keyboardGeometry)
        refreshSystemKeyboardControls()
        #if KEYKEY_TYPOGRAPHY_MEASUREMENT
        beginTypographyMeasurementIfRequested()
        #endif
    }

    #if KEYKEY_TYPOGRAPHY_MEASUREMENT
    private var typographyMeasurementRequest: String?
    private var typographyMeasurementLabel: UILabel?

    private func beginTypographyMeasurementIfRequested() {
        guard let request = sharedDefaults?.string(forKey: "keykeyTypographyMeasurementRequest"),
              request != typographyMeasurementRequest,
              let orientation = view.window?.windowScene?.interfaceOrientation,
              orientation != .unknown, request.hasSuffix(orientation.isLandscape ? ":landscape" : ":portrait"),
              let keyboardView, let engine, !engine.hasComposition else { return }
        typographyMeasurementRequest = request
        let label = UILabel(frame: CGRect(x: 1, y: 1, width: 1, height: 1))
        label.text = " "
        label.isAccessibilityElement = true
        label.accessibilityIdentifier = "keyboard.typography-measurement"
        label.accessibilityLabel = "實機字級量測"
        label.accessibilityValue = "running"
        view.addSubview(label)
        typographyMeasurementLabel = label
        Task { @MainActor in
            // Let the actual host finish connecting and rotating before sampling.
            try? await Task.sleep(for: .milliseconds(500))
            let saved = (profileSettings.profile, profileSettings.keycapArea,
                profileSettings.fontSize, profileSettings.deleteShiftPosition, methodSettings.method,
                engine.inputMode, engine.keyboardLayout)
            let panel = SettingsPanel(
                inputClicksEnabled: inputClicksEnabled, candidateColor: candidateColor,
                compositionMode: engine.bopomofoCompositionMode, chineseInputMethod: engine.chineseInputMethod,
                methodSettings: methodSettings, keyboardLayout: engine.keyboardLayout,
                layoutProfile: saved.0, keycapArea: saved.1, fontSize: saved.2, deleteShiftPosition: saved.3)
            var records = [[String: Any]]()
            var baseline: [Double]?
            var windowBaseline: [Double]?
            var failures = [String]()
            settingsPanel(panel, didChangeKeyboardLayout: .standard)
            for method in ChineseInputMethod.allCases {
                settingsPanel(panel, didChangeInputMethod: method)
                // English and number/symbol planes are independent of the chosen
                // Chinese method; exercise them once alongside all four methods.
                let modes: [KeyboardInput.InputMode] = method == .smart ? [.bopomofo, .english, .number] : [.bopomofo]
                for mode in modes {
                    engine.setAllowedInputModes(Set(KeyboardInput.InputMode.allCases), preferred: mode, selectPreferred: true)
                    refresh()
                    for profile in KeyboardLayoutProfile.available {
                        settingsPanel(panel, didChangeLayoutProfile: profile)
                        for spacing in KeyboardKeycapArea.allCases {
                            settingsPanel(panel, didChangeKeycapArea: spacing)
                            for font in KeyboardKeyFontSize.allCases {
                                settingsPanel(panel, didChangeFontSize: font)
                                for delete in KeyboardDeleteShiftPosition.allCases {
                                    settingsPanel(panel, didChangeDeleteShiftPosition: delete)
                                    // Yield to the real host/layout transaction, then
                                    // read the live production views and native fonts.
                                    try? await Task.sleep(for: .milliseconds(60))
                                    view.layoutIfNeeded()
                                    var record = keyboardView.typographyMeasurementSnapshot()
                                    record["method"] = method.rawValue
                                    record["mode"] = String(describing: mode)
                                    record["profile"] = profile.id
                                    record["spacing"] = spacing.rawValue
                                    record["font"] = font.rawValue
                                    record["delete"] = delete.rawValue
                                    let region = record["keyRegion"] as! [Double]
                                    let window = record["windowFrame"] as! [Double]
                                    if let baseline, zip(region, baseline).contains(where: { abs($0 - $1) > 0.5 }) {
                                        failures.append("Key region changed at case \(records.count): \(region)")
                                    } else if baseline == nil { baseline = region }
                                    if let windowBaseline, zip(window, windowBaseline).contains(where: { abs($0 - $1) > 0.5 }) {
                                        failures.append("Window changed at case \(records.count): \(window)")
                                    } else if windowBaseline == nil { windowBaseline = window }
                                    if record["primaryMismatchCount"] as? Int != 0 || record["spaceMismatchCount"] as? Int != 0
                                        || record["modeCaptionFits"] as? Bool != true {
                                        failures.append("Font/caption mismatch at case \(records.count)")
                                    }
                                    records.append(record)
                                }
                            }
                        }
                    }
                }
            }
            settingsPanel(panel, didChangeInputMethod: saved.4)
            engine.setAllowedInputModes(Set(KeyboardInput.InputMode.allCases), preferred: saved.5, selectPreferred: true)
            settingsPanel(panel, didChangeKeyboardLayout: saved.6)
            settingsPanel(panel, didChangeLayoutProfile: saved.0)
            settingsPanel(panel, didChangeKeycapArea: saved.1)
            settingsPanel(panel, didChangeFontSize: saved.2)
            settingsPanel(panel, didChangeDeleteShiftPosition: saved.3)
            refresh()
            let report: [String: Any] = ["request": request, "caseCount": records.count,
                "failures": failures, "records": records,
                "systemVersion": UIDevice.current.systemVersion,
                "scope": "Live production keyboard extension in its real input-host window; settings delegate callbacks"]
            let data = try! JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
            let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            try? data.write(to: directory.appendingPathComponent("typography-measurement.json"), options: .atomic)
            label.accessibilityValue = String(decoding: data, as: UTF8.self)
        }
    }
    #endif

    private func refreshSystemKeyboardControls() {
        guard view.window != nil else { return }
        // Apple DTS confirmed false on iPhone Duo in iOS 27.1 is a runtime bug
        // (FB25073949). Limit the fallback to that version and wide phone hosts;
        // other runtimes and form factors continue to use the system property.
        let version = ProcessInfo.processInfo.operatingSystemVersion
        let affectedWidePhone = version.majorVersion == 27 && version.minorVersion == 1
            && traitCollection.userInterfaceIdiom == .phone
            && traitCollection.horizontalSizeClass == .regular
            && traitCollection.verticalSizeClass == .regular
            && view.safeAreaLayoutGuide.layoutFrame.width >= 600
        keyboardView?.setNeedsInputModeSwitch(needsInputModeSwitchKey || affectedWidePhone)
    }

    private func selectLayoutProfile(_ profile: KeyboardLayoutProfile) {
        profileSettings.setProfile(profile)
        keyboardView?.setLayoutProfile(profile)
        applyMetrics()
    }

    private func refreshLayoutOptions() {
        keyboardView?.setLayoutOptions(keycapArea: profileSettings.keycapArea,
            fontSize: profileSettings.fontSize, deleteShiftPosition: profileSettings.deleteShiftPosition)
    }

    private func refreshAppSettings() {
        keyboardView?.setLayoutProfile(profileSettings.profile)
        refreshLayoutOptions()
        candidateColor = candidateColorSettings.color
        inputClicksEnabled = clickSettings.enabled
        if let engine {
            apply(engine.setChineseInputMethod(methodSettings.method))
            let nextOptions = methodSettings.options(for: engine.chineseInputMethod, virtualKeyboard: true)
            if engine.tableOptions != nextOptions { apply(engine.finishCompositionForInputHandoff()) }
            engine.tableOptions = nextOptions
        }
        applyPhraseSelection(phraseSettings.enabledCollections)
        if let engine {
            apply(engine.setKeyboardLayout(layoutSettings.layout))
            engine.spaceSelectsCandidates = spaceSettings.enabled
            pendingToneOmission = toneOmissionSettings.enabled
        }
        applyLearningResetRequests()
        if let engine {
            do { try engine.refreshUserPhrases(from: guanyinmaPhraseData) }
            catch { statusOverride = "Guanyinma 自訂詞同步失敗：\(error.localizedDescription)" }
        }
        refresh()
    }

    private func applyLearningResetRequests() {
        let reset = learningResetRequest.applyIfNeeded {
            if let engine {
                try engine.resetLearning()
            } else {
                guard let model = Bundle.main.url(forResource: "KeyKey", withExtension: "db") else {
                    throw NSError(domain: "KeyKey.Core", code: 1)
                }
                let local = FileManager.default.urls(
                    for: .applicationSupportDirectory, in: .userDomainMask
                )[0]
                try GuanyinmaInputEngine.resetLearning(
                    modelURL: model, userDatabaseURL: local.appendingPathComponent("GuanyinmaUser.db")
                )
            }
        }
        if reset {
            discardMarkedText()
            engine?.reset()
            touchHostText.reset()
        }
    }

    private func applyMetrics() {
        let metrics = currentMetrics
        keyboardView?.setMetrics(metrics)
        applyHeight(metrics)
    }

    /// The settings list needs more room than the keyboard, but landscape has
    /// none to give, so it only grows where there is height to spare.
    private func applyHeight(_ metrics: KeyboardMetrics) {
        let geometry = keyboardGeometry
        let requestedHeight = metrics.contentHeight * geometry.top
        let wantsTallPanel = settingsPanel != nil && !metrics.isCompactHeight
        let targetHeight: CGFloat
        if heightEditor != nil {
            // Give the preview room to grow without resizing the remote host
            // window for every touch update.
            targetHeight = CGFloat(metrics.contentHeight * KeyboardEdgeGeometry.maximumTop)
        } else {
            targetHeight = CGFloat(wantsTallPanel ? max(requestedHeight, 360) : requestedHeight)
        }
        if heightConstraint?.constant != targetHeight {
            heightConstraint?.constant = targetHeight
        }
        layoutHeightPreview(metrics, geometry: geometry)
    }

    private func layoutHeightPreview(_ metrics: KeyboardMetrics, geometry: KeyboardEdgeGeometry) {
        let requestedHeight = CGFloat(metrics.contentHeight * geometry.top)
        let inset = heightEditor != nil || settlingHeightPreview ? max(0, view.bounds.height - requestedHeight) : 0
        if keyboardTopConstraint?.constant != inset {
            keyboardTopConstraint?.constant = inset
        }
        if heightEditor == nil && inset <= 0.5 {
            settlingHeightPreview = false
        }
        applyBottomGap(metrics, geometry: geometry)
    }

    private var keyboardGeometry: KeyboardEdgeGeometry {
        heightDraft[keyboardOrientation] ?? heightSettings.geometry(for: keyboardOrientation)
    }

    private func applyBottomGap(_ metrics: KeyboardMetrics, geometry: KeyboardEdgeGeometry) {
        guard let keyboardView else { return }
        let safeArea = keyboardView.safeAreaLayoutGuide.layoutFrame
        let insetHeight = keyboardView.safeAreaInsets.top + keyboardView.safeAreaInsets.bottom
        // The host may enforce a smaller height than requested. Give usable
        // keyboard rows precedence over the requested clearance in that host.
        let minimumUsable = max(0, CGFloat(metrics.contentHeight * 0.75) - insetHeight)
        let gap = min(CGFloat(geometry.bottom * metrics.contentHeight), max(0, safeArea.height - minimumUsable))
        if heightDrag == nil {
            keyboardView.setBottomGap(gap)
        }
        heightEditor?.update(geometry: geometry, bottomGap: gap)
    }

    private var currentMetrics: KeyboardMetrics {
        profileSettings.profile.metrics(
            compactHeight: traitCollection.verticalSizeClass == .compact,
            isPad: traitCollection.userInterfaceIdiom == .pad,
            regularWidth: traitCollection.horizontalSizeClass == .regular
        )
    }

    override func viewWillDisappear(_ animated: Bool) {
        if let engine { apply(engine.finishCompositionForInputHandoff()) }
        super.viewWillDisappear(animated)
        keyboardView?.cancelBackspaceRepeat()
        resetInputState()
        settingsPanel?.removeFromSuperview()
        settingsPanel = nil
        finishEditingKeyboardHeight(save: false)
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
        if let engine { apply(engine.finishCompositionForInputHandoff()) }
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
        markedTouchReading = ""
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
            do {
                guanyinmaPhraseData = try SharedPhrasePublication(
                    phrasesURL: (groupDirectory ?? localDirectory).appendingPathComponent("GuanyinmaUserPhrase.db"),
                    writablePhrases: false
                )
            } catch {
                statusOverride = "自訂詞同步失敗：\(error.localizedDescription)"
            }
            let phrases = AssociatedPhraseStore(database: database)
            collections = (try? phrases.collections()) ?? []
            phraseStore = phrases
            applyPhraseSelection(phraseSettings.enabledCollections)
            engine = try KeyboardInputEngine(
                modelURL: url,
                userDatabaseURL: localDirectory.appendingPathComponent("GuanyinmaUser.db"),
                method: methodSettings.method,
                keyboardLayout: layoutSettings.layout,
                tableOptions: methodSettings.options(for: methodSettings.method, virtualKeyboard: true),
                spaceSelectsCandidates: spaceSettings.enabled,
                omitsTones: toneOmissionSettings.enabled,
                associatedPhrases: phrases,
                candidateFilter: CandidateGlyphSupport.shared.canDisplay
            )
            do { try engine?.refreshUserPhrases(from: guanyinmaPhraseData) }
            catch { statusOverride = "Guanyinma 自訂詞同步失敗：\(error.localizedDescription)" }
        } catch {
            loadFailure = String(describing: error)
        }
    }

    /// Only sources the database actually has are passed down, so a stale
    /// stored selection cannot silently widen the query.
    private func applyPhraseSelection(_ selection: Set<String>) {
        guard let phraseStore else { return }
        let enabledInPriorityOrder = collections
            .filter { selection.contains($0.source) }
            .map(\.source)
        guard phraseStore.enabledSources != enabledInPriorityOrder else { return }
        phraseStore.setEnabledSources(enabledInPriorityOrder)
        if engine?.isShowingAssociatedPhrases == true {
            engine?.setAssociatedPhraseSource(phraseStore)
        }
    }

    private func showSettingsPanel() {
        guard settingsPanel == nil, heightEditor == nil else { return }
        keyboardView?.cancelBackspaceRepeat()
        let panel = SettingsPanel(
            inputClicksEnabled: inputClicksEnabled, candidateColor: candidateColor,
            compositionMode: engine?.bopomofoCompositionMode ?? .smart,
            chineseInputMethod: engine?.chineseInputMethod ?? methodSettings.method,
            methodSettings: methodSettings,
            keyboardLayout: engine?.keyboardLayout ?? layoutSettings.layout,
            omitsTones: toneOmissionSettings.enabled,
            layoutProfile: profileSettings.profile,
            keycapArea: profileSettings.keycapArea,
            fontSize: profileSettings.fontSize,
            deleteShiftPosition: profileSettings.deleteShiftPosition
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

    private func beginEditingKeyboardHeight() {
        guard heightEditor == nil, let keyboardView else { return }
        settlingHeightPreview = false
        keyboardView.cancelBackspaceRepeat()
        let editor = KeyboardHeightEditor()
        editor.onDrag = { [weak self] edge, state, y in
            self?.dragKeyboardHeight(edge, state: state, y: y)
        }
        editor.onStep = { [weak self] edge, delta in
            guard let self, heightDrag == nil else { return }
            editKeyboardHeight(keyboardGeometry.moving(edge, by: delta))
        }
        editor.onReset = { [weak self] in
            self?.endKeyboardHeightDrag()
            self?.editKeyboardHeight(KeyboardEdgeGeometry())
        }
        editor.onCancel = { [weak self] in self?.finishEditingKeyboardHeight(save: false) }
        editor.onDone = { [weak self] in self?.finishEditingKeyboardHeight(save: true) }
        editor.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(editor)
        let safeArea = keyboardView.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            editor.topAnchor.constraint(equalTo: safeArea.topAnchor),
            editor.bottomAnchor.constraint(equalTo: safeArea.bottomAnchor),
            editor.leadingAnchor.constraint(equalTo: safeArea.leadingAnchor),
            editor.trailingAnchor.constraint(equalTo: safeArea.trailingAnchor)
        ])
        heightEditor = editor
        applyHeight(currentMetrics)
    }

    private func dragKeyboardHeight(
        _ edge: KeyboardEdgeGeometry.Edge, state: KeyboardHeightEditor.DragPhase, y: CGFloat
    ) {
        switch state {
        case .began:
            guard heightEditor != nil, heightDrag == nil else { return }
            heightDrag = HeightDrag(edge: edge, startY: y, start: keyboardGeometry)
            keyboardView?.setHeightDragPreview(true)
        case .changed, .ended:
            guard let drag = heightDrag, drag.edge == edge else { return }
            let delta = Double(drag.startY - y) / currentMetrics.contentHeight
            UIView.performWithoutAnimation {
                editKeyboardHeight(drag.start.moving(edge, by: delta))
                if state == .ended { endKeyboardHeightDrag() }
            }
        case .cancelled:
            if heightDrag?.edge == edge { endKeyboardHeightDrag() }
        }
    }

    private func endKeyboardHeightDrag() {
        guard heightDrag != nil else { return }
        heightDrag = nil
        applyBottomGap(currentMetrics, geometry: keyboardGeometry)
        keyboardView?.setHeightDragPreview(false)
    }

    private func editKeyboardHeight(_ geometry: KeyboardEdgeGeometry) {
        guard heightEditor != nil, geometry != keyboardGeometry else { return }
        heightDraft[keyboardOrientation] = geometry
        layoutHeightPreview(currentMetrics, geometry: geometry)
        view.layoutIfNeeded()
    }

    private func finishEditingKeyboardHeight(save: Bool) {
        guard let heightEditor else { return }
        if save {
            for (orientation, geometry) in heightDraft {
                heightSettings.setGeometry(geometry, for: orientation)
            }
        }
        heightDraft.removeAll()
        endKeyboardHeightDrag()
        heightEditor.removeFromSuperview()
        self.heightEditor = nil
        settlingHeightPreview = true
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
        if let pendingToneOmission, !engine.hasComposition, !engine.hasPendingPhoneticInput {
            engine.omitsTones = pendingToneOmission
            self.pendingToneOmission = nil
        }
        var state = KeyboardView.State()
        state.reading = engine.usesTouchPhoneticGrid ? engine.touchSmartHostReading : engine.composingText
        state.smartMode = engine.bopomofoCompositionMode == .smart
            && engine.inputMode == .bopomofo
        state.smartCells = engine.touchSmartCells
        state.phoneticPending = engine.hasPendingPhoneticInput
        state.phoneticSpaceFirstTone = engine.phoneticSpaceIsFirstTone
        state.smartEditableCount = engine.touchSmartEditableCount
        state.candidates = engine.displayedCandidates
        state.highlightedIndex = engine.isShowingAssociatedPhrases
            ? -1 : engine.highlightedIndex
        state.pageCount = engine.pageCount
        state.mode = engine.inputMode
        state.chineseInputMethod = engine.chineseInputMethod
        state.keyboardLayout = engine.keyboardLayout
        state.shifted = engine.isShifted
        state.temporaryEnglish = engine.isTemporaryEnglish
        state.statusOverride = statusOverride ?? engine.coreError
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

    private func apply(_ result: KeyboardInput.Result) {
        defer { engine?.acknowledgeHostEffects() }
        if engine?.isTouchSmartComposition == true || !touchHostText.editableText.isEmpty
            || !markedTouchReading.isEmpty {
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

    private func applyTouchSmart(_ result: KeyboardInput.Result) {
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
        let reading = engine?.touchSmartHostReading ?? ""
        if hasMarkedText && (markedTouchReading.isEmpty || reading.isEmpty
                             || !edit.isEmpty || result.deletesBackward) {
            // The marked reading follows ordinary Chinese text. Clear it
            // before inserting an evicted prefix or changing those characters.
            discardMarkedText()
        }
        if !edit.isEmpty || result.deletesBackward {
            mutateDocument {
                for _ in 0..<edit.deleteCount { textDocumentProxy.deleteBackward() }
                if !edit.insertion.isEmpty { textDocumentProxy.insertText(edit.insertion) }
                if result.deletesBackward { textDocumentProxy.deleteBackward() }
            }
        }
        if !reading.isEmpty && reading != markedTouchReading {
            setMarkedReading(reading)
            markedTouchReading = reading
        }
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
        setMarkedReading(reading)
    }

    private func setMarkedReading(_ reading: String) {
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
        markedTouchReading = ""
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
        if key == "HIDE_KEYBOARD" {
            if let engine {
                let handoff = engine.finishCompositionForKeyboardDismissal()
                apply(handoff.result)
                guard handoff.succeeded else { return }
            }
            keyboardView?.cancelBackspaceRepeat()
            // Give a pending marked-text replacement a main-loop turn before
            // requesting dismissal of the remote input view.
            DispatchQueue.main.async { [weak self] in self?.dismissKeyboard() }
            return
        }
        guard let engine else { return }
        if key == "CLOSE_CANDIDATES" {
            apply(engine.closeTouchSmartCandidates())
            return
        }
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
    func settingsPanel(_ panel: SettingsPanel, didChangeKeycapArea area: KeyboardKeycapArea) {
        profileSettings.setKeycapArea(area)
        refreshLayoutOptions()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeFontSize size: KeyboardKeyFontSize) {
        profileSettings.setFontSize(size)
        refreshLayoutOptions()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeDeleteShiftPosition position: KeyboardDeleteShiftPosition) {
        profileSettings.setDeleteShiftPosition(position)
        refreshLayoutOptions()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeLayoutProfile profile: KeyboardLayoutProfile) {
        selectLayoutProfile(profile)
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeInputMethod method: ChineseInputMethod) {
        if let engine {
            apply(engine.setChineseInputMethod(method))
            engine.tableOptions = methodSettings.options(for: method, virtualKeyboard: true)
        }
        methodSettings.setMethod(method)
        refresh()
    }
    func settingsPanelDidChangeTableOptions(_ panel: SettingsPanel) {
        if let engine {
            apply(engine.finishCompositionForInputHandoff())
            engine.tableOptions = methodSettings.options(for: engine.chineseInputMethod, virtualKeyboard: true)
        }
        refresh()
    }

    func settingsPanelResetLearning(_ panel: SettingsPanel) -> Bool {
        CandidateGlyphSupport.shared.reset()
        guard let engine else { return false }
        do {
            try engine.resetLearning()
            discardMarkedText()
            engine.reset()
            touchHostText.reset()
            refresh()
            return true
        } catch {
            return false
        }
    }

    func settingsPanel(
        _ panel: SettingsPanel, didChangeCompositionMode mode: BopomofoCompositionMode
    ) {
        let method: ChineseInputMethod = mode == .smart ? .smart : .traditional
        if let engine { apply(engine.setChineseInputMethod(method)) }
        methodSettings.setMethod(method)
        refresh()
    }

    func settingsPanelDidRequestKeyboardHeight(_ panel: SettingsPanel) {
        guard settingsPanel === panel else { return }
        panel.removeFromSuperview()
        settingsPanel = nil
        beginEditingKeyboardHeight()
    }

    func settingsPanelDidClose(_ panel: SettingsPanel) {
        panel.removeFromSuperview()
        settingsPanel = nil
        applyHeight(currentMetrics)
        refresh()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeKeyboardLayout layout: BopomofoKeyboardLayout) {
        if let engine { apply(engine.setKeyboardLayout(layout)) }
        layoutSettings.setLayout(layout)
        refresh()
    }

    func settingsPanel(_ panel: SettingsPanel, didChangeToneOmission enabled: Bool) {
        toneOmissionSettings.setEnabled(enabled)
        pendingToneOmission = enabled
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

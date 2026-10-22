import KeyKeyEngine
import UIKit

@MainActor
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didPress key: String)
    func keyboardView(_ view: KeyboardView, didSelectCandidateAt index: Int)
    func keyboardView(_ view: KeyboardView, didSelectSmartCellAt index: Int)
    func keyboardView(_ view: KeyboardView, didChangePageBy delta: Int)
}

/// The Bopomofo keyboard: a candidate strip over five equal bands -- four rows
/// of reading keys and a weighted function row. Built from real views rather
/// than a drawn canvas like the Android port, which gets VoiceOver for free and
/// keeps hit testing independent of paint order.
final class KeyboardView: UIView {
    struct State: Equatable {
        var reading = ""
        var smartMode = false
        var smartCells: [String] = []
        var smartEditableCount = 0
        var candidates: [String] = []
        var highlightedIndex = -1
        var pageCount = 0
        var mode = BopomofoEngine.InputMode.bopomofo
        var chineseInputMethod = ChineseInputMethod.smart
        var keyboardLayout = BopomofoKeyboardLayout.standard
        var shifted = false
        var temporaryEnglish = false
        var statusOverride: String?
        var fieldPolicy = InputFieldPolicy.default
        var returnKeyPolicy = ReturnKeyPolicy(hint: .default)
        var inputClicksEnabled = true
        var candidateColor = CandidateColor.purple
        var supportPromptVisible = false

        var showsSmartSupportPrompt: Bool {
            supportPromptVisible && smartMode && chineseInputMethod == .smart
                && reading.isEmpty && smartCells.isEmpty && smartEditableCount == 0
                && candidates.isEmpty && statusOverride == nil
        }
    }

    /// A reading key carries two labels at fixed heights rather than two lines
    /// of one label: the position digit has to sit level across the whole row,
    /// and a two-line label would push it down under an enlarged tone mark.
    private struct KeyView {
        let button: UIButton
        let glyph: UILabel
        let position: UILabel
        let glyphCentre: NSLayoutConstraint
        let positionCentre: NSLayoutConstraint
    }

    weak var delegate: KeyboardViewDelegate?

    private let statusLabel = UILabel()
    private var candidateButtons: [UIButton] = []
    private let previousPageButton = UIButton(type: .system)
    private let nextPageButton = UIButton(type: .system)
    private let candidateStrip = KeyboardRow(spacing: 2)
    private let candidateContainer = UIView()
    private let smartCellStrip = KeyboardRow(spacing: 2)
    private var smartCellButtons: [UIButton] = []
    private var smartCellStripHeight: NSLayoutConstraint?
    private var candidateStripHeight: NSLayoutConstraint?
    private var rootStack: UIStackView?
    private var keyBands: UIStackView?
    private var candidateOverlayConstraints: [NSLayoutConstraint] = []
    private var candidateIsOverlay = false
    private var contentWidthConstraint: NSLayoutConstraint?
    private var keyViews: [[KeyView]] = []
    private var keyRows: [KeyboardRow] = []
    private let functionRow = KeyboardRow()
    private var punctuationButtons: [(key: String, button: UIButton)] = []
    private let dismissButton = UIButton(type: .system)
    private let closeCandidatesButton = UIButton(type: .system)
    private let candidateSpacer = UIView()
    private let smartDismissSpacer = UIView()
    private var bottomContentConstraint: NSLayoutConstraint?
    private struct RowLayout: Equatable {
        let presentation: KeyboardPresentation
        let expanded: Bool
        let needsInputModeSwitch: Bool
    }
    private var appliedRowLayout: RowLayout?
    private var presentation = KeyboardPresentation.full
    private var functionButtons: [(key: String, button: UIButton)] = []
    private let backspaceRepeater = BackspaceRepeater()
    private var backspaceTouchActive = false

    func cancelBackspaceRepeat() {
        backspaceRepeater.stop()
        backspaceTouchActive = false
        hideKeyPreview()
    }
    private let keyPreview = UILabel()
    private var state = State()
    private var metrics = KeyboardMetrics.portrait
    private var enterIconSide: Double = 0
    private var needsInputModeSwitch: Bool
    /// Left for the controller to wire to `handleInputModeList`, which gives
    /// the key the system behaviour: tap advances, long press opens the
    /// keyboard picker. Kept alive when hidden so host changes can reveal it.
    private(set) var inputModeSwitchButton: UIButton?

    init(needsInputModeSwitch: Bool) {
        self.needsInputModeSwitch = needsInputModeSwitch
        super.init(frame: .zero)
        backgroundColor = Palette.background
        buildInterface()
        updateRowLayout()
        apply(State(), force: true)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // MARK: - Construction

    private func buildInterface() {
        // Five equal bands below the strip, matching the Android division of
        // the remaining height.
        let bands = UIStackView(arrangedSubviews: buildKeyRows() + [buildFunctionRow()])
        keyBands = bands
        bands.axis = .vertical
        bands.distribution = .fillEqually
        bands.spacing = 3

        let root = UIStackView(arrangedSubviews: [
            buildSmartCellStrip(), buildCandidateStrip(), bands
        ])
        rootStack = root
        root.axis = .vertical
        root.spacing = 3
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        // The keyboard has its own safe area, which can differ from the host
        // app's. Respect each edge independently as the host resizes or moves it.
        let guide = safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -3),
            root.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            root.topAnchor.constraint(equalTo: guide.topAnchor, constant: 3)
        ])
        let bottom = root.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -3)
        bottom.isActive = true
        bottomContentConstraint = bottom
        // Candidate titles have different intrinsic widths (for example the
        // anime collection offers 「的名字」 after 「你」). Without an explicit
        // fill width, those titles resize all eleven key columns when the
        // candidate strip appears and the keyboard shrinks again when it is
        // dismissed. Priority 999 fills a phone while still allowing the
        // required maximum below to cap regular-width layouts.
        let fillWidth = root.widthAnchor.constraint(equalTo: guide.widthAnchor, constant: -6)
        fillWidth.priority = UILayoutPriority(999)
        fillWidth.isActive = true
        let contentWidth = root.widthAnchor.constraint(
            lessThanOrEqualToConstant: metrics.maximumContentWidth
        )
        contentWidth.isActive = true
        contentWidthConstraint = contentWidth

        keyPreview.backgroundColor = Palette.primaryText
        keyPreview.textColor = Palette.normalKey
        keyPreview.textAlignment = .center
        keyPreview.font = .systemFont(ofSize: 28, weight: .medium)
        keyPreview.layer.cornerRadius = 12
        keyPreview.layer.masksToBounds = true
        keyPreview.isHidden = true
        keyPreview.isUserInteractionEnabled = false
        addSubview(keyPreview)
    }

    private func buildCandidateStrip() -> UIView {
        configurePageButton(previousPageButton, title: "▲", label: "上一頁", delta: -1)
        configurePageButton(nextPageButton, title: "▼", label: "下一頁", delta: 1)
        closeCandidatesButton.backgroundColor = Palette.specialKey
        closeCandidatesButton.layer.cornerRadius = 6
        closeCandidatesButton.setTitle("×", for: .normal)
        closeCandidatesButton.setTitleColor(Palette.primaryText, for: .normal)
        closeCandidatesButton.accessibilityIdentifier = "keyboard.candidates.close"
        closeCandidatesButton.accessibilityLabel = "關閉候選"
        closeCandidatesButton.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        closeCandidatesButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        candidateSpacer.addSubview(closeCandidatesButton)

        candidateButtons = (0..<BopomofoEngine.candidatesPerPage).map { index in
            let button = UIButton(type: .system)
            button.backgroundColor = Palette.candidateCell
            button.layer.cornerRadius = 6
            button.titleLabel?.numberOfLines = 2
            button.titleLabel?.textAlignment = .center
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.tag = index
            button.addTarget(self, action: #selector(candidateTapped(_:)), for: .touchUpInside)
            return button
        }

        candidateStrip.configure([previousPageButton] + candidateButtons + [nextPageButton])

        statusLabel.textColor = Palette.hintText
        statusLabel.accessibilityIdentifier = "keyboard.status"
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7

        let container = candidateContainer
        container.backgroundColor = Palette.background
        // Keep status text below the strip: in expanded split mode its last
        // slot remains an interactive hide control even with no candidates.
        for child in [statusLabel, candidateStrip] as [UIView] {
            child.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(child)
            NSLayoutConstraint.activate([
                child.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                child.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                child.topAnchor.constraint(equalTo: container.topAnchor),
                child.bottomAnchor.constraint(equalTo: container.bottomAnchor)
            ])
        }

        // A horizontal drag across the strip pages, matching the Android swipe.
        container.addGestureRecognizer(
            UIPanGestureRecognizer(target: self, action: #selector(candidatePanned(_:)))
        )

        let height = container.heightAnchor.constraint(
            equalToConstant: metrics.candidateStripHeight
        )
        height.isActive = true
        candidateStripHeight = height
        return container
    }

    private func buildSmartCellStrip() -> UIView {
        smartCellButtons = (0..<11).map { index in
            let button = UIButton(type: .system)
            button.tag = index
            button.accessibilityIdentifier = "keyboard.smart-cell.\(index + 1)"
            button.backgroundColor = Palette.candidateCell
            button.layer.cornerRadius = 6
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.5
            button.addTarget(self, action: #selector(smartCellTapped(_:)), for: .touchUpInside)
            return button
        }
        smartCellStrip.configure(smartCellButtons)
        dismissButton.backgroundColor = Palette.specialKey
        dismissButton.layer.cornerRadius = 6
        dismissButton.setTitle("▼", for: .normal)
        dismissButton.setTitleColor(Palette.primaryText, for: .normal)
        dismissButton.accessibilityIdentifier = "keyboard.dismiss"
        dismissButton.accessibilityLabel = "收起鍵盤"
        dismissButton.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
        dismissButton.autoresizingMask = [.flexibleWidth, .flexibleHeight]
        let height = smartCellStrip.heightAnchor.constraint(
            equalToConstant: metrics.candidateStripHeight
        )
        height.isActive = true
        smartCellStripHeight = height
        return smartCellStrip
    }

    private func buildKeyRows() -> [UIView] {
        (0..<4).map { rowIndex in
            let stack = KeyboardRow()
            var keys: [KeyView] = []
            for columnIndex in 0..<11 {
                let button = UIButton(type: .system)
                button.layer.cornerRadius = 6
                button.tag = rowIndex * 100 + columnIndex
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                installPreviewHandlers(on: button)
                keys.append(makeKeyView(button))
            }
            keyViews.append(keys)
            stack.configure(keys.map(\.button))
            keyRows.append(stack)
            let punctuation = ExpandedSplitKeyboardLayout.punctuation[rowIndex]
            let button = UIButton(type: .system)
            button.layer.cornerRadius = 6
            button.backgroundColor = Palette.specialKey
            button.setTitleColor(Palette.primaryText, for: .normal)
            button.accessibilityIdentifier = "keyboard.split.punctuation.\(rowIndex)"
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            installPreviewHandlers(on: button)
            punctuationButtons.append((punctuation, button))
            return stack
        }
    }

    private func makeKeyView(_ button: UIButton) -> KeyView {
        let glyph = keyLabel()
        let position = keyLabel()
        let glyphCentre = glyph.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        let positionCentre = position.centerYAnchor.constraint(equalTo: button.centerYAnchor)
        for label in [glyph, position] {
            button.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: button.centerXAnchor),
                label.leadingAnchor.constraint(
                    greaterThanOrEqualTo: button.leadingAnchor, constant: 1
                ),
                label.trailingAnchor.constraint(
                    lessThanOrEqualTo: button.trailingAnchor, constant: -1
                )
            ])
        }
        NSLayoutConstraint.activate([glyphCentre, positionCentre])
        return KeyView(
            button: button, glyph: glyph, position: position,
            glyphCentre: glyphCentre, positionCentre: positionCentre
        )
    }

    private func keyLabel() -> UILabel {
        let label = UILabel()
        label.textAlignment = .center
        label.adjustsFontSizeToFitWidth = true
        label.minimumScaleFactor = 0.6
        label.translatesAutoresizingMaskIntoConstraints = false
        return label
    }

    /// Each half gets a space key in split mode; both send the same engine action.
    private func buildFunctionRow() -> UIView {
        var keys = KeyboardLayout.functionRow(withInputModeSwitch: true)
        let splitIndex = keys.firstIndex(of: "SPACE")! + 1
        keys.insert("SPACE", at: splitIndex)
        for (index, key) in keys.enumerated() {
            let button = UIButton(type: .system)
            button.backgroundColor = Palette.specialKey
            button.tintColor = Palette.primaryText
            button.layer.cornerRadius = 6
            button.setTitleColor(Palette.primaryText, for: .normal)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.accessibilityIdentifier = index == splitIndex ? "keyboard.space.right" : key
            if key == KeyboardLayout.inputModeSwitchKey {
                inputModeSwitchButton = button
            } else if key == "BACKSPACE" {
                button.addTarget(self, action: #selector(backspaceTouchDown), for: .touchDown)
                button.addTarget(self, action: #selector(backspaceTouchUpInside), for: .touchUpInside)
                button.addTarget(
                    self, action: #selector(backspaceTouchEnded),
                    for: [.touchUpOutside, .touchCancel]
                )
                button.addTarget(self, action: #selector(backspaceTouchExited), for: .touchDragExit)
                installPreviewHandlers(on: button)
            } else {
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                installPreviewHandlers(on: button)
            }
            functionButtons.append((key, button))
        }
        return functionRow
    }

    private func configurePageButton(
        _ button: UIButton, title: String, label: String, delta: Int
    ) {
        button.setTitle(title, for: .normal)
        button.setTitleColor(Palette.hintText, for: .normal)
        button.backgroundColor = Palette.specialKey
        button.layer.cornerRadius = 6
        button.accessibilityLabel = label
        button.tag = delta
        button.addTarget(self, action: #selector(pageTapped(_:)), for: .touchUpInside)
    }

    // MARK: - State

    private func setCandidateOverlay(_ enabled: Bool) {
        guard enabled != candidateIsOverlay,
              let rootStack, let firstKeyRow = keyBands?.arrangedSubviews.first
        else { return }
        candidateIsOverlay = enabled
        if enabled {
            candidateStripHeight?.isActive = false
            rootStack.removeArrangedSubview(candidateContainer)
            candidateContainer.removeFromSuperview()
            candidateContainer.translatesAutoresizingMaskIntoConstraints = false
            addSubview(candidateContainer)
            candidateOverlayConstraints = [
                candidateContainer.leadingAnchor.constraint(equalTo: firstKeyRow.leadingAnchor),
                candidateContainer.trailingAnchor.constraint(equalTo: firstKeyRow.trailingAnchor),
                candidateContainer.topAnchor.constraint(equalTo: firstKeyRow.topAnchor),
                candidateContainer.bottomAnchor.constraint(equalTo: firstKeyRow.bottomAnchor)
            ]
            NSLayoutConstraint.activate(candidateOverlayConstraints)
        } else {
            NSLayoutConstraint.deactivate(candidateOverlayConstraints)
            candidateOverlayConstraints = []
            candidateContainer.removeFromSuperview()
            rootStack.insertArrangedSubview(candidateContainer, at: 1)
            candidateStripHeight?.isActive = true
        }
    }

    func setPresentation(_ presentation: KeyboardPresentation) {
        guard presentation != self.presentation else { return }
        self.presentation = presentation
        cancelBackspaceRepeat()
        updateRowLayout()
    }

    func setNeedsInputModeSwitch(_ needed: Bool) {
        guard needed != needsInputModeSwitch else { return }
        needsInputModeSwitch = needed
        updateRowLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRowLayout()
    }

    private func updateCandidateVisibility() {
        let hasCandidates = !state.candidates.isEmpty
        let expanded = appliedRowLayout?.expanded == true
        candidateStrip.isHidden = !hasCandidates && !expanded
        (candidateButtons + [previousPageButton, nextPageButton]).forEach { $0.isHidden = !hasCandidates }
        let slot = state.smartMode ? smartDismissSpacer : candidateSpacer
        if dismissButton.superview !== slot {
            dismissButton.removeFromSuperview()
            dismissButton.frame = slot.bounds
            slot.addSubview(dismissButton)
        }
        dismissButton.isHidden = !expanded
        closeCandidatesButton.isHidden = !expanded || !state.smartMode || !hasCandidates
    }

    private func updateRowLayout() {
        let split = presentation == .split
        let expanded = split && !metrics.isCompactHeight
            && safeAreaLayoutGuide.layoutFrame.width >= ExpandedSplitKeyboardLayout.minimumWidth
        let next = RowLayout(presentation: presentation, expanded: expanded,
                             needsInputModeSwitch: needsInputModeSwitch)
        guard next != appliedRowLayout else { return }
        appliedRowLayout = next
        cancelBackspaceRepeat()
        for (index, row) in keyRows.enumerated() {
            var buttons = keyViews[index].map(\.button)
            if expanded { buttons.insert(punctuationButtons[index].button, at: 5) }
            row.configure(buttons, splitIndex: split ? (expanded ? 6 : 5) : nil)
        }
        // Eleven composition cells, six on the left and five on the right.
        // The twelfth slot is an independent dismissal control, not another cell.
        smartCellStrip.configure(smartCellButtons + (expanded ? [smartDismissSpacer] : []),
                                 splitIndex: split ? 6 : nil)
        let candidates: [UIView] = [previousPageButton] + candidateButtons + [nextPageButton]
        candidateStrip.configure(candidates + (expanded ? [candidateSpacer] : []),
                                 splitIndex: split ? (expanded ? 6 : 5) : nil)
        let visible = functionButtons.filter { key, button in
            if key == KeyboardLayout.inputModeSwitchKey { return needsInputModeSwitch }
            if button.accessibilityIdentifier == "keyboard.space.right" { return split }
            return !expanded || (key != "，" && key != "。")
        }
        let weights = visible.map { item in
            expanded ? ExpandedSplitKeyboardLayout.functionWeight(for: item.key)
                : KeyboardLayout.weight(for: item.key)
        }
        let functionSplit = split ? visible.firstIndex { $0.key == "SPACE" }.map { $0 + 1 } : nil
        functionRow.configure(visible.map(\.button), weights: weights, splitIndex: functionSplit)
        // Align to the usable bottom edge, retaining the system's safe area.
        bottomContentConstraint?.constant = expanded ? 0 : -3
        updateCandidateVisibility()
        setNeedsLayout()
    }

    func setMetrics(_ metrics: KeyboardMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
        candidateStripHeight?.constant = metrics.candidateStripHeight
        smartCellStripHeight?.constant = metrics.candidateStripHeight
        contentWidthConstraint?.constant = metrics.maximumContentWidth
        apply(state, force: true)
    }

    func apply(_ nextState: State, force: Bool = false) {
        let previousState = state
        state = nextState
        setCandidateOverlay(state.smartMode)
        if state.smartMode != previousState.smartMode { setNeedsLayout() }
        updateCandidateVisibility()

        let hasCandidates = !state.candidates.isEmpty
        let hadCandidates = !previousState.candidates.isEmpty
        if force || hasCandidates != hadCandidates
            || state.reading != previousState.reading
            || state.mode != previousState.mode
            || state.keyboardLayout != previousState.keyboardLayout
            || state.chineseInputMethod != previousState.chineseInputMethod
            || state.shifted != previousState.shifted
            || state.temporaryEnglish != previousState.temporaryEnglish
            || state.statusOverride != previousState.statusOverride
            || state.supportPromptVisible != previousState.supportPromptVisible {
            statusLabel.isHidden = hasCandidates
            statusLabel.font = .systemFont(ofSize: metrics.statusFont)
            let normalStatus = state.chineseInputMethod.isTable && state.mode == .bopomofo && state.reading.isEmpty
                ? state.chineseInputMethod.displayName : KeyboardLayout.statusText(
                reading: state.reading, mode: state.mode, shifted: state.shifted,
                temporaryEnglish: state.temporaryEnglish, layout: state.keyboardLayout
            )
            if state.statusOverride == nil, state.supportPromptVisible,
               state.reading.isEmpty, state.mode == .bopomofo {
                statusLabel.text = "\(normalStatus)　歡迎付費支持"
            } else {
                statusLabel.text = state.statusOverride ?? normalStatus
            }
        }

        smartCellStrip.isHidden = !state.smartMode
        candidateContainer.isHidden = state.smartMode && !hasCandidates
        if force || state.smartCells != previousState.smartCells
            || state.smartEditableCount != previousState.smartEditableCount
            || state.smartMode != previousState.smartMode
            || state.showsSmartSupportPrompt != previousState.showsSmartSupportPrompt {
            for (index, button) in smartCellButtons.enumerated() {
                let isSupportCell = state.showsSmartSupportPrompt && index >= 8
                let value = isSupportCell ? ["歡迎", "付費", "支持"][index - 8]
                    : index < state.smartCells.count ? state.smartCells[index] : ""
                button.setTitle(value, for: .normal)
                button.setTitleColor(Palette.primaryText, for: .normal)
                button.setTitleColor(isSupportCell ? Palette.hintText : nil, for: .disabled)
                button.titleLabel?.font = .systemFont(
                    ofSize: isSupportCell ? metrics.statusFont : metrics.candidateFont
                )
                button.isEnabled = !isSupportCell
                    && index < state.smartEditableCount && !value.isEmpty
                button.accessibilityTraits = isSupportCell ? .staticText : .button
                button.accessibilityLabel = isSupportCell ? value : button.isEnabled
                    ? "第 \(index + 1) 個組字，\(value)" : nil
                button.isAccessibilityElement = button.isEnabled || isSupportCell
            }
        }

        if force || state.candidates != previousState.candidates
            || state.highlightedIndex != previousState.highlightedIndex
            || state.candidateColor != previousState.candidateColor {
            for (index, button) in candidateButtons.enumerated() {
                let candidate = index < state.candidates.count ? state.candidates[index] : nil
                let highlighted = index == state.highlightedIndex
                button.isEnabled = candidate != nil
                button.setAttributedTitle(candidate.map {
                    candidateTitle($0, index: index, highlighted: highlighted)
                }, for: .normal)
                button.backgroundColor = highlighted
                    ? Palette.candidateHighlight(for: state.candidateColor)
                    : Palette.candidateCell
                button.accessibilityLabel = candidate.map { "第 \(index + 1) 個候選，\($0)" }
                // An empty cell stays laid out to keep the strip's spacing, but it
                // must leave the accessibility tree: an unlabelled button is a stop
                // VoiceOver announces with nothing to say.
                button.isAccessibilityElement = candidate != nil
            }
        }
        if force || state.pageCount != previousState.pageCount {
            for button in [previousPageButton, nextPageButton] {
                button.titleLabel?.font = .systemFont(ofSize: metrics.pageFont)
                button.isEnabled = state.pageCount > 1
            }
        }

        let keyPlaneChanged = force
            || state.keyboardLayout != previousState.keyboardLayout
            || state.chineseInputMethod != previousState.chineseInputMethod
            || state.mode != previousState.mode
            || state.shifted != previousState.shifted
            || state.temporaryEnglish != previousState.temporaryEnglish
            || state.fieldPolicy != previousState.fieldPolicy
        if keyPlaneChanged {
            let rows = KeyboardLayout.rows(mode: state.mode, shifted: state.shifted)
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, key) in row.enumerated() {
                    let keyView = keyViews[rowIndex][columnIndex]
                    keyView.button.accessibilityIdentifier = key
                    keyView.button.backgroundColor = KeyboardLayout.isSpecial(key)
                        ? Palette.specialKey : Palette.normalKey
                    keyView.button.accessibilityLabel = accessibilityLabel(for: key)
                    let enabled = state.fieldPolicy.isKeyEnabled(
                        key, mode: state.mode, shifted: state.shifted
                    )
                    keyView.button.isEnabled = enabled
                    keyView.button.alpha = enabled ? 1 : 0.36
                    configure(keyView, for: key)
                }
            }
        }

        if keyPlaneChanged || state.returnKeyPolicy != previousState.returnKeyPolicy {
            for button in [dismissButton, closeCandidatesButton] {
                button.titleLabel?.font = .systemFont(ofSize: metrics.pageFont)
            }
            for (key, button) in functionButtons + punctuationButtons {
                button.accessibilityLabel = accessibilityLabel(for: key)
                let enabled = state.fieldPolicy.isKeyEnabled(
                    key, mode: state.mode, shifted: state.shifted
                )
                button.isEnabled = enabled
                button.alpha = enabled ? 1 : 0.36
                if key == "ENTER" {
                    applyEnterAppearance(to: button)
                    continue
                }
                if key == KeyboardLayout.inputModeSwitchKey {
                    button.setTitle(nil, for: .normal)
                    button.setImage(UIImage(systemName: "globe"), for: .normal)
                    continue
                }
                let caption = key == "MODE"
                    ? state.fieldPolicy.modeCaption(for: state.mode).replacingOccurrences(of: "ㄅ", with: state.chineseInputMethod.symbol)
                    : KeyboardLayout.caption(for: key, mode: state.mode)
                button.setTitle(caption, for: .normal)
                button.titleLabel?.font = .systemFont(
                    ofSize: caption.count > 3 ? metrics.functionFontSmall : metrics.functionFont
                )
            }
        }
    }

    /// The host supplies the intended action through `returnKeyType`. The
    /// default action retains the shared Android/iOS arrow; all others receive
    /// a short textual purpose such as 「搜尋」 or 「下一個」.
    private func applyEnterAppearance(to button: UIButton) {
        if let title = state.returnKeyPolicy.title {
            button.setImage(nil, for: .normal)
            button.setTitle(title, for: .normal)
            button.titleLabel?.font = .systemFont(
                ofSize: metrics.functionFontSmall, weight: .semibold
            )
            enterIconSide = 0
            return
        }
        let side = metrics.functionFont * 1.3
        guard side != enterIconSide else { return }
        button.setTitle(nil, for: .normal)
        button.setImage(EnterGlyph.image(side: side), for: .normal)
        enterIconSide = side
    }

    private func candidateTitle(
        _ candidate: String, index: Int, highlighted: Bool
    ) -> NSAttributedString {
        let colour = highlighted
            ? Palette.candidateHighlightText(for: state.candidateColor)
            : Palette.primaryText
        let title = NSMutableAttributedString(
            string: candidate,
            attributes: [
                .font: UIFont.systemFont(ofSize: metrics.candidateFont),
                .foregroundColor: colour
            ]
        )
        title.append(NSAttributedString(
            string: "\n\(index + 1)",
            attributes: [
                .font: UIFont.systemFont(ofSize: metrics.candidateIndexFont),
                .foregroundColor: highlighted
                    ? Palette.candidateHighlightText(for: state.candidateColor)
                    : Palette.hintText
            ]
        ))
        return title
    }

    /// Reading keys carry the Bopomofo glyph and the physical key position.
    /// Temporary English swaps them so the Latin letter reads first.
    ///
    /// Both labels sit at heights derived from the two type sizes, never from
    /// the glyph actually drawn, so the position digits stay level across the
    /// row even where the glyph above them is a tone mark drawn half again as
    /// large. Anything without a second label -- English, digits, symbols,
    /// punctuation -- centres in the key instead.
    private func inputGlyph(for key: String) -> String? {
        state.chineseInputMethod.isTable ? ChineseInputMethod.root(for: key)
            : KeyboardLayout.bopomofoGlyph(for: key, layout: state.keyboardLayout)
    }

    private func configure(_ keyView: KeyView, for key: String) {
        let caption = KeyboardLayout.caption(for: key, mode: state.mode)
        guard state.mode == .bopomofo,
              let glyph = inputGlyph(for: key)
        else {
            keyView.glyph.text = caption
            keyView.glyph.font = .systemFont(
                ofSize: caption.count > 2 ? metrics.functionFontSmall : metrics.keyGlyphFont
            )
            keyView.glyph.textColor = Palette.primaryText
            keyView.glyphCentre.constant = 0
            keyView.position.isHidden = true
            return
        }

        guard metrics.stacksKeyLabels else {
            // Landscape has no vertical room for two rows of labels, so both
            // read on one line, as they do on Android.
            let pair = state.temporaryEnglish ? "\(key) \(glyph)" : "\(glyph) \(key)"
            keyView.glyph.text = pair
            keyView.glyph.font = .systemFont(ofSize: metrics.keyGlyphFont)
            keyView.glyph.textColor = Palette.primaryText
            keyView.glyphCentre.constant = 0
            keyView.position.isHidden = true
            return
        }

        let scale = state.temporaryEnglish || state.chineseInputMethod.isTable ? 1 : KeyboardLayout.glyphPointScale(for: key)
        let glyphSize = metrics.keyGlyphFont * scale
        keyView.glyph.text = state.temporaryEnglish ? key : glyph
        keyView.glyph.font = .systemFont(ofSize: glyphSize)
        keyView.glyph.textColor = Palette.primaryText
        // A tone mark's ink sits high in its em box, so an enlarged one needs
        // pushing down to draw at the same height as a letter.
        keyView.glyphCentre.constant = -(metrics.keyHintFont * 1.2) / 2
            + (glyphSize - metrics.keyGlyphFont) * 0.25

        keyView.position.isHidden = false
        keyView.position.text = state.temporaryEnglish ? glyph : key
        keyView.position.font = .systemFont(ofSize: metrics.keyHintFont)
        keyView.position.textColor = Palette.hintText
        keyView.positionCentre.constant = (metrics.keyGlyphFont * 1.2) / 2
    }

    private func accessibilityLabel(for key: String) -> String {
        switch key {
        case "MODE": return "切換輸入模式"
        case "SYMBOL": return "符號"
        case "SETTINGS": return "設定"
        case "SPACE": return "空白鍵"
        case "BACKSPACE": return "刪除"
        case "ENTER": return state.returnKeyPolicy.accessibilityLabel
        case "SHIFT": return "Shift"
        case "EMOJI": return "表情符號"
        case KeyboardLayout.inputModeSwitchKey: return "下一個鍵盤"
        default:
            if state.mode == .bopomofo,
               let glyph = inputGlyph(for: key) {
                return glyph
            }
            return key
        }
    }

    // MARK: - Actions

    private func actionKey(for button: UIButton) -> String? {
        if button === dismissButton { return "HIDE_KEYBOARD" }
        if button === closeCandidatesButton { return "CLOSE_CANDIDATES" }
        return (functionButtons + punctuationButtons).first { $0.button === button }?.key
            ?? button.accessibilityIdentifier
    }

    @objc private func keyTapped(_ sender: UIButton) {
        guard let key = actionKey(for: sender) else { return }
        hideKeyPreview()
        playInputClick()
        delegate?.keyboardView(self, didPress: key)
    }

    @objc private func backspaceTouchDown(_ sender: UIButton) {
        guard sender.isEnabled else { return }
        backspaceTouchActive = true
        playInputClick()
        delegate?.keyboardView(self, didPress: "BACKSPACE")
        backspaceRepeater.start { [weak self] in
            guard let self else { return }
            self.delegate?.keyboardView(self, didPress: "BACKSPACE")
        }
    }

    @objc private func backspaceTouchUpInside() {
        // Accessibility activation can produce an up action without touch down.
        if !backspaceTouchActive {
            playInputClick()
            delegate?.keyboardView(self, didPress: "BACKSPACE")
        }
        backspaceTouchEnded()
    }

    @objc private func backspaceTouchEnded() {
        cancelBackspaceRepeat()
    }

    @objc private func backspaceTouchExited() {
        backspaceRepeater.stop()
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        if window == nil { cancelBackspaceRepeat() }
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        playInputClick()
        delegate?.keyboardView(self, didSelectCandidateAt: sender.tag)
    }

    @objc private func smartCellTapped(_ sender: UIButton) {
        guard sender.isEnabled else { return }
        delegate?.keyboardView(self, didSelectSmartCellAt: sender.tag)
    }

    @objc private func pageTapped(_ sender: UIButton) {
        playInputClick()
        delegate?.keyboardView(self, didChangePageBy: sender.tag)
    }

    @objc private func candidatePanned(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .ended, !state.candidates.isEmpty else { return }
        let dx = gesture.translation(in: self).x
        guard abs(dx) > 38 else { return }
        // Dragging left moves forward, matching the Android strip.
        delegate?.keyboardView(self, didChangePageBy: dx < 0 ? 1 : -1)
    }

    // MARK: - Press feedback

    private func installPreviewHandlers(on button: UIButton) {
        button.addTarget(self, action: #selector(previewTouchDown(_:)), for: .touchDown)
        button.addTarget(
            self, action: #selector(previewTouchEnded),
            for: [.touchUpOutside, .touchCancel, .touchDragExit]
        )
    }

    @objc private func previewTouchDown(_ sender: UIButton) {
        guard sender.isEnabled, let key = actionKey(for: sender) else { return }
        showKeyPreview(previewText(for: key), from: sender)
    }

    @objc private func previewTouchEnded() {
        hideKeyPreview()
    }

    private func previewText(for key: String) -> String {
        if key == "MODE" {
            return state.fieldPolicy.modePreviewCaption(
                for: state.mode, temporaryEnglish: state.temporaryEnglish
            )
        }
        if key == "SHIFT" {
            return state.fieldPolicy.shiftPreviewCaption(
                for: state.mode, shifted: state.shifted,
                temporaryEnglish: state.temporaryEnglish
            )
        }
        if key == "ENTER" { return state.returnKeyPolicy.accessibilityLabel }
        if state.mode == .bopomofo,
           let glyph = inputGlyph(for: key) {
            return state.temporaryEnglish ? key.uppercased() : glyph
        }
        return KeyboardLayout.caption(for: key, mode: state.mode)
    }

    private func showKeyPreview(_ text: String, from button: UIButton) {
        guard !text.isEmpty else { return }
        layoutIfNeeded()
        let keyFrame = button.convert(button.bounds, to: self)
        let width = max(
            56, min(116, text.size(withAttributes: [.font: keyPreview.font!]).width + 28)
        )
        let height: CGFloat = 62
        keyPreview.text = text
        keyPreview.frame = CGRect(
            x: min(max(3, keyFrame.midX - width / 2), bounds.width - width - 3),
            y: max(3, keyFrame.minY - height - 6), width: width, height: height
        )
        keyPreview.isHidden = false
        bringSubviewToFront(keyPreview)
    }

    private func hideKeyPreview() {
        keyPreview.isHidden = true
    }

    private func playInputClick() {
        guard state.inputClicksEnabled else { return }
        UIDevice.current.playInputClick()
    }
}

// A keyboard extension may play the standard click without Full Access.
extension KeyboardView: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { state.inputClicksEnabled }
}

/// Frames only change the placement of existing controls, preserving targets,
/// accessibility, backspace repeat and the active composition during a switch.
@MainActor
private final class KeyboardRow: UIView {
    private let spacing: Double
    private var items: [UIView] = []
    private var weights: [Double] = []
    private var splitIndex: Int?

    init(spacing: Double = 3) {
        self.spacing = spacing
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ items: [UIView], weights: [Double]? = nil, splitIndex: Int? = nil) {
        self.items.forEach { $0.removeFromSuperview() }
        self.items = items
        self.weights = weights ?? Array(repeating: 1, count: items.count)
        self.splitIndex = splitIndex
        items.forEach(addSubview)
        setNeedsLayout()
    }

    // Preserve a fitting height for the keyboard host even though the children
    // use frames. Compact-height constraints may compress this preferred size.
    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 44)
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let frames = KeyboardRowGeometry.frames(
            width: bounds.width, height: bounds.height, weights: weights,
            splitIndex: splitIndex, spacing: spacing
        )
        for (item, frame) in zip(items, frames) { item.frame = frame }
    }
}

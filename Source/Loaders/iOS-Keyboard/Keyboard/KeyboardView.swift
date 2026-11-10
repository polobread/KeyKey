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
        var mode = KeyboardInput.InputMode.bopomofo
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

        var usesPinyin: Bool {
            mode == .bopomofo && !chineseInputMethod.isTable && keyboardLayout == .hanyuPinyin
        }

        var showsPinyinFirstTone: Bool {
            usesPinyin && !reading.isEmpty && candidates.isEmpty
        }

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
        let button: KeyboardKeyButton
        var glyph: UILabel { button.glyph }
        var position: UILabel { button.hint }
    }

    weak var delegate: KeyboardViewDelegate?

    private let statusLabel = KeyboardStatusLabel()
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
        let profile: KeyboardLayoutProfile
        let plane: KeyboardLayoutProfile.Plane
        let needsInputModeSwitch: Bool
        let deleteShiftPosition: KeyboardDeleteShiftPosition
    }
    private var appliedRowLayout: RowLayout?
    private var layoutProfile: KeyboardLayoutProfile
    private var layoutOrientation = KeyboardLayoutProfile.Orientation.portrait
    private var keycapArea: KeyboardKeycapArea
    private var keyFontSize: KeyboardKeyFontSize
    private var deleteShiftPosition: KeyboardDeleteShiftPosition
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

    init(needsInputModeSwitch: Bool, layoutProfile: KeyboardLayoutProfile = .standard,
         keycapArea: KeyboardKeycapArea = .small,
         fontSize: KeyboardKeyFontSize = .normal,
         deleteShiftPosition: KeyboardDeleteShiftPosition = .aboveEnter) {
        self.layoutProfile = layoutProfile
        self.keycapArea = keycapArea
        self.keyFontSize = fontSize
        self.deleteShiftPosition = deleteShiftPosition
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
        bands.spacing = layoutProfile.keySpacing

        let root = UIStackView(arrangedSubviews: [
            buildSmartCellStrip(), buildCandidateStrip(), bands
        ])
        rootStack = root
        root.axis = .vertical
        root.spacing = layoutProfile.keySpacing
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

        candidateButtons = (0..<KeyboardInput.candidatesPerPage).map { index in
            let button = KeyboardStripButton(type: .system)
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
        // Keep status text below the strip: in split mode its last
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
        smartCellButtons = makeSmartCellButtons()
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

    private func makeSmartCellButtons() -> [UIButton] {
        return (0..<layoutProfile.compositionCellCount).map { index in
            let button = KeyboardStripButton(type: .system)
            button.tag = index
            button.accessibilityIdentifier = "keyboard.smart-cell.\(index + 1)"
            button.backgroundColor = Palette.candidateCell
            button.layer.cornerRadius = 6
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.5
            button.addTarget(self, action: #selector(smartCellTapped(_:)), for: .touchUpInside)
            return button
        }
    }

    private func buildKeyRows() -> [UIView] {
        currentKeyRows.enumerated().map { rowIndex, row in
            let stack = KeyboardRow()
            var keys: [KeyView] = []
            for columnIndex in row.indices {
                let button = KeyboardKeyButton(type: .system)
                button.usesGlyphLabels = true
                button.tag = rowIndex * 100 + columnIndex
                button.addTarget(self, action: #selector(mainKeyTouchDown(_:)), for: .touchDown)
                button.addTarget(self, action: #selector(mainKeyTouchUpInside(_:)), for: .touchUpInside)
                button.addTarget(self, action: #selector(mainKeyTouchEnded),
                    for: [.touchUpOutside, .touchCancel])
                button.addTarget(self, action: #selector(mainKeyTouchExited), for: .touchDragExit)
                keys.append(KeyView(button: button))
            }
            keyViews.append(keys)
            stack.configure(keys.map(\.button))
            keyRows.append(stack)
            let punctuation = layoutProfile.splitGeometry?.punctuation
            let key = punctuation.flatMap { $0.indices.contains(rowIndex) ? $0[rowIndex] : nil } ?? ""
            let button = KeyboardKeyButton(type: .system)
            button.keycap.backgroundColor = Palette.specialKey
            button.setTitleColor(Palette.primaryText, for: .normal)
            button.accessibilityIdentifier = "keyboard.split.punctuation.\(rowIndex)"
            button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
            installPreviewHandlers(on: button)
            punctuationButtons.append((key, button))
            return stack
        }
    }

    /// Each half gets a space key in split mode; both send the same engine action.
    private func buildFunctionRow() -> UIView {
        var keys = KeyboardLayoutProfile.available.flatMap(\.functionKeys).reduce(into: [String]()) {
            if !$0.contains($1) { $0.append($1) }
        }
        if !keys.contains("SHIFT") { keys.append("SHIFT") }
        keys.insert(KeyboardLayout.inputModeSwitchKey, at: 0)
        let splitIndex = keys.firstIndex(of: "SPACE")! + 1
        keys.insert("SPACE", at: splitIndex)
        for (index, key) in keys.enumerated() {
            let button = KeyboardKeyButton(type: .system)
            button.keycap.backgroundColor = Palette.specialKey
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

    func setLayoutProfile(_ profile: KeyboardLayoutProfile) {
        guard profile != layoutProfile else { return }
        cancelBackspaceRepeat()
        let rebuild = layoutProfile.placements(for: layoutOrientation) != profile.placements(for: layoutOrientation)
            || layoutProfile.splitGeometry != profile.splitGeometry
        layoutProfile = profile
        if rebuild { rebuildKeyRows() }
        if smartCellButtons.count != profile.compositionCellCount {
            smartCellButtons = makeSmartCellButtons()
        }
        keyBands?.spacing = profile.keySpacing
        rootStack?.spacing = profile.keySpacing
        appliedRowLayout = nil
        updateRowLayout()
        apply(state, force: true)
    }

    func setLayoutOptions(keycapArea: KeyboardKeycapArea, fontSize: KeyboardKeyFontSize,
                          deleteShiftPosition: KeyboardDeleteShiftPosition) {
        guard self.keycapArea != keycapArea || self.keyFontSize != fontSize
            || self.deleteShiftPosition != deleteShiftPosition else { return }
        cancelBackspaceRepeat()
        self.keycapArea = keycapArea
        self.keyFontSize = fontSize
        self.deleteShiftPosition = deleteShiftPosition
        appliedRowLayout = nil
        updateRowLayout()
        apply(state, force: true)
    }

    private var currentPlane: KeyboardLayoutProfile.Plane {
        .resolve(inputMethod: state.chineseInputMethod, mode: state.mode)
    }

    private var currentKeyRows: [[String]] {
        layoutProfile.resolvedRows(orientation: layoutOrientation,
            plane: currentPlane,
            shifted: state.shifted, deleteShiftPosition: deleteShiftPosition)
    }

    func setLayoutOrientation(_ orientation: KeyboardLayoutProfile.Orientation) {
        guard orientation != layoutOrientation else { return }
        cancelBackspaceRepeat()
        layoutOrientation = orientation
        rebuildKeyRows()
        appliedRowLayout = nil
        updateRowLayout()
        apply(state, force: true)
    }

    private func rebuildKeyRows() {
        guard let bands = keyBands else { return }
        let restoreOverlay = candidateIsOverlay
        if restoreOverlay { setCandidateOverlay(false) }
        for row in keyRows {
            bands.removeArrangedSubview(row)
            row.removeFromSuperview()
        }
        keyRows = []; keyViews = []; punctuationButtons = []
        for (index, row) in buildKeyRows().enumerated() {
            bands.insertArrangedSubview(row, at: index)
        }
        if restoreOverlay { setCandidateOverlay(true) }
    }

    func setNeedsInputModeSwitch(_ needed: Bool) {
        guard needed != needsInputModeSwitch else { return }
        needsInputModeSwitch = needed
        updateRowLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        updateRowLayout()
        rootStack?.layoutIfNeeded()
        updateKeyTypography()
    }

    private var cachedKeyTypography: (size: CGSize, inset: CGFloat, normal: Double, full: Double)?

    private func updateKeyTypography() {
        // Use the physical ㄖ slot even on a plane without that character.
        // Measuring the same geometry prevents a mode switch changing font size.
        let rows = layoutProfile.resolvedRows(orientation: layoutOrientation,
            plane: .bopomofo, shifted: false, deleteShiftPosition: deleteShiftPosition)
        guard let row = rows.firstIndex(where: { $0.contains("b") }),
              let column = rows[row].firstIndex(of: "b"), keyRows.indices.contains(row) else { return }
        let host = keyRows[row]
        host.layoutIfNeeded()
        let frames = layoutProfile.keyRowGeometry(for: rows, plane: .bopomofo, rowIndex: row)
            .frames(width: host.bounds.width, height: host.bounds.height, spacing: layoutProfile.keySpacing)
        let slot = column + (layoutProfile.splitGeometry.map { column >= $0.keySplit - 1 ? 1 : 0 } ?? 0)
        guard frames.indices.contains(slot), frames[slot].width > 0, frames[slot].height > 0 else { return }
        let inset: CGFloat = layoutProfile.usesStaggeredRows ? 1 : 0
        let size = frames[slot].size
        if cachedKeyTypography?.size != size || cachedKeyTypography?.inset != inset {
            let fitted = KeyboardKeyTypography.endpoints(in: size, capInset: inset)
            cachedKeyTypography = (size, inset, fitted.normal, fitted.full)
        }
        guard let endpoints = cachedKeyTypography else { return }
        let pointSize = keyFontSize.keyPointSize(normal: endpoints.normal, largeFit: endpoints.full)
        let buttons = keyViews.flatMap { $0.map(\.button) }
            + (functionButtons + punctuationButtons).compactMap { $0.button as? KeyboardKeyButton }
        for button in buttons {
            button.sharedPointSize = pointSize
            button.setNeedsLayout()
            button.layoutIfNeeded()
        }
    }

    #if KEYKEY_TYPOGRAPHY_MEASUREMENT
    // Explicit instrumentation build only; no diagnostic API in normal builds.
    func typographyMeasurementSnapshot() -> [String: Any] {
        layoutIfNeeded()
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height] }
        let primary = keyViews.flatMap { $0 }.filter {
            !KeyboardLayout.isSpecial($0.button.accessibilityIdentifier ?? "")
        }
        let pointSize = primary.first.map { $0.glyph.font.pointSize / $0.button.glyphScale } ?? 0
        let mismatches = primary.filter {
            abs($0.glyph.font.pointSize / $0.button.glyphScale - pointSize) > 0.001
        }.count
        let spaces = functionButtons.filter { $0.key == "SPACE" && $0.button.superview != nil }
        let spaceFonts = spaces.map { $0.button.titleLabel!.font.pointSize }
        let mode = functionButtons.first { $0.key == "MODE" }!.button
        let modeText = mode.currentTitle ?? ""
        let modeLabel = mode.titleLabel!
        let modeWidth = modeText.size(withAttributes: [.font: modeLabel.font!]).width
        return ["keyRegion": keyBands.map { rect($0.convert($0.bounds, to: self)) } ?? [],
            "viewFrame": rect(frame), "viewBounds": rect(bounds),
            "windowFrame": window.map { rect($0.frame) } ?? [],
            "primaryPointSize": pointSize, "primaryMismatchCount": mismatches,
            "spacePointSizes": spaceFonts,
            "spaceMismatchCount": spaceFonts.filter { abs($0 - pointSize) > 0.001 }.count,
            "modeCaption": modeText, "modeCaptionFits": modeWidth <= modeLabel.bounds.width + 0.01,
            "modePointSize": modeLabel.font.pointSize]
    }
    #endif

    private func updateCandidateVisibility() {
        let hasCandidates = !state.candidates.isEmpty
        let isSplit = layoutProfile.splitGeometry != nil
        candidateStrip.isHidden = !hasCandidates && !isSplit
        (candidateButtons + [previousPageButton, nextPageButton]).forEach { $0.isHidden = !hasCandidates }
        let slot = state.smartMode ? smartDismissSpacer : candidateSpacer
        if dismissButton.superview !== slot {
            dismissButton.removeFromSuperview()
            dismissButton.frame = slot.bounds
            slot.addSubview(dismissButton)
        }
        dismissButton.isHidden = !isSplit
        closeCandidatesButton.isHidden = !isSplit || !state.smartMode || !hasCandidates
    }

    private func updateRowLayout() {
        let split = layoutProfile.splitGeometry
        let next = RowLayout(profile: layoutProfile, plane: currentPlane,
                             needsInputModeSwitch: needsInputModeSwitch,
                             deleteShiftPosition: deleteShiftPosition)
        guard next != appliedRowLayout else { return }
        appliedRowLayout = next
        cancelBackspaceRepeat()
        for (index, row) in keyRows.enumerated() {
            var buttons: [UIButton] = keyViews[index].map(\.button)
            if let split, split.punctuation.indices.contains(index) {
                buttons.insert(punctuationButtons[index].button, at: min(split.keySplit - 1, buttons.count))
            }
            row.configure(buttons, spacing: layoutProfile.keySpacing,
                keyGeometry: layoutProfile.keyRowGeometry(for: currentKeyRows, plane: currentPlane,
                    rowIndex: index))
        }
        smartCellStrip.configure(smartCellButtons + (split != nil ? [smartDismissSpacer] : []),
                                 splitIndex: split?.compositionSplit, spacing: layoutProfile.stripSpacing)
        let candidates: [UIView] = [previousPageButton] + candidateButtons + [nextPageButton]
        candidateStrip.configure(candidates + (split != nil ? [candidateSpacer] : []),
            splitIndex: split?.candidateSplit,
            spacing: layoutProfile.stripSpacing)
        var keys = layoutProfile.functionKeys(deleteShiftPosition: deleteShiftPosition)
        if split != nil, let space = keys.firstIndex(of: "SPACE") { keys.insert("SPACE", at: space + 1) }
        if needsInputModeSwitch { keys.insert(KeyboardLayout.inputModeSwitchKey, at: 0) }
        var seenSpace = false
        let visible = keys.compactMap { key -> (key: String, button: UIButton)? in
            let rightSpace = key == "SPACE" && seenSpace
            if key == "SPACE" { seenSpace = true }
            return functionButtons.first {
                $0.key == key && ($0.button.accessibilityIdentifier == "keyboard.space.right") == rightSpace
            }
        }
        let weights = visible.map { layoutProfile.functionWeight(for: $0.key) }
        let functionSplit = split != nil ? visible.firstIndex { $0.key == "SPACE" }.map { $0 + 1 } : nil
        functionRow.configure(visible.map(\.button), weights: weights, splitIndex: functionSplit,
                              spacing: layoutProfile.keySpacing)
        for button in keyViews.flatMap({ $0.map(\.button) })
            + (functionButtons + punctuationButtons).compactMap({ $0.button as? KeyboardKeyButton }) {
            button.capArea = keycapArea
            button.capInset = layoutProfile.usesStaggeredRows ? 1 : 0
            button.fontSize = keyFontSize
        }
        updateCandidateVisibility()
        setNeedsLayout()
    }

    func setBottomGap(_ gap: CGFloat) {
        if bottomContentConstraint?.constant != -3 - gap {
            bottomContentConstraint?.constant = -3 - gap
        }
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
            statusLabel.basePointSize = metrics.statusFont
            statusLabel.fontSize = keyFontSize
            statusLabel.font = .systemFont(ofSize: metrics.statusFont)
            let normalStatus = state.chineseInputMethod.isTable && state.mode == .bopomofo && state.reading.isEmpty
                ? state.chineseInputMethod.displayName : KeyboardLayout.statusText(
                reading: state.reading, mode: state.mode, shifted: state.shifted,
                temporaryEnglish: state.temporaryEnglish,
                layout: state.chineseInputMethod.isTable ? .standard : state.keyboardLayout
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
            let supportStart = max(0, smartCellButtons.count - 3)
            for (index, button) in smartCellButtons.enumerated() {
                let isSupportCell = state.showsSmartSupportPrompt && index >= supportStart
                let value = isSupportCell ? ["歡迎", "付費", "支持"][index - supportStart]
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
                (button as? KeyboardStripButton)?.configureText(
                    primary: value, index: nil, fontSize: keyFontSize,
                    baseSize: isSupportCell ? metrics.statusFont : metrics.candidateFont,
                    indexSize: metrics.candidateIndexFont,
                    primaryColor: isSupportCell ? Palette.hintText : Palette.primaryText,
                    indexColor: Palette.hintText)
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
                (button as? KeyboardStripButton)?.configureText(
                    primary: candidate ?? "", index: candidate == nil ? nil : String(index + 1),
                    fontSize: keyFontSize, baseSize: metrics.candidateFont,
                    indexSize: metrics.candidateIndexFont,
                    primaryColor: highlighted ? Palette.candidateHighlightText(for: state.candidateColor) : Palette.primaryText,
                    indexColor: highlighted ? Palette.candidateHighlightText(for: state.candidateColor) : Palette.hintText)
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
            let rows = currentKeyRows
            if rows.map(\.count) != keyViews.map(\.count) {
                rebuildKeyRows()
                appliedRowLayout = nil
            }
            updateRowLayout()
            for (rowIndex, row) in rows.enumerated() {
                for (columnIndex, key) in row.enumerated() {
                    let keyView = keyViews[rowIndex][columnIndex]
                    keyView.button.accessibilityIdentifier = key
                    keyView.button.keycap.backgroundColor = KeyboardLayout.isSpecial(key)
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

        if keyPlaneChanged || state.returnKeyPolicy != previousState.returnKeyPolicy
            || state.showsPinyinFirstTone != previousState.showsPinyinFirstTone {
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
                    : caption(for: key)
                button.setTitle(caption, for: .normal)
                let pointSize = caption.count > 3 ? metrics.functionFontSmall : metrics.functionFont
                button.titleLabel?.font = .systemFont(ofSize: pointSize)
            }
        }
        setNeedsLayout()
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
        let button = keyView.button
        let glyph = state.mode == .bopomofo ? inputGlyph(for: key) : nil
        button.fontSize = keyFontSize
        let normalInlineHints = !metrics.stacksKeyLabels && layoutProfile.splitGeometry == nil
        button.inlineHints = normalInlineHints && keyFontSize.showsKeyHints
        button.hint.isHidden = !keyFontSize.showsKeyHints || glyph == nil
        button.glyph.textColor = Palette.primaryText
        button.hint.textColor = Palette.hintText
        let readingScale = state.chineseInputMethod.isTable ? 1 : KeyboardLayout.glyphPointScale(for: key)
        button.glyphScale = glyph != nil && !state.temporaryEnglish ? readingScale : 1
        button.hintScale = glyph != nil && state.temporaryEnglish ? readingScale : 1
        if let glyph {
            button.glyph.text = state.temporaryEnglish ? key : glyph
            button.hint.text = state.temporaryEnglish ? glyph : key
        } else {
            button.glyph.text = caption
        }
        button.setNeedsLayout()
    }

    private func caption(for key: String) -> String {
        if key == "SPACE", state.showsPinyinFirstTone { return "一聲" }
        return KeyboardLayout.caption(for: key, mode: state.mode)
    }

    private func accessibilityLabel(for key: String) -> String {
        if state.usesPinyin {
            switch key {
            case "2": return "二聲（2）"
            case "3": return "三聲（3）"
            case "4": return "四聲（4）"
            case "5": return "輕聲（5）"
            default: break
            }
        }
        switch key {
        case "MODE": return "切換輸入模式"
        case "SYMBOL": return "符號"
        case "SETTINGS": return "設定"
        case "SPACE": return state.showsPinyinFirstTone ? "一聲（空白鍵）" : "空白鍵"
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

    @objc private func mainKeyTouchDown(_ sender: UIButton) {
        if actionKey(for: sender) == "BACKSPACE" { backspaceTouchDown(sender) }
        else { previewTouchDown(sender) }
    }

    @objc private func mainKeyTouchUpInside(_ sender: UIButton) {
        if actionKey(for: sender) == "BACKSPACE" { backspaceTouchUpInside() }
        else { keyTapped(sender) }
    }

    @objc private func mainKeyTouchEnded() { cancelBackspaceRepeat() }

    @objc private func mainKeyTouchExited() {
        backspaceTouchExited()
        hideKeyPreview()
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
        return caption(for: key)
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
    private var spacing: Double
    private var items: [UIView] = []
    private var weights: [Double] = []
    private var splitIndex: Int?
    private var keyGeometry: KeyboardLayoutProfile.KeyRowGeometry?

    init(spacing: Double = 3) {
        self.spacing = spacing
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configure(_ items: [UIView], weights: [Double]? = nil, splitIndex: Int? = nil,
                   spacing: Double? = nil,
                   keyGeometry: KeyboardLayoutProfile.KeyRowGeometry? = nil) {
        self.keyGeometry = keyGeometry
        if let spacing { self.spacing = spacing }
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
        let frames = keyGeometry?.frames(width: bounds.width, height: bounds.height, spacing: spacing)
            ?? KeyboardRowGeometry.frames(
                width: bounds.width, height: bounds.height, weights: weights,
                splitIndex: splitIndex, spacing: spacing)
        for (item, frame) in zip(items, frames) { item.frame = frame }
    }
}

/// One radical-based font budget for every main label, independent of its ink.
@MainActor
private enum KeyboardKeyTypography {
    static let hintRatio = 10.0 / 18
    static let gap = 2.0

    static func box(in size: CGSize, capInset: CGFloat) -> CGRect {
        CGRect(origin: .zero, size: size).insetBy(dx: capInset + 2, dy: capInset + 2)
    }

    static func referenceSize(at pointSize: Double) -> CGSize {
        let font = UIFont.systemFont(ofSize: pointSize)
        let measured = "ㄖ".size(withAttributes: [.font: font])
        return CGSize(width: measured.width, height: max(font.lineHeight, measured.height))
    }

    static func hintSize(at pointSize: Double) -> CGSize {
        let font = UIFont.systemFont(ofSize: pointSize * hintRatio)
        let width = "ㄖ1234567890qwertyuiopasdfghjklzxcvbnm@".map {
            String($0).size(withAttributes: [.font: font]).width
        }.max() ?? 0
        return CGSize(width: width, height: max(font.lineHeight,
            "ㄖ".size(withAttributes: [.font: font]).height))
    }

    static func endpoints(in size: CGSize, capInset: CGFloat) -> (normal: Double, full: Double) {
        let box = box(in: size, capInset: capInset)
        // Native font metrics can vary with optical size, so fit the requested
        // point size itself instead of assuming a fixed pixel-to-point ratio.
        func fit(reservingHint: Bool) -> Double {
            var low = 0.01
            var high = max(size.width, size.height) * 4
            for _ in 0..<24 {
                let candidate = (low + high) / 2
                let reference = referenceSize(at: candidate)
                let hint = reservingHint ? hintSize(at: candidate) : .zero
                let padding = reservingHint ? gap : 0
                if reference.width + hint.width + padding <= max(0.01, box.width)
                    && reference.height + hint.height + padding <= max(0.01, box.height) {
                    low = candidate
                } else { high = candidate }
            }
            return low
        }
        let full = fit(reservingHint: false)
        let normal = fit(reservingHint: true)
        return (min(normal, full), full)
    }
}

/// Paint and labels are separate from the UIButton's full-size hit target.
@MainActor
private final class KeyboardKeyButton: UIButton {
    let keycap = UIView()
    let glyph = UILabel()
    let hint = UILabel()
    var usesGlyphLabels = false
    var inlineHints = false
    var glyphScale: Double = 1
    var hintScale: Double = 1
    var capArea: KeyboardKeycapArea = .small { didSet { setNeedsLayout() } }
    var capInset: CGFloat = 0 { didSet { setNeedsLayout() } }
    var fontSize: KeyboardKeyFontSize = .normal { didSet { setNeedsLayout() } }
    var sharedPointSize: Double = 18

    override init(frame: CGRect) {
        super.init(frame: frame)
        keycap.isUserInteractionEnabled = false
        keycap.layer.cornerRadius = 6
        insertSubview(keycap, at: 0)
        for label in [glyph, hint] {
            label.isUserInteractionEnabled = false
            label.textAlignment = .center
            label.adjustsFontSizeToFitWidth = false
            label.isAccessibilityElement = false
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        let capBounds = bounds.insetBy(dx: capInset, dy: capInset)
        keycap.frame = capArea.frame(in: capBounds)
        sendSubviewToBack(keycap)
        glyph.isHidden = !usesGlyphLabels
        let box = KeyboardKeyTypography.box(in: bounds.size, capInset: capInset)
        if usesGlyphLabels {
            var pointSize = sharedPointSize * glyphScale
            // Icons and long action captions fit their control, while all input
            // characters retain the common size, including full-width punctuation.
            if let text = glyph.text, text.count > 1 || ["☺", "⌫", "⇧", "▼", "🌐"].contains(text) {
                pointSize = KeyboardTextFitting.font(for: text, target: pointSize, in: box.size).pointSize
            }
            glyph.font = .systemFont(ofSize: pointSize)
            hint.font = .systemFont(ofSize: sharedPointSize * KeyboardKeyTypography.hintRatio * hintScale)
            let reference = KeyboardKeyTypography.referenceSize(at: sharedPointSize)
            let small = KeyboardKeyTypography.hintSize(at: sharedPointSize)
            var mainCenter = CGPoint(x: box.midX, y: box.midY)
            if !hint.isHidden {
                if inlineHints {
                    let total = reference.width + KeyboardKeyTypography.gap + small.width
                    mainCenter.x = box.midX - total / 2 + reference.width / 2
                    hint.center = CGPoint(x: box.midX + total / 2 - small.width / 2, y: box.midY)
                } else {
                    let total = reference.height + KeyboardKeyTypography.gap + small.height
                    mainCenter.y = box.midY - total / 2 + reference.height / 2
                    hint.center = CGPoint(x: box.midX, y: box.midY + total / 2 - small.height / 2)
                }
                hint.bounds = CGRect(origin: .zero, size: CGSize(width: box.width,
                    height: max(small.height, hint.font.lineHeight)))
            }
            // A tone uses its established relative font scale. Its larger font
            // box must not shrink the neighbouring ordinary primary labels.
            glyph.bounds = CGRect(origin: .zero, size: CGSize(width: max(box.width,
                glyphScale > 1 ? (glyph.text ?? "").size(withAttributes: [.font: glyph.font!]).width : 0),
                height: max(reference.height, glyph.font.lineHeight)))
            glyph.center = CGPoint(x: mainCenter.x,
                y: mainCenter.y + (glyph.font.pointSize - sharedPointSize) * 0.25)
        } else {
            hint.isHidden = true
            if let titleLabel, currentImage == nil {
                let text = currentTitle ?? ""
                // Both split SPACE buttons use precisely the common point size.
                // Other multi-character action captions may fit their own control.
                let target = text == "空白" || text.count <= 1 ? sharedPointSize
                    : KeyboardTextFitting.font(for: text, target: sharedPointSize, in: box.size).pointSize
                titleLabel.font = .systemFont(ofSize: target)
                titleLabel.adjustsFontSizeToFitWidth = false
                titleLabel.lineBreakMode = .byClipping
                titleLabel.textAlignment = .center
                titleLabel.frame = box
            }
        }
    }
}

/// Shared measurement fits text inside its existing control without changing
/// the control's frame or depending on the previously fitted font size.
@MainActor
private enum KeyboardTextFitting {
    static func font(for text: String?, target: Double, in size: CGSize) -> UIFont {
        func fits(_ pointSize: Double) -> Bool {
            let font = UIFont.systemFont(ofSize: pointSize)
            let measured = (text ?? "").size(withAttributes: [.font: font])
            return measured.width <= max(0, size.width)
                && max(font.lineHeight, measured.height) <= max(0, size.height)
        }
        let requested = max(0.01, target)
        if fits(requested) { return .systemFont(ofSize: requested) }
        var low = 0.01, high = requested
        for _ in 0..<24 {
            let candidate = (low + high) / 2
            if fits(candidate) { low = candidate } else { high = candidate }
        }
        return .systemFont(ofSize: low)
    }
}

/// Only the primary candidate/composition text scales. Its sequence number
/// keeps the original point size and its own reserved line.
@MainActor
private final class KeyboardStripButton: UIButton {
    private let primaryLabel = UILabel()
    private let indexLabel = UILabel()
    private var fontSize: KeyboardKeyFontSize = .normal
    private var primaryText = ""
    private var indexText: String?
    private var baseSize: Double = 18
    private var indexSize: Double = 10

    override init(frame: CGRect) {
        super.init(frame: frame)
        for label in [primaryLabel, indexLabel] {
            label.textAlignment = .center
            label.isUserInteractionEnabled = false
            label.isAccessibilityElement = false
            addSubview(label)
        }
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func configureText(primary: String, index: String?, fontSize: KeyboardKeyFontSize,
                       baseSize: Double, indexSize: Double,
                       primaryColor: UIColor, indexColor: UIColor) {
        primaryText = primary
        indexText = index
        self.fontSize = fontSize
        self.baseSize = baseSize
        self.indexSize = indexSize
        primaryLabel.text = primary
        indexLabel.text = index
        primaryLabel.textColor = primaryColor
        indexLabel.textColor = indexColor
        setNeedsLayout()
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        let scaled = fontSize != .normal
        let hasText = !primaryText.isEmpty
        // UIKit may retain the previous native label text when its title is
        // cleared. Keep an empty title hidden when choosing the font renderer.
        titleLabel?.isHidden = scaled || !hasText
        primaryLabel.isHidden = !scaled || !hasText
        indexLabel.isHidden = !scaled || !hasText || indexText == nil
        guard scaled else { return }
        let box = bounds.insetBy(dx: 1, dy: 0)
        indexLabel.font = .systemFont(ofSize: indexSize)
        let indexHeight = indexText == nil ? 0 : indexLabel.font.lineHeight
        indexLabel.frame = CGRect(x: box.minX, y: box.maxY - indexHeight,
            width: box.width, height: indexHeight)
        let primaryBox = CGRect(x: box.minX, y: box.minY,
            width: box.width, height: max(0, box.height - indexHeight))
        primaryLabel.font = KeyboardTextFitting.font(for: primaryText,
            target: fontSize.stripPointSize(base: baseSize),
            in: primaryBox.size)
        primaryLabel.frame = primaryBox
    }
}

@MainActor
private final class KeyboardStatusLabel: UILabel {
    var basePointSize: Double = 14 { didSet { setNeedsLayout() } }
    var fontSize: KeyboardKeyFontSize = .normal { didSet { setNeedsLayout() } }

    override func layoutSubviews() {
        super.layoutSubviews()
        adjustsFontSizeToFitWidth = fontSize == .normal
        guard fontSize != .normal else { return }
        let fitted = KeyboardTextFitting.font(for: text,
            target: fontSize.stripPointSize(base: basePointSize),
            in: bounds.size)
        if abs(font.pointSize - fitted.pointSize) > 0.01 { font = fitted }
    }
}

import KeyKeyEngine
import UIKit

@MainActor
protocol KeyboardViewDelegate: AnyObject {
    func keyboardView(_ view: KeyboardView, didPress key: String)
    func keyboardView(_ view: KeyboardView, didSelectCandidateAt index: Int)
    func keyboardView(_ view: KeyboardView, didChangePageBy delta: Int)
}

/// The Bopomofo keyboard: a candidate strip over five equal bands -- four rows
/// of eleven keys and a weighted function row. Built from real views rather
/// than a drawn canvas like the Android port, which gets VoiceOver for free and
/// keeps hit testing independent of paint order.
final class KeyboardView: UIView {
    struct State {
        var reading = ""
        var candidates: [String] = []
        var highlightedIndex = -1
        var pageCount = 0
        var mode = BopomofoEngine.InputMode.bopomofo
        var shifted = false
        var temporaryEnglish = false
        var statusOverride: String?
        var fieldPolicy = InputFieldPolicy.default
        var returnKeyPolicy = ReturnKeyPolicy(hint: .default)
        var inputClicksEnabled = true
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
    private let candidateStrip = UIStackView()
    private var candidateStripHeight: NSLayoutConstraint?
    private var contentWidthConstraint: NSLayoutConstraint?
    private var keyViews: [[KeyView]] = []
    private var functionButtons: [(key: String, button: UIButton)] = []
    private let keyPreview = UILabel()
    private var state = State()
    private var metrics = KeyboardMetrics.portrait
    private var enterIconSide: Double = 0
    private let needsInputModeSwitch: Bool
    /// Left for the controller to wire to `handleInputModeList`, which gives
    /// the key the system behaviour: tap advances, long press opens the
    /// keyboard picker. Nil where the host already draws a globe of its own.
    private(set) var inputModeSwitchButton: UIButton?

    init(needsInputModeSwitch: Bool) {
        self.needsInputModeSwitch = needsInputModeSwitch
        super.init(frame: .zero)
        backgroundColor = Palette.background
        buildInterface()
        apply(State())
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    // MARK: - Construction

    private func buildInterface() {
        // Five equal bands below the strip, matching the Android division of
        // the remaining height.
        let bands = UIStackView(arrangedSubviews: buildKeyRows() + [buildFunctionRow()])
        bands.axis = .vertical
        bands.distribution = .fillEqually
        bands.spacing = 3

        let root = UIStackView(arrangedSubviews: [buildCandidateStrip(), bands])
        root.axis = .vertical
        root.spacing = 3
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)

        // Content sits at the top; the bottom safe area belongs to the system
        // globe key and the home indicator.
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 3),
            root.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3),
            root.centerXAnchor.constraint(equalTo: centerXAnchor),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            root.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -3
            )
        ])
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

        candidateStrip.axis = .horizontal
        candidateStrip.distribution = .fillEqually
        candidateStrip.spacing = 2
        candidateStrip.addArrangedSubview(previousPageButton)
        candidateButtons.forEach(candidateStrip.addArrangedSubview)
        candidateStrip.addArrangedSubview(nextPageButton)

        statusLabel.textColor = Palette.hintText
        statusLabel.textAlignment = .center
        statusLabel.adjustsFontSizeToFitWidth = true
        statusLabel.minimumScaleFactor = 0.7

        let container = UIView()
        for child in [candidateStrip, statusLabel] as [UIView] {
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

    private func buildKeyRows() -> [UIView] {
        (0..<4).map { rowIndex in
            let stack = UIStackView()
            stack.axis = .horizontal
            stack.distribution = .fillEqually
            stack.spacing = 3
            var keys: [KeyView] = []
            for columnIndex in 0..<11 {
                let button = UIButton(type: .system)
                button.layer.cornerRadius = 6
                button.tag = rowIndex * 100 + columnIndex
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                installPreviewHandlers(on: button)
                stack.addArrangedSubview(button)
                keys.append(makeKeyView(button))
            }
            keyViews.append(keys)
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

    /// The function row is the only non-uniform row, so its widths come from
    /// explicit multipliers rather than `fillEqually`.
    private func buildFunctionRow() -> UIView {
        let row = UIView()
        let keys = KeyboardLayout.functionRow(withInputModeSwitch: needsInputModeSwitch)
        let total = keys.reduce(0.0) { $0 + KeyboardLayout.weight(for: $1) }
        var previous: UIButton?
        for key in keys {
            let button = UIButton(type: .system)
            button.backgroundColor = Palette.specialKey
            button.tintColor = Palette.primaryText
            button.layer.cornerRadius = 6
            button.setTitleColor(Palette.primaryText, for: .normal)
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.6
            button.accessibilityIdentifier = key
            if key == KeyboardLayout.inputModeSwitchKey {
                inputModeSwitchButton = button
            } else {
                button.addTarget(self, action: #selector(keyTapped(_:)), for: .touchUpInside)
                installPreviewHandlers(on: button)
            }
            button.translatesAutoresizingMaskIntoConstraints = false
            row.addSubview(button)
            functionButtons.append((key, button))

            NSLayoutConstraint.activate([
                button.topAnchor.constraint(equalTo: row.topAnchor),
                button.bottomAnchor.constraint(equalTo: row.bottomAnchor),
                button.widthAnchor.constraint(
                    equalTo: row.widthAnchor,
                    multiplier: KeyboardLayout.weight(for: key) / total,
                    constant: -3
                ),
                button.leadingAnchor.constraint(
                    equalTo: previous?.trailingAnchor ?? row.leadingAnchor,
                    constant: previous == nil ? 0 : 3
                )
            ])
            previous = button
        }
        return row
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

    func setMetrics(_ metrics: KeyboardMetrics) {
        guard metrics != self.metrics else { return }
        self.metrics = metrics
        candidateStripHeight?.constant = metrics.candidateStripHeight
        contentWidthConstraint?.constant = metrics.maximumContentWidth
        apply(state)
    }

    func apply(_ state: State) {
        self.state = state

        let hasCandidates = !state.candidates.isEmpty
        candidateStrip.isHidden = !hasCandidates
        statusLabel.isHidden = hasCandidates
        statusLabel.font = .systemFont(ofSize: metrics.statusFont)
        statusLabel.text = state.statusOverride ?? KeyboardLayout.statusText(
            reading: state.reading,
            mode: state.mode,
            shifted: state.shifted,
            temporaryEnglish: state.temporaryEnglish
        )

        for (index, button) in candidateButtons.enumerated() {
            let candidate = index < state.candidates.count ? state.candidates[index] : nil
            let highlighted = index == state.highlightedIndex
            button.isEnabled = candidate != nil
            button.setAttributedTitle(candidate.map {
                candidateTitle($0, index: index, highlighted: highlighted)
            }, for: .normal)
            button.backgroundColor = highlighted ? Palette.highlight : Palette.candidateCell
            button.accessibilityLabel = candidate.map { "第 \(index + 1) 個候選，\($0)" }
            // An empty cell stays laid out to keep the strip's spacing, but it
            // must leave the accessibility tree: an unlabelled button is a stop
            // VoiceOver announces with nothing to say.
            button.isAccessibilityElement = candidate != nil
        }
        for button in [previousPageButton, nextPageButton] {
            button.titleLabel?.font = .systemFont(ofSize: metrics.pageFont)
            button.isEnabled = state.pageCount > 1
        }

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

        for (key, button) in functionButtons {
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
                ? state.fieldPolicy.modeCaption(for: state.mode)
                : KeyboardLayout.caption(for: key, mode: state.mode)
            button.setTitle(caption, for: .normal)
            button.titleLabel?.font = .systemFont(
                ofSize: caption.count > 3 ? metrics.functionFontSmall : metrics.functionFont
            )
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
        let colour = highlighted ? Palette.highlightText : Palette.primaryText
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
                .foregroundColor: highlighted ? Palette.highlightText : Palette.hintText
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
    private func configure(_ keyView: KeyView, for key: String) {
        let caption = KeyboardLayout.caption(for: key, mode: state.mode)
        guard state.mode == .bopomofo,
              let glyph = KeyboardLayout.bopomofoGlyph(for: key)
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

        let scale = state.temporaryEnglish ? 1 : KeyboardLayout.glyphPointScale(for: key)
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
            if state.mode == .bopomofo, let glyph = KeyboardLayout.bopomofoGlyph(for: key) {
                return glyph
            }
            return key
        }
    }

    // MARK: - Actions

    @objc private func keyTapped(_ sender: UIButton) {
        guard let key = sender.accessibilityIdentifier else { return }
        hideKeyPreview()
        playInputClick()
        delegate?.keyboardView(self, didPress: key)
    }

    @objc private func candidateTapped(_ sender: UIButton) {
        playInputClick()
        delegate?.keyboardView(self, didSelectCandidateAt: sender.tag)
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
        guard sender.isEnabled, let key = sender.accessibilityIdentifier else { return }
        showKeyPreview(previewText(for: key), from: sender)
    }

    @objc private func previewTouchEnded() {
        hideKeyPreview()
    }

    private func previewText(for key: String) -> String {
        if key == "MODE" {
            switch state.mode {
            case .bopomofo: return "英"
            case .english: return "數"
            case .number: return "ㄅ"
            }
        }
        if key == "SHIFT" {
            if state.mode == .bopomofo { return "英" }
            return state.shifted ? "小寫" : "大寫"
        }
        if key == "ENTER" { return state.returnKeyPolicy.accessibilityLabel }
        if state.mode == .bopomofo, let glyph = KeyboardLayout.bopomofoGlyph(for: key) {
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

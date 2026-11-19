import KeyKeyEngine
import UIKit

@MainActor
protocol SettingsPanelDelegate: AnyObject {
    func settingsPanel(_ panel: SettingsPanel, didChangeInputMethod method: ChineseInputMethod)
    func settingsPanelDidChangeTableOptions(_ panel: SettingsPanel)
    func settingsPanel(
        _ panel: SettingsPanel, didChangeCompositionMode mode: BopomofoCompositionMode
    )
    func settingsPanel(_ panel: SettingsPanel, didChangeSimplifiedOutput enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeSpaceSelection enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeUseBigrams enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeToneOmission enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeInputClicksEnabled enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeCandidateColor color: CandidateColor)
    func settingsPanel(_ panel: SettingsPanel, didChangeKeyboardLayout layout: BopomofoKeyboardLayout)
    func settingsPanel(_ panel: SettingsPanel, didChangeLayoutProfile profile: KeyboardLayoutProfile)
    func settingsPanel(_ panel: SettingsPanel, didChangeKeycapArea area: KeyboardKeycapArea)
    func settingsPanel(_ panel: SettingsPanel, didChangeFontSize size: KeyboardKeyFontSize)
    func settingsPanel(_ panel: SettingsPanel, didChangeDeleteShiftPosition position: KeyboardDeleteShiftPosition)
    func settingsPanelResetLearning(_ panel: SettingsPanel) -> Bool
    func settingsPanelDidRequestKeyboardHeight(_ panel: SettingsPanel)
    func settingsPanelDidClose(_ panel: SettingsPanel)
}

/// Settings shown over the input view when the 「設」 key is pressed.
final class SettingsPanel: UIView {
    weak var delegate: SettingsPanelDelegate?

    private var inputClicksEnabled: Bool
    private var candidateColor: CandidateColor
    private var compositionMode: BopomofoCompositionMode
    private var chineseInputMethod: ChineseInputMethod
    private let methodSettings: ChineseInputMethodSettings
    private var layoutProfile: KeyboardLayoutProfile
    private var keycapArea: KeyboardKeycapArea
    private var deleteShiftPosition: KeyboardDeleteShiftPosition
    private var fontSize: KeyboardKeyFontSize
    private var keyboardLayout: BopomofoKeyboardLayout
    private let simplifiedOutputEnabled: Bool
    private let omitsTones: Bool
    private let statusLabel = UILabel()
    private let candidateColorControl = UISegmentedControl(
        items: ["紫", "綠", "黃", "紅"]
    )
    private let compositionModeControl = UISegmentedControl(
        items: ChineseInputMethod.allCases.map(\.displayName)
    )
    private let resetLearningButton = UIButton(configuration: .tinted())
    private var tableOptionViews: [KeyboardTableOptionsView] = []
    private var resetConfirmation = false
    private var helpOverlay: UIView?
    private weak var helpSource: UIButton?

    init(
        inputClicksEnabled: Bool, candidateColor: CandidateColor,
        compositionMode: BopomofoCompositionMode,
        chineseInputMethod: ChineseInputMethod = .smart,
        methodSettings: ChineseInputMethodSettings = ChineseInputMethodSettings(),
        keyboardLayout: BopomofoKeyboardLayout = .standard,
        simplifiedOutputEnabled: Bool = false, omitsTones: Bool = false,
        layoutProfile: KeyboardLayoutProfile = .standard,
        keycapArea: KeyboardKeycapArea = .small,
        fontSize: KeyboardKeyFontSize = .normal,
        deleteShiftPosition: KeyboardDeleteShiftPosition = .aboveEnter
    ) {
        self.inputClicksEnabled = inputClicksEnabled
        self.candidateColor = candidateColor
        self.compositionMode = compositionMode
        self.chineseInputMethod = chineseInputMethod
        self.methodSettings = methodSettings
        self.keyboardLayout = keyboardLayout
        self.simplifiedOutputEnabled = simplifiedOutputEnabled
        self.omitsTones = omitsTones
        self.layoutProfile = layoutProfile
        self.keycapArea = keycapArea
        self.fontSize = fontSize
        self.deleteShiftPosition = deleteShiftPosition
        super.init(frame: .zero)
        backgroundColor = Palette.surface
        buildInterface()
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    private func buildInterface() {
        let title = UILabel()
        title.text = "虛擬鍵盤調整設定"
        title.font = .systemFont(ofSize: 16, weight: .semibold)
        title.textColor = Palette.primaryText

        let close = UIButton(type: .system)
        close.setTitle("完成", for: .normal)
        close.setTitleColor(Palette.highlight, for: .normal)
        close.titleLabel?.font = .systemFont(ofSize: 16, weight: .semibold)
        close.addTarget(self, action: #selector(closeTapped), for: .touchUpInside)

        let header = UIStackView(arrangedSubviews: [title, UIView(), close])
        header.alignment = .center

        statusLabel.font = .systemFont(ofSize: 12)
        statusLabel.textColor = Palette.hintText
        statusLabel.isHidden = true

        let scroll = UIScrollView()
        scroll.accessibilityIdentifier = "keyboard-settings.scroll"
        scroll.alwaysBounceVertical = true
        let resize = UIButton(configuration: .tinted())
        resize.setTitle("調整鍵盤高度", for: .normal)
        resize.addTarget(self, action: #selector(keyboardHeightTapped), for: .touchUpInside)
        resize.accessibilityIdentifier = "keyboard-settings.keyboard-height"
        let phonetic = KeyboardSettingsGroup(title: "注音與選字", identifier: "keyboard-settings.group.phonetic")
        for row in [toneOmissionRow(), spaceSelectionRow(), bigramRow(), keyboardLayoutRow(), resetLearningRow(), statusLabel] {
            phonetic.content.addArrangedSubview(row)
        }
        let tables = KeyboardSettingsGroup(title: "倉頡與簡易", identifier: "keyboard-settings.group.tables")
        for method in [ChineseInputMethod.cangjie, .simplex] {
            let view = tableOptionsView(for: method)
            tableOptionViews.append(view)
            tables.content.addArrangedSubview(view)
        }
        let appearance = KeyboardSettingsGroup(title: "外觀與操作", identifier: "keyboard-settings.group.appearance")
        for row in [candidateColorRow(), resize, layoutProfileRow(), keycapAreaRow(), fontSizeRow(), deleteShiftRow(), feedbackRow()] {
            appearance.content.addArrangedSubview(row)
        }
        let root = UIStackView(arrangedSubviews: [
            compositionModeRow(), simplifiedOutputRow(), phonetic, tables, appearance
        ])
        resetLearningButton.setTitle("重設好打注音學習紀錄", for: .normal)
        resetLearningButton.addTarget(self, action: #selector(resetLearningTapped), for: .touchUpInside)
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        header.translatesAutoresizingMaskIntoConstraints = false
        addSubview(header)
        addSubview(scroll)
        scroll.addSubview(root)
        NSLayoutConstraint.activate([
            header.leadingAnchor.constraint(equalTo: safeAreaLayoutGuide.leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: safeAreaLayoutGuide.trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: safeAreaLayoutGuide.topAnchor, constant: 10),
            scroll.topAnchor.constraint(equalTo: header.bottomAnchor, constant: 8),
            scroll.leadingAnchor.constraint(equalTo: header.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: header.trailingAnchor),
            scroll.bottomAnchor.constraint(equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8),
            root.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            root.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            root.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            root.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            root.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    @objc private func keyboardHeightTapped() {
        delegate?.settingsPanelDidRequestKeyboardHeight(self)
    }

    private func resetLearningRow() -> UIView {
        resetLearningButton.accessibilityIdentifier = "keyboard-settings.reset-learning"
        let help = helpButton(title: "重設好打注音學習紀錄",
            message: "僅清除此鍵盤的好打注音學習紀錄，自訂詞保留。App 內實體鍵盤編輯器的學習紀錄維持原狀。按鈕需按兩次確認。",
            identifier: "reset-learning")
        let row = UIStackView(arrangedSubviews: [resetLearningButton, help])
        row.alignment = .center
        row.spacing = 8
        return row
    }

    @objc private func resetLearningTapped() {
        if !resetConfirmation {
            resetConfirmation = true
            resetLearningButton.setTitle("再按一次重設此鍵盤", for: .normal)
            return
        }
        resetConfirmation = false
        resetLearningButton.setTitle("重設好打注音學習紀錄", for: .normal)
        statusLabel.isHidden = false
        statusLabel.text = delegate?.settingsPanelResetLearning(self) == true
            ? "此鍵盤學習紀錄已重設，自訂詞保留。" : "無法重設此鍵盤學習紀錄。"
    }

    private func layoutProfileRow() -> UIView {
        let profiles = KeyboardLayoutProfile.available
        let control = UISegmentedControl(items: profiles.map(\.displayName))
        control.selectedSegmentIndex = profiles.firstIndex(of: layoutProfile) ?? 0
        control.accessibilityIdentifier = "keyboard.layout-profile"
        control.accessibilityLabel = "版面"
        control.addTarget(self, action: #selector(layoutProfileChanged(_:)), for: .valueChanged)
        return layoutOptionRow(title: "版面", control: control)
    }

    @objc private func layoutProfileChanged(_ sender: UISegmentedControl) {
        guard KeyboardLayoutProfile.available.indices.contains(sender.selectedSegmentIndex) else { return }
        layoutProfile = KeyboardLayoutProfile.available[sender.selectedSegmentIndex]
        delegate?.settingsPanel(self, didChangeLayoutProfile: layoutProfile)
    }

    private func keycapAreaRow() -> UIView {
        let control = UISegmentedControl(items: KeyboardKeycapArea.allCases.map(\.displayName))
        control.selectedSegmentIndex = KeyboardKeycapArea.allCases.firstIndex(of: keycapArea) ?? 0
        control.accessibilityIdentifier = "keyboard.keycap-area"
        control.accessibilityLabel = "鍵帽間隔"
        control.addTarget(self, action: #selector(keycapAreaChanged(_:)), for: .valueChanged)
        return layoutOptionRow(title: "鍵帽間隔", control: control)
    }

    private func fontSizeRow() -> UIView {
        let control = UISegmentedControl(items: KeyboardKeyFontSize.allCases.map(\.displayName))
        control.selectedSegmentIndex = KeyboardKeyFontSize.allCases.firstIndex(of: fontSize) ?? 0
        control.accessibilityIdentifier = "keyboard.key-font-size"
        control.accessibilityLabel = "字體大小"
        control.addTarget(self, action: #selector(fontSizeChanged(_:)), for: .valueChanged)
        let help = helpButton(title: "字體大小",
            message: "「標準」保留英文鍵位提示；選擇「中」、「大」或「特大」會隱藏提示，放大主要字。",
            identifier: "key-font-size")
        return layoutOptionRow(title: "字體大小", control: control, help: help)
    }

    @objc private func fontSizeChanged(_ sender: UISegmentedControl) {
        guard KeyboardKeyFontSize.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        fontSize = KeyboardKeyFontSize.allCases[sender.selectedSegmentIndex]
        delegate?.settingsPanel(self, didChangeFontSize: fontSize)
    }

    private func deleteShiftRow() -> UIView {
        let control = UISegmentedControl(items: KeyboardDeleteShiftPosition.allCases.map(\.displayName))
        control.selectedSegmentIndex = KeyboardDeleteShiftPosition.allCases.firstIndex(of: deleteShiftPosition) ?? 0
        control.accessibilityIdentifier = "keyboard.delete-position"
        control.accessibilityLabel = "刪除鍵位置"
        control.addTarget(self, action: #selector(deleteShiftChanged(_:)), for: .valueChanged)
        return layoutOptionRow(title: "刪除鍵位置", control: control)
    }

    private func layoutOptionRow(title: String, control: UIView, help: UIButton? = nil) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText
        let heading: UIView = help.map { helpRow(label, help: $0) } ?? label
        let stack = UIStackView(arrangedSubviews: [heading, control])
        stack.axis = .vertical
        stack.spacing = 6
        return stack
    }

    @objc private func keycapAreaChanged(_ sender: UISegmentedControl) {
        guard KeyboardKeycapArea.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        keycapArea = KeyboardKeycapArea.allCases[sender.selectedSegmentIndex]
        delegate?.settingsPanel(self, didChangeKeycapArea: keycapArea)
    }

    @objc private func deleteShiftChanged(_ sender: UISegmentedControl) {
        guard KeyboardDeleteShiftPosition.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        deleteShiftPosition = KeyboardDeleteShiftPosition.allCases[sender.selectedSegmentIndex]
        delegate?.settingsPanel(self, didChangeDeleteShiftPosition: deleteShiftPosition)
    }

    private func feedbackRow() -> UIView {
        let label = UILabel()
        label.text = "按鍵音"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText

        let toggle = UISwitch()
        toggle.isOn = inputClicksEnabled
        toggle.accessibilityIdentifier = "input-clicks"
        toggle.accessibilityLabel = "按鍵音"
        toggle.addTarget(self, action: #selector(inputClicksToggled(_:)), for: .valueChanged)

        let help = helpButton(
            title: "按鍵音",
            message: "按鍵音不需完整取用。震動由 iOS 限制。",
            identifier: "input-clicks"
        )
        return helpRow(label, control: toggle, help: help)
    }

    private func compositionModeRow() -> UIView {
        let label = UILabel()
        label.text = "輸入法"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText

        compositionModeControl.selectedSegmentIndex = ChineseInputMethod.allCases.firstIndex(
            of: chineseInputMethod
        ) ?? 0
        compositionModeControl.accessibilityIdentifier = "bopomofo-composition-mode"
        compositionModeControl.accessibilityLabel = "輸入法"
        compositionModeControl.addTarget(
            self, action: #selector(compositionModeChanged(_:)), for: .valueChanged
        )

        let row = UIStackView(arrangedSubviews: [label, compositionModeControl])
        row.axis = .vertical
        row.alignment = .center
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
        return row
    }

    private func simplifiedOutputRow() -> UIView {
        let title = SimplifiedChineseOutputSettings.displayName
        let label = UILabel()
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.primaryText
        label.isAccessibilityElement = false

        let toggle = UISwitch()
        toggle.isOn = simplifiedOutputEnabled
        toggle.accessibilityLabel = title
        toggle.accessibilityIdentifier = "keyboard-settings.simplified-chinese-output"
        toggle.addTarget(self, action: #selector(simplifiedOutputChanged(_:)), for: .valueChanged)
        let help = helpButton(
            title: title,
            message: "開啟後，接下來送出的文字會轉成簡體，組字和候選仍顯示繁體。這裡的選擇會保存在鍵盤。要套用 App 的虛擬鍵盤設定，請到琦琦 App 首頁 →「虛擬鍵盤調整設定」，按最上方的「套用到鍵盤」。實體鍵盤設定及上下緣高度維持原狀。",
            identifier: "simplified-chinese-output"
        )
        return helpRow(label, control: toggle, help: help)
    }

    @objc private func simplifiedOutputChanged(_ sender: UISwitch) {
        delegate?.settingsPanel(self, didChangeSimplifiedOutput: sender.isOn)
    }

    private func tableOptionsView(for method: ChineseInputMethod) -> KeyboardTableOptionsView {
        KeyboardTableOptionsView(method: method, identifierPrefix: "keyboard-settings.table", foreground: Palette.primaryText,
            read: { [weak self] in
                self?.methodSettings.options(for: method, virtualKeyboard: true) ?? TableInputOptions(method: method)
            }, write: { [weak self] options in
                guard let self else { return }
                self.methodSettings.setOptions(options, for: method, virtualKeyboard: true)
                self.delegate?.settingsPanelDidChangeTableOptions(self)
                self.tableOptionViews.forEach { $0.refresh() }
            }, showHelp: { [weak self] title, message, source in
                self?.showHelp(title: title, message: message, source: source)
            })
    }

    private func spaceSelectionRow() -> UIView {
        let title = "好打注音使用空白鍵選字"
        let label = UILabel(); label.text = title; label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Palette.primaryText
        let toggle = UISwitch()
        toggle.isOn = SmartMandarinSpaceSettings().enabled
        toggle.accessibilityIdentifier = "space-selects-candidates"
        toggle.accessibilityLabel = title
        toggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.settingsPanel(self, didChangeSpaceSelection: toggle.isOn)
        }, for: .valueChanged)
        return helpRow(label, control: toggle, help: helpButton(title: title,
            message: "開啟後，空白鍵可完成讀音、開啟候選及翻頁。選擇保存在鍵盤，不需完整取用。",
            identifier: "space-selects-candidates"))
    }
    private func bigramRow() -> UIView {
        let title = "使用上下文選字"
        let label = UILabel(); label.text = title; label.font = .preferredFont(forTextStyle: .subheadline)
        label.textColor = Palette.primaryText
        let shared = UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier)
        let toggle = UISwitch()
        toggle.isOn = KeyboardTypingSettings(sharedDefaults: shared).options.useBigrams
        toggle.accessibilityIdentifier = "keyboard-settings.use-bigrams"
        toggle.accessibilityLabel = title
        toggle.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            self.delegate?.settingsPanel(self, didChangeUseBigrams: toggle.isOn)
        }, for: .valueChanged)
        return helpRow(label, control: toggle, help: helpButton(title: title,
            message: "使用前後文協助好打注音選詞，預設開啟。完成目前組字後生效。", identifier: "use-bigrams"))
    }

    private func toneOmissionRow() -> UIView {
        let label = UILabel()
        let title = SmartMandarinToneOmissionSettings.displayName
        label.text = title
        label.font = .preferredFont(forTextStyle: .subheadline)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = Palette.primaryText

        let control = UISwitch()
        control.isOn = omitsTones
        control.accessibilityLabel = SmartMandarinToneOmissionSettings.displayName
        control.accessibilityIdentifier = "keyboard-settings.omit-tones"
        control.addTarget(self, action: #selector(toneOmissionChanged(_:)), for: .valueChanged)
        let help = helpButton(
            title: title,
            message: "標準注音、許氏、漢語拼音、倚天與倚天 26 鍵都可連續輸入讀音，也可照常輸入聲調。",
            identifier: "omit-tones"
        )
        return helpRow(label, control: control, help: help)
    }

    @objc private func toneOmissionChanged(_ sender: UISwitch) {
        delegate?.settingsPanel(self, didChangeToneOmission: sender.isOn)
    }

    private func keyboardLayoutRow() -> UIView {
        let label = UILabel()
        label.text = "注音鍵盤"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText
        let control = UISegmentedControl(items: BopomofoKeyboardLayout.allCases.map(\.displayName))
        control.apportionsSegmentWidthsByContent = true
        control.selectedSegmentIndex = BopomofoKeyboardLayout.allCases.firstIndex(of: keyboardLayout) ?? 0
        control.accessibilityIdentifier = "bopomofo-keyboard-layout"
        control.accessibilityLabel = "注音鍵盤"
        control.addTarget(self, action: #selector(keyboardLayoutChanged(_:)), for: .valueChanged)
        let help = helpButton(
            title: "注音鍵盤",
            message: BopomofoKeyboardLayout.settingsHelp,
            identifier: "keyboard-layout"
        )
        let row = UIStackView(arrangedSubviews: [helpRow(label, help: help), control])
        row.axis = .vertical
        return row
    }

    @objc private func keyboardLayoutChanged(_ sender: UISegmentedControl) {
        let layouts = BopomofoKeyboardLayout.allCases
        guard layouts.indices.contains(sender.selectedSegmentIndex) else { return }
        keyboardLayout = layouts[sender.selectedSegmentIndex]
        delegate?.settingsPanel(self, didChangeKeyboardLayout: keyboardLayout)
    }

    private func candidateColorRow() -> UIView {
        let label = UILabel()
        label.text = "候選字底色"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText

        candidateColorControl.selectedSegmentIndex = CandidateColor.allCases.firstIndex(
            of: candidateColor
        ) ?? 0
        candidateColorControl.accessibilityIdentifier = "candidate-color"
        candidateColorControl.accessibilityLabel = "候選字底色"
        candidateColorControl.addTarget(
            self, action: #selector(candidateColorChanged(_:)), for: .valueChanged
        )
        refreshCandidateColorControl()

        let row = UIStackView(arrangedSubviews: [label, UIView(), candidateColorControl])
        row.alignment = .center
        row.spacing = 8
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
        return row
    }

    private func refreshCandidateColorControl() {
        candidateColorControl.selectedSegmentTintColor = Palette.candidateHighlight(
            for: candidateColor
        )
        candidateColorControl.setTitleTextAttributes(
            [.foregroundColor: Palette.primaryText], for: .normal
        )
        candidateColorControl.setTitleTextAttributes(
            [.foregroundColor: Palette.candidateHighlightText(for: candidateColor)],
            for: .selected
        )
    }

    private func helpRow(_ label: UILabel, control: UIView? = nil, help: UIButton) -> UIView {
        label.numberOfLines = 0
        let row = UIStackView(arrangedSubviews: [label])
        if let control {
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            row.addArrangedSubview(control)
        }
        row.addArrangedSubview(help)
        row.alignment = .center
        row.spacing = 8
        return row
    }

    private func helpButton(title: String, message: String, identifier: String) -> UIButton {
        let button = UIButton(type: .system)
        button.setImage(UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        button.tintColor = Palette.primaryText
        button.accessibilityLabel = "\(title)說明"
        button.accessibilityIdentifier = "keyboard-settings.help." + identifier
        button.widthAnchor.constraint(equalToConstant: 44).isActive = true
        button.heightAnchor.constraint(equalToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self, weak button] _ in
            guard let button else { return }
            self?.showHelp(title: title, message: message, source: button)
        }, for: .touchUpInside)
        return button
    }

    private func showHelp(title: String, message: String, source: UIButton) {
        guard helpOverlay == nil else { return }
        let overlay = UIView()
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        overlay.accessibilityViewIsModal = true

        let card = UIView()
        card.backgroundColor = Palette.surface
        card.layer.cornerRadius = 12

        let heading = UILabel()
        heading.text = title
        heading.textColor = Palette.primaryText
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.numberOfLines = 0
        heading.accessibilityTraits.insert(.header)
        heading.accessibilityIdentifier = "keyboard-settings.help.title"

        let detail = UILabel()
        detail.text = message
        detail.textColor = Palette.primaryText
        detail.font = .preferredFont(forTextStyle: .body)
        detail.adjustsFontForContentSizeCategory = true
        detail.numberOfLines = 0
        detail.accessibilityIdentifier = "keyboard-settings.help.message"

        let text = UIStackView(arrangedSubviews: [heading, detail])
        text.axis = .vertical
        text.spacing = 8
        let scroll = UIScrollView()

        let close = UIButton(configuration: .tinted())
        close.setTitle("關閉", for: .normal)
        close.accessibilityIdentifier = "keyboard-settings.help.close"
        close.addTarget(self, action: #selector(closeHelp), for: .touchUpInside)

        for view in [overlay, card, scroll, text, close] {
            view.translatesAutoresizingMaskIntoConstraints = false
        }
        addSubview(overlay)
        overlay.addSubview(card)
        card.addSubview(scroll)
        card.addSubview(close)
        scroll.addSubview(text)

        let safe = overlay.safeAreaLayoutGuide
        let cardWidth = card.widthAnchor.constraint(equalTo: safe.widthAnchor, constant: -24)
        cardWidth.priority = .defaultHigh
        let contentHeight = scroll.frameLayoutGuide.heightAnchor.constraint(equalTo: text.heightAnchor)
        contentHeight.priority = .defaultLow
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: trailingAnchor),
            overlay.topAnchor.constraint(equalTo: topAnchor),
            overlay.bottomAnchor.constraint(equalTo: bottomAnchor),
            card.centerXAnchor.constraint(equalTo: safe.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: safe.centerYAnchor),
            card.topAnchor.constraint(greaterThanOrEqualTo: safe.topAnchor, constant: 8),
            card.bottomAnchor.constraint(lessThanOrEqualTo: safe.bottomAnchor, constant: -8),
            card.widthAnchor.constraint(lessThanOrEqualToConstant: 440),
            cardWidth,
            scroll.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: card.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: close.topAnchor, constant: -4),
            contentHeight,
            text.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            text.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            text.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            text.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            text.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor),
            close.centerXAnchor.constraint(equalTo: card.centerXAnchor),
            close.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -6),
            close.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            close.widthAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])
        helpOverlay = overlay
        helpSource = source
        layoutIfNeeded()
        UIAccessibility.post(notification: .screenChanged, argument: heading)
    }

    @objc private func closeHelp() {
        helpOverlay?.removeFromSuperview()
        helpOverlay = nil
        UIAccessibility.post(notification: .screenChanged, argument: helpSource)
        helpSource = nil
    }

    override func accessibilityPerformEscape() -> Bool {
        guard helpOverlay != nil else { return super.accessibilityPerformEscape() }
        closeHelp()
        return true
    }

    // MARK: - Actions

    @objc private func inputClicksToggled(_ sender: UISwitch) {
        inputClicksEnabled = sender.isOn
        delegate?.settingsPanel(self, didChangeInputClicksEnabled: inputClicksEnabled)
    }

    @objc private func compositionModeChanged(_ sender: UISegmentedControl) {
        let modes = ChineseInputMethod.allCases
        let index = min(max(sender.selectedSegmentIndex, 0), modes.count - 1)
        chineseInputMethod = modes[index]
        delegate?.settingsPanel(self, didChangeInputMethod: chineseInputMethod)
    }

    @objc private func candidateColorChanged(_ sender: UISegmentedControl) {
        let index = min(max(sender.selectedSegmentIndex, 0), CandidateColor.allCases.count - 1)
        candidateColor = CandidateColor.allCases[index]
        refreshCandidateColorControl()
        delegate?.settingsPanel(self, didChangeCandidateColor: candidateColor)
    }

    @objc private func closeTapped() {
        delegate?.settingsPanelDidClose(self)
    }
}

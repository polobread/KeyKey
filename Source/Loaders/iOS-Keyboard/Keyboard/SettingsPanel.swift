import KeyKeyEngine
import UIKit

@MainActor
protocol SettingsPanelDelegate: AnyObject {
    func settingsPanel(_ panel: SettingsPanel, didChangeInputMethod method: ChineseInputMethod)
    func settingsPanelDidChangeTableOptions(_ panel: SettingsPanel)
    func settingsPanel(
        _ panel: SettingsPanel, didChangeCompositionMode mode: BopomofoCompositionMode
    )
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
    private let omitsTones: Bool
    private let statusLabel = UILabel()
    private let candidateColorControl = UISegmentedControl(
        items: ["紫", "綠", "黃", "紅"]
    )
    private let compositionModeControl = UISegmentedControl(
        items: ChineseInputMethod.allCases.map(\.displayName)
    )
    private let resetLearningButton = UIButton(configuration: .tinted())
    private var resetConfirmation = false

    init(
        inputClicksEnabled: Bool, candidateColor: CandidateColor,
        compositionMode: BopomofoCompositionMode,
        chineseInputMethod: ChineseInputMethod = .smart,
        methodSettings: ChineseInputMethodSettings = ChineseInputMethodSettings(),
        keyboardLayout: BopomofoKeyboardLayout = .standard, omitsTones: Bool = false,
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
        title.text = "輸入法設定"
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
        let root = UIStackView(arrangedSubviews: [
            compositionModeRow(), spaceSelectionRow(), resetLearningButton, statusLabel, keyboardLayoutRow(),
            toneOmissionRow(),
            tableOptionsButton(for: .cangjie), tableOptionsButton(for: .simplex),
            candidateColorRow(), resize, layoutProfileRow(), keycapAreaRow(), fontSizeRow(), deleteShiftRow(),
            feedbackRow()
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

    @objc private func resetLearningTapped() {
        if !resetConfirmation {
            resetConfirmation = true
            resetLearningButton.setTitle("再按一次確認重設", for: .normal)
            return
        }
        resetConfirmation = false
        resetLearningButton.setTitle("重設好打注音學習紀錄", for: .normal)
        statusLabel.isHidden = false
        statusLabel.text = delegate?.settingsPanelResetLearning(self) == true
            ? "學習紀錄已重設，自訂詞保留。" : "無法重設學習紀錄。"
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
        control.accessibilityLabel = "字體"
        control.addTarget(self, action: #selector(fontSizeChanged(_:)), for: .valueChanged)
        return layoutOptionRow(title: "字體", control: control)
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

    private func layoutOptionRow(title: String, control: UIView) -> UIView {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText
        let stack = UIStackView(arrangedSubviews: [label, control])
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

        let detail = UILabel()
        detail.text = "不需完整取用；震動由 iOS 限制"
        detail.font = .systemFont(ofSize: 11)
        detail.textColor = Palette.hintText

        let labels = UIStackView(arrangedSubviews: [label, detail])
        labels.axis = .vertical
        labels.spacing = 1

        let toggle = UISwitch()
        toggle.isOn = inputClicksEnabled
        toggle.onTintColor = Palette.highlight
        toggle.accessibilityIdentifier = "input-clicks"
        toggle.accessibilityLabel = "按鍵音"
        toggle.addTarget(self, action: #selector(inputClicksToggled(_:)), for: .valueChanged)

        let row = UIStackView(arrangedSubviews: [labels, UIView(), toggle])
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        row.directionalLayoutMargins = .init(top: 4, leading: 0, bottom: 4, trailing: 0)
        return row
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

    private func tableOptionsButton(for method: ChineseInputMethod) -> UIButton {
        let button = UIButton(configuration: .tinted())
        button.setTitle(method.displayName + (method == .cangjie ? "設定（虛擬鍵盤）" : "設定"), for: .normal)
        button.accessibilityIdentifier = "table-options." + method.rawValue
        button.showsMenuAsPrimaryAction = true
        refreshTableOptions(button, for: method)
        return button
    }

    private func refreshTableOptions(_ button: UIButton, for method: ChineseInputMethod) {
        let options = methodSettings.options(for: method, virtualKeyboard: true)
        var children: [UIMenuElement] = options.switches(for: method).map { item in
            UIAction(title: item.title, attributes: item.key == "prefix" && !options.composeWhileTyping ? .disabled : [], state: item.enabled ? .on : .off) { [weak self, weak button] _ in
                guard let self, let button else { return }
                var next = self.methodSettings.options(for: method, virtualKeyboard: true)
                next.toggle(item.key)
                self.methodSettings.setOptions(next, for: method, virtualKeyboard: true)
                self.delegate?.settingsPanelDidChangeTableOptions(self)
                self.refreshTableOptions(button, for: method)
            }
        }
        if method == .cangjie {
            children.append(UIMenu(title: "標點", children: ["原字表", "中英混合", "半形"].enumerated().map { index, title in
                UIAction(title: title, state: options.punctuation == index ? .on : .off) { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    var next = self.methodSettings.options(for: method, virtualKeyboard: true)
                    next.punctuation = index
                    self.methodSettings.setOptions(next, for: method, virtualKeyboard: true)
                    self.delegate?.settingsPanelDidChangeTableOptions(self)
                    self.refreshTableOptions(button, for: method)
                }
            }))
        }
        button.menu = UIMenu(title: method.displayName + "設定", children: children)
    }

    private func spaceSelectionRow() -> UIView {
        let label = UILabel()
        let enabled = SmartMandarinSpaceSettings().enabled
        label.text = "使用空白鍵選字：\(enabled ? "開啟" : "關閉")\n與實體鍵盤共用；請至琦琦 App 的「輸入法設定」調整。"
        label.font = .systemFont(ofSize: 14)
        label.textColor = Palette.primaryText
        label.numberOfLines = 0
        label.accessibilityIdentifier = "space-selects-candidates"
        return label
    }

    private func toneOmissionRow() -> UIView {
        let label = UILabel()
        label.text = SmartMandarinToneOmissionSettings.displayName
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText

        let control = UISwitch()
        control.isOn = omitsTones
        control.accessibilityLabel = SmartMandarinToneOmissionSettings.displayName
        control.accessibilityIdentifier = "keyboard-settings.omit-tones"
        control.addTarget(self, action: #selector(toneOmissionChanged(_:)), for: .valueChanged)
        let row = UIStackView(arrangedSubviews: [label, UIView(), control])
        row.alignment = .center
        row.spacing = 8

        let hint = UILabel()
        hint.text = "標準注音、許氏與漢語拼音都可連續輸入讀音，也可照常輸入聲調。"
        hint.font = .systemFont(ofSize: 13)
        hint.textColor = Palette.hintText
        hint.numberOfLines = 0
        let section = UIStackView(arrangedSubviews: [row, hint])
        section.axis = .vertical
        section.spacing = 4
        return section
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
        let row = UIStackView(arrangedSubviews: [label, UIView(), control])
        row.alignment = .center
        row.spacing = 8
        return row
    }

    @objc private func keyboardLayoutChanged(_ sender: UISegmentedControl) {
        keyboardLayout = BopomofoKeyboardLayout.allCases[sender.selectedSegmentIndex]
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

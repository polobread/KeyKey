import KeyKeyEngine
import UIKit

@MainActor
protocol SettingsPanelDelegate: AnyObject {
    func settingsPanel(_ panel: SettingsPanel, didChangeInputMethod method: ChineseInputMethod)
    func settingsPanelDidChangeTableOptions(_ panel: SettingsPanel)
    func settingsPanel(_ panel: SettingsPanel, didChange enabled: Set<String>)
    func settingsPanel(
        _ panel: SettingsPanel, didChangeCompositionMode mode: BopomofoCompositionMode
    )
    func settingsPanel(_ panel: SettingsPanel, didChangeInputClicksEnabled enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeCandidateColor color: CandidateColor)
    func settingsPanel(_ panel: SettingsPanel, didChangeKeyboardLayout layout: BopomofoKeyboardLayout)
    func settingsPanelResetLearning(_ panel: SettingsPanel) -> Bool
    func settingsPanelDidClose(_ panel: SettingsPanel)
}

/// The associated-phrase collection picker, shown over the keyboard when the
/// 「設」 key is pressed.
///
/// It lives inside the input view rather than in the container app: keeping the
/// settings in the extension's own sandbox is what lets the keyboard ship
/// without Full Access. The list scrolls, so thirty collections fit.
final class SettingsPanel: UIView {
    weak var delegate: SettingsPanelDelegate?

    private let collections: [AssociatedPhraseStore.Collection]
    private var enabled: Set<String>
    private var inputClicksEnabled: Bool
    private var candidateColor: CandidateColor
    private var compositionMode: BopomofoCompositionMode
    private var chineseInputMethod: ChineseInputMethod
    private let methodSettings: ChineseInputMethodSettings
    private var keyboardLayout: BopomofoKeyboardLayout
    private let statusLabel = UILabel()
    private let candidateColorControl = UISegmentedControl(
        items: ["紫", "綠", "黃", "紅"]
    )
    private let compositionModeControl = UISegmentedControl(
        items: ChineseInputMethod.allCases.map(\.displayName)
    )
    private var switches: [String: UISwitch] = [:]
    private let resetLearningButton = UIButton(configuration: .tinted())
    private var resetConfirmation = false

    init(
        collections: [AssociatedPhraseStore.Collection], enabled: Set<String>,
        inputClicksEnabled: Bool, candidateColor: CandidateColor,
        compositionMode: BopomofoCompositionMode,
        chineseInputMethod: ChineseInputMethod = .smart,
        methodSettings: ChineseInputMethodSettings = ChineseInputMethodSettings(),
        keyboardLayout: BopomofoKeyboardLayout = .standard
    ) {
        self.collections = collections
        self.enabled = enabled
        self.inputClicksEnabled = inputClicksEnabled
        self.candidateColor = candidateColor
        self.compositionMode = compositionMode
        self.chineseInputMethod = chineseInputMethod
        self.methodSettings = methodSettings
        self.keyboardLayout = keyboardLayout
        super.init(frame: .zero)
        backgroundColor = Palette.surface
        buildInterface()
        refreshStatus()
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

        let bulk = UIStackView(arrangedSubviews: [
            bulkButton("全部啟用", #selector(enableAll)),
            bulkButton("僅小麥注音", #selector(enableBaseOnly)),
            bulkButton("全部關閉", #selector(disableAll))
        ])
        bulk.distribution = .fillEqually
        bulk.spacing = 6

        let rows = UIStackView(arrangedSubviews: collections.map(collectionRow))
        rows.axis = .vertical
        rows.spacing = 0

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        let root = UIStackView(arrangedSubviews: [
            compositionModeRow(), tableOptionsButton(for: .cangjie), tableOptionsButton(for: .simplex), keyboardLayoutRow(), resetLearningButton, feedbackRow(), candidateColorRow(),
            statusLabel, bulk, rows
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
            header.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            header.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            header.topAnchor.constraint(equalTo: topAnchor, constant: 10),
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

    private func bulkButton(_ title: String, _ action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.buttonSize = .small
        let button = UIButton(configuration: configuration)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func resetLearningTapped() {
        if !resetConfirmation {
            resetConfirmation = true
            resetLearningButton.setTitle("再按一次確認重設", for: .normal)
            return
        }
        resetConfirmation = false
        resetLearningButton.setTitle("重設好打注音學習紀錄", for: .normal)
        statusLabel.text = delegate?.settingsPanelResetLearning(self) == true
            ? "學習紀錄已重設，自訂詞保留。" : "無法重設學習紀錄。"
    }

    private func collectionRow(_ collection: AssociatedPhraseStore.Collection) -> UIView {
        let label = UILabel()
        label.text = collection.display
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText

        let toggle = UISwitch()
        toggle.isOn = enabled.contains(collection.source)
        toggle.onTintColor = Palette.highlight
        toggle.accessibilityIdentifier = collection.source
        toggle.accessibilityLabel = collection.display
        toggle.addTarget(self, action: #selector(toggled(_:)), for: .valueChanged)
        switches[collection.source] = toggle

        let row = UIStackView(arrangedSubviews: [label, UIView(), toggle])
        row.alignment = .center
        row.isLayoutMarginsRelativeArrangement = true
        // 44pt keeps every row a comfortable target inside a short panel.
        row.directionalLayoutMargins = .init(top: 6, leading: 0, bottom: 6, trailing: 0)
        row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        return row
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
        button.setTitle(method.displayName + "設定", for: .normal)
        button.accessibilityIdentifier = "table-options." + method.rawValue
        button.showsMenuAsPrimaryAction = true
        refreshTableOptions(button, for: method)
        return button
    }

    private func refreshTableOptions(_ button: UIButton, for method: ChineseInputMethod) {
        let options = methodSettings.options(for: method)
        var children: [UIMenuElement] = options.switches(for: method).map { item in
            UIAction(title: item.title, state: item.enabled ? .on : .off) { [weak self, weak button] _ in
                guard let self, let button else { return }
                var next = self.methodSettings.options(for: method)
                next.toggle(item.key)
                self.methodSettings.setOptions(next, for: method)
                self.delegate?.settingsPanelDidChangeTableOptions(self)
                self.refreshTableOptions(button, for: method)
            }
        }
        if method == .cangjie {
            children.append(UIMenu(title: "標點", children: ["原字表", "中英混合", "半形"].enumerated().map { index, title in
                UIAction(title: title, state: options.punctuation == index ? .on : .off) { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    var next = self.methodSettings.options(for: method)
                    next.punctuation = index
                    self.methodSettings.setOptions(next, for: method)
                    self.delegate?.settingsPanelDidChangeTableOptions(self)
                    self.refreshTableOptions(button, for: method)
                }
            }))
        }
        button.menu = UIMenu(title: method.displayName + "設定", children: children)
    }

    private func keyboardLayoutRow() -> UIView {
        let label = UILabel()
        label.text = "注音鍵盤"
        label.font = .systemFont(ofSize: 15)
        label.textColor = Palette.primaryText
        let control = UISegmentedControl(items: BopomofoKeyboardLayout.allCases.map(\.displayName))
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

    @objc private func toggled(_ sender: UISwitch) {
        guard let source = sender.accessibilityIdentifier else { return }
        if sender.isOn {
            enabled.insert(source)
        } else {
            enabled.remove(source)
        }
        publish()
    }

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

    @objc private func enableAll() {
        enabled = Set(collections.map(\.source))
        syncSwitches()
    }

    @objc private func enableBaseOnly() {
        enabled = [PhraseSettings.baseCollection]
        syncSwitches()
    }

    @objc private func disableAll() {
        enabled = []
        syncSwitches()
    }

    @objc private func closeTapped() {
        delegate?.settingsPanelDidClose(self)
    }

    /// Set every switch without letting each one publish a separate change.
    private func syncSwitches() {
        for (source, toggle) in switches {
            toggle.setOn(enabled.contains(source), animated: true)
        }
        publish()
    }

    private func publish() {
        refreshStatus()
        delegate?.settingsPanel(self, didChange: enabled)
    }

    private func refreshStatus() {
        statusLabel.text = enabled.isEmpty
            ? "關聯詞已全部關閉"
            : "已啟用 \(enabled.count)／\(collections.count) 個詞庫"
    }
}

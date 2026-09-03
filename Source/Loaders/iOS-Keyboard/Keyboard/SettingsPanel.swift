import KeyKeyEngine
import UIKit

@MainActor
protocol SettingsPanelDelegate: AnyObject {
    func settingsPanel(_ panel: SettingsPanel, didChange enabled: Set<String>)
    func settingsPanel(_ panel: SettingsPanel, didChangeInputClicksEnabled enabled: Bool)
    func settingsPanel(_ panel: SettingsPanel, didChangeCandidateColor color: CandidateColor)
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
    private let statusLabel = UILabel()
    private let candidateColorControl = UISegmentedControl(
        items: ["紫", "綠", "黃", "紅"]
    )
    private var switches: [String: UISwitch] = [:]

    init(
        collections: [AssociatedPhraseStore.Collection], enabled: Set<String>,
        inputClicksEnabled: Bool, candidateColor: CandidateColor
    ) {
        self.collections = collections
        self.enabled = enabled
        self.inputClicksEnabled = inputClicksEnabled
        self.candidateColor = candidateColor
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
        title.text = "關聯詞詞庫"
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
        rows.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        NSLayoutConstraint.activate([
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])

        let root = UIStackView(arrangedSubviews: [
            header, feedbackRow(), candidateColorRow(), statusLabel, bulk, scroll
        ])
        root.axis = .vertical
        root.spacing = 8
        root.translatesAutoresizingMaskIntoConstraints = false
        addSubview(root)
        NSLayoutConstraint.activate([
            root.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            root.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            root.topAnchor.constraint(equalTo: topAnchor, constant: 10),
            root.bottomAnchor.constraint(
                equalTo: safeAreaLayoutGuide.bottomAnchor, constant: -8
            )
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

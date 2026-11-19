// Copyright (c) 2026 Chui-Ping Cheng. MIT License.
import KeyKeyEngine
import UIKit

/// Frontend-only settings presentation shared by the App and keyboard extension.
@MainActor
final class KeyboardSettingsGroup: UIStackView {
    let content = UIStackView()
    private let header = UIButton(type: .system)
    private let body = UIView()
    private var expanded = false

    init(title: String, identifier: String) {
        super.init(frame: .zero)
        axis = .vertical
        spacing = 10
        var configuration = UIButton.Configuration.tinted()
        configuration.title = title
        configuration.image = UIImage(systemName: "chevron.right")
        configuration.imagePlacement = .trailing
        configuration.imagePadding = 8
        configuration.contentInsets = .init(top: 12, leading: 12, bottom: 12, trailing: 12)
        header.configuration = configuration
        header.contentHorizontalAlignment = .leading
        header.accessibilityIdentifier = identifier
        header.accessibilityValue = "collapsed"
        header.accessibilityHint = "展開設定選項"
        header.addAction(UIAction { [weak self] _ in self?.toggle() }, for: .touchUpInside)
        content.axis = .vertical
        content.spacing = 12
        content.accessibilityIdentifier = identifier + ".content"
        content.translatesAutoresizingMaskIntoConstraints = false
        body.clipsToBounds = true
        body.addSubview(content)
        let bottom = content.bottomAnchor.constraint(equalTo: body.bottomAnchor)
        bottom.priority = .defaultHigh
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: body.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: body.trailingAnchor),
            content.topAnchor.constraint(equalTo: body.topAnchor), bottom
        ])
        body.isHidden = true
        addArrangedSubview(header)
        addArrangedSubview(body)
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    private func toggle() {
        expanded.toggle()
        body.isHidden = !expanded
        header.configuration?.image = UIImage(systemName: expanded ? "chevron.down" : "chevron.right")
        header.accessibilityValue = expanded ? "expanded" : "collapsed"
        header.accessibilityHint = expanded ? "收合設定選項" : "展開設定選項"
    }
}

/// Keeps the same controls and layout while mutually dependent switches refresh.
@MainActor
final class KeyboardTableOptionsView: UIStackView {
    private let method: ChineseInputMethod
    private let readOptions: () -> TableInputOptions
    private let writeOptions: (TableInputOptions) -> Void
    private var switches: [String: UISwitch] = [:]
    private var punctuation: UISegmentedControl?

    init(method: ChineseInputMethod, identifierPrefix: String, foreground: UIColor = .label,
         optionFont: UIFont = .preferredFont(forTextStyle: .subheadline), infoTintColor: UIColor? = nil,
         read: @escaping () -> TableInputOptions, write: @escaping (TableInputOptions) -> Void,
         showHelp: @escaping (String, String, UIButton) -> Void) {
        self.method = method
        readOptions = read
        writeOptions = write
        super.init(frame: .zero)
        axis = .vertical
        spacing = 10
        let heading = UILabel()
        heading.text = method.displayName
        heading.font = .preferredFont(forTextStyle: .headline)
        heading.adjustsFontForContentSizeCategory = true
        heading.textColor = foreground
        addArrangedSubview(heading)
        for item in read().switches(for: method) {
            let label = UILabel()
            label.text = item.title
            label.font = optionFont
            label.adjustsFontForContentSizeCategory = true
            label.numberOfLines = 0
            label.textColor = foreground
            label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            let control = UISwitch()
            control.onTintColor = .systemGreen
            let identifier = identifierPrefix + "." + method.rawValue + "." + item.key
            control.accessibilityIdentifier = identifier
            control.accessibilityLabel = item.title
            control.setContentHuggingPriority(.required, for: .horizontal)
            control.setContentCompressionResistancePriority(.required, for: .horizontal)
            switches[item.key] = control
            control.addAction(UIAction { [weak self] _ in
                guard let self else { return }
                var options = self.readOptions()
                options.toggle(item.key)
                self.writeOptions(options)
                self.refresh()
            }, for: .valueChanged)
            let info = Self.infoButton(identifier: identifier + ".info", title: item.title,
                message: Self.help(for: item.key), foreground: infoTintColor ?? foreground, showHelp: showHelp)
            let row = UIStackView(arrangedSubviews: [label, control, info])
            row.alignment = .center
            row.spacing = 8
            addArrangedSubview(row)
        }
        if method == .cangjie {
            let label = UILabel()
            label.text = "標點"
            label.font = optionFont
            label.adjustsFontForContentSizeCategory = true
            label.textColor = foreground
            let info = Self.infoButton(identifier: identifierPrefix + ".cangjie.punctuation.info",
                title: "標點", message: "選擇沿用原字表、中英混合或半形標點。", foreground: infoTintColor ?? foreground,
                showHelp: showHelp)
            let control = UISegmentedControl(items: ["原字表", "中英混合", "半形"])
            control.accessibilityIdentifier = identifierPrefix + ".cangjie.punctuation"
            control.accessibilityLabel = "標點"
            control.addAction(UIAction { [weak self, weak control] _ in
                guard let self, let control else { return }
                var options = self.readOptions()
                options.punctuation = control.selectedSegmentIndex
                self.writeOptions(options)
                self.refresh()
            }, for: .valueChanged)
            punctuation = control
            let row = UIStackView(arrangedSubviews: [label, control, info])
            row.alignment = .center
            row.spacing = 8
            addArrangedSubview(row)
        }
        refresh()
    }
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    func refresh() {
        let options = readOptions()
        for item in options.switches(for: method) {
            switches[item.key]?.isOn = item.enabled
            switches[item.key]?.isEnabled = item.key != "prefix" || options.composeWhileTyping
        }
        punctuation?.selectedSegmentIndex = options.punctuation
    }
    private static func infoButton(identifier: String, title: String, message: String,
                                   foreground: UIColor,
                                   showHelp: @escaping (String, String, UIButton) -> Void) -> UIButton {
        let info = UIButton(type: .system)
        info.setImage(UIImage(systemName: "info.circle", withConfiguration: UIImage.SymbolConfiguration(pointSize: 20)), for: .normal)
        info.tintColor = foreground
        info.accessibilityIdentifier = identifier
        info.accessibilityLabel = "查看「\(title)」說明"
        info.widthAnchor.constraint(equalToConstant: 44).isActive = true
        info.heightAnchor.constraint(equalToConstant: 44).isActive = true
        info.addAction(UIAction { [weak info] _ in
            guard let info else { return }
            showHelp(title, message, info)
        }, for: .touchUpInside)
        return info
    }
    private static func help(for key: String) -> String {
        switch key {
        case "realtime": "輸入字根時立即顯示候選。開啟後會關閉錯碼清除。"
        case "prefix": "字根尚未打完時也列出可選字。需先開啟即時候選；停用時保留原選擇。"
        case "clear": "沒有對應字時清除錯碼。開啟後會關閉即時候選。"
        case "maximum": "倉頡輸入滿五碼時開啟候選。"
        case "learning": "依照之前的選字紀錄調整候選順序。"
        default: ""
        }
    }
}

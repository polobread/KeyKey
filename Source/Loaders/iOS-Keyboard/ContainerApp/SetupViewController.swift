import UIKit

/// Setup guidance, mirroring the Android launcher screen. The keyboard itself
/// carries the settings, so this screen only has to get the user to the point
/// where the keyboard is enabled and selected.
final class SetupViewController: UIViewController {
    private let supporterStore = SupporterStore()
    private let supporterPrice = UILabel()
    private let supporterButton = UIButton(configuration: .filled())
    private let restoreButton = UIButton(configuration: .plain())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = label("琦琦注音", size: 28, weight: .bold)
        let subtitle = label(
            "注音輸入法，支援直式與橫式鍵盤、候選字、關聯詞與符號面板。",
            size: 16, weight: .regular
        )
        subtitle.textColor = .secondaryLabel

        let steps = label(
            """
            1. 開啟「設定 → 一般 → 鍵盤 → 鍵盤 → 加入新的鍵盤」
            2. 在「第三方鍵盤」中選擇「琦琦注音」
            3. 打字時長按地球鍵切換到琦琦注音

            鍵盤上的「設」鍵可以調整關聯詞詞庫。
            """,
            size: 15, weight: .regular
        )

        let openSettings = UIButton(configuration: .filled())
        openSettings.setTitle("開啟「設定」", for: .normal)
        openSettings.addTarget(self, action: #selector(openSystemSettings), for: .touchUpInside)

        let note = label(
            "鍵盤不需要「完整取用權限」，不連線、不收集輸入內容。付費支持由 App Store 處理。",
            size: 13, weight: .regular
        )
        note.textColor = .tertiaryLabel

        let supporterTitle = label("支持開發", size: 20, weight: .semibold)
        supporterTitle.textColor = .tintColor

        let supporterDescription = label(
            "琦琦輸入法即使未付費也可以繼續完整使用。如果覺得好用，歡迎一次付費支持後續維護與開發。",
            size: 14, weight: .regular
        )
        supporterDescription.textColor = .secondaryLabel

        supporterPrice.font = .preferredFont(forTextStyle: .body)
        supporterPrice.textColor = .tintColor
        supporterPrice.textAlignment = .center
        supporterPrice.numberOfLines = 0
        supporterPrice.accessibilityIdentifier = "supporter.price"
        supporterPrice.isHidden = true

        supporterButton.setTitle("正在確認…", for: .normal)
        supporterButton.accessibilityIdentifier = "supporter.purchase"
        supporterButton.isEnabled = false
        supporterButton.addTarget(self, action: #selector(purchaseSupport), for: .touchUpInside)

        restoreButton.setTitle("恢復購買", for: .normal)
        restoreButton.accessibilityIdentifier = "supporter.restore"
        restoreButton.isEnabled = false
        restoreButton.addTarget(self, action: #selector(restoreSupport), for: .touchUpInside)

        let acknowledgements = UIButton(configuration: .plain())
        acknowledgements.setTitle("授權與致謝", for: .normal)
        acknowledgements.accessibilityIdentifier = "open-acknowledgements"
        acknowledgements.addTarget(self, action: #selector(openAcknowledgements), for: .touchUpInside)

        var items: [UIView] = [
            title, subtitle, steps, openSettings, note,
            supporterTitle, supporterDescription, supporterPrice,
            supporterButton, restoreButton, acknowledgements
        ]
        #if DEBUG
        if !ProcessInfo.processInfo.arguments.contains("-KeyKeySupporterReview") {
            let inputFieldTest = UIButton(configuration: .tinted())
            inputFieldTest.setTitle("開啟輸入欄位測試", for: .normal)
            inputFieldTest.accessibilityIdentifier = "open-input-field-test"
            inputFieldTest.addTarget(
                self, action: #selector(openInputFieldTest), for: .touchUpInside
            )
            items.append(inputFieldTest)
        }
        #endif

        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.alwaysBounceVertical = true
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        view.addSubview(scroll)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: guide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 32),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -48)
        ])

        supporterStore.onStateChanged = { [weak self] state in
            self?.updateSupporterUI(state)
        }
        supporterStore.onError = { [weak self] message in
            self?.showSupporterMessage(message)
        }
        supporterStore.start()

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-KeyKeySupporterReview") {
            DispatchQueue.main.async {
                scroll.layoutIfNeeded()
                let rect = self.supporterButton.convert(
                    self.supporterButton.bounds, to: scroll
                ).insetBy(dx: 0, dy: -140)
                scroll.scrollRectToVisible(rect, animated: false)
            }
        }
        #endif

        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-KeyKeyInputFieldTest") {
            DispatchQueue.main.async { [weak self] in self?.openInputFieldTest() }
        }
        #endif
    }

    private func label(_ text: String, size: CGFloat, weight: UIFont.Weight) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .systemFont(ofSize: size, weight: weight)
        label.numberOfLines = 0
        return label
    }

    @objc private func openSystemSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @objc private func openAcknowledgements() {
        present(
            UINavigationController(rootViewController: AcknowledgementsViewController()),
            animated: true
        )
    }

    @objc private func purchaseSupport() {
        Task { await supporterStore.purchase() }
    }

    @objc private func restoreSupport() {
        Task { await supporterStore.restore() }
    }

    private func updateSupporterUI(_ state: SupporterStore.ViewState) {
        if let formattedPrice = state.formattedPrice, !formattedPrice.isEmpty {
            supporterPrice.text = "一次付費支持：\(formattedPrice)"
            supporterPrice.isHidden = false
        } else {
            supporterPrice.isHidden = true
        }

        if state.checking {
            supporterButton.setTitle("正在確認…", for: .normal)
            supporterButton.isEnabled = false
            restoreButton.isEnabled = false
        } else if state.supporter {
            supporterButton.setTitle("謝謝支持", for: .normal)
            supporterButton.isEnabled = false
            restoreButton.isHidden = true
        } else {
            supporterButton.setTitle("付費支持", for: .normal)
            supporterButton.isEnabled = true
            restoreButton.isEnabled = true
            restoreButton.isHidden = false
        }
    }

    private func showSupporterMessage(_ message: String) {
        let alert = UIAlertController(title: "支持開發", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "好", style: .default))
        present(alert, animated: true)
    }

    #if DEBUG
    @objc private func openInputFieldTest() {
        let controller = InputFieldTestViewController()
        present(UINavigationController(rootViewController: controller), animated: true)
    }
    #endif
}

private final class AcknowledgementsViewController: UIViewController {
    override func viewDidLoad() {
        super.viewDidLoad()
        title = "授權與致謝"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close,
            target: self,
            action: #selector(close)
        )

        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = .preferredFont(forTextStyle: .footnote)
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "acknowledgements-text"
        textView.text = Self.loadText()
        textView.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(textView)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            textView.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            textView.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            textView.topAnchor.constraint(equalTo: guide.topAnchor),
            textView.bottomAnchor.constraint(equalTo: guide.bottomAnchor)
        ])
    }

    private static func loadText() -> String {
        guard let url = Bundle.main.url(forResource: "Acknowledgements", withExtension: "txt"),
              let text = try? String(contentsOf: url, encoding: .utf8) else {
            return "無法載入授權資訊。"
        }
        return text
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}

#if DEBUG
/// A deliberately in-app host for exercising the keyboard extension. It is
/// compiled only in Debug builds, so release users keep the small setup app.
/// Each control exposes a stable accessibility identifier for a future XCUITest
/// target, while manual Simulator testing can select any field directly.
private final class InputFieldTestViewController: UIViewController, UITextFieldDelegate {
    private struct Field {
        let id: String
        let title: String
        let keyboardType: UIKeyboardType
        let returnKeyType: UIReturnKeyType
        let secure: Bool
        let multiline: Bool
        let textContentType: UITextContentType?
    }

    private let fields: [Field] = [
        .init(id: "default", title: "一般文字／換行", keyboardType: .default,
              returnKeyType: .default, secure: false, multiline: false, textContentType: nil),
        .init(id: "email", title: "Email／傳送", keyboardType: .emailAddress,
              returnKeyType: .send, secure: false, multiline: false, textContentType: .emailAddress),
        .init(id: "url", title: "網址 URL／前往", keyboardType: .URL,
              returnKeyType: .go, secure: false, multiline: false, textContentType: .URL),
        .init(id: "phone", title: "電話／下一個（系統可能封鎖第三方鍵盤）", keyboardType: .phonePad,
              returnKeyType: .next, secure: false, multiline: false, textContentType: .telephoneNumber),
        .init(id: "integer", title: "整數／完成", keyboardType: .numberPad,
              returnKeyType: .done, secure: false, multiline: false, textContentType: nil),
        .init(id: "decimal", title: "小數／完成", keyboardType: .decimalPad,
              returnKeyType: .done, secure: false, multiline: false, textContentType: nil),
        .init(id: "date-time", title: "日期／時間（數字與標點）", keyboardType: .numbersAndPunctuation,
              returnKeyType: .done, secure: false, multiline: false, textContentType: nil),
        .init(id: "password", title: "密碼（iOS 會改用系統鍵盤）", keyboardType: .default,
              returnKeyType: .done, secure: true, multiline: false, textContentType: .password),
        .init(id: "name", title: "姓名／加入", keyboardType: .namePhonePad,
              returnKeyType: .join, secure: false, multiline: false, textContentType: .name),
        .init(id: "address", title: "地址／繼續", keyboardType: .default,
              returnKeyType: .continue, secure: false, multiline: true, textContentType: .fullStreetAddress),
        .init(id: "search", title: "搜尋／搜尋", keyboardType: .webSearch,
              returnKeyType: .search, secure: false, multiline: false, textContentType: nil),
        .init(id: "message", title: "簡訊／長文字", keyboardType: .default,
              returnKeyType: .send, secure: false, multiline: true, textContentType: nil),
        .init(id: "ascii", title: "ASCII 限定／路線", keyboardType: .asciiCapable,
              returnKeyType: .route, secure: false, multiline: false, textContentType: nil),
        .init(id: "ascii-number", title: "ASCII 數字／緊急", keyboardType: .asciiCapableNumberPad,
              returnKeyType: .emergencyCall, secure: false, multiline: false, textContentType: nil)
    ]

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "輸入欄位測試"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close)
        )

        let note = UILabel()
        note.text = "選欄位後長按地球鍵選「琦琦注音」。每個欄位會把 keyboardType 與 returnKeyType 傳給鍵盤。"
        note.font = .preferredFont(forTextStyle: .footnote)
        note.textColor = .secondaryLabel
        note.numberOfLines = 0

        let rows = UIStackView(arrangedSubviews: [note] + fields.map(makeRow))
        rows.axis = .vertical
        rows.spacing = 12
        rows.translatesAutoresizingMaskIntoConstraints = false

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(rows)
        view.addSubview(scroll)
        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 16),
            scroll.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -16),
            scroll.topAnchor.constraint(equalTo: guide.topAnchor, constant: 12),
            scroll.bottomAnchor.constraint(equalTo: guide.bottomAnchor),
            rows.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor),
            rows.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor),
            rows.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            rows.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            rows.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor)
        ])
    }

    private func makeRow(_ field: Field) -> UIView {
        let title = UILabel()
        title.text = field.title
        title.font = .preferredFont(forTextStyle: .subheadline)
        title.numberOfLines = 0

        let input: UIView
        if field.multiline {
            let textView = UITextView()
            textView.keyboardType = field.keyboardType
            textView.returnKeyType = field.returnKeyType
            textView.textContentType = field.textContentType
            textView.font = .preferredFont(forTextStyle: .body)
            textView.layer.borderColor = UIColor.separator.cgColor
            textView.layer.borderWidth = 1
            textView.layer.cornerRadius = 8
            textView.accessibilityIdentifier = "field.\(field.id)"
            textView.heightAnchor.constraint(equalToConstant: 84).isActive = true
            input = textView
        } else {
            let textField = UITextField()
            textField.keyboardType = field.keyboardType
            textField.returnKeyType = field.returnKeyType
            textField.textContentType = field.textContentType
            textField.isSecureTextEntry = field.secure
            textField.borderStyle = .roundedRect
            textField.placeholder = field.title
            textField.delegate = self
            textField.accessibilityIdentifier = "field.\(field.id)"
            textField.heightAnchor.constraint(equalToConstant: 44).isActive = true
            input = textField
        }

        let row = UIStackView(arrangedSubviews: [title, input])
        row.axis = .vertical
        row.spacing = 5
        return row
    }

    func textFieldShouldReturn(_ textField: UITextField) -> Bool {
        view.endEditing(true)
        return true
    }

    @objc private func close() {
        dismiss(animated: true)
    }
}
#endif

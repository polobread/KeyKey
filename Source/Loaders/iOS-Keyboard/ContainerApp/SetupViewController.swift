import UIKit

/// Setup guidance, mirroring the Android launcher screen. The keyboard itself
/// carries the settings, so this screen only has to get the user to the point
/// where the keyboard is enabled and selected.
final class SetupViewController: UIViewController {
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
            "本輸入法不需要「完整取用權限」，不連線、不收集輸入內容。",
            size: 13, weight: .regular
        )
        note.textColor = .tertiaryLabel

        var items: [UIView] = [title, subtitle, steps, openSettings, note]
        #if DEBUG
        let inputFieldTest = UIButton(configuration: .tinted())
        inputFieldTest.setTitle("開啟輸入欄位測試", for: .normal)
        inputFieldTest.accessibilityIdentifier = "open-input-field-test"
        inputFieldTest.addTarget(self, action: #selector(openInputFieldTest), for: .touchUpInside)
        items.append(inputFieldTest)
        #endif

        let stack = UIStackView(arrangedSubviews: items)
        stack.axis = .vertical
        stack.spacing = 20
        stack.alignment = .fill
        stack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(stack)

        let guide = view.safeAreaLayoutGuide
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: guide.leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(equalTo: guide.trailingAnchor, constant: -24),
            stack.topAnchor.constraint(equalTo: guide.topAnchor, constant: 32)
        ])

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

    #if DEBUG
    @objc private func openInputFieldTest() {
        let controller = InputFieldTestViewController()
        present(UINavigationController(rootViewController: controller), animated: true)
    }
    #endif
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

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

        let stack = UIStackView(arrangedSubviews: [title, subtitle, steps, openSettings, note])
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
}

import KeyKeyEngine
import UIKit
import UniformTypeIdentifiers

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
        let version = label(appVersionText, size: 14, weight: .regular)
        version.textColor = .secondaryLabel
        version.accessibilityIdentifier = "app.version"
        let titleBlock = UIStackView(arrangedSubviews: [title, version])
        titleBlock.axis = .vertical
        titleBlock.spacing = 4
        titleBlock.alignment = .fill

        let subtitle = label(
            "注音輸入法，支援直式與橫式鍵盤、候選字、關聯詞與符號面板。",
            size: 16, weight: .regular
        )
        subtitle.textColor = .secondaryLabel

        let hardwareEditor = UIButton(configuration: .tinted())
        hardwareEditor.setTitle("開啟實體鍵盤編輯器", for: .normal)
        hardwareEditor.accessibilityIdentifier = "open-hardware-editor"
        hardwareEditor.addTarget(
            self, action: #selector(openHardwareKeyboardEditor), for: .touchUpInside
        )

        let hardwareEditorNote = label(
            "USB／藍牙鍵盤可在 App 內使用琦琦選字，完成後一鍵複製或分享文字到其他 App。",
            size: 13, weight: .regular
        )
        hardwareEditorNote.textColor = .secondaryLabel

        let userPhrases = UIButton(configuration: .tinted())
        userPhrases.setTitle("管理好打注音自訂詞", for: .normal)
        userPhrases.accessibilityIdentifier = "open-user-phrases"
        userPhrases.addTarget(self, action: #selector(openUserPhrases), for: .touchUpInside)

        let inputSettings = UIButton(configuration: .tinted())
        inputSettings.setTitle("輸入法設定", for: .normal)
        inputSettings.accessibilityIdentifier = "open-input-method-settings"
        inputSettings.addTarget(self, action: #selector(openInputMethodSettings), for: .touchUpInside)

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
        openSettings.accessibilityIdentifier = "open-system-settings"
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
            titleBlock, subtitle, hardwareEditor, hardwareEditorNote, inputSettings, userPhrases,
            steps, openSettings, note,
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

    private var appVersionText: String {
        guard let value = Bundle.main.object(
            forInfoDictionaryKey: "CFBundleShortVersionString"
        ) as? String else {
            return "版本 —"
        }
        let version = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return "版本 \(version.isEmpty ? "—" : version)"
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

    @objc private func openHardwareKeyboardEditor() {
        let navigation = UINavigationController(
            rootViewController: HardwareKeyboardEditorViewController()
        )
        navigation.modalPresentationStyle = .fullScreen
        present(navigation, animated: true)
    }

    @objc private func openUserPhrases() {
        present(UINavigationController(rootViewController: UserPhrasesViewController()), animated: true)
    }

    @objc private func openInputMethodSettings() {
        present(UINavigationController(rootViewController: InputMethodSettingsViewController()),
                animated: true)
    }

    @objc private func purchaseSupport() {
        Task {
            if supporterStore.state.productAvailable {
                await supporterStore.purchase()
            } else {
                await supporterStore.reload(showError: true)
            }
        }
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

        restoreButton.isHidden = state.supporter
        restoreButton.setTitle(
            state.operation == .restoring ? "正在恢復…" : "恢復購買", for: .normal
        )
        if state.isBusy {
            supporterButton.setTitle(
                state.operation == .purchasing ? "正在購買…" : "正在確認…", for: .normal
            )
            supporterButton.isEnabled = false
            restoreButton.isEnabled = false
        } else if state.supporter {
            supporterButton.setTitle("謝謝支持", for: .normal)
            supporterButton.isEnabled = false
            restoreButton.isHidden = true
        } else if state.productAvailable {
            supporterButton.setTitle("付費支持", for: .normal)
            supporterButton.isEnabled = true
            restoreButton.isEnabled = true
            restoreButton.isHidden = false
        } else {
            supporterButton.setTitle("重新載入價格", for: .normal)
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

/// App-managed keyboard preferences are read by the keyboard from the App Group.
/// The keyboard still keeps its own changes in its private sandbox.
private final class InputMethodSettingsViewController: UIViewController {
    private let sharedDefaults = UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier)
    private var collections: [AssociatedPhraseStore.Collection] = []
    private var collectionSwitches: [String: UISwitch] = [:]
    private lazy var phraseSettings = PhraseSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var modeSettings = BopomofoCompositionModeSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var colorSettings = CandidateColorSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var clickSettings = KeyboardClickSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "輸入法設定"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )

        let scroll = UIScrollView()
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        let stack = UIStackView()
        stack.axis = .vertical
        stack.spacing = 14
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.safeAreaLayoutGuide.bottomAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -24),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])

        guard sharedDefaults != nil else {
            stack.addArrangedSubview(label("無法開啟共用設定，請檢查 App Group 設定。", size: 16))
            return
        }

        stack.addArrangedSubview(label("注音模式", size: 18))
        let modes = BopomofoCompositionMode.allCases
        let modeControl = UISegmentedControl(items: modes.map(\.displayName))
        modeControl.selectedSegmentIndex = modes.firstIndex(of: modeSettings.mode) ?? 0
        modeControl.accessibilityIdentifier = "app-settings.composition-mode"
        modeControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(modeControl)

        stack.addArrangedSubview(label("候選字底色", size: 18))
        let colors = CandidateColor.allCases
        let colorControl = UISegmentedControl(items: ["紫", "綠", "黃", "紅"])
        colorControl.selectedSegmentIndex = colors.firstIndex(of: colorSettings.color) ?? 0
        colorControl.accessibilityIdentifier = "app-settings.candidate-color"
        colorControl.addTarget(self, action: #selector(colorChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(colorControl)

        let clickRow = UIStackView()
        clickRow.axis = .horizontal
        clickRow.alignment = .center
        clickRow.addArrangedSubview(label("按鍵音", size: 18))
        clickRow.addArrangedSubview(UIView())
        let clicks = UISwitch()
        clicks.isOn = clickSettings.enabled
        clicks.accessibilityIdentifier = "app-settings.input-clicks"
        clicks.addTarget(self, action: #selector(clicksChanged(_:)), for: .valueChanged)
        clickRow.addArrangedSubview(clicks)
        stack.addArrangedSubview(clickRow)

        stack.addArrangedSubview(label("關聯詞詞庫", size: 18))
        let bulk = UIStackView(arrangedSubviews: [
            button("全部啟用", #selector(enableAll)),
            button("僅小麥注音", #selector(enableBaseOnly)),
            button("全部關閉", #selector(disableAll))
        ])
        bulk.axis = .horizontal
        bulk.distribution = .fillEqually
        bulk.spacing = 4
        stack.addArrangedSubview(bulk)

        collections = loadCollections()
        if collections.isEmpty {
            stack.addArrangedSubview(label("無法載入關聯詞詞庫。", size: 14))
        } else {
            for collection in collections {
                let row = UIStackView()
                row.axis = .horizontal
                row.alignment = .center
                row.addArrangedSubview(label(collection.display, size: 15))
                row.addArrangedSubview(UIView())
                let toggle = UISwitch()
                toggle.isOn = phraseSettings.enabledCollections.contains(collection.source)
                toggle.accessibilityIdentifier = "app-settings.collection.\(collection.source)"
                toggle.accessibilityLabel = collection.display
                toggle.addTarget(self, action: #selector(collectionChanged(_:)), for: .valueChanged)
                collectionSwitches[collection.source] = toggle
                row.addArrangedSubview(toggle)
                row.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
                stack.addArrangedSubview(row)
            }
        }

        let phrases = button("管理好打注音自訂詞", #selector(openPhrases))
        phrases.accessibilityIdentifier = "app-settings.user-phrases"
        stack.addArrangedSubview(phrases)
        let reset = button("重設好打注音學習紀錄", #selector(confirmLearningReset))
        reset.accessibilityIdentifier = "app-settings.reset-learning"
        stack.addArrangedSubview(reset)

        let note = label(
            "在這裡變更後，鍵盤下次開啟會套用。鍵盤內「設」頁的修改保存在鍵盤自己的資料區，無法顯示回 App。重設學習紀錄會在下次開啟鍵盤時生效。",
            size: 13
        )
        note.textColor = .secondaryLabel
        stack.addArrangedSubview(note)
    }

    private func label(_ title: String, size: CGFloat) -> UILabel {
        let label = UILabel()
        label.text = title
        label.font = .systemFont(ofSize: size, weight: size >= 18 ? .semibold : .regular)
        label.numberOfLines = 0
        return label
    }

    private func button(_ title: String, _ action: Selector) -> UIButton {
        let button = UIButton(configuration: .tinted())
        button.setTitle(title, for: .normal)
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    private func loadCollections() -> [AssociatedPhraseStore.Collection] {
        guard let plugIns = Bundle.main.builtInPlugInsURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: plugIns, includingPropertiesForKeys: nil
              ),
              let url = entries.lazy.filter({ $0.pathExtension == "appex" })
                .compactMap({ Bundle(url: $0)?.url(forResource: "KeyKey", withExtension: "db") }).first,
              let database = try? Database(url: url)
        else { return [] }
        let store = AssociatedPhraseStore(database: database)
        return (try? store.collections()) ?? []
    }

    private func syncCollectionSwitches() {
        let enabled = phraseSettings.enabledCollections
        for (source, toggle) in collectionSwitches { toggle.isOn = enabled.contains(source) }
    }

    @objc private func close() { dismiss(animated: true) }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        modeSettings.setMode(BopomofoCompositionMode.allCases[sender.selectedSegmentIndex])
    }

    @objc private func colorChanged(_ sender: UISegmentedControl) {
        colorSettings.setColor(CandidateColor.allCases[sender.selectedSegmentIndex])
    }

    @objc private func clicksChanged(_ sender: UISwitch) {
        clickSettings.setEnabled(sender.isOn)
    }

    @objc private func collectionChanged(_ sender: UISwitch) {
        guard let source = collectionSwitches.first(where: { $0.value === sender })?.key else { return }
        phraseSettings.setCollection(source, enabled: sender.isOn)
    }

    @objc private func enableAll() {
        phraseSettings.setEnabledCollections(Set(collections.map(\.source)))
        syncCollectionSwitches()
    }

    @objc private func enableBaseOnly() {
        phraseSettings.setEnabledCollections([PhraseSettings.baseCollection])
        syncCollectionSwitches()
    }

    @objc private func disableAll() {
        phraseSettings.setEnabledCollections([])
        syncCollectionSwitches()
    }

    @objc private func openPhrases() {
        navigationController?.pushViewController(UserPhrasesViewController(), animated: true)
    }

    @objc private func confirmLearningReset() {
        let alert = UIAlertController(
            title: "重設學習紀錄？",
            message: "自訂詞會保留；鍵盤學習紀錄會在下次開啟鍵盤時清除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "重設", style: .destructive) { [weak self] _ in
            self?.resetLearning()
        })
        present(alert, animated: true)
    }

    private func resetLearning() {
        KeyboardLearningResetRequest(sharedDefaults: sharedDefaults).request()
        var editorReset = false
        if let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: KeyboardPreferenceStore.appGroupIdentifier
        ) {
            let local = FileManager.default.urls(for: .applicationSupportDirectory,
                                                 in: .userDomainMask)[0]
            do {
                let data = try SmartMandarinUserData(
                    phrasesURL: group.appendingPathComponent("UserPhrase.db"),
                    learningURL: local.appendingPathComponent("SmartMandarinLearning.db"),
                    writablePhrases: true
                )
                try data.resetLearning()
                editorReset = true
            } catch { /* The keyboard reset request can still be applied. */ }
        }
        let alert = UIAlertController(
            title: "學習紀錄",
            message: editorReset
                ? "App 內編輯器已重設；鍵盤下次開啟時會重設。"
                : "鍵盤下次開啟時會重設；App 內編輯器的紀錄暫時無法清除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }
}

/// Writes only to the App Group phrase database. The keyboard can read it
/// without requesting Full Access; its learning database remains private.
private final class UserPhrasesViewController: UITableViewController, UIDocumentPickerDelegate {
    private var userData: SmartMandarinUserData?
    private var phrases: [SmartMandarinUserPhrase] = []

    init() {
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "好打注音自訂詞"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .add, target: self, action: #selector(addPhrase)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "user-phrases.add"
        navigationItem.rightBarButtonItems = [
            navigationItem.rightBarButtonItem!,
            UIBarButtonItem(title: "匯入／匯出", menu: UIMenu(children: [
                UIAction(title: "匯入自訂詞") { [weak self] _ in
                    self?.chooseImportFile()
                },
                UIAction(title: "匯出自訂詞") { [weak self] _ in
                    self?.exportPhrases()
                }
            ]))
        ]
        tableView.register(UITableViewCell.self, forCellReuseIdentifier: "phrase")
        tableView.accessibilityIdentifier = "user-phrases.list"

        guard let group = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "group.io.github.polobread.inputmethod.chichi77.ios"
        ) else {
            showError("無法開啟共用詞庫，請檢查 App Group 設定。")
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
            return
        }
        let local = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        )[0]
        do {
            userData = try SmartMandarinUserData(
                phrasesURL: group.appendingPathComponent("UserPhrase.db"),
                learningURL: local.appendingPathComponent("SmartMandarinLearning.db"),
                writablePhrases: true
            )
            reloadPhrases()
        } catch {
            showError(error.localizedDescription)
            navigationItem.rightBarButtonItems?.forEach { $0.isEnabled = false }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        phrases.count
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "phrase", for: indexPath)
        let phrase = phrases[indexPath.row]
        var content = cell.defaultContentConfiguration()
        content.text = phrase.text
        content.secondaryText = phrase.reading
        cell.contentConfiguration = content
        cell.accessoryType = .disclosureIndicator
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        editPhrase(phrases[indexPath.row])
    }

    override func tableView(
        _ tableView: UITableView, trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
    ) -> UISwipeActionsConfiguration? {
        let phrase = phrases[indexPath.row]
        let delete = UIContextualAction(style: .destructive, title: "刪除") { [weak self] _, _, done in
            guard let self else { done(false); return }
            do {
                try self.userData?.deletePhrase(id: phrase.id)
                self.reloadPhrases()
                done(true)
            } catch {
                self.showError(error.localizedDescription)
                done(false)
            }
        }
        return UISwipeActionsConfiguration(actions: [delete])
    }

    @objc private func close() {
        if navigationController?.viewControllers.first === self {
            dismiss(animated: true)
        } else {
            navigationController?.popViewController(animated: true)
        }
    }
    @objc private func addPhrase() { editPhrase(nil) }

    private func editPhrase(_ phrase: SmartMandarinUserPhrase?) {
        let alert = UIAlertController(
            title: phrase == nil ? "新增自訂詞" : "編輯自訂詞",
            message: "每個字輸入一組注音，以空格或逗號分隔，例如：你好／ㄋㄧˇ ㄏㄠˇ。",
            preferredStyle: .alert
        )
        alert.addTextField { field in
            field.placeholder = "詞句"
            field.text = phrase?.text
            field.accessibilityIdentifier = "user-phrases.text"
        }
        alert.addTextField { field in
            field.placeholder = "注音，例如 ㄋㄧˇ ㄏㄠˇ"
            field.text = phrase?.reading
            field.accessibilityIdentifier = "user-phrases.reading"
        }
        alert.addAction(UIAlertAction(title: "取消", style: .cancel))
        alert.addAction(UIAlertAction(title: "儲存", style: .default) { [weak self, weak alert] _ in
            guard let self, let fields = alert?.textFields else { return }
            do {
                try self.userData?.savePhrase(
                    id: phrase?.id, text: fields[0].text ?? "", reading: fields[1].text ?? ""
                )
                self.reloadPhrases()
            } catch {
                self.showError(error.localizedDescription)
            }
        })
        present(alert, animated: true)
    }

    private func reloadPhrases() {
        phrases = userData?.userPhrases() ?? []
        tableView.reloadData()
    }

    private func chooseImportFile() {
        let picker = UIDocumentPickerViewController(
            forOpeningContentTypes: [.plainText, .text, .data], asCopy: true
        )
        picker.delegate = self
        present(picker, animated: true)
    }

    func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
        guard let url = urls.first else { return }
        let accessed = url.startAccessingSecurityScopedResource()
        defer { if accessed { url.stopAccessingSecurityScopedResource() } }
        do {
            let contents = try String(contentsOf: url, encoding: .utf8)
            guard let userData else { return }
            let result = try userData.importPhrases(contents)
            reloadPhrases()
            showError("已匯入 \(result.imported) 筆，略過 \(result.skipped) 筆。")
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func exportPhrases() {
        guard let userData else { return }
        do {
            let url = FileManager.default.temporaryDirectory
                .appendingPathComponent("KeyKey-UserPhrases.mjsr")
            try userData.exportPhrases().write(to: url, atomically: true, encoding: .utf8)
            let activity = UIActivityViewController(activityItems: [url], applicationActivities: nil)
            activity.popoverPresentationController?.barButtonItem = navigationItem.rightBarButtonItems?.last
            present(activity, animated: true)
        } catch {
            showError(error.localizedDescription)
        }
    }

    private func showError(_ message: String) {
        let alert = UIAlertController(title: "自訂詞", message: message, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        DispatchQueue.main.async { [weak self] in self?.present(alert, animated: true) }
    }
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

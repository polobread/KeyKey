import KeyKeyEngine
import UIKit
import UniformTypeIdentifiers

private func embeddedKeyboardModelURL() -> URL? {
    guard let plugIns = Bundle.main.builtInPlugInsURL,
          let entries = try? FileManager.default.contentsOfDirectory(
            at: plugIns, includingPropertiesForKeys: nil
          ) else { return nil }
    return entries.lazy.filter { $0.pathExtension == "appex" }
        .compactMap { Bundle(url: $0)?.url(forResource: "KeyKey", withExtension: "db") }.first
}

/// Setup guidance and entry points for App-managed keyboard settings.
final class SetupViewController: UIViewController {
    private let supporterState: SupporterState = {
        #if DEBUG
        if let state = SupporterUIFixture.state { return state }
        #endif
        return SupporterState()
    }()
    private lazy var supporterStore: SupporterStore = {
        #if DEBUG
        if SupporterUIFixture.state != nil {
            return SupporterStore(supporterState: supporterState,
                                  client: SupporterUIFixture.storeClient)
        }
        #endif
        return SupporterStore(supporterState: supporterState)
    }()
    private let contentStack = UIStackView()
    private let supporterSection = UIStackView()
    private let supporterPrice = UILabel()
    private let supporterButton = UIButton(configuration: .filled())
    private let restoreButton = UIButton(configuration: .plain())

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground

        let title = label("琦琦輸入法", size: 28, weight: .bold)
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
        subtitle.accessibilityIdentifier = "app.subtitle"

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

        let phraseCollections = UIButton(configuration: .tinted())
        phraseCollections.setTitle("關聯詞詞庫", for: .normal)
        phraseCollections.accessibilityIdentifier = "open-phrase-collections"
        phraseCollections.addTarget(self, action: #selector(openPhraseCollections), for: .touchUpInside)

        let steps = label(
            """
            1. 開啟「設定 → 一般 → 鍵盤 → 鍵盤 → 加入新的鍵盤」
            2. 在「第三方鍵盤」中選擇「琦琦輸入法」
            3. 打字時長按地球鍵切換到琦琦輸入法

            關聯詞詞庫可在琦琦 App 首頁調整。
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
        supporterTitle.accessibilityIdentifier = "supporter.title"

        let supporterDescription = label(
            "琦琦輸入法未付費也能完整使用。若覺得好用，歡迎一次付費支持後續維護與開發。付費支持後，鍵盤上將不再顯示「歡迎付費支持」提示。",
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

        let supporterItems: [UIView] = [supporterTitle, supporterDescription, supporterPrice,
                                        supporterButton, restoreButton]
        for item in supporterItems {
            supporterSection.addArrangedSubview(item)
        }
        supporterSection.axis = .vertical
        supporterSection.spacing = 20
        supporterSection.alignment = .fill
        supporterSection.accessibilityIdentifier = "supporter.section"

        var items: [UIView] = [
            titleBlock, subtitle, hardwareEditor, hardwareEditorNote, inputSettings,
            phraseCollections, userPhrases, steps, openSettings, note, acknowledgements
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

        for item in items { contentStack.addArrangedSubview(item) }
        let stack = contentStack
        updateSupporterSectionPosition(supporter: supporterState.isSupporter)
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

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        var state = supporterStore.state
        state.supporter = supporterState.isSupporter
        updateSupporterUI(state)
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

    @objc private func openPhraseCollections() {
        guard let sharedDefaults = UserDefaults(suiteName: KeyboardPreferenceStore.appGroupIdentifier),
              let url = embeddedKeyboardModelURL(),
              let database = try? Database(url: url),
              let collections = try? AssociatedPhraseStore(database: database).collections(),
              !collections.isEmpty else {
            let alert = UIAlertController(
                title: "關聯詞詞庫", message: "無法載入關聯詞詞庫。", preferredStyle: .alert
            )
            alert.addAction(UIAlertAction(title: "知道了", style: .default))
            present(alert, animated: true)
            return
        }

        let settings = PhraseSettings(sharedDefaults: sharedDefaults, writesShared: true)
        let available = Set(collections.map(\.source))
        let picker = PhraseCollectionPickerViewController(
            collections: collections,
            enabled: settings.enabledCollections.intersection(available),
            accessibilityPrefix: "app-settings.phrases"
        )
        picker.didChange = { settings.setEnabledCollections($0.intersection(available)) }
        present(UINavigationController(rootViewController: picker), animated: true)
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

    private func updateSupporterSectionPosition(supporter: Bool) {
        let destination = supporter ? contentStack.arrangedSubviews.count - 1 : 1
        if contentStack.arrangedSubviews.firstIndex(of: supporterSection) == destination { return }
        contentStack.removeArrangedSubview(supporterSection)
        supporterSection.removeFromSuperview()
        if supporter {
            contentStack.addArrangedSubview(supporterSection)
        } else {
            contentStack.insertArrangedSubview(supporterSection, at: 1)
        }
    }

    private func updateSupporterUI(_ state: SupporterStore.ViewState) {
        updateSupporterSectionPosition(supporter: state.supporter)
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
    private lazy var modeSettings = ChineseInputMethodSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var spaceSettings = SmartMandarinSpaceSettings(sharedDefaults: sharedDefaults)
    private lazy var toneOmissionSettings = SmartMandarinToneOmissionSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var layoutSettings = BopomofoKeyboardLayoutSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var colorSettings = CandidateColorSettings(
        sharedDefaults: sharedDefaults, writesShared: true
    )
    private lazy var profileSettings = KeyboardLayoutProfileSettings(
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

        stack.addArrangedSubview(label("輸入法", size: 18))
        let modes = ChineseInputMethod.allCases
        let modeControl = UISegmentedControl(items: modes.map(\.displayName))
        modeControl.selectedSegmentIndex = modes.firstIndex(of: modeSettings.method) ?? 0
        modeControl.accessibilityIdentifier = "app-settings.composition-mode"
        modeControl.addTarget(self, action: #selector(modeChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(modeControl)

        let spaceRow = UIStackView()
        spaceRow.alignment = .center
        spaceRow.addArrangedSubview(label("使用空白鍵選字", size: 18))
        spaceRow.addArrangedSubview(UIView())
        let spaceSelection = UISwitch()
        spaceSelection.isOn = spaceSettings.enabled
        spaceSelection.accessibilityIdentifier = "app-settings.space-selects-candidates"
        spaceSelection.accessibilityLabel = "使用空白鍵選字"
        spaceSelection.addTarget(self, action: #selector(spaceSelectionChanged(_:)), for: .valueChanged)
        spaceRow.addArrangedSubview(spaceSelection)
        stack.addArrangedSubview(spaceRow)
        stack.addArrangedSubview(label("僅適用好打注音，虛擬與實體鍵盤共用。預設關閉：讀音完成後，在組字區插入空白，仍可繼續輸入及回頭選字；未完成讀音時仍以空白結束一聲。開啟後，空白鍵可完成讀音、開啟候選及翻頁。關閉時仍可點選組字或按實體鍵盤 ↓ 開啟候選。", size: 14))

        let phrases = button("管理好打注音自訂詞", #selector(openPhrases))
        phrases.accessibilityIdentifier = "app-settings.user-phrases"
        stack.addArrangedSubview(phrases)
        let reset = button("重設好打注音學習紀錄", #selector(confirmLearningReset))
        reset.accessibilityIdentifier = "app-settings.reset-learning"
        stack.addArrangedSubview(reset)

        stack.addArrangedSubview(label("注音鍵盤", size: 18))
        let layouts = BopomofoKeyboardLayout.allCases
        let layoutControl = UISegmentedControl(items: layouts.map(\.displayName))
        layoutControl.selectedSegmentIndex = layouts.firstIndex(of: layoutSettings.layout) ?? 0
        layoutControl.accessibilityIdentifier = "app-settings.keyboard-layout"
        layoutControl.addTarget(self, action: #selector(layoutChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(layoutControl)
        stack.addArrangedSubview(label("好打與傳統注音共用配置。許氏與漢語拼音使用英文字母鍵帽。拼音一聲按空白，二至四聲按 2～4，輕聲按 5，ü 可用 v。", size: 14))

        let toneOmissionRow = UIStackView()
        toneOmissionRow.alignment = .center
        toneOmissionRow.addArrangedSubview(label(SmartMandarinToneOmissionSettings.displayName, size: 18))
        toneOmissionRow.addArrangedSubview(UIView())
        let toneOmission = UISwitch()
        toneOmission.isOn = toneOmissionSettings.enabled
        toneOmission.accessibilityIdentifier = "app-settings.omit-tones"
        toneOmission.accessibilityLabel = SmartMandarinToneOmissionSettings.displayName
        toneOmission.addTarget(self, action: #selector(toneOmissionChanged(_:)), for: .valueChanged)
        toneOmissionRow.addArrangedSubview(toneOmission)
        stack.addArrangedSubview(toneOmissionRow)
        stack.addArrangedSubview(label("預設關閉。開啟後，觸控好打注音的標準注音、許氏與漢語拼音可連續輸入讀音，並在 11 格組字區顯示轉出的中文字。仍可照常輸入聲調。", size: 14))

        stack.addArrangedSubview(tableOptionsButton(for: .cangjie))
        stack.addArrangedSubview(tableOptionsButton(for: .cangjie, virtualKeyboard: false))
        stack.addArrangedSubview(tableOptionsButton(for: .simplex))

        stack.addArrangedSubview(label("候選字底色", size: 18))
        let colors = CandidateColor.allCases
        let colorControl = UISegmentedControl(items: ["紫", "綠", "黃", "紅"])
        colorControl.selectedSegmentIndex = colors.firstIndex(of: colorSettings.color) ?? 0
        colorControl.accessibilityIdentifier = "app-settings.candidate-color"
        colorControl.addTarget(self, action: #selector(colorChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(colorControl)
        addLayoutSettings(to: stack)

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

    @objc private func close() { dismiss(animated: true) }

    private func tableOptionsButton(for method: ChineseInputMethod, virtualKeyboard: Bool = true) -> UIButton {
        let button = UIButton(configuration: .tinted())
        button.setTitle(method.displayName + (method == .cangjie ? (virtualKeyboard ? "設定（虛擬鍵盤）" : "設定（實體鍵盤）") : "設定"), for: .normal)
        button.accessibilityIdentifier = "table-options." + method.rawValue + (virtualKeyboard ? "" : ".physical")
        button.showsMenuAsPrimaryAction = true
        refreshTableOptions(button, for: method, virtualKeyboard: virtualKeyboard)
        return button
    }

    private func refreshTableOptions(_ button: UIButton, for method: ChineseInputMethod, virtualKeyboard: Bool) {
        let options = modeSettings.options(for: method, virtualKeyboard: virtualKeyboard)
        var children: [UIMenuElement] = options.switches(for: method).map { item in
            UIAction(title: item.title, attributes: item.key == "prefix" && !options.composeWhileTyping ? .disabled : [], state: item.enabled ? .on : .off) { [weak self, weak button] _ in
                guard let self, let button else { return }
                var next = self.modeSettings.options(for: method, virtualKeyboard: virtualKeyboard)
                next.toggle(item.key)
                self.modeSettings.setOptions(next, for: method, virtualKeyboard: virtualKeyboard)

                self.refreshTableOptions(button, for: method, virtualKeyboard: virtualKeyboard)
            }
        }
        if method == .cangjie {
            children.append(UIMenu(title: "標點", children: ["原字表", "中英混合", "半形"].enumerated().map { index, title in
                UIAction(title: title, state: options.punctuation == index ? .on : .off) { [weak self, weak button] _ in
                    guard let self, let button else { return }
                    var next = self.modeSettings.options(for: method, virtualKeyboard: virtualKeyboard)
                    next.punctuation = index
                    self.modeSettings.setOptions(next, for: method, virtualKeyboard: virtualKeyboard)

                    self.refreshTableOptions(button, for: method, virtualKeyboard: virtualKeyboard)
                }
            }))
        }
        button.menu = UIMenu(title: method.displayName + "設定", children: children)
    }

    private func addLayoutSettings(to stack: UIStackView) {
        stack.addArrangedSubview(label("版面", size: 18))
        let profiles = KeyboardLayoutProfile.available
        let profile = UISegmentedControl(items: profiles.map(\.displayName))
        profile.selectedSegmentIndex = profiles.firstIndex(of: profileSettings.profile) ?? 0
        profile.accessibilityIdentifier = "app-settings.layout-profile"
        profile.accessibilityLabel = "版面"
        profile.addTarget(self, action: #selector(layoutProfileChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(profile)
        stack.addArrangedSubview(label("鍵帽間隔", size: 18))
        let area = UISegmentedControl(items: KeyboardKeycapArea.allCases.map(\.displayName))
        area.selectedSegmentIndex = KeyboardKeycapArea.allCases.firstIndex(of: profileSettings.keycapArea) ?? 0
        area.accessibilityIdentifier = "app-settings.keycap-area"
        area.accessibilityLabel = "鍵帽間隔"
        area.addTarget(self, action: #selector(keycapAreaChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(area)
        stack.addArrangedSubview(label("字體", size: 18))
        let font = UISegmentedControl(items: KeyboardKeyFontSize.allCases.map(\.displayName))
        font.selectedSegmentIndex = KeyboardKeyFontSize.allCases.firstIndex(of: profileSettings.fontSize) ?? 0
        font.accessibilityIdentifier = "app-settings.key-font-size"
        font.accessibilityLabel = "字體"
        font.addTarget(self, action: #selector(keyFontSizeChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(font)
        stack.addArrangedSubview(label("刪除鍵位置", size: 18))
        let position = UISegmentedControl(items: KeyboardDeleteShiftPosition.allCases.map(\.displayName))
        position.selectedSegmentIndex = KeyboardDeleteShiftPosition.allCases.firstIndex(
            of: profileSettings.deleteShiftPosition) ?? 0
        position.accessibilityIdentifier = "app-settings.delete-position"
        position.accessibilityLabel = "刪除鍵位置"
        position.addTarget(self, action: #selector(deleteShiftChanged(_:)), for: .valueChanged)
        stack.addArrangedSubview(position)
    }

    @objc private func layoutProfileChanged(_ sender: UISegmentedControl) {
        guard KeyboardLayoutProfile.available.indices.contains(sender.selectedSegmentIndex) else { return }
        profileSettings.setProfile(KeyboardLayoutProfile.available[sender.selectedSegmentIndex])
    }

    @objc private func keyFontSizeChanged(_ sender: UISegmentedControl) {
        guard KeyboardKeyFontSize.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        profileSettings.setFontSize(KeyboardKeyFontSize.allCases[sender.selectedSegmentIndex])
    }

    @objc private func keycapAreaChanged(_ sender: UISegmentedControl) {
        guard KeyboardKeycapArea.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        profileSettings.setKeycapArea(KeyboardKeycapArea.allCases[sender.selectedSegmentIndex])
    }

    @objc private func deleteShiftChanged(_ sender: UISegmentedControl) {
        guard KeyboardDeleteShiftPosition.allCases.indices.contains(sender.selectedSegmentIndex) else { return }
        profileSettings.setDeleteShiftPosition(KeyboardDeleteShiftPosition.allCases[sender.selectedSegmentIndex])
    }

    @objc private func modeChanged(_ sender: UISegmentedControl) {
        modeSettings.setMethod(ChineseInputMethod.allCases[sender.selectedSegmentIndex])
    }

    @objc private func spaceSelectionChanged(_ sender: UISwitch) {
        spaceSettings.setEnabled(sender.isOn)
    }

    @objc private func toneOmissionChanged(_ sender: UISwitch) {
        toneOmissionSettings.setEnabled(sender.isOn)
    }

    @objc private func layoutChanged(_ sender: UISegmentedControl) {
        layoutSettings.setLayout(BopomofoKeyboardLayout.allCases[sender.selectedSegmentIndex])
    }

    @objc private func colorChanged(_ sender: UISegmentedControl) {
        colorSettings.setColor(CandidateColor.allCases[sender.selectedSegmentIndex])
    }

    @objc private func clicksChanged(_ sender: UISwitch) {
        clickSettings.setEnabled(sender.isOn)
    }

    @objc private func openPhrases() {
        navigationController?.pushViewController(UserPhrasesViewController(), animated: true)
    }

    @objc private func confirmLearningReset() {
        let alert = UIAlertController(
            title: "重設好打注音學習紀錄？",
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
        let local = FileManager.default.urls(for: .applicationSupportDirectory,
                                            in: .userDomainMask)[0]
        var editorReset = false
        do {
            guard let modelURL = embeddedKeyboardModelURL() else { throw CocoaError(.fileNoSuchFile) }
            try GuanyinmaInputEngine.resetLearning(
                modelURL: modelURL, userDatabaseURL: local.appendingPathComponent("GuanyinmaUser.db")
            )
            editorReset = true
        } catch { /* The keyboard request remains pending for its next activation. */ }
        let alert = UIAlertController(
            title: "好打注音學習紀錄",
            message: editorReset
                ? "App 內編輯器已重設；鍵盤下次開啟時會重設。"
                : "鍵盤下次開啟時會重設；App 內編輯器的紀錄暫時無法清除。",
            preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default))
        present(alert, animated: true)
    }

}

/// Edits the App Group phrase publication. The keyboard reads it
/// without Full Access; engine learning stays private to each input surface.
private final class UserPhrasesViewController: UITableViewController, UIDocumentPickerDelegate {
    private var userData: SharedPhrasePublication?
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
        do {
            userData = try SharedPhrasePublication(
                phrasesURL: group.appendingPathComponent("GuanyinmaUserPhrase.db"),
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
                .appendingPathComponent("KeyKey-Guanyinma-UserPhrases.mjsr")
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

private struct AcknowledgementsCatalog: Decodable {
    struct Component: Decodable {
        let id: String
        let name: String
        let license: String
        let attribution: String
        let licenseIDs: [String]
        let source: String
    }
    struct Terms: Decodable {
        let id: String
        let text: String
    }
    let components: [Component]
    let licenses: [Terms]
}

private final class AcknowledgementsViewController: UITableViewController {
    private var catalog: AcknowledgementsCatalog?

    init() { super.init(style: .insetGrouped) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "授權與致謝"
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close)
        )
        tableView.accessibilityIdentifier = "acknowledgements.components"
        if let url = Bundle.main.url(forResource: "GuanyinmaNotices", withExtension: "json"),
           let data = try? Data(contentsOf: url),
           let decoded = try? JSONDecoder().decode(AcknowledgementsCatalog.self, from: data) {
            let available = Set(decoded.licenses.map(\.id))
            if !decoded.components.isEmpty && decoded.components.allSatisfy({
                !$0.licenseIDs.isEmpty && $0.licenseIDs.allSatisfy(available.contains)
            }) {
                catalog = decoded
            }
        }
    }

    override func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        catalog?.components.count ?? 0
    }

    override func tableView(_ tableView: UITableView, titleForHeaderInSection section: Int) -> String? {
        catalog == nil ? "無法完整載入授權資訊。" : "本產品以 Yahoo! KeyKey 為基礎，但不是 Yahoo 官方產品。"
    }

    override func tableView(_ tableView: UITableView, titleForFooterInSection section: Int) -> String? {
        catalog == nil ? nil : "點選元件可閱讀著作權聲明與完整授權條款。"
    }

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = UITableViewCell(style: .subtitle, reuseIdentifier: nil)
        guard let component = catalog?.components[indexPath.row] else { return cell }
        cell.textLabel?.text = component.name
        cell.textLabel?.numberOfLines = 0
        cell.detailTextLabel?.text = component.license
        cell.detailTextLabel?.numberOfLines = 0
        cell.accessoryType = .disclosureIndicator
        cell.accessibilityIdentifier = "acknowledgements.component.\(component.id)"
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        guard let catalog else { return }
        let component = catalog.components[indexPath.row]
        let terms = Dictionary(uniqueKeysWithValues: catalog.licenses.map { ($0.id, $0.text) })
        let text = ([component.name, component.license, component.attribution, component.source]
                    + component.licenseIDs.compactMap { terms[$0] })
            .filter { !$0.isEmpty }.joined(separator: "\n\n")
        navigationController?.pushViewController(
            AcknowledgementDetailViewController(name: component.name, text: text), animated: true
        )
    }

    @objc private func close() { dismiss(animated: true) }
}

private final class AcknowledgementDetailViewController: UIViewController {
    private let text: String

    init(name: String, text: String) {
        self.text = text
        super.init(nibName: nil, bundle: nil)
        title = name
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let textView = UITextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.alwaysBounceVertical = true
        textView.font = .preferredFont(forTextStyle: .footnote)
        textView.adjustsFontForContentSizeCategory = true
        textView.accessibilityIdentifier = "acknowledgements-text"
        textView.text = text
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
}

#if DEBUG
/// A deliberately in-app host for exercising the keyboard extension. It is
/// compiled only in Debug builds, so release users keep the small setup app.
/// Each control exposes a stable accessibility identifier for a future XCUITest
/// target, while manual Simulator testing can select any field directly.
private final class InputFieldTestViewController: UIViewController, UITextFieldDelegate {
    private weak var defaultInput: UIView?

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
        #if targetEnvironment(simulator)
        let nativeOnly = ProcessInfo.processInfo.arguments.contains("-KeyKeyNativeKeyboardOnly")
        #else
        let nativeOnly = false
        #endif
        note.text = nativeOnly
            ? "系統鍵盤對照：此工作階段已停用第三方鍵盤。"
            : "選欄位後長按地球鍵選「琦琦輸入法」。每個欄位會把 keyboardType 與 returnKeyType 傳給鍵盤。"
        note.accessibilityIdentifier = nativeOnly ? "test-host.native-keyboard-only" : "test-host.instructions"
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

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        // Keep a manual simulator session alive without relying on XCTest
        // tapping the active display or keeping its test runner connected.
        if ProcessInfo.processInfo.arguments.contains("-KeyKeyFocusDefaultField") {
            defaultInput?.becomeFirstResponder()
        }
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

        if field.id == "default" { defaultInput = input }
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

#if DEBUG
/// Isolated launch fixtures exercise the UI without changing real entitlements.
@MainActor
enum SupporterUIFixture {
    static let state: SupporterState? = {
        guard let status = argument("-KeyKeySupporterFixture"),
              ["expired", "trial", "paid"].contains(status),
              let defaults = UserDefaults(suiteName: "KeyKey.SupporterUIFixture") else { return nil }
        defaults.removePersistentDomain(forName: "KeyKey.SupporterUIFixture")
        let state = SupporterState(defaults: defaults)
        state.setSupporter(status == "paid")
        state.recordFirstUse(at: Date().addingTimeInterval(
            status == "trial" ? -29 * 24 * 60 * 60 : -31 * 24 * 60 * 60
        ))
        return state
    }()
    static let storeClient = StoreClient()

    static func argument(_ name: String) -> String? {
        let arguments = ProcessInfo.processInfo.arguments
        guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
        return arguments[index + 1]
    }

    final class StoreClient: SupporterStoreClient {
        private var entitled = SupporterUIFixture.argument("-KeyKeySupporterFixture") == "paid"
        func loadPrice() async throws -> String? { "NT$150" }
        func purchase() async throws -> SupporterPurchaseResult {
            entitled = true
            return .verified(finish: {})
        }
        func sync() async throws { entitled = true }
        func hasEntitlement() async -> Bool { entitled }
    }
}
#endif

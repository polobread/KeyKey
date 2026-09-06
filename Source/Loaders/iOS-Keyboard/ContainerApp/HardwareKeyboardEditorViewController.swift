import GameController
import KeyKeyEngine
import UIKit

@MainActor
fileprivate protocol HardwareKeyboardCaptureViewDelegate: AnyObject {
    func captureView(_ view: HardwareKeyboardCaptureView, didPress key: UIKey) -> Bool
}

/// A non-text responder receives raw hardware events without involving the
/// active system input method. Handled presses are deliberately not forwarded
/// to `super`, which prevents the same key from also reaching UIKit text input.
fileprivate final class HardwareKeyboardCaptureView: UIView {
    weak var keyDelegate: HardwareKeyboardCaptureViewDelegate?

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let key = press.key, keyDelegate?.captureView(self, didPress: key) == true else {
                unhandled.insert(press)
                continue
            }
        }
        if !unhandled.isEmpty {
            super.pressesBegan(unhandled, with: event)
        }
    }

}

fileprivate final class ClearConfirmationOverlayView: UIView {}

private final class PhraseCollectionPickerViewController: UITableViewController {
    private let collections: [AssociatedPhraseStore.Collection]
    private var enabled: Set<String>
    var didChange: ((Set<String>) -> Void)?
    var didClose: (() -> Void)?

    init(collections: [AssociatedPhraseStore.Collection], enabled: Set<String>) {
        self.collections = collections
        self.enabled = enabled
        super.init(style: .insetGrouped)
    }

    required init?(coder: NSCoder) {
        fatalError("not used")
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "關聯詞詞庫"
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .done, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier =
            "hardware-editor.phrases.done"
        tableView.allowsMultipleSelection = true
    }

    override func numberOfSections(in tableView: UITableView) -> Int { 2 }

    override func tableView(
        _ tableView: UITableView, numberOfRowsInSection section: Int
    ) -> Int {
        section == 0 ? 3 : collections.count
    }

    override func tableView(
        _ tableView: UITableView, titleForHeaderInSection section: Int
    ) -> String? {
        section == 0
            ? "快速選擇"
            : "詞庫（已啟用 \(enabled.count)／\(collections.count)）"
    }

    override func tableView(
        _ tableView: UITableView, cellForRowAt indexPath: IndexPath
    ) -> UITableViewCell {
        let cell = UITableViewCell(style: .default, reuseIdentifier: nil)
        var content = cell.defaultContentConfiguration()
        if indexPath.section == 0 {
            let choices = ["全部啟用", "僅小麥注音", "全部關閉"]
            let identifiers = ["all", "base-only", "none"]
            content.text = choices[indexPath.row]
            content.textProperties.color = .systemPurple
            cell.accessibilityIdentifier = "hardware-editor.phrases.\(identifiers[indexPath.row])"
            cell.accessoryType = .disclosureIndicator
        } else {
            let collection = collections[indexPath.row]
            content.text = collection.display
            cell.accessibilityIdentifier = "hardware-editor.phrases.\(collection.source)"
            cell.accessoryType = enabled.contains(collection.source) ? .checkmark : .none
        }
        cell.contentConfiguration = content
        return cell
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)
        if indexPath.section == 0 {
            switch indexPath.row {
            case 0:
                enabled = Set(collections.map(\.source))
            case 1:
                enabled = [PhraseSettings.baseCollection]
            default:
                enabled = []
            }
        } else {
            let source = collections[indexPath.row].source
            if enabled.contains(source) {
                enabled.remove(source)
            } else {
                enabled.insert(source)
            }
        }
        tableView.reloadSections(IndexSet(integer: 1), with: .automatic)
        didChange?(enabled)
    }

    @objc private func close() {
        dismiss(animated: true, completion: didClose)
    }
}

final class HardwareKeyboardEditorViewController: UIViewController {
    private let captureView = HardwareKeyboardCaptureView()
    private let connectionLabel = UILabel()
    private let outputView = UITextView()
    private let cursorIndicator = UIView()
    private let cursorPositionLabel = UILabel()
    private let pageIndicatorLabel = UILabel()
    private let phraseButton = UIButton(configuration: .tinted())
    private let modeButton = UIButton(configuration: .tinted())
    private let widthButton = UIButton(configuration: .tinted())
    private let symbolButton = UIButton(configuration: .tinted())
    private let emojiButton = UIButton(configuration: .tinted())
    private let escapeButton = UIButton(configuration: .tinted())
    private let backspaceButton = UIButton(configuration: .tinted())
    private let enterButton = UIButton(configuration: .tinted())
    private let leftButton = UIButton(configuration: .tinted())
    private let upButton = UIButton(configuration: .tinted())
    private let downButton = UIButton(configuration: .tinted())
    private let spaceButton = UIButton(configuration: .tinted())
    private let rightButton = UIButton(configuration: .tinted())
    private let copyButton = UIButton(configuration: .filled())
    private let shareButton = UIButton(configuration: .tinted())
    private let clearButton = UIButton(configuration: .plain())
    private let scrollView = UIScrollView()
    private let mainStack = UIStackView()
    private let inputColumn = UIStackView()
    private let candidateWorkspace = UIStackView()
    private let candidateList = UIStackView()
    private let controlsColumn = UIStackView()
    private let actionsStack = UIStackView()
    private var clearConfirmationOverlay: ClearConfirmationOverlayView?
    private var candidateButtons: [UIButton] = []
    private var candidateButtonHeightConstraints: [NSLayoutConstraint] = []
    private var compactableButtonHeightConstraints: [NSLayoutConstraint] = []
    private var outputHeightConstraint: NSLayoutConstraint?
    private var portraitCandidateWidthConstraint: NSLayoutConstraint?
    private var landscapeInputWidthConstraint: NSLayoutConstraint?
    private var landscapeCandidateWidthConstraint: NSLayoutConstraint?
    private var landscapeActionsWidthConstraint: NSLayoutConstraint?
    private var landscapeMinimumHeightConstraint: NSLayoutConstraint?
    private var landscapeInputHeightConstraint: NSLayoutConstraint?
    private var portraitActionConstraints: [NSLayoutConstraint] = []
    private var landscapeScrollBottomConstraint: NSLayoutConstraint?
    private var optionalNavigationControls: [UIView] = []
    private var usesLandscapeLayout: Bool?
    private var usesCompactPortraitLayout: Bool?
    private var engine: BopomofoEngine?
    private var phraseStore: AssociatedPhraseStore?
    private var collections: [AssociatedPhraseStore.Collection] = []
    private let phraseSettings = PhraseSettings()
    private var committedText = ""
    private var insertionCharacterIndex = 0
    private var displayedCaretUTF16Offset = 0
    private var preferredCursorX: CGFloat?
    private var isFullWidth = false
    private var transientStatus: String?

    override func loadView() {
        view = captureView
        captureView.keyDelegate = self
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        title = "實體鍵盤編輯器"
        view.backgroundColor = .systemBackground
        navigationItem.leftBarButtonItem = UIBarButtonItem(
            barButtonSystemItem: .close, target: self, action: #selector(close)
        )
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            image: UIImage(systemName: "info.circle"),
            style: .plain,
            target: self,
            action: #selector(showHelp)
        )
        navigationItem.rightBarButtonItem?.accessibilityIdentifier = "hardware-editor.help"
        navigationItem.rightBarButtonItem?.accessibilityLabel = "實體鍵盤操作說明"

        configureViews()
        loadEngine()
        observeKeyboardConnection()
        refreshConnectionStatus()
        refresh()
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        captureView.becomeFirstResponder()
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureView.resignFirstResponder()
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        updateAdaptiveLayoutIfNeeded()
        updateCursorIndicatorFrame()
    }

    override func viewWillTransition(
        to size: CGSize, with coordinator: any UIViewControllerTransitionCoordinator
    ) {
        super.viewWillTransition(to: size, with: coordinator)
        updateAdaptiveLayout(
            isLandscape: size.width > size.height,
            availableHeight: size.height
        )
        coordinator.animate(alongsideTransition: { [weak self] _ in
            self?.view.layoutIfNeeded()
        }, completion: { [weak self] _ in
            self?.updateCursorIndicatorFrame()
        })
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func configureViews() {
        connectionLabel.font = .preferredFont(forTextStyle: .subheadline)
        connectionLabel.adjustsFontForContentSizeCategory = true
        connectionLabel.numberOfLines = 0
        connectionLabel.accessibilityIdentifier = "hardware-editor.connection"

        outputView.isEditable = false
        outputView.isSelectable = false
        outputView.isScrollEnabled = true
        outputView.backgroundColor = .secondarySystemBackground
        outputView.layer.cornerRadius = 12
        outputView.layer.borderWidth = 1
        outputView.layer.borderColor = UIColor.separator.cgColor
        outputView.textContainerInset = UIEdgeInsets(top: 14, left: 12, bottom: 14, right: 12)
        outputView.accessibilityIdentifier = "hardware-editor.output"
        cursorIndicator.backgroundColor = Self.accent
        cursorIndicator.layer.cornerRadius = 1
        cursorIndicator.isUserInteractionEnabled = false
        outputView.addSubview(cursorIndicator)
        let blink = CABasicAnimation(keyPath: "opacity")
        blink.fromValue = 1
        blink.toValue = 0.15
        blink.duration = 0.55
        blink.autoreverses = true
        blink.repeatCount = .infinity
        cursorIndicator.layer.add(blink, forKey: "hardware-editor.cursor-blink")
        outputHeightConstraint = outputView.heightAnchor.constraint(
            equalToConstant: traitCollection.userInterfaceIdiom == .pad ? 340 : 220
        )

        cursorPositionLabel.font = .preferredFont(forTextStyle: .caption1)
        cursorPositionLabel.adjustsFontForContentSizeCategory = true
        cursorPositionLabel.textColor = .secondaryLabel
        cursorPositionLabel.accessibilityIdentifier = "hardware-editor.cursor-position"

        pageIndicatorLabel.font = .preferredFont(forTextStyle: .footnote)
        pageIndicatorLabel.adjustsFontForContentSizeCategory = true
        pageIndicatorLabel.adjustsFontSizeToFitWidth = true
        pageIndicatorLabel.minimumScaleFactor = 0.55
        pageIndicatorLabel.lineBreakMode = .byClipping
        pageIndicatorLabel.textColor = .secondaryLabel
        pageIndicatorLabel.textAlignment = .center
        pageIndicatorLabel.numberOfLines = 1
        pageIndicatorLabel.backgroundColor = .secondarySystemBackground
        pageIndicatorLabel.accessibilityIdentifier = "hardware-editor.page"
        pageIndicatorLabel.setContentCompressionResistancePriority(.required, for: .horizontal)

        configurePhraseButton()
        configureCandidateList()
        configureControlsColumn()
        configureActionsStack()

        for view in [connectionLabel, outputView, cursorPositionLabel] {
            inputColumn.addArrangedSubview(view)
        }
        inputColumn.axis = .vertical
        inputColumn.spacing = traitCollection.userInterfaceIdiom == .pad ? 12 : 8
        mainStack.translatesAutoresizingMaskIntoConstraints = false

        scrollView.alwaysBounceVertical = true
        scrollView.keyboardDismissMode = .interactive
        scrollView.translatesAutoresizingMaskIntoConstraints = false
        scrollView.addSubview(mainStack)
        view.addSubview(scrollView)
        actionsStack.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(actionsStack)

        let guide = view.safeAreaLayoutGuide
        let preferredWidth = mainStack.widthAnchor.constraint(
            equalTo: scrollView.frameLayoutGuide.widthAnchor, constant: -32
        )
        // Reparenting arranged views during rotation must not let their
        // intrinsic widths shrink the portrait layout on the way back.
        preferredWidth.priority = UILayoutPriority(999)
        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: guide.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: guide.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: guide.topAnchor),
            scrollView.contentLayoutGuide.widthAnchor.constraint(
                equalTo: scrollView.frameLayoutGuide.widthAnchor
            ),
            mainStack.topAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.topAnchor,
                constant: traitCollection.userInterfaceIdiom == .pad ? 16 : 8
            ),
            mainStack.bottomAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.bottomAnchor,
                constant: traitCollection.userInterfaceIdiom == .pad ? -20 : -8
            ),
            mainStack.centerXAnchor.constraint(
                equalTo: scrollView.contentLayoutGuide.centerXAnchor
            ),
            mainStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: scrollView.contentLayoutGuide.leadingAnchor,
                constant: 16
            ),
            mainStack.trailingAnchor.constraint(
                lessThanOrEqualTo: scrollView.contentLayoutGuide.trailingAnchor,
                constant: -16
            ),
            preferredWidth,
            mainStack.widthAnchor.constraint(lessThanOrEqualToConstant: 1_400)
        ])
        let actionsPreferredWidth = actionsStack.widthAnchor.constraint(
            equalTo: guide.widthAnchor, constant: -32
        )
        actionsPreferredWidth.priority = .defaultHigh
        portraitActionConstraints = [
            scrollView.bottomAnchor.constraint(
                equalTo: actionsStack.topAnchor, constant: -4
            ),
            actionsStack.leadingAnchor.constraint(
                greaterThanOrEqualTo: guide.leadingAnchor, constant: 16
            ),
            actionsStack.trailingAnchor.constraint(
                lessThanOrEqualTo: guide.trailingAnchor, constant: -16
            ),
            actionsStack.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            actionsStack.widthAnchor.constraint(lessThanOrEqualToConstant: 760),
            actionsStack.bottomAnchor.constraint(equalTo: guide.bottomAnchor, constant: -4),
            actionsStack.heightAnchor.constraint(
                equalToConstant: traitCollection.userInterfaceIdiom == .pad ? 52 : 44
            ),
            actionsPreferredWidth
        ]
        landscapeScrollBottomConstraint = scrollView.bottomAnchor.constraint(
            equalTo: guide.bottomAnchor, constant: -4
        )
        landscapeMinimumHeightConstraint = mainStack.heightAnchor.constraint(
            greaterThanOrEqualTo: scrollView.frameLayoutGuide.heightAnchor,
            constant: traitCollection.userInterfaceIdiom == .pad ? -36 : -16
        )
        updateAdaptiveLayout(isLandscape: view.bounds.width > view.bounds.height)
    }

    private func updateAdaptiveLayoutIfNeeded() {
        let isLandscape = view.bounds.width > view.bounds.height
        updateAdaptiveLayout(isLandscape: isLandscape, availableHeight: view.bounds.height)
    }

    private func updateAdaptiveLayout(
        isLandscape: Bool, availableHeight: CGFloat? = nil
    ) {
        let resolvedHeight = availableHeight ?? view.bounds.height
        let screen = view.window?.windowScene?.screen
        let screenBounds = screen?.bounds ?? .zero
        let nativeScreenBounds = screen?.nativeBounds ?? .zero
        let isSmallPhoneScreen = screenBounds != .zero
            && (max(screenBounds.width, screenBounds.height) <= 700
                || max(nativeScreenBounds.width, nativeScreenBounds.height) <= 1_400)
        let isCompactPortrait = !isLandscape
            && traitCollection.userInterfaceIdiom == .phone
            && ((resolvedHeight > 0 && resolvedHeight < 750)
                || (view.bounds.width > 0 && view.bounds.width <= 375)
                || isSmallPhoneScreen)
        guard usesLandscapeLayout != isLandscape
                || usesCompactPortraitLayout != isCompactPortrait
        else { return }
        usesLandscapeLayout = isLandscape
        usesCompactPortraitLayout = isCompactPortrait

        NSLayoutConstraint.deactivate([
            portraitCandidateWidthConstraint,
            landscapeInputWidthConstraint,
            landscapeCandidateWidthConstraint,
            landscapeActionsWidthConstraint,
            landscapeInputHeightConstraint
        ].compactMap { $0 })
        NSLayoutConstraint.deactivate(portraitActionConstraints)
        landscapeScrollBottomConstraint?.isActive = false
        landscapeMinimumHeightConstraint?.isActive = false
        outputHeightConstraint?.isActive = false

        for item in [
            inputColumn, candidateList, controlsColumn, candidateWorkspace, actionsStack
        ] {
            for stack in [mainStack, candidateWorkspace]
            where stack.arrangedSubviews.contains(item) {
                stack.removeArrangedSubview(item)
            }
            item.removeFromSuperview()
        }

        mainStack.alignment = .fill
        mainStack.distribution = .fill
        mainStack.spacing = traitCollection.userInterfaceIdiom == .pad ? 16 : 12

        if isLandscape {
            // Keep all four regions in a fixed left-to-right order. Candidate
            // content only changes button titles, never the column geometry.
            mainStack.axis = .horizontal
            mainStack.alignment = .top
            mainStack.addArrangedSubview(inputColumn)
            mainStack.addArrangedSubview(candidateList)
            mainStack.addArrangedSubview(controlsColumn)
            mainStack.addArrangedSubview(actionsStack)
            actionsStack.axis = .vertical
            actionsStack.spacing = 8

            landscapeInputWidthConstraint = inputColumn.widthAnchor.constraint(
                equalTo: mainStack.widthAnchor,
                multiplier: traitCollection.userInterfaceIdiom == .pad ? 0.50 : 0.44
            )
            landscapeCandidateWidthConstraint = candidateList.widthAnchor.constraint(
                equalTo: mainStack.widthAnchor,
                multiplier: traitCollection.userInterfaceIdiom == .pad ? 0.18 : 0.20
            )
            landscapeActionsWidthConstraint = actionsStack.widthAnchor.constraint(
                equalTo: mainStack.widthAnchor,
                multiplier: traitCollection.userInterfaceIdiom == .pad ? 0.12 : 0.14
            )
            landscapeInputHeightConstraint = inputColumn.heightAnchor.constraint(
                equalTo: mainStack.heightAnchor
            )
            landscapeInputWidthConstraint?.isActive = true
            landscapeCandidateWidthConstraint?.isActive = true
            landscapeActionsWidthConstraint?.isActive = true
            landscapeInputHeightConstraint?.isActive = true
            landscapeMinimumHeightConstraint?.isActive = true
            landscapeScrollBottomConstraint?.isActive = true

            let compactHeight: CGFloat = traitCollection.userInterfaceIdiom == .pad ? 38 : 30
            compactableButtonHeightConstraints.forEach { $0.constant = compactHeight }
            candidateButtonHeightConstraints.forEach {
                $0.constant = traitCollection.userInterfaceIdiom == .pad ? 38 : 24
            }
            let lacksVerticalSpace = traitCollection.userInterfaceIdiom == .phone
                && (availableHeight ?? view.bounds.height) < 500
            optionalNavigationControls.forEach { $0.isHidden = lacksVerticalSpace }
        } else {
            mainStack.axis = .vertical
            mainStack.alignment = .fill
            mainStack.addArrangedSubview(inputColumn)

            candidateWorkspace.axis = .horizontal
            candidateWorkspace.alignment = .fill
            candidateWorkspace.distribution = .fill
            candidateWorkspace.spacing = 12
            candidateWorkspace.addArrangedSubview(candidateList)
            candidateWorkspace.addArrangedSubview(controlsColumn)
            mainStack.addArrangedSubview(candidateWorkspace)
            actionsStack.axis = .horizontal
            actionsStack.spacing = 10
            actionsStack.translatesAutoresizingMaskIntoConstraints = false
            view.addSubview(actionsStack)

            portraitCandidateWidthConstraint = candidateList.widthAnchor.constraint(
                equalTo: candidateWorkspace.widthAnchor, multiplier: 0.48
            )
            portraitCandidateWidthConstraint?.isActive = true
            outputHeightConstraint?.constant = isCompactPortrait
                ? 160
                : (traitCollection.userInterfaceIdiom == .pad ? 340 : 220)
            outputHeightConstraint?.isActive = true
            NSLayoutConstraint.activate(portraitActionConstraints)
            compactableButtonHeightConstraints.forEach { $0.constant = 38 }
            candidateButtonHeightConstraints.forEach {
                $0.constant = traitCollection.userInterfaceIdiom == .pad ? 38 : 32
            }
            optionalNavigationControls.forEach { $0.isHidden = false }
        }

        view.setNeedsLayout()
    }

    private func configureCandidateList() {
        candidateList.axis = .vertical
        candidateList.spacing = 1
        candidateList.backgroundColor = .separator
        candidateList.layer.borderWidth = 1
        candidateList.layer.borderColor = UIColor.separator.cgColor
        candidateList.layer.cornerRadius = 8
        candidateList.clipsToBounds = true

        for index in 0..<BopomofoEngine.candidatesPerPage {
            let button = UIButton(configuration: .plain())
            button.tag = index
            button.contentHorizontalAlignment = .leading
            button.accessibilityIdentifier = "hardware-editor.candidate.\(index + 1)"
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.7
            let height = button.heightAnchor.constraint(
                equalToConstant: traitCollection.userInterfaceIdiom == .pad ? 38 : 32
            )
            height.isActive = true
            candidateButtonHeightConstraints.append(height)
            button.addTarget(self, action: #selector(selectCandidate(_:)), for: .touchUpInside)
            candidateButtons.append(button)
            candidateList.addArrangedSubview(button)
        }
        pageIndicatorLabel.heightAnchor.constraint(equalToConstant: 24).isActive = true
        candidateList.addArrangedSubview(pageIndicatorLabel)
    }

    private func configureControlsColumn() {
        for view in [
            phraseButton, makeModeControlPanel(), makeEditingControlPanel(), UIView()
        ] {
            controlsColumn.addArrangedSubview(view)
        }
        controlsColumn.axis = .vertical
        controlsColumn.spacing = 10
    }

    private func makeModeControlPanel() -> UIView {
        modeButton.accessibilityIdentifier = "hardware-editor.mode"
        modeButton.addTarget(self, action: #selector(changeMode), for: .touchUpInside)
        widthButton.accessibilityIdentifier = "hardware-editor.width"
        widthButton.addTarget(self, action: #selector(changeWidth), for: .touchUpInside)
        symbolButton.setTitle("符", for: .normal)
        symbolButton.accessibilityIdentifier = "hardware-editor.symbols"
        symbolButton.addTarget(self, action: #selector(showSymbols), for: .touchUpInside)
        emojiButton.setTitle("🙂", for: .normal)
        emojiButton.accessibilityIdentifier = "hardware-editor.emoji"
        emojiButton.accessibilityLabel = "表情符號"
        emojiButton.addTarget(self, action: #selector(showEmojis), for: .touchUpInside)

        for button in [modeButton, widthButton, symbolButton, emojiButton] {
            button.configuration?.buttonSize = .small
            button.setContentCompressionResistancePriority(.required, for: .horizontal)
            let height = button.heightAnchor.constraint(equalToConstant: 38)
            height.isActive = true
            compactableButtonHeightConstraints.append(height)
        }

        let firstRow = UIStackView(arrangedSubviews: [UIView(), modeButton, widthButton])
        let secondRow = UIStackView(arrangedSubviews: [UIView(), symbolButton, emojiButton])
        for row in [firstRow, secondRow] {
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
        }

        let panel = UIStackView(arrangedSubviews: [firstRow, secondRow])
        panel.axis = .vertical
        panel.spacing = 6
        return panel
    }

    private func makeEditingControlPanel() -> UIView {
        configureEditingButton(
            escapeButton, title: "Esc", identifier: "hardware-editor.escape",
            action: #selector(pressEscape)
        )
        configureEditingButton(
            backspaceButton, title: "⌫", identifier: "hardware-editor.backspace",
            action: #selector(pressBackspace)
        )
        configureEditingButton(
            enterButton, title: "Enter", identifier: "hardware-editor.enter",
            action: #selector(pressEnter)
        )
        enterButton.accessibilityLabel = "Enter"
        configureEditingButton(
            leftButton, title: "←", identifier: "hardware-editor.left",
            action: #selector(pressLeft)
        )
        configureEditingButton(
            upButton, title: "↑", identifier: "hardware-editor.up",
            action: #selector(pressUp)
        )
        configureEditingButton(
            downButton, title: "↓", identifier: "hardware-editor.down",
            action: #selector(pressDown)
        )
        configureEditingButton(
            rightButton, title: "→", identifier: "hardware-editor.right",
            action: #selector(pressRight)
        )
        configureEditingButton(
            spaceButton, title: "空白", identifier: "hardware-editor.space",
            action: #selector(pressSpace)
        )

        let firstRow = UIStackView(arrangedSubviews: [
            escapeButton, backspaceButton, enterButton
        ])
        let upRow = UIStackView(arrangedSubviews: [UIView(), upButton, UIView()])
        let directionRow = UIStackView(arrangedSubviews: [
            leftButton, downButton, rightButton
        ])
        for row in [firstRow, upRow, directionRow] {
            row.axis = .horizontal
            row.spacing = 6
            row.distribution = .fillEqually
        }
        let panel = UIStackView(arrangedSubviews: [
            firstRow, upRow, directionRow, spaceButton
        ])
        panel.axis = .vertical
        panel.spacing = 6
        optionalNavigationControls = [upRow, directionRow, spaceButton]
        return panel
    }

    private func configureEditingButton(
        _ button: UIButton, title: String, identifier: String, action: Selector
    ) {
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = identifier
        button.configuration?.buttonSize = .small
        button.configuration?.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: 3, bottom: 4, trailing: 3
        )
        button.configuration?.titleLineBreakMode = .byClipping
        let buttonFont = UIFontMetrics(forTextStyle: .subheadline).scaledFont(
            for: UIFont.systemFont(ofSize: 15), maximumPointSize: 17
        )
        button.configuration?.titleTextAttributesTransformer =
            UIConfigurationTextAttributesTransformer { attributes in
                var attributes = attributes
                attributes.font = buttonFont
                return attributes
            }
        button.titleLabel?.numberOfLines = 1
        button.titleLabel?.lineBreakMode = .byClipping
        button.titleLabel?.adjustsFontSizeToFitWidth = true
        button.titleLabel?.minimumScaleFactor = 0.7
        let height = button.heightAnchor.constraint(greaterThanOrEqualToConstant: 38)
        height.isActive = true
        compactableButtonHeightConstraints.append(height)
        button.addTarget(self, action: action, for: .touchUpInside)
    }

    private func configurePhraseButton() {
        phraseButton.accessibilityIdentifier = "hardware-editor.phrases"
        phraseButton.contentHorizontalAlignment = .leading
        phraseButton.addTarget(
            self, action: #selector(showPhraseCollections), for: .touchUpInside
        )
    }

    private func configureActionsStack() {
        clearButton.setTitle("清除", for: .normal)
        clearButton.accessibilityIdentifier = "hardware-editor.clear"
        clearButton.addTarget(
            self, action: #selector(requestClearText), for: .touchUpInside
        )

        copyButton.setTitle("複製", for: .normal)
        copyButton.accessibilityIdentifier = "hardware-editor.copy"
        copyButton.addTarget(self, action: #selector(copyText), for: .touchUpInside)

        shareButton.setTitle("分享文字", for: .normal)
        shareButton.accessibilityIdentifier = "hardware-editor.share"
        shareButton.addTarget(self, action: #selector(shareText), for: .touchUpInside)

        for button in [clearButton, copyButton, shareButton] {
            button.configuration?.titleLineBreakMode = .byClipping
            button.titleLabel?.numberOfLines = 1
            button.titleLabel?.adjustsFontSizeToFitWidth = true
            button.titleLabel?.minimumScaleFactor = 0.72
            button.heightAnchor.constraint(
                equalToConstant: traitCollection.userInterfaceIdiom == .pad ? 52 : 44
            ).isActive = true
        }

        actionsStack.addArrangedSubview(clearButton)
        actionsStack.addArrangedSubview(copyButton)
        actionsStack.addArrangedSubview(shareButton)
        actionsStack.axis = .horizontal
        actionsStack.spacing = 10
        actionsStack.distribution = .fillEqually
    }

    private func loadEngine() {
        guard let url = embeddedDatabaseURL() else {
            transientStatus = "找不到內嵌字庫，請重新安裝 App。"
            return
        }
        do {
            let database = try Database(url: url)
            let phrases = AssociatedPhraseStore(database: database)
            collections = try phrases.collections()
            phraseStore = phrases
            applyPhraseSelection(phraseSettings.enabledCollections, persist: false)
            engine = BopomofoEngine(
                dictionary: try CandidateStore(database: database),
                associatedPhrases: phrases
            )
        } catch {
            transientStatus = "字庫載入失敗：\(error)"
        }
    }

    private func applyPhraseSelection(_ selection: Set<String>, persist: Bool = true) {
        let available = Set(collections.map(\.source))
        let validSelection = selection.intersection(available)
        if persist { phraseSettings.setEnabledCollections(validSelection) }
        phraseStore?.setEnabledSources(
            collections.filter { validSelection.contains($0.source) }.map(\.source)
        )
        if engine?.isShowingAssociatedPhrases == true {
            engine?.setAssociatedPhraseSource(phraseStore)
        }
        refreshPhraseButton(selection: validSelection)
    }

    private func refreshPhraseButton(selection: Set<String>? = nil) {
        let selected = selection ?? phraseSettings.enabledCollections
        let title: String
        if selected.isEmpty {
            title = "詞庫：全部關閉"
        } else if selected.count == 1,
                  let source = selected.first,
                  let collection = collections.first(where: { $0.source == source }) {
            title = "詞庫：\(collection.display)"
        } else {
            title = "詞庫：\(selected.count)／\(collections.count)"
        }
        phraseButton.setTitle(title, for: .normal)
        phraseButton.isEnabled = !collections.isEmpty
    }

    private func embeddedDatabaseURL() -> URL? {
        guard let plugInsURL = Bundle.main.builtInPlugInsURL,
              let entries = try? FileManager.default.contentsOfDirectory(
                at: plugInsURL, includingPropertiesForKeys: nil
              )
        else { return nil }
        for url in entries where url.pathExtension == "appex" {
            if let bundle = Bundle(url: url),
               let database = bundle.url(forResource: "KeyKey", withExtension: "db") {
                return database
            }
        }
        return nil
    }

    private func observeKeyboardConnection() {
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardConnectionChanged),
            name: .GCKeyboardDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(keyboardConnectionChanged),
            name: .GCKeyboardDidDisconnect, object: nil
        )
    }

    @objc private func keyboardConnectionChanged() {
        refreshConnectionStatus()
        if GCKeyboard.coalesced != nil {
            captureView.becomeFirstResponder()
        }
    }

    private func refreshConnectionStatus() {
        if let keyboard = GCKeyboard.coalesced {
            let name = keyboard.vendorName.flatMap { $0.isEmpty ? nil : $0 } ?? "實體鍵盤"
            connectionLabel.text = "已連線：\(name)・可以直接輸入"
            connectionLabel.textColor = .systemGreen
        } else {
            connectionLabel.text = "尚未偵測到實體鍵盤"
            connectionLabel.textColor = .secondaryLabel
        }
    }

    private func refresh() {
        insertionCharacterIndex = min(max(insertionCharacterIndex, 0), committedText.count)
        let insertionIndex = committedText.index(
            committedText.startIndex, offsetBy: insertionCharacterIndex
        )
        let prefix = String(committedText[..<insertionIndex])
        let suffix = String(committedText[insertionIndex...])
        let bodyFont = UIFont.preferredFont(forTextStyle: .body)
        let text = NSMutableAttributedString(
            string: prefix,
            attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
        )
        if let reading = engine?.readingText, !reading.isEmpty {
            text.append(NSAttributedString(
                string: reading,
                attributes: [
                    .font: bodyFont,
                    .foregroundColor: Self.accent,
                    .underlineStyle: NSUnderlineStyle.single.rawValue
                ]
            ))
        }
        displayedCaretUTF16Offset = text.length
        text.append(NSAttributedString(
            string: suffix,
            attributes: [.font: bodyFont, .foregroundColor: UIColor.label]
        ))
        outputView.attributedText = text
        outputView.accessibilityValue = committedText
        outputView.scrollRangeToVisible(
            NSRange(location: displayedCaretUTF16Offset, length: 0)
        )
        refreshCursorPositionLabel()
        outputView.layoutIfNeeded()
        updateCursorIndicatorFrame()

        guard let engine else {
            pageIndicatorLabel.text = transientStatus ?? "無法啟動琦琦引擎"
            candidateButtons.enumerated().forEach { index, button in
                configureCandidate(button, number: index + 1, text: nil, highlighted: false)
            }
            updateExportButtons()
            return
        }

        let candidates = engine.displayedCandidates
        for (index, button) in candidateButtons.enumerated() {
            let candidate = index < candidates.count ? candidates[index] : nil
            let highlighted = !engine.isShowingAssociatedPhrases
                && index == engine.highlightedIndex && candidate != nil
            configureCandidate(
                button, number: index + 1, text: candidate, highlighted: highlighted
            )
        }

        if let transientStatus {
            pageIndicatorLabel.text = transientStatus
        } else if !candidates.isEmpty, engine.pageCount > 0 {
            pageIndicatorLabel.text = "\(engine.page + 1)/\(engine.pageCount)"
        } else {
            // Keep the page row's fixed height so opening/closing candidates
            // never changes the editor layout.
            pageIndicatorLabel.text = " "
        }
        modeButton.setTitle(engine.inputMode == .bopomofo ? "ㄅ" : "英", for: .normal)
        modeButton.accessibilityLabel = engine.inputMode == .bopomofo
            ? "目前注音模式，切換英文" : "目前英文模式，切換注音"
        widthButton.setTitle(isFullWidth ? "全" : "半", for: .normal)
        widthButton.accessibilityLabel = isFullWidth
            ? "目前全形，切換半形" : "目前半形，切換全形"
        updateExportButtons()
    }

    private func configureCandidate(
        _ button: UIButton, number: Int, text: String?, highlighted: Bool
    ) {
        var configuration = UIButton.Configuration.plain()
        configuration.title = text.map { "\(number)  \($0)" } ?? "\(number)"
        configuration.contentInsets = NSDirectionalEdgeInsets(
            top: 4, leading: 10, bottom: 4, trailing: 10
        )
        configuration.background.backgroundColor = highlighted
            ? Self.accent : .secondarySystemBackground
        configuration.background.cornerRadius = 0
        configuration.baseForegroundColor = highlighted
            ? .white : (text == nil ? .tertiaryLabel : .label)
        button.configuration = configuration
        button.isEnabled = text != nil
        button.accessibilityLabel = text.map { "第 \(number) 個候選，\($0)" } ?? "第 \(number) 個候選，空白"
    }

    private func updateExportButtons() {
        let canExport = !committedText.isEmpty || engine?.readingText.isEmpty == false
        copyButton.isEnabled = canExport
        shareButton.isEnabled = canExport
        clearButton.isEnabled = canExport || engine?.displayedCandidates.isEmpty == false
    }

    private func refreshCursorPositionLabel() {
        let prefix = committedText.prefix(insertionCharacterIndex)
        let line = prefix.reduce(into: 1) { count, character in
            if character == "\n" { count += 1 }
        }
        let column = prefix.reversed().prefix { $0 != "\n" }.count + 1
        cursorPositionLabel.text = "插入游標：第 \(line) 行・第 \(column) 格"
    }

    private func updateCursorIndicatorFrame() {
        guard let position = outputView.position(
            from: outputView.beginningOfDocument,
            offset: min(displayedCaretUTF16Offset, outputView.text.utf16.count)
        ) else {
            cursorIndicator.isHidden = true
            return
        }
        var caret = outputView.caretRect(for: position)
        guard caret.origin.x.isFinite, caret.origin.y.isFinite else {
            cursorIndicator.isHidden = true
            return
        }
        let lineHeight = outputView.font?.lineHeight
            ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        if caret.height < 1 { caret.size.height = lineHeight }
        caret.size.width = 2.5
        cursorIndicator.frame = caret.integral
        cursorIndicator.isHidden = false
        outputView.bringSubviewToFront(cursorIndicator)
    }

    private func insertCommittedText(_ text: String) {
        guard !text.isEmpty else { return }
        let index = committedText.index(
            committedText.startIndex, offsetBy: insertionCharacterIndex
        )
        committedText.insert(contentsOf: text, at: index)
        insertionCharacterIndex += text.count
        preferredCursorX = nil
    }

    private func deleteCommittedCharacterBackward() {
        guard insertionCharacterIndex > 0 else { return }
        let end = committedText.index(
            committedText.startIndex, offsetBy: insertionCharacterIndex
        )
        let start = committedText.index(before: end)
        committedText.removeSubrange(start..<end)
        insertionCharacterIndex -= 1
        preferredCursorX = nil
    }

    private func apply(_ result: BopomofoEngine.Result, widenASCII: Bool = false) {
        if result.deletesBackward { deleteCommittedCharacterBackward() }
        if !result.text.isEmpty {
            insertCommittedText(widenASCII ? fullWidth(result.text) : result.text)
        }
        if result.sendsReturn { insertCommittedText("\n") }
        transientStatus = nil
        refresh()
    }

    private func fullWidth(_ text: String) -> String {
        guard isFullWidth else { return text }
        return String(text.unicodeScalars.map { scalar -> Character in
            if scalar.value == 0x20 { return "　" }
            if (0x21...0x7E).contains(scalar.value),
               let mapped = UnicodeScalar(scalar.value + 0xFEE0) {
                return Character(String(mapped))
            }
            return Character(String(scalar))
        })
    }

    private func prepareTextForExport() -> Bool {
        guard let engine else { return false }
        if engine.isShowingAssociatedPhrases {
            apply(engine.escape())
        } else if !engine.displayedCandidates.isEmpty {
            apply(engine.selectHighlightedCandidate())
            if engine.isShowingAssociatedPhrases { apply(engine.escape()) }
        } else if !engine.readingText.isEmpty {
            apply(engine.enter())
            if !engine.isShowingAssociatedPhrases, !engine.displayedCandidates.isEmpty {
                apply(engine.selectHighlightedCandidate())
            }
            if engine.isShowingAssociatedPhrases { apply(engine.escape()) }
        }
        guard engine.readingText.isEmpty else {
            transientStatus = "這組注音沒有候選字，請修改後再複製或分享。"
            refresh()
            return false
        }
        return !committedText.isEmpty
    }

    @objc private func selectCandidate(_ sender: UIButton) {
        guard let engine else { return }
        apply(engine.selectDisplayedCandidate(sender.tag))
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func changeMode() {
        guard let engine else { return }
        apply(engine.toggleHardwareLanguage())
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func showPhraseCollections() {
        guard !collections.isEmpty else { return }
        captureView.resignFirstResponder()
        let picker = PhraseCollectionPickerViewController(
            collections: collections,
            enabled: phraseSettings.enabledCollections.intersection(Set(collections.map(\.source)))
        )
        picker.didChange = { [weak self] selection in
            self?.applyPhraseSelection(selection)
            self?.refresh()
        }
        picker.didClose = { [weak self] in
            self?.restoreCaptureFocusAfterModalDismissal()
        }
        let navigation = UINavigationController(rootViewController: picker)
        navigation.modalPresentationStyle = .formSheet
        navigation.isModalInPresentation = true
        present(navigation, animated: true)
    }

    @objc private func changeWidth() {
        isFullWidth.toggle()
        transientStatus = nil
        refresh()
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func showSymbols() {
        guard let engine else { return }
        apply(engine.handleSoftKey("SYMBOL"))
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func showEmojis() {
        guard let engine else { return }
        apply(engine.handleSoftKey("EMOJI"))
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressEscape() {
        guard let engine else { return }
        apply(engine.escape())
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressBackspace() {
        guard let engine else { return }
        apply(engine.backspace())
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressEnter() {
        guard let engine else { return }
        apply(engine.enter())
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressSpace() {
        guard let engine else { return }
        apply(engine.space(), widenASCII: true)
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressLeft() {
        moveCursorOrCandidate(.left)
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressRight() {
        moveCursorOrCandidate(.right)
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressUp() {
        moveCursorOrCandidate(.up)
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func pressDown() {
        moveCursorOrCandidate(.down)
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func requestClearText() {
        guard clearConfirmationOverlay == nil else { return }
        guard !committedText.isEmpty || engine?.readingText.isEmpty == false else {
            transientStatus = "目前沒有文字可清除。"
            refresh()
            restoreCaptureFocusAfterControlAction()
            return
        }

        let overlay = ClearConfirmationOverlayView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        overlay.backgroundColor = UIColor.black.withAlphaComponent(0.35)
        overlay.accessibilityIdentifier = "hardware-editor.clear-confirmation"

        let title = makeLabel("清除全部文字？", style: .headline, color: .label)
        title.textAlignment = .center
        let message = makeLabel(
            "按 Enter 確認清除，按 Esc 取消。",
            style: .body,
            color: .secondaryLabel
        )
        message.textAlignment = .center

        let cancel = UIButton(configuration: .tinted())
        cancel.setTitle("取消（Esc）", for: .normal)
        cancel.accessibilityIdentifier = "hardware-editor.clear-cancel"
        cancel.addTarget(self, action: #selector(cancelClearText), for: .touchUpInside)

        var destructiveConfiguration = UIButton.Configuration.filled()
        destructiveConfiguration.baseBackgroundColor = .systemRed
        let confirm = UIButton(configuration: destructiveConfiguration)
        confirm.setTitle("清除（Enter）", for: .normal)
        confirm.accessibilityIdentifier = "hardware-editor.clear-confirm"
        confirm.addTarget(self, action: #selector(confirmClearText), for: .touchUpInside)

        let actions = UIStackView(arrangedSubviews: [cancel, confirm])
        actions.axis = .horizontal
        actions.spacing = 10
        actions.distribution = .fillEqually

        let content = UIStackView(arrangedSubviews: [title, message, actions])
        content.axis = .vertical
        content.spacing = 16
        content.translatesAutoresizingMaskIntoConstraints = false

        let card = UIView()
        card.translatesAutoresizingMaskIntoConstraints = false
        card.backgroundColor = .secondarySystemBackground
        card.layer.cornerRadius = 16
        card.layer.shadowColor = UIColor.black.cgColor
        card.layer.shadowOpacity = 0.2
        card.layer.shadowRadius = 18
        card.layer.shadowOffset = CGSize(width: 0, height: 8)
        card.addSubview(content)
        overlay.addSubview(card)
        view.addSubview(overlay)

        let guide = view.safeAreaLayoutGuide
        let preferredWidth = card.widthAnchor.constraint(equalToConstant: 360)
        preferredWidth.priority = .defaultHigh
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: view.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: view.bottomAnchor),
            card.centerXAnchor.constraint(equalTo: guide.centerXAnchor),
            card.centerYAnchor.constraint(equalTo: guide.centerYAnchor),
            card.leadingAnchor.constraint(greaterThanOrEqualTo: guide.leadingAnchor, constant: 24),
            card.trailingAnchor.constraint(lessThanOrEqualTo: guide.trailingAnchor, constant: -24),
            preferredWidth,
            content.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 20),
            content.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -20),
            content.topAnchor.constraint(equalTo: card.topAnchor, constant: 22),
            content.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -20),
            cancel.heightAnchor.constraint(greaterThanOrEqualToConstant: 44),
            confirm.heightAnchor.constraint(greaterThanOrEqualToConstant: 44)
        ])

        clearConfirmationOverlay = overlay
        captureView.becomeFirstResponder()
    }

    @objc private func confirmClearText() {
        dismissClearConfirmation()
        committedText = ""
        insertionCharacterIndex = 0
        preferredCursorX = nil
        engine?.reset()
        transientStatus = "已清除"
        refresh()
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func cancelClearText() {
        dismissClearConfirmation()
        transientStatus = nil
        refresh()
        restoreCaptureFocusAfterControlAction()
    }

    private func dismissClearConfirmation() {
        clearConfirmationOverlay?.removeFromSuperview()
        clearConfirmationOverlay = nil
    }

    @objc private func copyText() {
        guard prepareTextForExport() else { return }
        UIPasteboard.general.string = committedText
        transientStatus = "已複製，可直接貼到其他 App。"
        refresh()
        restoreCaptureFocusAfterControlAction()
    }

    @objc private func shareText() {
        guard prepareTextForExport() else { return }
        let activity = UIActivityViewController(
            activityItems: [committedText], applicationActivities: nil
        )
        if let popover = activity.popoverPresentationController {
            popover.sourceView = shareButton
            popover.sourceRect = shareButton.bounds
        }
        present(activity, animated: true)
    }

    @objc private func showHelp() {
        let message = """
        一般候選：1–9
        關聯候選：Shift+1–9（! @ # $ % ^ & * (）
        翻頁：Space／Page Up／Page Down
        切換ㄅ／英：Ctrl+Space
        切換半／全形：Shift+Space
        符號：Ctrl+0／Ctrl+1
        逗號／句號：Ctrl+,／Ctrl+.
        複製全文：Ctrl+C／⌘C
        分享全文：Ctrl+S／⌘S
        清除全文：Ctrl+K／⌘K（Enter 確認、Esc 取消）
        一般候選：↑／↓移動，←／→換頁
        無組字及候選時：方向鍵移動插入游標
        """
        let alert = UIAlertController(
            title: "實體鍵盤操作", message: message, preferredStyle: .alert
        )
        alert.addAction(UIAlertAction(title: "知道了", style: .default) { [weak self] _ in
            self?.restoreCaptureFocusAfterModalDismissal()
        })
        present(alert, animated: true)
    }

    private func restoreCaptureFocusAfterModalDismissal() {
        // UIAlertController invokes its action before the dismissal transition
        // is completely finished. Waiting for that transition prevents a
        // timing-dependent loss of physical-keyboard focus.
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self else { return }
            self.view.window?.endEditing(true)
            self.captureView.becomeFirstResponder()
        }
    }

    private func restoreCaptureFocusAfterControlAction() {
        // UIButton actions run before UIKit finishes updating first-responder
        // focus for the touch. Restore it on the next main-loop turn so the
        // following physical key is never lost.
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.view.window?.endEditing(true)
            self.captureView.becomeFirstResponder()
        }
    }

    @objc private func close() {
        dismiss(animated: true)
    }

    private func makeLabel(
        _ text: String, style: UIFont.TextStyle, color: UIColor
    ) -> UILabel {
        let label = UILabel()
        label.text = text
        label.font = .preferredFont(forTextStyle: style)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = color
        label.numberOfLines = 0
        return label
    }

    private static let accent = UIColor(
        red: 128 / 255, green: 0, blue: 128 / 255, alpha: 1
    )

    private enum CursorDirection {
        case left, right, up, down
    }

    private func moveCursorOrCandidate(_ direction: CursorDirection) {
        guard let engine else { return }
        guard !engine.displayedCandidates.isEmpty else {
            moveInsertionCursor(direction)
            return
        }

        switch direction {
        case .left:
            engine.changePage(by: -1)
        case .right:
            engine.changePage(by: 1)
        case .up:
            engine.moveHighlight(by: -1)
        case .down:
            engine.moveHighlight(by: 1)
        }
        transientStatus = nil
        refresh()
    }

    private func moveInsertionCursor(_ direction: CursorDirection) {
        guard engine?.readingText.isEmpty == true,
              engine?.displayedCandidates.isEmpty == true
        else { return }

        switch direction {
        case .left:
            insertionCharacterIndex = max(0, insertionCharacterIndex - 1)
            preferredCursorX = nil
        case .right:
            insertionCharacterIndex = min(committedText.count, insertionCharacterIndex + 1)
            preferredCursorX = nil
        case .up, .down:
            moveInsertionCursorVertically(upward: direction == .up)
        }
        transientStatus = nil
        refresh()
    }

    private func moveInsertionCursorVertically(upward: Bool) {
        outputView.layoutIfNeeded()
        let offset = utf16Offset(atCharacterIndex: insertionCharacterIndex)
        guard let position = outputView.position(
            from: outputView.beginningOfDocument, offset: offset
        ) else { return }
        let caret = outputView.caretRect(for: position)
        let x = preferredCursorX ?? caret.minX
        preferredCursorX = x
        let lineHeight = max(
            caret.height,
            outputView.font?.lineHeight ?? UIFont.preferredFont(forTextStyle: .body).lineHeight
        )
        let target = CGPoint(
            x: x,
            y: caret.midY + (upward ? -lineHeight : lineHeight)
        )
        guard let targetPosition = outputView.closestPosition(to: target) else { return }
        let targetOffset = outputView.offset(
            from: outputView.beginningOfDocument, to: targetPosition
        )
        insertionCharacterIndex = characterIndex(nearestUTF16Offset: targetOffset)
    }

    private func utf16Offset(atCharacterIndex characterIndex: Int) -> Int {
        let index = committedText.index(committedText.startIndex, offsetBy: characterIndex)
        return committedText[..<index].utf16.count
    }

    private func characterIndex(nearestUTF16Offset target: Int) -> Int {
        var bestIndex = 0
        var bestDistance = Int.max
        var utf16Offset = 0
        for (index, character) in committedText.enumerated() {
            let distance = abs(utf16Offset - target)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
            utf16Offset += String(character).utf16.count
        }
        if abs(utf16Offset - target) < bestDistance {
            bestIndex = committedText.count
        }
        return bestIndex
    }
}

extension HardwareKeyboardEditorViewController: HardwareKeyboardCaptureViewDelegate {
    fileprivate func captureView(
        _ view: HardwareKeyboardCaptureView, didPress key: UIKey
    ) -> Bool {
        let modifiers = hardwareModifiers(key.modifierFlags)
        let usage = Int(key.keyCode.rawValue)
        let mapped = StandardHardwareKeyMapper.key(
            forHIDUsage: usage, modifiers: modifiers
        )

        if clearConfirmationOverlay != nil {
            switch mapped {
            case .returnKey:
                confirmClearText()
            case .escape:
                cancelClearText()
            default:
                break
            }
            return true
        }

        guard let engine else { return false }

        if StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: usage, modifiers: modifiers
        ) {
            copyText()
            return true
        }
        if StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: usage, modifiers: modifiers
        ) {
            shareText()
            return true
        }
        if StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: usage, modifiers: modifiers
        ) {
            requestClearText()
            return true
        }
        if modifiers.contains(.command) {
            return false
        }
        if modifiers.contains(.option) { return false }
        if modifiers.contains(.control) {
            guard !modifiers.contains(.shift) else { return false }
            switch mapped {
            case .space:
                apply(engine.toggleHardwareLanguage())
            case .character("0"), .character("1"):
                apply(engine.showHardwareSymbols())
            case .character(","):
                apply(engine.commitHardwarePunctuation("，"))
            case .character("."):
                apply(engine.commitHardwarePunctuation("。"))
            default:
                return false
            }
            return true
        }
        if mapped == .space, modifiers.contains(.shift) {
            changeWidth()
            return true
        }

        switch mapped {
        case let .character(character):
            if let index = StandardHardwareKeyMapper.candidateIndex(
                forHIDUsage: usage,
                modifiers: modifiers,
                showingAssociatedPhrases: engine.isShowingAssociatedPhrases
            ), engine.displayedCandidates.indices.contains(index) {
                apply(engine.selectDisplayedCandidate(index))
            } else {
                apply(engine.handleHardwareCharacter(character), widenASCII: true)
            }
        case .returnKey:
            apply(engine.enter())
        case .escape:
            apply(engine.escape())
        case .backspace:
            apply(engine.backspace())
        case .tab:
            apply(engine.handleSoftKey("\t"), widenASCII: true)
        case .space:
            apply(engine.space(), widenASCII: true)
        case .pageUp:
            engine.changePage(by: -1)
            transientStatus = nil
            refresh()
        case .pageDown:
            engine.changePage(by: 1)
            transientStatus = nil
            refresh()
        case .leftArrow:
            moveCursorOrCandidate(.left)
        case .rightArrow:
            moveCursorOrCandidate(.right)
        case .upArrow:
            moveCursorOrCandidate(.up)
        case .downArrow:
            moveCursorOrCandidate(.down)
        case nil:
            return false
        }
        return true
    }

    private func hardwareModifiers(_ flags: UIKeyModifierFlags) -> HardwareKeyboardModifiers {
        var modifiers: HardwareKeyboardModifiers = []
        if flags.contains(.shift) { modifiers.insert(.shift) }
        if flags.contains(.control) { modifiers.insert(.control) }
        if flags.contains(.alternate) { modifiers.insert(.option) }
        if flags.contains(.command) { modifiers.insert(.command) }
        if flags.contains(.alphaShift) { modifiers.insert(.capsLock) }
        return modifiers
    }

}

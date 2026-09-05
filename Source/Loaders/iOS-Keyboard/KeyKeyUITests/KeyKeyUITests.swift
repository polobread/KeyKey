import XCTest

@MainActor
final class KeyKeyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchHostApp() {
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeyInputFieldTest"]
        app.launch()
        XCTAssertTrue(app.navigationBars["輸入欄位測試"].waitForExistence(timeout: 8))
    }

    func testAcknowledgementsAreBundledAndReachable() {
        app = XCUIApplication()
        app.launch()

        let button = app.buttons["open-acknowledgements"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()

        XCTAssertTrue(app.navigationBars["授權與致謝"].waitForExistence(timeout: 3))
        let notices = app.textViews["acknowledgements-text"]
        XCTAssertTrue(notices.exists)
        XCTAssertTrue((notices.value as? String)?.contains("Yahoo! KeyKey") == true)
        XCTAssertTrue((notices.value as? String)?.contains("McBopomofo") == true)
    }

    func testSupporterPurchaseControlsAreReachable() {
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeySupporterReview"]
        app.launch()

        let purchase = app.buttons["supporter.purchase"]
        let restore = app.buttons["supporter.restore"]
        for _ in 0..<6 where !purchase.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(purchase.exists)
        XCTAssertTrue(purchase.isHittable)
        XCTAssertTrue(restore.exists)
        XCTAssertTrue(restore.isHittable)
    }

    func testInputFieldMatrixIsReachable() {
        launchHostApp()
        let identifiers = [
            "default", "email", "url", "phone", "integer", "decimal", "date-time",
            "password", "name", "address", "search", "message", "ascii", "ascii-number"
        ]

        for identifier in identifiers {
            XCTAssertTrue(revealField(identifier), "找不到欄位：\(identifier)")
        }
    }

    func test00KeyboardOptInIsConfigured() {
        // Launch once so the extension is installed and registered before Settings
        // enumerates third-party keyboards, especially on the iOS 17 runtime.
        launchHostApp()
        app.terminate()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()

        XCTAssertTrue(openKeyboardList(in: settings), "無法在此 iOS 版本導覽到系統鍵盤清單")
        if settingRow(named: ["琦琦注音"], in: settings).exists { return }

        XCTAssertTrue(tapSettingRow(
            named: [
                "新增鍵盤", "新增鍵盤…", "新增鍵盤⋯", "新增鍵盤...",
                "加入新的鍵盤…", "加入新的鍵盤⋯", "加入新的鍵盤...",
                "Add New Keyboard", "Add New Keyboard…", "Add New Keyboard..."
            ],
            in: settings
        ), "鍵盤清單中找不到「加入新的鍵盤」")
        XCTAssertTrue(tapSettingRow(named: ["琦琦注音"], in: settings), "第三方鍵盤清單中找不到琦琦注音")
    }

    func testKeyboardExtensionModesAndComposition() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()

        guard selectKeyKeyKeyboard() else {
            throw XCTSkip(keyboardActivationFailureMessage)
        }
        let status = app.staticTexts["keyboard.status"]
        XCTAssertEqual(status.label, "標準注音")

        let mode = app.buttons["MODE"]
        XCTAssertTrue(mode.exists)
        mode.tap()
        XCTAssertEqual(status.label, "英文小寫")
        mode.tap()
        XCTAssertEqual(status.label, "數字與符號（一）")
        mode.tap()
        XCTAssertEqual(status.label, "標準注音")

        let stableModeFrame = mode.frame
        app.buttons["ㄋ"].tap()
        app.buttons["ㄧ"].tap()
        app.buttons["ˇ"].tap()
        XCTAssertTrue(app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '第 1 個候選，'")
        ).firstMatch.waitForExistence(timeout: 3))
        app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH '第 1 個候選，'")
        ).firstMatch.tap()

        // The base McBopomofo association for 你 starts with 們. Wait past the
        // document-proxy callbacks so a transient candidate flash cannot pass.
        let associated = app.buttons["第 1 個候選，們"]
        XCTAssertTrue(associated.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)
        XCTAssertTrue(associated.exists)
        XCTAssertTrue(associated.isHittable)
        XCTAssertEqual(field("default").value as? String, "你")
        XCTAssertEqual(mode.frame.minX, stableModeFrame.minX, accuracy: 1)
        XCTAssertEqual(mode.frame.minY, stableModeFrame.minY, accuracy: 1)
        XCTAssertEqual(mode.frame.width, stableModeFrame.width, accuracy: 1)
        XCTAssertEqual(mode.frame.height, stableModeFrame.height, accuracy: 1)
    }

    func testMultiCharacterAssociationsDoNotResizeKeyboard() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()
        guard selectKeyKeyKeyboard() else {
            throw XCTSkip(keyboardActivationFailureMessage)
        }

        try selectOnlyPhraseCollection("anime")
        addTeardownBlock { [weak self] in
            try? self?.selectOnlyPhraseCollection("McBopomofo")
        }

        let mode = app.buttons["MODE"]
        let initialFrame = mode.frame
        app.buttons["ㄋ"].tap()
        app.buttons["ㄧ"].tap()
        app.buttons["ˇ"].tap()
        let primary = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        primary.tap()

        let associated = app.buttons["第 1 個候選，的名字"]
        XCTAssertTrue(associated.waitForExistence(timeout: 3))
        Thread.sleep(forTimeInterval: 0.4)
        assertFrame(mode.frame, equals: initialFrame, message: "顯示多字關聯候選時")
        associated.tap()
        XCTAssertEqual(field("default").value as? String, "你的名字")
        assertFrame(mode.frame, equals: initialFrame, message: "選完關聯候選後")
    }

    func testPortraitAndLandscapeKeepCoreKeysReachable() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()
        guard selectKeyKeyKeyboard() else {
            throw XCTSkip(keyboardActivationFailureMessage)
        }

        assertCoreKeys()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["MODE"].waitForExistence(timeout: 3))
        assertCoreKeys()
        XCUIDevice.shared.orientation = .portrait
    }

    private func assertCoreKeys() {
        for identifier in ["1", "q", "a", "z", "MODE", "SPACE", "BACKSPACE", "ENTER"] {
            XCTAssertTrue(app.buttons[identifier].exists, "方向切換後找不到按鍵：\(identifier)")
            XCTAssertTrue(app.buttons[identifier].isHittable, "方向切換後按鍵不可點：\(identifier)")
        }
    }

    private func selectOnlyPhraseCollection(_ identifier: String) throws {
        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(app.buttons["全部關閉"].waitForExistence(timeout: 2))
        app.buttons["全部關閉"].tap()

        let toggle = app.switches[identifier]
        for _ in 0..<8 where !toggle.isHittable {
            app.swipeUp()
        }
        XCTAssertTrue(toggle.exists, "找不到關聯詞庫：\(identifier)")
        XCTAssertTrue(toggle.isHittable, "關聯詞庫不可操作：\(identifier)")
        toggle.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 2))
    }

    private func assertFrame(_ frame: CGRect, equals expected: CGRect, message: String) {
        XCTAssertEqual(frame.minX, expected.minX, accuracy: 1, message)
        XCTAssertEqual(frame.minY, expected.minY, accuracy: 1, message)
        XCTAssertEqual(frame.width, expected.width, accuracy: 1, message)
        XCTAssertEqual(frame.height, expected.height, accuracy: 1, message)
    }

    private func field(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)["field.\(identifier)"]
    }

    private var keyboardActivationFailureMessage: String {
        "找不到琦琦鍵盤。請先在此 Simulator 的「設定 → 一般 → 鍵盤 → 鍵盤 → 加入新的鍵盤」加入琦琦注音；自動測試不得把鍵盤項目標成 skip。"
    }

    /// Switches among keyboards already enabled for this Simulator. iOS intentionally
    /// does not expose a supported API for silently granting a third-party keyboard,
    /// so the one-time Settings opt-in remains an explicit test precondition.
    private func selectKeyKeyKeyboard() -> Bool {
        let status = app.staticTexts["keyboard.status"]
        if status.waitForExistence(timeout: 2) { return true }

        if let nextKeyboard = nextKeyboardButton() {
            nextKeyboard.press(forDuration: 1)
            let keyKeyPredicate = NSPredicate(
                format: "label BEGINSWITH '琦琦注音' OR label CONTAINS 'KeyKey'"
            )
            let keyKeyButton = app.buttons.matching(keyKeyPredicate).firstMatch
            let keyKeyCell = app.cells.matching(keyKeyPredicate).firstMatch
            let keyKeyText = app.staticTexts.matching(keyKeyPredicate).firstMatch
            if keyKeyButton.waitForExistence(timeout: 1), keyKeyButton.isHittable {
                keyKeyButton.tap()
                if status.waitForExistence(timeout: 2) { return true }
            } else if keyKeyCell.waitForExistence(timeout: 1), keyKeyCell.isHittable {
                let cellFrame = keyKeyCell.frame
                let appFrame = app.frame
                let destination = app.coordinate(withNormalizedOffset: CGVector(
                    dx: cellFrame.midX / appFrame.width,
                    dy: cellFrame.midY / appFrame.height
                ))
                app.otherElements["PopoverDismissRegion"].tap()
                nextKeyboard.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                    .press(forDuration: 1, thenDragTo: destination)
                if status.waitForExistence(timeout: 2) { return true }
            } else if keyKeyText.waitForExistence(timeout: 1) {
                keyKeyText.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
                if status.waitForExistence(timeout: 2) { return true }
            } else {
                app.tap()
            }
        }

        for _ in 0..<8 {
            guard let nextKeyboard = nextKeyboardButton() else { return false }
            nextKeyboard.tap()
            if status.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    private func nextKeyboardButton() -> XCUIElement? {
        let knownLabels = [
            "Next keyboard", "下一個鍵盤", "切換鍵盤", "地球鍵"
        ]
        for label in knownLabels {
            let button = app.buttons[label]
            if button.exists && button.isHittable { return button }
        }

        let matchingButton = app.buttons.matching(NSPredicate(
            format: "label CONTAINS[c] 'keyboard' OR label CONTAINS '鍵盤' OR label CONTAINS '地球'"
        )).firstMatch
        return matchingButton.exists && matchingButton.isHittable ? matchingButton : nil
    }

    private func openKeyboardList(in settings: XCUIApplication) -> Bool {
        // Settings remembers its last page. Walk back until General is visible,
        // while retaining iPad's persistent sidebar behavior.
        for _ in 0..<8 {
            if settingRow(named: ["一般", "General"], in: settings).exists { break }
            let back = settings.navigationBars.buttons.element(boundBy: 0)
            guard back.exists && back.isHittable else { break }
            back.tap()
        }

        guard tapSettingRow(named: ["一般", "General"], in: settings) else { return false }
        let keyboardSetting = settings.staticTexts.matching(identifier: "Keyboard").firstMatch
        if keyboardSetting.waitForExistence(timeout: 2), keyboardSetting.frame.width > 0 {
            keyboardSetting.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        } else if !tapSettingRow(named: ["鍵盤", "Keyboard"], in: settings) {
            return false
        }
        let keyboards = settings.cells["KEYBOARDS"]
        if keyboards.waitForExistence(timeout: 3) {
            keyboards.tap()
            return true
        }
        return tapSettingRow(named: ["鍵盤", "Keyboards"], in: settings)
    }

    @discardableResult
    private func tapSettingRow(named names: [String], in settings: XCUIApplication) -> Bool {
        for _ in 0..<12 {
            let row = settingRow(named: names, in: settings)
            if row.exists && row.isHittable {
                row.tap()
                return true
            }
            if row.exists && row.frame.minY < 180 {
                settings.swipeDown()
            } else {
                settings.swipeUp()
            }
        }
        return false
    }

    private func settingRow(named names: [String], in settings: XCUIApplication) -> XCUIElement {
        let predicate = NSCompoundPredicate(orPredicateWithSubpredicates: names.map {
            NSPredicate(format: "label == %@ OR label BEGINSWITH %@", $0, "\($0),")
        })
        let exactCell = settings.cells.matching(predicate).firstMatch
        if exactCell.exists { return exactCell }

        for name in names {
            let text = settings.staticTexts.matching(identifier: name).firstMatch
            if text.exists { return text }
        }
        return exactCell
    }

    @discardableResult
    private func revealField(_ identifier: String) -> Bool {
        let element = field(identifier)
        for _ in 0..<10 {
            if element.exists && element.isHittable { return true }
            app.swipeUp()
        }
        return element.exists
    }
}

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

    func testHardwareKeyboardEditorHasCopyAndShareActions() {
        app = XCUIApplication()
        app.launch()

        let openEditor = app.buttons["open-hardware-editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()

        XCTAssertTrue(app.navigationBars["實體鍵盤編輯器"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["hardware-editor.output"].exists)
        for action in ["hardware-editor.clear", "hardware-editor.copy", "hardware-editor.share"] {
            XCTAssertTrue(app.buttons[action].exists)
            XCTAssertTrue(app.buttons[action].isHittable)
        }
        XCTAssertTrue(app.buttons["hardware-editor.mode"].exists)
        XCTAssertTrue(app.buttons["hardware-editor.width"].exists)
        XCTAssertTrue(app.buttons["hardware-editor.symbols"].exists)
        XCTAssertTrue(app.buttons["hardware-editor.emoji"].exists)
        XCTAssertEqual(app.buttons["hardware-editor.emoji"].label, "表情符號")
        let editorOutput = app.textViews["hardware-editor.output"]
        let clearAction = app.buttons["hardware-editor.clear"]
        for control in [
            "escape", "backspace", "enter", "left", "up", "down", "right", "space"
        ] {
            let button = app.buttons["hardware-editor.\(control)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(
                button.isHittable,
                "\(control) should be visible and hittable; frame=\(button.frame); "
                    + "output=\(editorOutput.frame); clear=\(clearAction.frame)"
            )
        }
        let help = app.buttons["hardware-editor.help"]
        XCTAssertTrue(help.exists)
        XCTAssertTrue(help.isHittable)
        let phrasePicker = app.buttons["hardware-editor.phrases"]
        XCTAssertTrue(phrasePicker.exists)
        XCTAssertTrue(app.staticTexts["hardware-editor.cursor-position"].exists)
        XCTAssertFalse(app.staticTexts["準備輸入"].exists)
        for number in 1...9 {
            XCTAssertTrue(app.buttons["hardware-editor.candidate.\(number)"].exists)
        }

        // Verify the physical-keyboard path before any touch control can take
        // first-responder focus away from the capture view.
        app.typeKey("q", modifierFlags: [])
        app.typeKey("k", modifierFlags: .control)
        let cancelClear = app.buttons["hardware-editor.clear-cancel"]
        let confirmClear = app.buttons["hardware-editor.clear-confirm"]
        XCTAssertTrue(cancelClear.waitForExistence(timeout: 2))
        XCTAssertTrue(confirmClear.exists)
        // iOS 26 Simulator consumes XCUIKeyboardKeyEscape before UIKit's app
        // responder chain. The app still handles both UIKeyCommand Escape and
        // raw HID Escape; use the visible cancel action for UI automation.
        cancelClear.tap()
        XCTAssertFalse(confirmClear.exists)
        app.typeKey("k", modifierFlags: .command)
        XCTAssertTrue(confirmClear.waitForExistence(timeout: 2))
        confirmClear.tap()
        XCTAssertFalse(confirmClear.exists)

        let layoutScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        layoutScreenshot.name = "Hardware keyboard editor layout"
        layoutScreenshot.lifetime = .keepAlways
        add(layoutScreenshot)

        help.tap()
        XCTAssertTrue(app.alerts["實體鍵盤操作"].waitForExistence(timeout: 2))
        app.alerts["實體鍵盤操作"].buttons["知道了"].tap()

        let firstCandidate = app.buttons["hardware-editor.candidate.1"]
        let stableOutputFrame = app.textViews["hardware-editor.output"].frame
        let stableFirstCandidateFrame = firstCandidate.frame
        let stableLastCandidateFrame = app.buttons["hardware-editor.candidate.9"].frame
        XCTAssertFalse(firstCandidate.isEnabled)
        app.buttons["hardware-editor.symbols"].tap()
        XCTAssertTrue(firstCandidate.isEnabled)
        XCTAssertEqual(
            app.textViews["hardware-editor.output"].frame.minY,
            stableOutputFrame.minY,
            accuracy: 0.5
        )
        XCTAssertEqual(firstCandidate.frame.minY, stableFirstCandidateFrame.minY, accuracy: 0.5)
        XCTAssertEqual(
            app.buttons["hardware-editor.candidate.9"].frame.maxY,
            stableLastCandidateFrame.maxY,
            accuracy: 0.5
        )
        let page = app.staticTexts["hardware-editor.page"]
        XCTAssertTrue(page.waitForExistence(timeout: 1))
        XCTAssertEqual(page.label, "1/10")
        XCTAssertGreaterThanOrEqual(
            page.frame.minY,
            app.buttons["hardware-editor.candidate.9"].frame.maxY - 1
        )
        let pagingScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        pagingScreenshot.name = "Hardware keyboard editor paging layout"
        pagingScreenshot.lifetime = .keepAlways
        add(pagingScreenshot)
        let firstSymbol = firstCandidate.label
        app.buttons["hardware-editor.emoji"].tap()
        XCTAssertTrue(firstCandidate.isEnabled)
        XCTAssertNotEqual(firstCandidate.label, firstSymbol)

        phrasePicker.tap()
        XCTAssertTrue(app.navigationBars["關聯詞詞庫"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.cells["hardware-editor.phrases.base-only"].exists)
        XCTAssertTrue(app.cells["hardware-editor.phrases.none"].exists)
        app.buttons["hardware-editor.phrases.done"].tap()
        XCTAssertTrue(app.navigationBars["實體鍵盤編輯器"].waitForExistence(timeout: 3))

        let output = app.textViews["hardware-editor.output"]
        let clear = app.buttons["hardware-editor.clear"]
        let copy = app.buttons["hardware-editor.copy"]
        let share = app.buttons["hardware-editor.share"]
        let portraitOutputFrame = output.frame
        let portraitCandidateFrame = firstCandidate.frame
        let portraitClearFrame = clear.frame
        let portraitCopyFrame = copy.frame
        let portraitShareFrame = share.frame

        XCUIDevice.shared.orientation = .landscapeLeft
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let landscapeCandidate = app.buttons["hardware-editor.candidate.1"]
        XCTAssertTrue(output.waitForExistence(timeout: 2))
        XCTAssertTrue(landscapeCandidate.waitForExistence(timeout: 2))
        XCTAssertTrue(waitForLayout {
            output.frame.maxX <= landscapeCandidate.frame.minX + 1
                && phrasePicker.frame.maxX <= clear.frame.minX + 1
        })
        XCTAssertLessThanOrEqual(output.frame.maxX, landscapeCandidate.frame.minX + 1)
        XCTAssertLessThanOrEqual(landscapeCandidate.frame.maxX, phrasePicker.frame.minX + 1)
        XCTAssertLessThanOrEqual(phrasePicker.frame.maxX, clear.frame.minX + 1)
        XCTAssertLessThan(clear.frame.minY, copy.frame.minY)
        XCTAssertLessThan(copy.frame.minY, share.frame.minY)

        let landscapeScreenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        landscapeScreenshot.name = "Hardware keyboard editor landscape columns"
        landscapeScreenshot.lifetime = .keepAlways
        add(landscapeScreenshot)

        XCUIDevice.shared.orientation = .portrait
        let restoredPortraitLayout = waitForLayout {
            abs(output.frame.width - portraitOutputFrame.width) <= 1
                && abs(clear.frame.minY - portraitClearFrame.minY) <= 1
        }
        XCTAssertTrue(
            restoredPortraitLayout,
            "旋轉前 output=\(portraitOutputFrame), clear=\(portraitClearFrame)；"
                + "旋轉後 output=\(output.frame), clear=\(clear.frame)"
        )
        assertFrame(output.frame, equals: portraitOutputFrame, message: "橫式轉回直式的輸入區")
        assertFrame(
            firstCandidate.frame,
            equals: portraitCandidateFrame,
            message: "橫式轉回直式的候選區"
        )
        assertFrame(clear.frame, equals: portraitClearFrame, message: "橫式轉回直式的清除按鈕")
        assertFrame(copy.frame, equals: portraitCopyFrame, message: "橫式轉回直式的複製按鈕")
        assertFrame(share.frame, equals: portraitShareFrame, message: "橫式轉回直式的分享按鈕")
    }

    func testHardwareKeyboardEditorLandscapeColumns() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        app = XCUIApplication()
        app.launch()
        let openEditor = app.buttons["open-hardware-editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()
        XCTAssertTrue(app.navigationBars["實體鍵盤編輯器"].waitForExistence(timeout: 3))

        XCUIDevice.shared.orientation = .landscapeLeft
        let output = app.textViews["hardware-editor.output"]
        let firstCandidate = app.buttons["hardware-editor.candidate.1"]
        let phrasePicker = app.buttons["hardware-editor.phrases"]
        let clear = app.buttons["hardware-editor.clear"]
        let copy = app.buttons["hardware-editor.copy"]
        let share = app.buttons["hardware-editor.share"]
        XCTAssertTrue(output.waitForExistence(timeout: 3))
        XCTAssertTrue(firstCandidate.waitForExistence(timeout: 3))
        XCTAssertTrue(phrasePicker.waitForExistence(timeout: 3))
        XCTAssertTrue(clear.waitForExistence(timeout: 3))
        XCTAssertLessThanOrEqual(output.frame.maxX, firstCandidate.frame.minX + 1)
        XCTAssertLessThanOrEqual(firstCandidate.frame.maxX, phrasePicker.frame.minX + 1)
        XCTAssertLessThanOrEqual(phrasePicker.frame.maxX, clear.frame.minX + 1)
        XCTAssertLessThan(clear.frame.minY, copy.frame.minY)
        XCTAssertLessThan(copy.frame.minY, share.frame.minY)

        for control in ["left", "up", "down", "right", "space"] {
            let button = app.buttons["hardware-editor.\(control)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
        }

        let stableOutputFrame = output.frame
        let stableCandidateFrame = firstCandidate.frame
        let stableLastCandidateFrame = app.buttons["hardware-editor.candidate.9"].frame
        let stablePhraseFrame = phrasePicker.frame
        app.buttons["hardware-editor.symbols"].tap()
        XCTAssertTrue(firstCandidate.isEnabled)
        XCTAssertTrue(app.staticTexts["hardware-editor.page"].exists)
        XCTAssertEqual(output.frame.minX, stableOutputFrame.minX, accuracy: 0.5)
        XCTAssertEqual(output.frame.width, stableOutputFrame.width, accuracy: 0.5)
        XCTAssertEqual(firstCandidate.frame.minX, stableCandidateFrame.minX, accuracy: 0.5)
        XCTAssertEqual(firstCandidate.frame.width, stableCandidateFrame.width, accuracy: 0.5)
        XCTAssertEqual(
            app.buttons["hardware-editor.candidate.9"].frame.maxY,
            stableLastCandidateFrame.maxY,
            accuracy: 0.5
        )
        XCTAssertEqual(phrasePicker.frame.minX, stablePhraseFrame.minX, accuracy: 0.5)
        XCTAssertEqual(phrasePicker.frame.width, stablePhraseFrame.width, accuracy: 0.5)

        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Hardware keyboard editor iPad landscape columns"
        screenshot.lifetime = .keepAlways
        add(screenshot)
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

    func testEnterDismissesAssociatedPhrasesBeforeSendingReturn() throws {
        launchHostApp()
        XCTAssertTrue(revealField("message"))
        field("message").tap()
        guard selectKeyKeyKeyboard() else {
            throw XCTSkip(keyboardActivationFailureMessage)
        }

        app.buttons["ㄋ"].tap()
        app.buttons["ㄧ"].tap()
        app.buttons["ˇ"].tap()
        let primary = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(primary.waitForExistence(timeout: 3))
        primary.tap()

        let associated = app.buttons["第 1 個候選，們"]
        XCTAssertTrue(associated.waitForExistence(timeout: 3))
        app.buttons["ENTER"].tap()

        XCTAssertFalse(associated.waitForExistence(timeout: 1))
        XCTAssertEqual(field("message").value as? String, "你\n")
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

    private func waitForLayout(
        timeout: TimeInterval = 3, condition: () -> Bool
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            Thread.sleep(forTimeInterval: 0.05)
        }
        return condition()
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

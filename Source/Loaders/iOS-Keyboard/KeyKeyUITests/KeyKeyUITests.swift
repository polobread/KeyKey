import XCTest
import KeyKeyEngine

@MainActor
final class KeyKeyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    private func launchHostApp(geometryProbe: Bool = false) {
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeyInputFieldTest"] + (geometryProbe ? ["-KeyKeyGeometryProbe"] : [])
        app.launch()
        XCTAssertTrue(app.navigationBars["輸入欄位測試"].waitForExistence(timeout: 8))
    }

    func testNativeGlyphSupportAndResetOnIOS() {
        let native = CandidateGlyphSupport()
        for text in ["你好", "妳", "𠮷", "e\u{301}", "✌️", "🇹🇼", "👩‍💻", "你\u{E0100}"] {
            XCTAssertTrue(native.canDisplay(text), text)
        }
        XCTAssertFalse(native.canDisplay("\u{10FFFF}"))
        XCTAssertFalse(native.canDisplay("你\u{10FFFF}"))
        var available = false
        let cached = CandidateGlyphSupport { _ in available }
        XCTAssertFalse(cached.canDisplay("字"))
        available = true
        XCTAssertFalse(cached.canDisplay("字"))
        cached.reset()
        XCTAssertTrue(cached.canDisplay("字"))
    }

    func testSmokeContainerAppLaunchesWithProductionControls() {
        app = XCUIApplication()
        app.launch()

        XCTAssertTrue(app.staticTexts["琦琦輸入法"].waitForExistence(timeout: 8))
        let version = app.staticTexts["app.version"]
        XCTAssertTrue(version.exists)
        XCTAssertTrue(version.label.hasPrefix("版本 "))
        XCTAssertNotEqual(version.label, "版本 —")
        for identifier in [
            "open-hardware-editor", "open-input-method-settings", "open-user-phrases",
            "open-system-settings", "supporter.purchase",
            "supporter.restore", "open-acknowledgements"
        ] {
            XCTAssertTrue(app.buttons[identifier].exists, "首頁缺少控制項：\(identifier)")
        }

        #if DEBUG
        XCTAssertTrue(app.buttons["open-input-field-test"].exists)
        #else
        XCTAssertFalse(app.buttons["open-input-field-test"].exists)
        #endif
    }

    func testAppSettingsEntryOpensAndPersistsCompositionMode() {
        app = XCUIApplication()
        app.launch()

        let entry = app.buttons["open-input-method-settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        XCTAssertTrue(app.navigationBars["輸入法設定"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.segmentedControls["app-settings.candidate-color"].exists)
        XCTAssertTrue(app.switches["app-settings.input-clicks"].exists)
        XCTAssertTrue(app.switches["app-settings.collection.McBopomofo"].exists)
        XCTAssertTrue(app.buttons["app-settings.user-phrases"].exists)
        XCTAssertTrue(app.buttons["app-settings.reset-learning"].exists)

        let mode = app.segmentedControls["app-settings.composition-mode"]
        mode.buttons["傳統注音"].tap()
        app.navigationBars["輸入法設定"].buttons.element(boundBy: 0).tap()
        entry.tap()
        XCTAssertTrue(mode.buttons["傳統注音"].isSelected)
        mode.buttons["好打注音"].tap()
    }

    func testTouchKeyboardUsesSharedSpaceSetting() {
        test00KeyboardOptInIsConfigured()
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        app.segmentedControls["app-settings.composition-mode"].buttons["好打注音"].tap()
        app.segmentedControls["app-settings.keyboard-layout"].buttons["標準"].tap()
        let toggle = app.switches["app-settings.space-selects-candidates"]
        XCTAssertTrue(toggle.exists)
        if toggle.value as? String != "0" { toggle.tap() }
        XCTAssertEqual(toggle.value as? String, "0")
        app.buttons["app-settings.reset-learning"].tap()
        app.alerts.buttons["重設"].tap()
        launchHostApp()
        XCTAssertTrue(revealField("message"))
        let output = field("message")
        output.tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        for key in "su3" { app.buttons[String(key)].tap() }
        app.buttons["SPACE"].tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "你 " })
        app.buttons["BACKSPACE"].tap() // Remove the space, then correct the earlier character.
        app.buttons["keyboard.smart-cell.1"].tap()
        let alternate = app.buttons["第 2 個候選，妳"]
        XCTAssertTrue(alternate.waitForExistence(timeout: 3))
        alternate.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "妳" })
        app.buttons["keyboard.smart-cell.1"].tap()
        let original = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "候選，你")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 3))
        original.tap() // Restore the learning preference before testing the enabled setting.
        XCTAssertTrue(waitForLayout { output.value as? String == "你" })
        app.terminate()
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        let enabled = app.switches["app-settings.space-selects-candidates"]
        if enabled.value as? String != "1" { enabled.tap() }
        XCTAssertEqual(enabled.value as? String, "1")
        app.terminate()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        XCTAssertEqual(app.switches["app-settings.space-selects-candidates"].value as? String, "1")
        launchHostApp()
        XCTAssertTrue(revealField("message"))
        let secondOutput = field("message")
        secondOutput.tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        for key in "su3" { app.buttons[String(key)].tap() }
        app.buttons["SPACE"].tap()
        XCTAssertTrue(app.buttons["第 1 個候選，你"].waitForExistence(timeout: 3))
        XCTAssertEqual(secondOutput.value as? String, "你")
        app.terminate()
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        let restored = app.switches["app-settings.space-selects-candidates"]
        if restored.value as? String != "0" { restored.tap() }
        XCTAssertEqual(restored.value as? String, "0")
    }

    func testSharedSpaceSelectionAndIndependentDownArrow() {
        app = XCUIApplication()
        app.launch()
        let settings = app.buttons["open-input-method-settings"]
        settings.tap()
        app.segmentedControls["app-settings.composition-mode"].buttons["好打注音"].tap()
        app.segmentedControls["app-settings.keyboard-layout"].buttons["標準"].tap()
        let toggle = app.switches["app-settings.space-selects-candidates"]
        XCTAssertTrue(toggle.exists)
        if toggle.value as? String != "0" { toggle.tap() }
        app.buttons["app-settings.reset-learning"].tap()
        app.alerts.buttons["重設"].tap()
        app.navigationBars["輸入法設定"].buttons.element(boundBy: 0).tap()
        app.buttons["open-hardware-editor"].tap()
        let output = app.textViews["hardware-editor.output"]
        XCTAssertTrue(output.waitForExistence(timeout: 3))
        for key in "su3" { app.typeKey(String(key), modifierFlags: []) }
        app.buttons["hardware-editor.down"].tap()
        let firstCandidate = app.buttons["hardware-editor.candidate.1"]
        XCTAssertTrue(firstCandidate.label.contains("你"), firstCandidate.label)
        let firstPage = firstCandidate.label
        app.typeKey(" ", modifierFlags: [])
        XCTAssertNotEqual(firstCandidate.label, firstPage, "候選開啟後，空白仍負責翻頁")
        let secondPage = firstCandidate.label
        app.buttons["hardware-editor.backspace"].tap()
        XCTAssertEqual(firstCandidate.label, secondPage, "候選開啟時退格不能修改組字")
        app.buttons["hardware-editor.escape"].tap()
        XCTAssertFalse(firstCandidate.isEnabled)
        // With the list closed and Space selection disabled, Space inserts into
        // preedit. Removing it must reveal the original syllable to Down again.
        app.typeKey(" ", modifierFlags: [])
        XCTAssertEqual(output.value as? String, "")
        app.buttons["hardware-editor.backspace"].tap()
        app.buttons["hardware-editor.down"].tap()
        XCTAssertTrue(app.buttons["hardware-editor.candidate.1"].label.contains("你"))
        app.buttons["hardware-editor.candidate.1"].tap()
        app.buttons["hardware-editor.enter"].tap()
        XCTAssertEqual(output.value as? String, "你")
        app.navigationBars["實體鍵盤編輯器"].buttons.element(boundBy: 0).tap()
        settings.tap()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.terminate()
        app.launch()
        settings.tap()
        XCTAssertEqual(toggle.value as? String, "1")
        app.navigationBars["輸入法設定"].buttons.element(boundBy: 0).tap()
        app.buttons["open-hardware-editor"].tap()
        for key in "su3" { app.typeKey(String(key), modifierFlags: []) }
        app.buttons["hardware-editor.space"].tap()
        XCTAssertTrue(app.buttons["hardware-editor.candidate.1"].label.contains("你"))
        XCTAssertEqual(output.value as? String, "") // Candidate selection retains uncommitted composition.
        app.buttons["hardware-editor.candidate.1"].tap()
        app.buttons["hardware-editor.enter"].tap()
        XCTAssertEqual(output.value as? String, "你")
        app.navigationBars["實體鍵盤編輯器"].buttons.element(boundBy: 0).tap()
        settings.tap()
        toggle.tap()
        XCTAssertEqual(toggle.value as? String, "0")
    }

    func testHsuLayoutSettingsPersistAndKeyboardKeepsEnglishKeycaps() {
        test00KeyboardOptInIsConfigured()
        app = XCUIApplication()
        app.launch()
        let entry = app.buttons["open-input-method-settings"]
        XCTAssertTrue(entry.waitForExistence(timeout: 8))
        entry.tap()
        let layout = app.segmentedControls["app-settings.keyboard-layout"]
        layout.buttons["許氏鍵盤"].tap()
        app.terminate()
        app.launch()
        entry.tap()
        XCTAssertTrue(layout.buttons["許氏鍵盤"].isSelected)

        launchHostApp()
        XCTAssertTrue(revealField("message"))
        field("message").tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        app.buttons["SETTINGS"].tap()
        let keyboardLayout = app.segmentedControls["bopomofo-keyboard-layout"]
        // Extension preferences also work without Full Access to the App Group.
        keyboardLayout.buttons["許氏鍵盤"].tap()
        app.segmentedControls["bopomofo-composition-mode"].buttons["傳統注音"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["j"].label, "j")
        for key in "nef" { app.buttons[String(key)].tap() }
        let candidate = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        candidate.tap()
        XCTAssertTrue(waitForLayout { (self.field("message").value as? String) == "你" })

        app.buttons["SETTINGS"].tap()
        keyboardLayout.buttons["標準"].tap()
        app.segmentedControls["bopomofo-composition-mode"].buttons["好打注音"].tap()
        app.buttons["完成"].tap()
        XCTAssertEqual(app.buttons["j"].label, "ㄨ")
        app.terminate()
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        app.segmentedControls["app-settings.keyboard-layout"].buttons["標準"].tap()
    }

    func testUserPhraseManagerOpensAndCreatesPhrase() {
        app = XCUIApplication()
        app.launch()

        let manager = app.buttons["open-user-phrases"]
        XCTAssertTrue(manager.waitForExistence(timeout: 8))
        manager.tap()
        XCTAssertTrue(app.navigationBars["好打注音自訂詞"].waitForExistence(timeout: 3))
        let list = app.tables["user-phrases.list"]
        XCTAssertTrue(list.exists)
        let phrase = list.cells.containing(.staticText, identifier: "琦琦").firstMatch
        if phrase.exists {
            phrase.swipeLeft()
            app.buttons["刪除"].tap()
        }

        let add = app.buttons["user-phrases.add"]
        XCTAssertTrue(add.isEnabled,
            "自訂詞無法新增；請檢查測試包的 App Group 簽章。\(app.alerts.debugDescription)")
        add.tap()
        let text = app.textFields["user-phrases.text"]
        let reading = app.textFields["user-phrases.reading"]
        XCTAssertTrue(text.waitForExistence(timeout: 3))
        text.tap()
        text.typeText("琦琦")
        reading.tap()
        reading.typeText("su3cl3")
        app.alerts["新增自訂詞"].buttons["儲存"].tap()
        XCTAssertTrue(phrase.waitForExistence(timeout: 3))
        phrase.swipeLeft()
        app.buttons["刪除"].tap()
        XCTAssertFalse(phrase.exists)
    }

    func testSmokeHardwareKeyboardEditorOpens() {
        app = XCUIApplication()
        app.launch()

        let openEditor = app.buttons["open-hardware-editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()

        XCTAssertTrue(app.navigationBars["實體鍵盤編輯器"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.textViews["hardware-editor.output"].exists)
        XCTAssertTrue(app.buttons["hardware-editor.candidate.1"].exists)
        for identifier in [
            "hardware-editor.clear", "hardware-editor.copy", "hardware-editor.share"
        ] {
            XCTAssertTrue(app.buttons[identifier].exists, "編輯器缺少控制項：\(identifier)")
        }
    }

    func testSmokeContainerAppSurvivesRotationAndRelaunch() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }

        app = XCUIApplication()
        app.launch()
        let openEditor = app.buttons["open-hardware-editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(openEditor.waitForExistence(timeout: 3))
        XCTAssertTrue(revealControl(openEditor), "旋轉或重開後找不到可操作的編輯器入口")
        XCTAssertTrue(openEditor.isHittable)

        app.terminate()
        app.launch()
        XCTAssertTrue(app.staticTexts["琦琦輸入法"].waitForExistence(timeout: 8))
        XCTAssertTrue(revealControl(openEditor), "旋轉或重開後找不到可操作的編輯器入口")
        XCTAssertTrue(openEditor.isHittable)
    }

    func testSmokeSettingsEntryOpensSystemSettings() {
        app = XCUIApplication()
        app.launch()

        let openSettings = app.buttons["open-system-settings"]
        XCTAssertTrue(openSettings.waitForExistence(timeout: 8))
        openSettings.tap()

        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        XCTAssertTrue(settings.wait(for: .runningForeground, timeout: 5))
    }

    func testAcknowledgementsAreBundledAndReachable() {
        app = XCUIApplication()
        app.launch()

        let button = app.buttons["open-acknowledgements"]
        XCTAssertTrue(button.waitForExistence(timeout: 8))
        button.tap()

        XCTAssertTrue(app.navigationBars["授權與致謝"].waitForExistence(timeout: 3))
        let directory = app.tables["acknowledgements.components"]
        XCTAssertTrue(directory.waitForExistence(timeout: 3))
        let yahoo = directory.cells["acknowledgements.component.yahoo"]
        XCTAssertTrue(yahoo.exists)
        yahoo.tap()
        let notices = app.textViews["acknowledgements-text"]
        XCTAssertTrue(notices.waitForExistence(timeout: 3))
        XCTAssertTrue((notices.value as? String)?.contains("Yahoo! Inc.") == true)
        XCTAssertTrue((notices.value as? String)?.contains("Redistribution and use") == true)
        app.navigationBars.buttons.element(boundBy: 0).tap()

        let rust = directory.cells["acknowledgements.component.rust"]
        XCTAssertTrue(revealControl(rust))
        rust.tap()
        XCTAssertTrue(notices.waitForExistence(timeout: 3))
        let rustText = notices.value as? String ?? ""
        XCTAssertTrue(rustText.contains("The Rust Project Developers"))
        XCTAssertTrue(rustText.contains("The Crossbeam Project Developers"))
        XCTAssertTrue(rustText.contains("Unicode"))
        XCTAssertTrue(rustText.contains("Permission is hereby granted"))
        let detail = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        detail.name = "iOS Rust component acknowledgements"
        detail.lifetime = .keepAlways
        add(detail)
        app.navigationBars.buttons.element(boundBy: 0).tap()
        let keykey = directory.cells["acknowledgements.component.keykey"]
        XCTAssertTrue(revealControl(keykey))
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "iOS acknowledgements component directory"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        keykey.tap()
        XCTAssertTrue((notices.value as? String)?.contains("Chui-Ping Cheng") == true)

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

    func testSupporterSectionOrderFollowsEntitlement() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        for status in ["trial", "expired", "paid"] {
            app = XCUIApplication()
            app.launchArguments = ["-KeyKeySupporterFixture", status]
            app.launch()
            let title = app.staticTexts["supporter.title"]
            let purchase = app.buttons["supporter.purchase"]
            let restore = app.buttons["supporter.restore"]
            XCTAssertTrue(title.waitForExistence(timeout: 8))
            if status == "paid" {
                for _ in 0..<8 where !purchase.isHittable { app.swipeUp() }
                XCTAssertTrue(purchase.isHittable)
                XCTAssertEqual(purchase.label, "謝謝支持")
                XCTAssertFalse(purchase.isEnabled)
                XCTAssertFalse(restore.exists)
                XCTAssertLessThan(app.buttons["open-acknowledgements"].frame.maxY,
                                  title.frame.minY)
                XCTAssertLessThan(app.buttons["open-input-field-test"].frame.maxY,
                                  title.frame.minY)
            } else {
                XCTAssertLessThan(app.staticTexts["app.version"].frame.maxY, title.frame.minY)
                XCTAssertLessThan(restore.frame.maxY, app.staticTexts["app.subtitle"].frame.minY)
                XCTAssertTrue(restore.exists)
                XCTAssertTrue(waitForLayout { purchase.label == "付費支持" && purchase.isEnabled })
            }
            XCTAssertTrue(app.staticTexts["supporter.price"].exists)
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Supporter section order: \(status)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            app.terminate()
        }
    }

    func testHardwareEditorSupportPromptGatingAndLongConnection() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        let keyboardName = "Magic Keyboard Bluetooth USB Keyboard with a very long device name"
        for status in ["expired", "trial", "paid"] {
            app = XCUIApplication()
            app.launchArguments = ["-KeyKeySupporterFixture", status,
                                   "-KeyKeyHardwareKeyboardName", keyboardName]
            app.launch()
            let editor = app.buttons["open-hardware-editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 8))
            for _ in 0..<8 where !editor.isHittable { app.swipeUp() }
            editor.tap()
            let method = app.buttons["hardware-editor.composition-mode"]
            XCTAssertTrue(method.waitForExistence(timeout: 3))
            method.tap(); app.buttons["好打注音"].tap()
            let prompt = app.staticTexts["hardware-editor.supporter-prompt"]
            let connection = app.staticTexts["hardware-editor.connection"]
            XCTAssertEqual(connection.label, "已連線：\(keyboardName)・可以直接輸入")
            if status == "expired" {
                XCTAssertTrue(prompt.waitForExistence(timeout: 3))
                XCTAssertEqual(prompt.label, "歡迎付費支持")
                XCTAssertFalse(app.buttons["hardware-editor.supporter-prompt"].exists)
                XCTAssertEqual(connection.frame.midY, prompt.frame.midY, accuracy: 1)
                XCTAssertLessThan(connection.frame.maxX, prompt.frame.minX)
                XCTAssertGreaterThan(connection.frame.width, 0)
                XCTAssertLessThanOrEqual(prompt.frame.maxX, app.frame.maxX)
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "Hardware editor long connection and support prompt"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                for name in ["傳統注音", "倉頡", "簡易"] {
                    method.tap(); app.buttons[name].tap()
                    XCTAssertFalse(prompt.exists, "提示應只出現在好打注音")
                }
                method.tap(); app.buttons["好打注音"].tap()
                XCTAssertTrue(prompt.exists)
                app.buttons["hardware-editor.mode"].tap()
                XCTAssertFalse(prompt.exists)
                app.buttons["hardware-editor.mode"].tap()
                XCTAssertTrue(prompt.exists)
                app.navigationBars["實體鍵盤編輯器"].buttons.element(boundBy: 0).tap()
                let purchase = app.buttons["supporter.purchase"]
                for _ in 0..<8 where !purchase.isHittable { app.swipeDown() }
                XCTAssertTrue(waitForLayout { purchase.label == "付費支持" && purchase.isEnabled })
                purchase.tap()
                XCTAssertTrue(waitForLayout { purchase.label == "謝謝支持" })
                for _ in 0..<8 where !editor.isHittable { app.swipeDown() }
                editor.tap()
                XCTAssertTrue(method.waitForExistence(timeout: 3))
                XCTAssertFalse(prompt.exists, "購買完成後重進編輯器應刷新授權")
            } else {
                XCTAssertFalse(prompt.exists)
            }
            app.terminate()
        }
    }

    func testSupporterRestoreReordersSectionAndHidesPrompt() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeySupporterFixture", "expired"]
        app.launch()
        let restore = app.buttons["supporter.restore"]
        let purchase = app.buttons["supporter.purchase"]
        XCTAssertTrue(restore.waitForExistence(timeout: 8))
        XCTAssertTrue(waitForLayout { restore.isEnabled })
        for _ in 0..<8 where !restore.isHittable { app.swipeUp() }
        restore.tap()
        XCTAssertTrue(waitForLayout { purchase.label == "謝謝支持" })
        XCTAssertFalse(purchase.isEnabled)
        XCTAssertFalse(restore.exists)
        for _ in 0..<8 where !purchase.isHittable { app.swipeUp() }
        XCTAssertTrue(purchase.isHittable)
        XCTAssertLessThan(app.buttons["open-acknowledgements"].frame.maxY,
                          app.staticTexts["supporter.title"].frame.minY)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Restored supporter section at the bottom"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        let editor = app.buttons["open-hardware-editor"]
        for _ in 0..<8 where !editor.isHittable { app.swipeDown() }
        XCTAssertTrue(editor.isHittable)
        editor.tap()
        let method = app.buttons["hardware-editor.composition-mode"]
        XCTAssertTrue(method.waitForExistence(timeout: 3))
        method.tap(); app.buttons["好打注音"].tap()
        XCTAssertFalse(app.staticTexts["hardware-editor.supporter-prompt"].exists,
                       "恢復購買後重進編輯器應隱藏提示")
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
        XCTAssertTrue(app.buttons["hardware-editor.composition-mode"].exists)
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

    func testTableMethodsInHardwareEditorAndSingleRowControls() {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app = XCUIApplication()
        app.launch()
        app.buttons["open-hardware-editor"].tap()
        let method = app.buttons["hardware-editor.composition-mode"]
        let layout = app.buttons["hardware-editor.keyboard-layout"]
        XCTAssertTrue(method.waitForExistence(timeout: 3))
        XCTAssertEqual(method.frame.midY, layout.frame.midY, accuracy: 1)
        XCTAssertLessThan(method.frame.maxX, layout.frame.minX)
        method.tap(); app.buttons["倉頡"].tap()
        XCTAssertTrue(method.label.contains("倉頡"))
        let output = app.textViews["hardware-editor.output"]
        app.typeKey("m", modifierFlags: [])
        app.buttons["hardware-editor.space"].tap()
        XCTAssertEqual(output.value as? String, "一")
        app.typeKey("a", modifierFlags: [])
        app.buttons["hardware-editor.mode"].tap()
        XCTAssertEqual(output.value as? String, "一日")
        app.buttons["hardware-editor.mode"].tap()
        method.tap(); app.buttons["簡易"].tap()
        app.typeKey("a", modifierFlags: [])
        app.typeKey("b", modifierFlags: [])
        XCTAssertTrue(app.buttons["hardware-editor.candidate.1"].label.contains("明"))
        app.buttons["hardware-editor.candidate.1"].tap()
        XCTAssertEqual(output.value as? String, "一日明")
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(waitForLayout { abs(method.frame.midY - layout.frame.midY) < 1 })
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Table methods and single-row landscape controls"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        method.tap(); app.buttons["好打注音"].tap()
    }

    func testPhysicalCangjiePrefixSettingAndNumberSelection() throws {
        app = XCUIApplication()
        app.launch()
        app.buttons["open-hardware-editor"].tap()
        let method = app.buttons["hardware-editor.composition-mode"]
        XCTAssertTrue(method.waitForExistence(timeout: 3))
        method.tap(); app.buttons["倉頡"].tap()
        app.typeKey("h", modifierFlags: [])
        app.typeKey("k", modifierFlags: [])
        let qiao = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label CONTAINS %@",
            "hardware-editor.candidate.", "喬")).firstMatch
        XCTAssertFalse(qiao.exists, "Physical prefix must default off")
        app.buttons["hardware-editor.escape"].tap()
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        XCTAssertFalse(app.buttons["未打完也能選字"].isEnabled)
        app.buttons["即時候選"].tap()
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        XCTAssertTrue(app.buttons["未打完也能選字"].isEnabled)
        app.buttons["未打完也能選字"].tap()
        app.typeKey("h", modifierFlags: [])
        app.typeKey("k", modifierFlags: [])
        XCTAssertTrue(qiao.waitForExistence(timeout: 3))
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Physical Cangjie HK prefix candidates"
        preview.lifetime = .keepAlways
        add(preview)
        let number = try XCTUnwrap(qiao.identifier.split(separator: ".").last)
        app.typeKey(String(number), modifierFlags: [])
        let output = app.textViews["hardware-editor.output"]
        XCTAssertEqual(output.value as? String, "喬")
        // Disabling the physical preview restores the original wait-for-Space flow.
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        app.buttons["錯碼清除"].tap()
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        XCTAssertFalse(app.buttons["未打完也能選字"].isEnabled)
        app.buttons["即時候選"].tap()
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        app.buttons["未打完也能選字"].tap()
        method.tap(); app.buttons["倉頡設定（實體鍵盤）"].tap()
        app.buttons["即時候選"].tap()
        app.typeKey("h", modifierFlags: [])
        app.typeKey("k", modifierFlags: [])
        XCTAssertFalse(qiao.exists)
        app.buttons["hardware-editor.escape"].tap()
        method.tap(); app.buttons["好打注音"].tap()
    }

    func testTouchCangjiePrefixesKeepQiaoSelectable() throws {
        test00KeyboardOptInIsConfigured()
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        output.tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("倉頡")
        let qiao = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "候選，喬")).firstMatch
        app.buttons["h"].tap()
        XCTAssertFalse(qiao.exists)
        app.buttons["k"].tap()
        XCTAssertTrue(qiao.waitForExistence(timeout: 3))
        XCTAssertTrue(qiao.isHittable)
        let preview = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        preview.name = "Cangjie HK prefix candidates"
        preview.lifetime = .keepAlways
        add(preview)
        app.buttons["r"].tap()
        XCTAssertTrue(qiao.waitForExistence(timeout: 3))
        app.buttons["b"].tap()
        XCTAssertTrue(app.buttons["第 1 個候選，喬"].waitForExistence(timeout: 3))
        app.buttons["r"].tap()
        XCTAssertTrue(app.buttons["第 1 個候選，喬"].waitForExistence(timeout: 3))
        XCTAssertTrue(waitForLayout { output.value as? String == "竹大口月口" })
        app.buttons["BACKSPACE"].tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "竹大口月" })
        app.buttons["第 1 個候選，喬"].tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "喬" })
        try selectCompositionMode("好打注音")
    }

    func testTouchCangjieAndSimplexUseExistingCandidateFlow() throws {
        test00KeyboardOptInIsConfigured()
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        output.tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("倉頡")
        XCTAssertEqual(app.buttons["a"].label, "日")
        for key in ["0", "-", "@"] { XCTAssertTrue(app.buttons[key].exists) }
        app.buttons["m"].tap()
        let exact = app.buttons["第 1 個候選，一"]
        XCTAssertTrue(exact.waitForExistence(timeout: 3))
        exact.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "一" })
        try selectCompositionMode("簡易")
        app.buttons["a"].tap(); app.buttons["b"].tap()
        let first = app.buttons["第 1 個候選，明"]
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        first.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "一明" })
        try selectCompositionMode("好打注音")
        app.buttons["MODE"].tap() // ASCII @ belongs to the English placement; Chinese uses ＠.
        app.buttons["@"].tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "一明@" })
        app.buttons["MODE"].tap() // Return through numbers to Chinese for the next field/session.
        app.buttons["MODE"].tap()
        XCTAssertEqual(output.value as? String, "一明@")
    }

    func testHardwareEditorModeWidthAndFunctionButtonsKeepSmartText() {
        app = XCUIApplication()
        app.launch()
        let openEditor = app.buttons["open-hardware-editor"]
        XCTAssertTrue(openEditor.waitForExistence(timeout: 8))
        openEditor.tap()

        let compositionMode = app.buttons["hardware-editor.composition-mode"]
        XCTAssertTrue(compositionMode.waitForExistence(timeout: 3))
        if !compositionMode.label.contains("好打注音") {
            compositionMode.tap()
            let smart = app.buttons["好打注音"]
            XCTAssertTrue(smart.waitForExistence(timeout: 3))
            smart.tap()
        }

        let output = app.textViews["hardware-editor.output"]
        let mode = app.buttons["hardware-editor.mode"]
        let width = app.buttons["hardware-editor.width"]
        func typeReading(_ keys: String) {
            for key in keys { app.typeKey(String(key), modifierFlags: []) }
        }

        typeReading("su3cl3")
        mode.tap()
        XCTAssertEqual(output.value as? String, "你好")

        mode.tap()
        typeReading("su3")
        width.tap()
        XCTAssertEqual(output.value as? String, "你好")
        mode.tap()
        XCTAssertEqual(output.value as? String, "你好你")

        mode.tap()
        typeReading("cl3")
        app.buttons["hardware-editor.symbols"].tap()
        XCTAssertEqual(output.value as? String, "你好你好")

        typeReading("su3")
        app.buttons["hardware-editor.emoji"].tap()
        XCTAssertEqual(output.value as? String, "你好你好你")
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

        for control in ["escape", "backspace", "enter"] {
            let button = app.buttons["hardware-editor.\(control)"]
            XCTAssertTrue(button.exists)
            XCTAssertTrue(button.isHittable)
        }
        // The App deliberately hides optional navigation in a short phone
        // landscape. This editor contract is separate from touch layout profiles.
        let shortPhone = UIDevice.current.userInterfaceIdiom == .phone && app.frame.height < 500
        for control in ["left", "up", "down", "right", "space"] {
            let button = app.buttons["hardware-editor.\(control)"]
            if shortPhone {
                XCTAssertFalse(button.exists, "短橫式不應擠入選用方向控制")
            } else {
                XCTAssertTrue(button.exists)
                XCTAssertTrue(button.isHittable)
            }
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
        screenshot.name = "Hardware keyboard editor landscape columns"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        XCUIDevice.shared.orientation = .portrait
        for control in ["left", "up", "down", "right", "space"] {
            XCTAssertTrue(app.buttons["hardware-editor.\(control)"].waitForExistence(timeout: 3))
            XCTAssertTrue(app.buttons["hardware-editor.\(control)"].isHittable)
        }
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
        if settingRow(named: ["琦琦輸入法"], in: settings).exists { return }

        XCTAssertTrue(tapSettingRow(
            named: [
                "新增鍵盤", "新增鍵盤…", "新增鍵盤⋯", "新增鍵盤...",
                "加入新的鍵盤…", "加入新的鍵盤⋯", "加入新的鍵盤...",
                "Add New Keyboard", "Add New Keyboard…", "Add New Keyboard..."
            ],
            in: settings
        ), "鍵盤清單中找不到「加入新的鍵盤」")
        XCTAssertTrue(tapSettingRow(named: ["琦琦輸入法"], in: settings), "第三方鍵盤清單中找不到琦琦輸入法")
    }

    /// Run locally on the development Mac's iOS 17 Simulator. It drives the
    /// actual keyboard extension, not the container app's editor or engine API.
    /// The embedded fixture is generated from the shared annotated Heart Sutra.
    func testHeartSutraKeyboardExtension() throws {
        XCTAssertEqual(HeartSutraFixture.entries.count, 268)

        // Third-party keyboards require user opt-in. Settings UI is the only
        // supported path, so do it in this test rather than relying on order.
        launchHostApp()
        app.terminate()
        let settings = XCUIApplication(bundleIdentifier: "com.apple.Preferences")
        settings.launch()
        XCTAssertTrue(openKeyboardList(in: settings), "無法開啟系統鍵盤清單")
        if !settingRow(named: ["琦琦輸入法"], in: settings).exists {
            XCTAssertTrue(tapSettingRow(
                named: ["新增鍵盤", "新增鍵盤…", "新增鍵盤⋯", "新增鍵盤...",
                        "加入新的鍵盤…", "加入新的鍵盤⋯", "加入新的鍵盤...",
                        "Add New Keyboard", "Add New Keyboard…", "Add New Keyboard..."],
                in: settings
            ), "找不到加入鍵盤的設定")
            XCTAssertTrue(tapSettingRow(named: ["琦琦輸入法"], in: settings), "無法加入琦琦輸入法")
        }

        launchHostApp()
        XCTAssertTrue(revealField("message"))
        let output = field("message")
        output.tap()
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("傳統注音")
        selectLayoutProfile(.full)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        let disableAll = app.buttons["全部關閉"]
        XCTAssertTrue(disableAll.waitForExistence(timeout: 3))
        disableAll.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 3))

        var expected = ""
        var observed: [String] = []
        defer {
            let textCapture = XCTAttachment(string: output.value as? String ?? "")
            textCapture.name = "ios.txt"
            textCapture.lifetime = .keepAlways
            add(textCapture)
            let rankCapture = XCTAttachment(string: observed.joined(separator: "\n") + "\n")
            rankCapture.name = "ios.positions.tsv"
            rankCapture.lifetime = .keepAlways
            add(rankCapture)
        }

        for (index, entry) in HeartSutraFixture.entries.enumerated() {
            for key in entry.keys {
                let button = app.buttons[String(key)]
                XCTAssertTrue(button.exists, "第 \(index + 1) 字找不到注音鍵 \(key)")
                button.tap()
            }
            if !entry.reading.contains(where: { "ˊˇˋ˙".contains($0) }) {
                app.buttons["SPACE"].tap()
            }

            let nextExpected = expected + entry.target
            // The button's accessibility label exposes its displayed slot.
            // Checking that exact slot after paging proves the target occupies
            // the shared CIN's absolute rank without an expensive nine-cell
            // accessibility snapshot on every one of the 268 syllables.
            let page = (entry.expectedRank - 1) / 9
            let slot = (entry.expectedRank - 1) % 9 + 1
            let candidate = app.buttons["第 \(slot) 個候選，\(entry.target)"]
            // Complete each reading and explicitly choose its target before
            // typing the next character. Visible marked text is not a commit.
            for _ in 0..<page {
                let nextPage = app.buttons["下一頁"]
                XCTAssertTrue(nextPage.waitForExistence(timeout: 3))
                XCTAssertTrue(nextPage.isEnabled, "第 \(index + 1) 字無法翻到基準順位")
                nextPage.tap()
            }
            if candidate.waitForExistence(timeout: 3) {
                candidate.tap()
            } else {
                // A unique reading may commit immediately without a choice.
                XCTAssertEqual(entry.expectedRank, 1,
                               "第 \(index + 1) 字 \(entry.reading) → \(entry.target) 候選順位不同")
                let remainingCandidates = app.buttons.matching(NSPredicate(
                    format: "label MATCHES %@", "第 [0-9]+ 個候選，.*"
                ))
                XCTAssertEqual(remainingCandidates.count, 0,
                               "第 \(index + 1) 字仍有候選，不能把顯示文字當成已選字")
                XCTAssertEqual(output.value as? String, nextExpected,
                               "第 \(index + 1) 字沒有候選也沒有提交")
            }
            let prefixMatches = waitForLayout(timeout: 3) {
                (output.value as? String) == nextExpected
            }
            let actualPrefix = output.value as? String ?? "<nil>"
            if !prefixMatches {
                // XCTest's stop-on-failure can bypass Swift defer. Save the
                // evidence before asserting without changing the expected text.
                let detail = "index=\(index + 1)\nreading=\(entry.reading)\nrank=\(entry.expectedRank)\nexpected=\(nextExpected)\nactual=\(actualPrefix)\n"
                let failureText = XCTAttachment(string: detail)
                failureText.name = "ios-failure-prefix.txt"
                failureText.lifetime = .keepAlways
                add(failureText)
                let failureHierarchy = XCTAttachment(string: app.debugDescription)
                failureHierarchy.name = "ios-failure-hierarchy.txt"
                failureHierarchy.lifetime = .keepAlways
                add(failureHierarchy)
                let failureScreen = XCTAttachment(screenshot: app.screenshot())
                failureScreen.name = "ios-failure-screen"
                failureScreen.lifetime = .keepAlways
                add(failureScreen)
            }
            XCTAssertTrue(prefixMatches,
                "第 \(index + 1) 字提交後全文前綴不符；預期：\(nextExpected)，實際：\(actualPrefix)")
            observed.append("\(index + 1)\t\(entry.reading)\t\(entry.target)\t\(entry.expectedRank)")
            expected = nextExpected

            for mark in entry.punctuation {
                switch mark {
                case "，", "。":
                    app.buttons[String(mark)].tap()
                case "、", "；":
                    app.buttons["SYMBOL"].tap()
                    let slot = mark == "、" ? 3 : 7
                    let symbol = app.buttons["第 \(slot) 個候選，\(mark)"]
                    XCTAssertTrue(symbol.waitForExistence(timeout: 3))
                    symbol.tap()
                default:
                    XCTFail("心經含未定義的標點：\(mark)")
                }
                expected.append(mark)
                XCTAssertTrue(waitForLayout(timeout: 3) {
                    (output.value as? String) == expected
                }, "第 \(index + 1) 字後的標點 \(mark) 不符")
            }
        }
        XCTAssertEqual(observed.count, 268)
        XCTAssertEqual(expected, HeartSutraFixture.expectedText)
        XCTAssertEqual(output.value as? String, HeartSutraFixture.expectedText)
    }

    func testKeyboardExtensionModesAndComposition() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()

        guard selectKeyKeyKeyboard() else {
            XCTFail(keyboardActivationFailureMessage)
            return
        }
        try selectCompositionMode("好打注音")
        // Smart mode deliberately hides its empty candidate/status strip.
        // Check the accessible key plane instead of requiring a hidden label.
        XCTAssertEqual(app.buttons["s"].label, "ㄋ")
        let mode = app.buttons["MODE"]
        XCTAssertTrue(mode.exists)
        mode.tap()
        XCTAssertEqual(app.buttons["s"].label, "s")
        mode.tap()
        XCTAssertTrue(app.buttons["!"].exists)
        mode.tap()
        XCTAssertEqual(app.buttons["s"].label, "ㄋ")

        let stableModeFrame = mode.frame
        app.buttons["ㄋ"].tap()
        app.buttons["ㄧ"].tap()
        app.buttons["ˇ"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你" })
        app.buttons["ㄏ"].tap()
        app.buttons["ㄠ"].tap()
        app.buttons["ˇ"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你好" })
        XCTAssertEqual(mode.frame.minX, stableModeFrame.minX, accuracy: 1)
        XCTAssertEqual(mode.frame.minY, stableModeFrame.minY, accuracy: 1)
        XCTAssertEqual(mode.frame.width, stableModeFrame.width, accuracy: 1)
        XCTAssertEqual(mode.frame.height, stableModeFrame.height, accuracy: 1)
        keepKeyboardEvidence("Extension composing 你好", output: field("default"))
        app.buttons["ENTER"].tap()
        XCTAssertEqual(field("default").value as? String, "你好")
        keepKeyboardEvidence("Extension committed 你好", output: field("default"))
    }

    func testTouchSmartHandoffCommitsTextWhenChangingKeyboard() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        output.tap()
        guard selectKeyKeyKeyboard() else {
            XCTFail(keyboardActivationFailureMessage)
            return
        }
        try selectCompositionMode("好打注音")

        let syllables = ["fu/3", "ru84", "ul4", "fm4", "s83",
                         "xu3", "j06", "sk7", "fm4", "c93"]
        for (index, syllable) in syllables.enumerated() {
            for key in syllable {
                let button = app.buttons[String(key)]
                XCTAssertTrue(button.exists, "找不到注音鍵 \(key)")
                button.tap()
            }
            if index == 6 {
                // This checks host handoff, not the model's 完／玩 ranking.
                // Select the intended word through the real candidate UI.
                app.buttons["keyboard.smart-cell.7"].tap()
                let playing = app.buttons.matching(NSPredicate(
                    format: "label ENDSWITH %@", "候選，玩"
                )).firstMatch
                XCTAssertTrue(playing.waitForExistence(timeout: 3))
                playing.tap()
            }
        }
        XCTAssertTrue(waitForLayout {
            (output.value as? String) == "請假要去哪裡玩呢去海"
        }, "實際宿主文字：\(output.value as? String ?? "<nil>")")
        XCTAssertTrue(app.buttons["keyboard.smart-cell.1"].exists)

        app.buttons["BACKSPACE"].tap()
        XCTAssertTrue(waitForLayout {
            (output.value as? String) == "請假要去哪裡玩呢去"
        })
        for key in "c93" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout {
            (output.value as? String) == "請假要去哪裡玩呢去海"
        })

        let nextKeyboard = try XCTUnwrap(nextKeyboardButton())
        nextKeyboard.tap()
        XCTAssertTrue(waitForLayout(timeout: 5) { !self.app.buttons["SETTINGS"].exists })
        XCTAssertTrue(waitForLayout(timeout: 5) {
            (output.value as? String) == "請假要去哪裡玩呢去海"
        })
        keepKeyboardEvidence("Extension handoff preserved 請假要去哪裡玩呢去海", output: output)
    }

    func testMultiCharacterAssociationsDoNotResizeKeyboard() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()
        guard selectKeyKeyKeyboard() else {
            XCTFail(keyboardActivationFailureMessage)
            return
        }

        try selectCompositionMode("傳統注音")
        addTeardownBlock { [weak self] in
            try? self?.selectCompositionMode("好打注音")
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
            XCTFail(keyboardActivationFailureMessage)
            return
        }

        try selectCompositionMode("傳統注音")
        addTeardownBlock { [weak self] in
            try? self?.selectCompositionMode("好打注音")
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

    /// Run at each pose using Device Hub; failure to activate the extension is
    /// a failure, never a skipped geometry/composition check.
    func testFullProfileLayoutAtCurrentPose() throws {
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeyInputFieldTest", "-KeyKeyGeometryProbe"]
        app.launch()
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.full)
        let orientation = try currentPoseOrientation()
        assertProfileKeysReachable(.full, orientation: orientation)
        let modeFrame = app.buttons["MODE"].frame
        let rightEdge = app.buttons["ENTER"].frame.maxX
        let keyArea = app.buttons["1"].frame.union(app.buttons["-"].frame)
        XCTAssertLessThanOrEqual(rightEdge - modeFrame.minX, KeyboardLayoutProfile.full.wideMetrics.maximumContentWidth + 1)
        for identifier in ["1", "-", "q", "@", "a", "SHIFT", "MODE", "SPACE", "BACKSPACE", "ENTER"] {
            let key = app.buttons[identifier]
            XCTAssertTrue(key.isHittable, identifier)
            XCTAssertGreaterThan(key.frame.width, 15, identifier)
            XCTAssertGreaterThanOrEqual(key.frame.minX, 0, identifier)
            XCTAssertGreaterThanOrEqual(key.frame.minX, keyArea.minX - 1, identifier)
            XCTAssertLessThanOrEqual(key.frame.maxX, keyArea.maxX + 1, identifier)
        }
        for key in "su3cl3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你好" })
        XCTAssertTrue(waitForLayout { abs(self.app.buttons["MODE"].frame.minY - modeFrame.minY) < 1 })
        for scope in ["app", "extension"] {
            let probe = app.staticTexts["\(scope).geometry"]
            if probe.exists, let value = probe.value as? String {
                let attachment = XCTAttachment(string: value)
                attachment.name = "\(scope)-geometry.json"
                attachment.lifetime = .keepAlways
                add(attachment)
            }
        }
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "keyboard-current-pose"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testManualSplitKeyboardPreservesCompositionAndPersists() throws {
        XCUIDevice.shared.orientation = .portrait
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        let activated = selectKeyKeyKeyboard()
        if !activated {
            let evidence = XCTAttachment(screenshot: app.screenshot())
            evidence.name = "manual-keyboard-activation-failure"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCTAssertTrue(activated, keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.full)
        let expanded = app.buttons["ENTER"].frame.maxX - app.buttons["1"].frame.minX
            >= KeyboardLayoutProfile.split.splitGeometry!.minimumExpandedWidth
        let fullHeight = app.buttons["ENTER"].frame.maxY - app.buttons["1"].frame.minY
        XCTAssertFalse(app.buttons["keyboard.space.right"].exists)

        // An unfinished reading must still accept the remaining keys after switching.
        app.buttons["s"].tap()
        app.buttons["SETTINGS"].press(forDuration: 1)
        app.buttons[KeyboardLayoutProfile.split.displayName].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].isHittable)
        assertSplitKeyboardGeometry()
        for key in "u3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你" })
        XCTAssertEqual(app.buttons["ENTER"].frame.maxY - app.buttons["1"].frame.minY,
                       fullHeight + (expanded ? 3 : 0), accuracy: 1)

        // Opening settings and changing appearance must retain the current candidate target.
        app.buttons["keyboard.smart-cell.1"].tap()
        let candidate = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        let lastLeftNumber = expanded ? 5 : 4
        let lastLeft = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(lastLeftNumber) 個候選，")).firstMatch
        let firstRight = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(lastLeftNumber + 1) 個候選，")).firstMatch
        XCTAssertTrue(lastLeft.exists)
        XCTAssertTrue(firstRight.exists)
        let leftEdgeKey = expanded ? "keyboard.split.punctuation.0" : "5"
        XCTAssertEqual(lastLeft.frame.maxX, app.buttons[leftEdgeKey].frame.maxX, accuracy: 1)
        XCTAssertEqual(firstRight.frame.minX, app.buttons["6"].frame.minX, accuracy: 1)
        selectLayoutProfile(.full)
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        candidate.tap()
        XCTAssertEqual(field("default").value as? String, "你")
        selectLayoutProfile(.split)
        app.buttons["keyboard.space.right"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你 " })
        app.buttons["BACKSPACE"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你" })
        app.buttons["SPACE"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你 " })

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "manual-split-keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)

        app.buttons["MODE"].tap()
        app.buttons["a"].tap()
        app.buttons["b"].tap()
        app.buttons["MODE"].tap()
        app.buttons["1"].tap()
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你 ab1" })
        app.buttons["MODE"].tap()
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(app.buttons["keyboard.space.right"].waitForExistence(timeout: 3))
        assertSplitKeyboardGeometry(orientation: .landscape)
        XCUIDevice.shared.orientation = .portrait
        assertSplitKeyboardGeometry()
        XCTAssertEqual(field("default").value as? String, "你 ab1")

        // Another host session reads the saved extension preference.
        app.terminate()
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        assertSplitKeyboardGeometry()
        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(app.buttons["keyboard.layout-profile.\(KeyboardLayoutProfile.split.id)"].isSelected)
        app.buttons["完成"].tap()
        selectLayoutProfile(.full)
        XCTAssertFalse(app.buttons["keyboard.space.right"].exists)
    }

    /// Device Hub controls the pose; this test never changes its orientation.
    func testSplitSmartPagingAtCurrentPoseKeepsUnfinishedReading() throws {
        try checkSplitSmartPagingKeepsUnfinishedReading(rotating: false)
    }

    func testSplitSmartPagingRotationKeepsUnfinishedReading() throws {
        try checkSplitSmartPagingKeepsUnfinishedReading(rotating: true)
    }

    private func checkSplitSmartPagingKeepsUnfinishedReading(rotating: Bool) throws {
        if rotating { XCUIDevice.shared.orientation = .portrait }
        launchHostApp(geometryProbe: !rotating)
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.split)
        for key in "g4" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "是" })
        let target = app.buttons["keyboard.smart-cell.1"]
        target.tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 1 個候選，")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let firstPage = first.label
        XCTAssertTrue(app.buttons["下一頁"].isEnabled)
        app.buttons["下一頁"].tap()
        XCTAssertNotEqual(first.label, firstPage)
        let secondPage = first.label

        let portraitFrame = app.frame
        let directions: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portrait]
        for index in 0..<(rotating ? directions.count : 1) {
            if rotating {
                XCUIDevice.shared.orientation = directions[index]
                assertAppRotation(directions[index], relativeToPortrait: portraitFrame)
            } else {
                attachSimulatorGeometry(name: "candidate-second-page-current-pose")
            }
            XCTAssertTrue(first.waitForExistence(timeout: 3))
            XCTAssertEqual(first.label, secondPage, "旋轉應保留候選頁與目標")
            XCTAssertEqual(output.value as? String, "是")
            XCTAssertTrue(app.buttons["keyboard.space.right"].isHittable)
            let expanded = app.buttons["keyboard.split.punctuation.1"].exists
            let close = app.buttons["keyboard.candidates.close"]
            XCTAssertEqual(close.isHittable, expanded)
            let controls = [app.buttons["上一頁"]] + (1...9).map { index in
                self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(index) 個候選，")).firstMatch
            } + [app.buttons["下一頁"]] + (expanded ? [close] : [])
            let splitIndex = expanded ? 6 : 5
            let leftWidth = app.buttons["q"].frame.width
            let rightWidth = app.buttons["y"].frame.width
            let rowY = controls[0].frame.minY
            for (index, control) in controls.enumerated() {
                XCTAssertTrue(control.exists)
                // Narrow split has five left slots and six right slots. Only
                // the expanded six/six layout promises equal widths throughout.
                XCTAssertEqual(control.frame.width, index < splitIndex ? leftWidth : rightWidth, accuracy: 1)
                XCTAssertEqual(control.frame.minY, rowY, accuracy: 1)
            }
            XCTAssertEqual(controls[splitIndex - 1].frame.maxX,
                           app.buttons[expanded ? "keyboard.split.punctuation.1" : "t"].frame.maxX, accuracy: 1)
            XCTAssertEqual(controls[splitIndex].frame.minX, app.buttons["y"].frame.minX, accuracy: 1)
            XCTAssertTrue(app.buttons["BACKSPACE"].isHittable)
            XCTAssertTrue(app.buttons["ENTER"].isHittable)
        }
        app.buttons["上一頁"].tap()
        XCTAssertEqual(first.label, firstPage)
        app.buttons["下一頁"].tap()
        let enter = app.buttons["ENTER"].frame
        let close = app.buttons["keyboard.candidates.close"]
        if close.isHittable { close.tap() } else { target.tap() }
        XCTAssertTrue(app.buttons["1"].isHittable)
        assertFrame(app.buttons["ENTER"].frame, equals: enter, message: "翻頁後關閉候選")
        XCTAssertEqual(output.value as? String, "是")
        // Pending phonetics cannot open a candidate list in the single core.
        // Exercise their preservation separately after the page/target checks.
        for key in "su" { app.buttons[String(key)].tap() }
        target.tap()
        XCTAssertFalse(first.exists, "未完成注音時不應另開候選")
        XCTAssertEqual(output.value as? String, "是")
        selectLayoutProfile(.full)
        selectLayoutProfile(.split)
        if rotating {
            for direction in directions {
                XCUIDevice.shared.orientation = direction
                assertAppRotation(direction, relativeToPortrait: portraitFrame)
                XCTAssertEqual(output.value as? String, "是")
            }
        }
        app.buttons["3"].tap() // Completes the pending reading preserved above.
        XCTAssertTrue(waitForLayout { output.value as? String == "是你" })
        for key in "cl3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "是你好" }, "候選目標不能改變句尾輸入位置")
        app.buttons["BACKSPACE"].tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "是你" })
        target.tap()
        XCTAssertEqual(first.label, firstPage, "重開候選應回到第一頁")
        if close.isHittable { close.tap() } else { target.tap() }
        selectLayoutProfile(.full)
    }

    func testSplitSmartNineTenSyllableBoundaryAtCurrentPose() throws {
        try checkSplitSmartNineTenSyllableBoundary(rotating: false)
    }

    func testSplitSmartNineTenSyllableBoundaryAndDeletion() throws {
        try checkSplitSmartNineTenSyllableBoundary(rotating: true)
    }

    private func checkSplitSmartNineTenSyllableBoundary(rotating: Bool) throws {
        if rotating { XCUIDevice.shared.orientation = .portrait }
        launchHostApp(geometryProbe: !rotating)
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.split)
        let initialOrientation: KeyboardLayoutProfile.Orientation = rotating ? .portrait : try currentPoseOrientation()
        for _ in 0..<9 { for key in "su3" { app.buttons[String(key)].tap() } }
        XCTAssertTrue(waitForLayout { output.value as? String == String(repeating: "你", count: 9) })
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個組字，")).count, 9)
        XCTAssertEqual(app.buttons["keyboard.smart-cell.9"].label, "第 9 個組字，你")
        app.buttons["s"].tap()
        // Switch both appearance and orientation while the tenth reading is unfinished.
        selectLayoutProfile(.full)
        selectLayoutProfile(.split)
        let portraitFrame = app.frame
        let directions: [UIDeviceOrientation] = [.landscapeLeft, .portrait, .landscapeRight, .portrait]
        for index in 0..<(rotating ? directions.count : 1) {
            if rotating {
                XCUIDevice.shared.orientation = directions[index]
                assertAppRotation(directions[index], relativeToPortrait: portraitFrame)
            } else {
                attachSimulatorGeometry(name: "ninth-syllable-unfinished-current-pose")
            }
            let orientation: KeyboardLayoutProfile.Orientation = rotating
                ? (directions[index].isLandscape ? .landscape : .portrait) : initialOrientation
            assertSplitKeyboardGeometry(orientation: orientation)
            XCTAssertEqual(output.value as? String, String(repeating: "你", count: 9))
        }
        for key in "u3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == String(repeating: "你", count: 10) })
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個組字，")).count, 9)
        XCTAssertEqual(app.buttons["keyboard.smart-cell.9"].label, "第 9 個組字，你")
        app.buttons["keyboard.smart-cell.1"].tap()
        let original = app.buttons.matching(NSPredicate(format: "label ENDSWITH %@", "候選，你")).firstMatch
        XCTAssertTrue(original.waitForExistence(timeout: 3))
        original.tap()
        XCTAssertEqual(output.value as? String, String(repeating: "你", count: 10))
        // Only the nine still-editable syllables are removed. The first character
        // already evicted to the host stays in the document.
        for count in stride(from: 9, through: 1, by: -1) {
            app.buttons["BACKSPACE"].tap()
            XCTAssertTrue(waitForLayout { output.value as? String == String(repeating: "你", count: count) })
        }
        if rotating { XCUIDevice.shared.orientation = .portrait }
        assertSplitKeyboardGeometry()
        for key in "cl3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你好" })
        selectLayoutProfile(.full)
        app.buttons["ENTER"].tap()
        XCTAssertEqual(output.value as? String, "你好")
    }

    func testWideSplitPunctuationCompositionCellsAndDismissal() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.split)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "此測試必須在展開的 Duo 內螢幕或寬版 iPad 執行")
        assertSplitKeyboardGeometry()
        for index in 0..<4 {
            let punctuation = app.buttons["keyboard.split.punctuation.\(index)"]
            XCTAssertTrue(punctuation.isHittable)
            XCTAssertEqual(punctuation.label, ["，", "。", "、", "？"][index])
            punctuation.tap()
        }
        XCTAssertEqual(output.value as? String, "，。、？")
        let prefix = "，。、？"
        for _ in 0..<7 { for key in "su3" { app.buttons[String(key)].tap() } }
        XCTAssertTrue(waitForLayout { output.value as? String == prefix + String(repeating: "你", count: 7) })
        let sixth = app.buttons["keyboard.smart-cell.6"]
        let seventh = app.buttons["keyboard.smart-cell.7"]
        XCTAssertTrue(sixth.isHittable)
        XCTAssertTrue(seventh.isHittable)
        XCTAssertEqual(sixth.frame.maxX, app.buttons["keyboard.split.punctuation.0"].frame.maxX, accuracy: 1)
        XCTAssertEqual(seventh.frame.minX, app.buttons["6"].frame.minX, accuracy: 1)
        XCTAssertFalse(app.buttons["keyboard.smart-cell.12"].exists)
        let hide = app.buttons["keyboard.dismiss"]
        XCTAssertEqual(hide.frame.width, app.buttons["1"].frame.width, accuracy: 1)
        var expected = prefix + String(repeating: "你", count: 7)
        hide.tap()
        XCTAssertTrue(waitForLayout { !self.app.buttons["SETTINGS"].exists })
        XCTAssertEqual(output.value as? String, expected)
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        XCTAssertEqual(output.value as? String, expected)
        // Verify a new reading does not replay the composition committed on hide.
        for key in "cl3" { app.buttons[String(key)].tap() }
        expected += "好"
        XCTAssertTrue(waitForLayout { output.value as? String == expected })
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "wide-six-column-split-keyboard"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["MODE"].tap() // The hide control also remains reachable in English.
        XCTAssertTrue(waitForLayout { hide.isHittable }, hide.debugDescription)
        hide.tap()
        XCTAssertTrue(waitForLayout { !self.app.buttons["SETTINGS"].exists })
        XCTAssertEqual(output.value as? String, expected)
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("傳統注音")
        // The extension may be re-created after dismissal and start in Chinese.
        for _ in 0..<3 {
            if app.buttons["ㄋ"].exists { break }
            app.buttons["MODE"].tap()
        }
        XCTAssertTrue(app.buttons["ㄋ"].exists)
        for key in "su3" { app.buttons[String(key)].tap() }
        let completed = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(completed.waitForExistence(timeout: 3))
        completed.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == expected + "你" })
        XCTAssertTrue(hide.isHittable)
        hide.tap()
        XCTAssertTrue(waitForLayout { !self.app.buttons["SETTINGS"].exists })
        XCTAssertTrue(waitForLayout { output.value as? String == expected + "你" },
                      "收鍵盤後應保留已確認文字，實際為 \(output.value ?? "nil")")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        for key in "cl3" { app.buttons[String(key)].tap() }
        let nextCandidate = app.buttons["第 1 個候選，好"]
        XCTAssertTrue(nextCandidate.waitForExistence(timeout: 3))
        nextCandidate.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == expected + "你好" })
        try selectCompositionMode("好打注音")
        selectLayoutProfile(.full)
    }

    func testWideSplitSmartCandidateRowHasTwelveControls() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        app.buttons["完成"].tap()
        selectLayoutProfile(.split)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "此測試要求寬版分離鍵盤")
        let numberLeft = app.buttons["1"].frame
        let numberRight = app.buttons["-"].frame
        let leftBoundary = app.buttons["keyboard.split.punctuation.0"].frame.maxX
        let rightBoundary = app.buttons["6"].frame.minX
        let enter = app.buttons["ENTER"].frame
        let close = app.buttons["keyboard.candidates.close"]
        XCTAssertFalse(close.isHittable)
        for key in "su3cl3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你好" })
        app.buttons["keyboard.smart-cell.1"].tap()
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 1 個候選，")).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        XCTAssertTrue(["第 1 個候選，你", "第 1 個候選，你好"].contains(first.label),
                      "首候選可為「你」或「你好」，實際為 \(first.label)")
        let candidates = (1...9).map { index in
            self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(index) 個候選，")).firstMatch
        }
        let controls = [app.buttons["上一頁"]] + candidates + [app.buttons["下一頁"], close]
        XCTAssertEqual(controls.count, 12)
        for control in controls {
            XCTAssertTrue(control.exists)
            XCTAssertEqual(control.frame.width, controls[0].frame.width, accuracy: 1)
            XCTAssertEqual(control.frame.minY, controls[0].frame.minY, accuracy: 1)
        }
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(controls[0].frame.minX, numberLeft.minX, accuracy: 1)
        XCTAssertEqual(controls[5].frame.maxX, leftBoundary, accuracy: 1)
        XCTAssertEqual(controls[6].frame.minX, rightBoundary, accuracy: 1)
        XCTAssertEqual(close.frame.maxX, numberRight.maxX, accuracy: 1)
        assertFrame(app.buttons["ENTER"].frame, equals: enter, message: "顯示十二格候選列")
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "wide-twelve-slot-smart-candidates"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        close.tap()
        XCTAssertTrue(waitForLayout { !close.isHittable && self.app.buttons["1"].isHittable })
        XCTAssertEqual(output.value as? String, "你好")
        assertFrame(app.buttons["ENTER"].frame, equals: enter, message: "關閉候選恢復數字列")
        for key in "su3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你好你" })
        app.buttons["keyboard.smart-cell.1"].tap()
        XCTAssertTrue(close.isHittable)
        let candidateBeforeProfileSwitch = first.label
        selectLayoutProfile(.full)
        XCTAssertFalse(close.isHittable)
        XCTAssertTrue(first.isHittable)
        XCTAssertEqual(first.label, candidateBeforeProfileSwitch)
        selectLayoutProfile(.split)
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(first.label, candidateBeforeProfileSwitch)
        close.tap()
        XCTAssertEqual(output.value as? String, "你好你")
        selectLayoutProfile(.full)
    }

    /// A control experiment for native UIKit input-mode crashes. The Debug
    /// host rejects the keyboard extension point, including our own keyboard.
    func testNativeKeyboardSwitchAtCurrentPoseWithoutExtension() {
        app = XCUIApplication()
        app.launchArguments = ["-KeyKeyInputFieldTest", "-KeyKeyGeometryProbe",
                               "-KeyKeyNativeKeyboardOnly", "-KeyKeyFocusDefaultField"]
        app.launch()
        XCTAssertTrue(app.staticTexts["test-host.native-keyboard-only"].waitForExistence(timeout: 8),
                      "原生對照必須確認宿主已停用第三方鍵盤")
        let output = field("default")
        XCTAssertTrue(output.exists)
        tapInputField(output)
        attachSimulatorGeometry(name: "native-only-before-switch")
        XCTAssertFalse(app.buttons["SETTINGS"].exists)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5),
                      "未顯示系統鍵盤，不能判定原生切換成功或失敗")
        guard let globe = nextKeyboardButton() else {
            XCTFail("原生鍵盤缺少可操作的地球鍵")
            return
        }
        globe.tap()
        dismissSystemKeyboardTip()
        guard let pickerGlobe = nextKeyboardButton() else {
            XCTFail("關閉首次使用提示後應仍可開啟鍵盤清單")
            return
        }
        pickerGlobe.press(forDuration: 1)
        let zhuyin = app.cells.matching(NSPredicate(format: "label CONTAINS '注音'")).firstMatch
        XCTAssertTrue(zhuyin.waitForExistence(timeout: 3), "必須在清單選到系統注音，不能只顯示教學提示")
        zhuyin.tap()
        XCTAssertEqual(app.state, .runningForeground, "系統鍵盤切換不應讓宿主當機")
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.keys["ㄅ"].waitForExistence(timeout: 3), "應已切到系統注音鍵盤")
        XCTAssertFalse(app.buttons["SETTINGS"].exists)
        attachSimulatorGeometry(name: "native-only-after-switch")
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "native-only-screen-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    func testWideSplitInputModeSwitchControls() throws {
        try checkWideSplitInputModeSwitch(checkPicker: true, typeComposition: true)
    }

    func testWideSplitInputModeSingleTapWithComposition() throws {
        try checkWideSplitInputModeSwitch(checkPicker: false, typeComposition: true)
    }

    func testWideSplitInputModeSingleTapFromEmptyField() throws {
        try checkWideSplitInputModeSwitch(checkPicker: false, typeComposition: false)
    }

    private func checkWideSplitInputModeSwitch(checkPicker: Bool, typeComposition: Bool) throws {
        launchHostApp(geometryProbe: true)
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode("好打注音")
        selectLayoutProfile(.split)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "此測試必須在展開的 Duo 內螢幕或寬版 iPad 執行")
        if typeComposition {
            for key in "su3cl3" { app.buttons[String(key)].tap() }
        }
        let expected = typeComposition ? "你好" : ""
        let emptyPlaceholder = "一般文字／換行"
        XCTAssertTrue(waitForLayout {
            let text = output.value as? String ?? ""
            return typeComposition ? text == expected : (text.isEmpty || text == emptyPlaceholder)
        })
        XCTAssertTrue(app.buttons[KeyboardLayout.inputModeSwitchKey].isHittable,
                      "Duo 的地球鍵必須能使用，即使 iOS 27.1 錯誤回報 false")
        if checkPicker {
            app.buttons[KeyboardLayout.inputModeSwitchKey].press(forDuration: 1)
            XCTAssertTrue(app.cells.matching(NSPredicate(format: "label CONTAINS 'Keyboard Settings' OR label CONTAINS '鍵盤設定'")).firstMatch.waitForExistence(timeout: 3))
            // The containing sheet can have its own PopoverDismissRegion.
            tapInputField(output)
            XCTAssertTrue(waitForLayout {
                !self.app.cells.matching(NSPredicate(format: "label CONTAINS 'Keyboard Settings' OR label CONTAINS '鍵盤設定'")).firstMatch.exists
            }, "必須先確認系統鍵盤清單已關閉")
            XCTAssertTrue(app.buttons["keyboard.dismiss"].isHittable)
        }
        app.buttons[KeyboardLayout.inputModeSwitchKey].tap()
        XCTAssertTrue(waitForLayout { !self.app.buttons["SETTINGS"].exists })
        XCTAssertEqual(app.state, .runningForeground, "切換輸入法不應讓宿主 App 當機")
        if typeComposition { XCTAssertEqual(output.value as? String, expected) }
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        if typeComposition { XCTAssertEqual(output.value as? String, expected) }
        XCTAssertEqual(app.state, .runningForeground, "切回輸入法後宿主應維持前景")
        selectLayoutProfile(.full)
    }

    private func selectLayoutProfile(_ profile: KeyboardLayoutProfile) {
        app.buttons["SETTINGS"].tap()
        let option = app.buttons["keyboard.layout-profile.\(profile.id)"]
        XCTAssertTrue(option.waitForExistence(timeout: 3))
        if !option.isSelected { option.tap() }
        app.windows.containing(.scrollView, identifier: "keyboard-settings.scroll")
            .firstMatch.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 3))
    }

    private func assertSplitKeyboardGeometry(orientation: KeyboardLayoutProfile.Orientation = .portrait) {
        let profile = KeyboardLayoutProfile.split
        let geometry = profile.splitGeometry!
        assertProfileKeysReachable(profile, orientation: orientation)
        let expanded = app.buttons["keyboard.split.punctuation.0"].exists
        let keys = profile.rows(orientation: orientation, plane: .bopomofo, shifted: false)[0]
        let left = app.buttons[expanded ? "keyboard.split.punctuation.0" : keys[geometry.keySplit - 1]].frame
        let right = app.buttons[keys[geometry.keySplit]].frame
        XCTAssertGreaterThan(right.minX, left.maxX, "分離樣式必須保留中央空隙")
        let lastLeft = app.buttons["SPACE"]
        let firstRight = app.buttons["keyboard.space.right"]
        XCTAssertTrue(firstRight.isHittable)
        if expanded {
            XCTAssertTrue(app.buttons["keyboard.dismiss"].isHittable)
            XCTAssertEqual(app.buttons[keys[0]].frame.width, right.width, accuracy: 1)
            let mode = app.buttons["MODE"].frame
            XCTAssertEqual(app.buttons["SYMBOL"].frame.width / mode.width,
                profile.functionWeight(for: "SYMBOL", expanded: true) / profile.functionWeight(for: "MODE", expanded: true),
                accuracy: 0.03)
            XCTAssertEqual(lastLeft.frame.width / mode.width,
                profile.functionWeight(for: "SPACE", expanded: true) / profile.functionWeight(for: "MODE", expanded: true),
                accuracy: 0.03)
        }
        XCTAssertEqual(lastLeft.frame.maxX, left.maxX, accuracy: 1)
        XCTAssertEqual(firstRight.frame.minX, right.minX, accuracy: 1)
        let identifiers = Set(profile.rows(orientation: orientation, plane: .bopomofo, shifted: false).flatMap { $0 }
            + profile.functionKeys)
        for identifier in identifiers.sorted() {
            let key = app.buttons[identifier]
            XCTAssertTrue(key.isHittable, identifier)
            XCTAssertTrue(key.frame.maxX <= left.maxX + 1 || key.frame.minX >= right.minX - 1,
                          "按鍵跨越中央空隙：\(identifier)")
        }
    }

    func testFullProfilePortraitAndLandscapeKeepDeclaredKeysReachable() throws {
        XCUIDevice.shared.orientation = .portrait
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        field("default").tap()
        guard selectKeyKeyKeyboard() else {
            XCTFail(keyboardActivationFailureMessage)
            return
        }

        try selectCompositionMode("好打注音")
        selectLayoutProfile(.full)
        let portraitFrame = app.frame
        assertProfileKeysReachable(.full)
        XCUIDevice.shared.orientation = .landscapeLeft
        assertAppRotation(.landscapeLeft, relativeToPortrait: portraitFrame)
        assertProfileKeysReachable(.full, orientation: .landscape)
        XCUIDevice.shared.orientation = .portrait
        assertAppRotation(.portrait, relativeToPortrait: portraitFrame)
        assertProfileKeysReachable(.full)
    }

    private func keepKeyboardEvidence(_ name: String, output: XCUIElement) {
        let text = XCTAttachment(string: output.value as? String ?? "")
        text.name = name
        text.lifetime = .keepAlways
        add(text)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = name
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    private func assertProfileKeysReachable(_ profile: KeyboardLayoutProfile,
                                            orientation: KeyboardLayoutProfile.Orientation = .portrait) {
        let representatives = profile.rows(orientation: orientation, plane: .bopomofo, shifted: false)
            .compactMap { $0.first }
        // These four actions are input affordances, not a fixed visual grid.
        for identifier in Set(representatives + ["MODE", "SPACE", "BACKSPACE", "ENTER"]).sorted() {
            XCTAssertTrue(app.buttons[identifier].exists, "方向切換後找不到按鍵：\(identifier)")
            XCTAssertTrue(app.buttons[identifier].isHittable, "方向切換後按鍵不可點：\(identifier)")
        }
    }

    private func selectOnlyPhraseCollection(_ identifier: String) throws {
        app.buttons["SETTINGS"].tap()
        XCTAssertTrue(app.buttons["全部關閉"].waitForExistence(timeout: 2))
        app.buttons["全部關閉"].tap()

        let toggle = app.switches[identifier]
        XCTAssertTrue(toggle.exists, "找不到關聯詞庫：\(identifier)")
        let scroll = app.scrollViews["keyboard-settings.scroll"]
        for _ in 0..<12 {
            if toggle.isHittable { break }
            // Avoid inertial swipes skipping a row in the short keyboard view.
            let velocity = XCUIGestureVelocity(rawValue: 100)
            if toggle.frame.midY < scroll.frame.midY {
                scroll.swipeDown(velocity: velocity)
            } else {
                scroll.swipeUp(velocity: velocity)
            }
            Thread.sleep(forTimeInterval: 0.3)
        }
        XCTAssertTrue(toggle.isHittable, "關聯詞庫不可操作：\(identifier)")
        toggle.tap()
        app.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 2))
    }

    private func selectCompositionMode(_ label: String) throws {
        app.buttons["SETTINGS"].tap()
        let control = app.segmentedControls["bopomofo-composition-mode"]
        XCTAssertTrue(control.waitForExistence(timeout: 2), "找不到注音模式設定")
        let option = control.buttons[label]
        XCTAssertTrue(option.exists, "找不到注音模式：\(label)")
        if option.value as? String != "1" { option.tap() }
        app.windows.containing(.scrollView, identifier: "keyboard-settings.scroll")
            .firstMatch.buttons["完成"].tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 2))
    }

    private func assertAppRotation(_ orientation: UIDeviceOrientation, relativeToPortrait portrait: CGRect) {
        // The full-screen test App must actually adopt the requested axis. Compare
        // to its own portrait frame; do not assume every display is taller than wide.
        let expected = orientation.isLandscape
            ? CGSize(width: portrait.height, height: portrait.width) : portrait.size
        XCTAssertTrue(waitForLayout(timeout: 5) {
            let frame = self.app.frame
            return abs(frame.width - expected.width) <= 1 && abs(frame.height - expected.height) <= 1
        }, "輸入測試頁面未完成方向切換：\(app.frame)，預期 \(expected)")
    }

    private func currentPoseOrientation() throws -> KeyboardLayoutProfile.Orientation {
        let probe = app.staticTexts["app.geometry"]
        var result: KeyboardLayoutProfile.Orientation?
        XCTAssertTrue(waitForLayout(timeout: 5) {
            guard probe.exists, let value = probe.value as? String,
                  let data = value.data(using: .utf8),
                  let snapshot = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let raw = snapshot["interfaceOrientation"] as? Int,
                  let orientation = UIInterfaceOrientation(rawValue: raw), orientation != .unknown
            else { return false }
            result = orientation.isLandscape ? .landscape : .portrait
            return true
        }, "目前姿態診斷需要 Debug Simulator 的有效 app.geometry 探針")
        return try XCTUnwrap(result)
    }

    private func attachSimulatorGeometry(name: String) {
        for scope in ["app", "extension"] {
            let diagnostic = app.staticTexts["\(scope).geometry"]
            if diagnostic.exists, let value = diagnostic.value as? String {
                let evidence = XCTAttachment(string: value)
                evidence.name = "\(scope)-\(name).json"
                evidence.lifetime = .keepAlways
                add(evidence)
            }
        }
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

    private func tapInputField(_ input: XCUIElement) {
        // A centered sheet puts the text field's midpoint on Duo's reserved
        // fold. Its right quarter remains in the active display region.
        input.coordinate(withNormalizedOffset: CGVector(dx: 0.75, dy: 0.5)).tap()
    }

    private func field(_ identifier: String) -> XCUIElement {
        app.descendants(matching: .any)["field.\(identifier)"]
    }

    private var keyboardActivationFailureMessage: String {
        "找不到琦琦鍵盤。請先在此 Simulator 的「設定 → 一般 → 鍵盤 → 鍵盤 → 加入新的鍵盤」加入琦琦輸入法；自動測試不得把鍵盤項目標成 skip。"
    }

    /// Switches among keyboards already enabled for this Simulator. iOS intentionally
    /// does not expose a supported API for silently granting a third-party keyboard,
    /// so the one-time Settings opt-in remains an explicit test precondition.
    private func selectKeyKeyKeyboard() -> Bool {
        dismissSystemKeyboardTip()
        // Smart mode hides the empty candidate/status row. The settings key
        // identifies the extension in either composition mode and layout.
        let status = app.buttons["SETTINGS"]
        if status.waitForExistence(timeout: 8) { return true }

        if let globe = nextKeyboardButton() {
            globe.press(forDuration: 1)
            let predicate = NSPredicate(
                format: "label BEGINSWITH '琦琦輸入法' OR label CONTAINS 'KeyKey'"
            )
            let matches = app.descendants(matching: .any).matching(predicate)
            let row = matches.allElementsBoundByIndex.last {
                $0.isHittable && !$0.frame.isEmpty
            }
            if let row {
                // Filter out the covered setup screen's same-name title, then
                // tap the actual system menu row. Tapping the application to
                // dismiss this menu can activate its Keyboard Settings item.
                row.tap()
                dismissSystemKeyboardTip()
                if status.waitForExistence(timeout: 5) { return true }
            } else {
                let menu = XCTAttachment(string: app.debugDescription)
                menu.name = "Keyboard menu has no hittable KeyKey row"
                menu.lifetime = .keepAlways
                add(menu)
                app.tap()
            }
        }
        let capture = XCTAttachment(string: app.debugDescription)
        capture.name = "Keyboard activation failure hierarchy"
        capture.lifetime = .keepAlways
        add(capture)
        let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        screenshot.name = "Keyboard activation failure"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        return false
    }

    private func dismissSystemKeyboardTip() {
        // iOS can present its first-use keyboard-switching tutorial after
        // cycling keyboards. It covers the globe until Continue is tapped.
        for title in ["Continue", "繼續"] {
            let button = app.buttons[title]
            if button.exists && button.isHittable { button.tap() }
        }
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
            // A root-app swipe starts in the fold region on a half-open
            // Duo. Scroll the relevant Settings pane instead.
            let scrolls = settings.scrollViews.allElementsBoundByIndex
                + settings.tables.allElementsBoundByIndex
                + settings.collectionViews.allElementsBoundByIndex
            let visible = scrolls.filter {
                $0.isHittable && $0.frame.width > 100 && $0.frame.height > 100
            }
            let sidebar = names.contains("一般") || names.contains("General")
            let pane = sidebar
                ? visible.min { $0.frame.midX < $1.frame.midX }
                : visible.max { $0.frame.midX < $1.frame.midX }
            let scrollTarget = pane ?? settings
            if row.exists && row.frame.minY < 180 {
                scrollTarget.swipeDown()
            } else {
                scrollTarget.swipeUp()
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

    private func revealControl(_ element: XCUIElement) -> Bool {
        let scroll = app.tables["acknowledgements.components"].exists
            ? app.tables["acknowledgements.components"] : app.scrollViews.firstMatch
        guard scroll.exists else { return element.isHittable }
        for _ in 0..<20 {
            if element.isHittable { return true }
            let above = element.frame.midY < scroll.frame.midY
            let from = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.4 : 0.6))
            let to = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.6 : 0.4))
            from.press(forDuration: 0.05, thenDragTo: to)
        }
        return element.isHittable
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

import XCTest
import Darwin
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

    func testHardwareEditorRightHandSelectionSurvivesRotationAndRefocus() throws {
        try requireSimulatorHIDBridge()
        let output = launchHardwareEditorWithFreshSmartLearning()
        typeHardwareEditorASCII("su3cl3")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.downArrow)
        // Longer phrases covering the target may precede its single character.
        // Select the actual core position, without changing or assuming its order.
        let target = app.buttons.matching(NSPredicate(
            format: "identifier BEGINSWITH %@ AND label ENDSWITH %@",
            "hardware-editor.candidate.", "候選，郝"
        )).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 3))
        guard let suffix = target.identifier.split(separator: ".").last,
              let number = Int(suffix), (1...9).contains(number) else {
            XCTFail("The target candidate must expose a visible number: \(target.debugDescription)")
            return
        }
        typeHardwareEditorKey(.forwardDelete)
        XCTAssertTrue(target.label.hasSuffix("候選，郝"), "An open candidate list must keep its target")
        app.typeKey(String(number), modifierFlags: [])
        XCTAssertEqual(output.value as? String, "")

        let portrait = app.frame
        XCUIDevice.shared.orientation = .landscapeLeft
        assertAppRotation(.landscapeLeft, relativeToPortrait: portrait)
        XCUIDevice.shared.orientation = .portrait
        assertAppRotation(.portrait, relativeToPortrait: portrait)
        XCTAssertEqual(output.value as? String, "", "Rotation must not commit the composition")

        app.buttons["hardware-editor.help"].tap()
        let help = app.alerts["實體鍵盤操作"]
        XCTAssertTrue(help.waitForExistence(timeout: 3))
        help.buttons["知道了"].tap()
        XCTAssertTrue(waitForLayout { !help.exists })
        // The production modal-dismissal focus restoration waits 0.4 seconds.
        Thread.sleep(forTimeInterval: 0.5)
        typeHardwareEditorASCII("a8 ")
        // XCTest's Return does not reach this iOS Simulator's raw responder.
        // The host bridge emits a complete Return HID press/release pair.
        typeHardwareEditorKey(.return)
        XCTAssertTrue(waitForLayout { output.value as? String == "你郝媽" })
        typeHardwareEditorKey(.return)
        XCTAssertEqual(output.value as? String, "你郝媽\n", "A plain Enter inserts one newline")
        keepKeyboardEvidence("Hardware editor right-hand selection, rotation and refocus", output: output)
    }

    func testHardwareEditorForwardDeleteKeepsCompositionAndRemovesLastReading() throws {
        try requireSimulatorHIDBridge()
        let output = launchHardwareEditorWithFreshSmartLearning()
        typeHardwareEditorASCII("su3cl3")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.forwardDelete)
        typeHardwareEditorASCII("a8 ")
        typeHardwareEditorKey(.return)
        XCTAssertTrue(waitForLayout { output.value as? String == "你媽" },
                      "Deleting 好 must also remove its reading before further input")

        clearHardwareEditor()
        typeHardwareEditorASCII("su3")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.forwardDelete)
        typeHardwareEditorASCII("cl3")
        typeHardwareEditorKey(.return)
        XCTAssertTrue(waitForLayout { output.value as? String == "好" },
                      "Deleting the last reading must not restore 你 on the next input")

        clearHardwareEditor()
        app.buttons["hardware-editor.mode"].tap()
        typeHardwareEditorASCII("z")
        typeHardwareEditorKey(.leftArrow)
        app.buttons["hardware-editor.mode"].tap()
        typeHardwareEditorASCII("su3")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.forwardDelete)
        XCTAssertEqual(output.value as? String, "z",
                       "Deleting the final reading must not also delete the committed suffix")
        typeHardwareEditorASCII("cl3")
        typeHardwareEditorKey(.return)
        XCTAssertTrue(waitForLayout { output.value as? String == "好z" })

        clearHardwareEditor()
        typeHardwareEditorASCII("su3c")
        typeHardwareEditorKey(.forwardDelete)
        typeHardwareEditorASCII("l3")
        typeHardwareEditorKey(.return)
        XCTAssertTrue(waitForLayout { output.value as? String == "你好" },
                      "Delete preserves an unfinished reading, as required by the core")
        keepKeyboardEvidence("Hardware editor forward Delete in composition", output: output)
    }

    func testHardwareEditorForwardDeleteRemovesCommittedGraphemes() throws {
        try requireSimulatorHIDBridge()
        let output = launchHardwareEditorWithFreshSmartLearning()
        // Set up the English plane through the existing control; this test
        // isolates Forward Delete from system-reserved language shortcuts.
        app.buttons["hardware-editor.mode"].tap()
        typeHardwareEditorASCII("ab")
        XCTAssertEqual(output.value as? String, "ab")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.forwardDelete)
        XCTAssertTrue(waitForLayout { output.value as? String == "a" },
                      "The paired Forward Delete HID event must reach the editor's right-delete path")
        typeHardwareEditorKey(.forwardDelete)
        XCTAssertEqual(output.value as? String, "a", "Delete at the end leaves committed text intact")

        clearHardwareEditor()
        typeHardwareEditorASCII("a")
        selectHardwareEditorEmoji("✌️")
        typeHardwareEditorASCII("b")
        XCTAssertEqual(output.value as? String, "a✌️b")
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.leftArrow)
        typeHardwareEditorKey(.forwardDelete)
        XCTAssertTrue(waitForLayout { output.value as? String == "ab" },
                      "Delete removes the whole variation-selector grapheme")
        typeHardwareEditorASCII("x")
        XCTAssertEqual(output.value as? String, "axb", "Forward Delete keeps the insertion cursor")
        keepKeyboardEvidence("Hardware editor forward Delete of committed Unicode", output: output)
    }

    private func launchHardwareEditorWithFreshSmartLearning() -> XCUIElement {
        XCUIDevice.shared.orientation = .portrait
        addTeardownBlock { XCUIDevice.shared.orientation = .portrait }
        app = XCUIApplication()
        app.launch()
        let settings = app.buttons["open-input-method-settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 8))
        settings.tap()
        let scroll = app.scrollViews.firstMatch
        let mode = app.segmentedControls["app-settings.composition-mode"]
        revealSetting(mode, in: scroll)
        mode.buttons["好打注音"].tap()
        let layout = app.segmentedControls["app-settings.keyboard-layout"]
        revealSetting(layout, in: scroll)
        layout.buttons["標準"].tap()
        let space = app.switches["app-settings.space-selects-candidates"]
        revealSetting(space, in: scroll)
        if space.value as? String != "0" { space.tap() }
        let reset = app.buttons["app-settings.reset-learning"]
        revealSetting(reset, in: scroll)
        reset.tap()
        app.alerts.buttons["重設"].tap()
        let result = app.alerts["好打注音學習紀錄"]
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.staticTexts.allElementsBoundByIndex.contains {
            $0.label.contains("App 內編輯器已重設")
        }, "The test requires an independently reset App learning store")
        result.buttons["知道了"].tap()
        app.navigationBars["輸入法設定"].buttons.element(boundBy: 0).tap()
        app.buttons["open-hardware-editor"].tap()
        let output = app.textViews["hardware-editor.output"]
        XCTAssertTrue(output.waitForExistence(timeout: 3))
        XCTAssertEqual(output.value as? String, "")
        return output
    }

    private func typeHardwareEditorASCII(_ text: String) {
        for character in text { app.typeKey(String(character), modifierFlags: []) }
    }

    private func typeHardwareEditorKey(_ key: XCUIKeyboardKey) {
        if key == .forwardDelete || key == .return {
            sendSimulatorKey(key == .forwardDelete ? "delete" : "return")
        } else {
            app.typeKey(key.rawValue, modifierFlags: [])
        }
    }

    private func requireSimulatorHIDBridge() throws {
        guard let value = ProcessInfo.processInfo.environment["KEYKEY_SIMULATOR_HID_PORT"],
              UInt16(value) != nil else {
            throw XCTSkip("Use run-simulator-tests.sh --functional-host, which prepares the isolated Simulator HID bridge")
        }
    }

    // XCTest's string ForwardDelete/Return events do not reach this non-text
    // responder on iOS 26. The host bridge sends paired HID messages to this
    // one selected Simulator, without posting keys to the macOS desktop.
    private func sendSimulatorKey(_ command: String) {
        guard let value = ProcessInfo.processInfo.environment["KEYKEY_SIMULATOR_HID_PORT"],
              let port = UInt16(value) else {
            XCTFail("The isolated Simulator HID bridge is required for Forward Delete")
            return
        }
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { XCTFail("Cannot create the Simulator HID socket"); return }
        defer { Darwin.close(descriptor) }
        var timeout = timeval(tv_sec: 15, tv_usec: 0)
        withUnsafePointer(to: &timeout) {
            _ = setsockopt(descriptor, SOL_SOCKET, SO_RCVTIMEO, $0, socklen_t(MemoryLayout<timeval>.size))
        }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard connected == 0 else { XCTFail("Cannot connect to the Simulator HID bridge"); return }
        let request = command + "\n"
        let sent = request.withCString { Darwin.send(descriptor, $0, request.utf8.count, 0) }
        XCTAssertEqual(sent, request.utf8.count)
        var bytes = [UInt8](repeating: 0, count: 128)
        let count = bytes.withUnsafeMutableBytes { Darwin.recv(descriptor, $0.baseAddress, $0.count, 0) }
        XCTAssertGreaterThan(count, 0)
        if count > 0 {
            XCTAssertEqual(String(decoding: bytes.prefix(count), as: UTF8.self), "OK\n")
        }
    }

    private func clearHardwareEditor() {
        app.buttons["hardware-editor.clear"].tap()
        let confirm = app.buttons["hardware-editor.clear-confirm"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 3))
        confirm.tap()
        XCTAssertTrue(waitForLayout {
            self.app.textViews["hardware-editor.output"].value as? String == ""
        })
    }

    private func selectHardwareEditorEmoji(_ emoji: String) {
        app.buttons["hardware-editor.emoji"].tap()
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND label ENDSWITH %@",
            "hardware-editor.candidate.", "候選，\(emoji)"
        )
        for _ in 0..<((KeyboardInput.emojis.count + 8) / 9) {
            let candidate = app.buttons.matching(predicate).firstMatch
            if candidate.exists, candidate.isEnabled {
                candidate.tap()
                return
            }
            typeHardwareEditorKey(.rightArrow)
        }
        XCTFail("The production Emoji palette must contain \(emoji)")
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
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.aligned)
        let orientation = try currentPoseOrientation()
        assertProfileKeysReachable(.aligned, orientation: orientation)
        let modeFrame = app.buttons["MODE"].frame
        let rightEdge = app.buttons["ENTER"].frame.maxX
        let keyArea = app.buttons["1"].frame.union(app.buttons["-"].frame)
        XCTAssertLessThanOrEqual(rightEdge - modeFrame.minX, KeyboardLayoutProfile.aligned.wideMetrics.maximumContentWidth + 1)
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
        selectLayoutProfile(.aligned)
        let split = try XCTUnwrap(KeyboardLayoutProfile.alignedSplit.splitGeometry)
        let portraitFrame = app.frame
        let fullHeight = app.buttons["ENTER"].frame.maxY - app.buttons["1"].frame.minY
        XCTAssertFalse(app.buttons["keyboard.space.right"].exists)

        // An unfinished reading must still accept the remaining keys after switching.
        app.buttons["s"].tap()
        selectLayoutProfile(.alignedSplit)
        XCTAssertTrue(app.buttons["SETTINGS"].isHittable)
        assertSplitKeyboardGeometry()
        for key in "u3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { self.field("default").value as? String == "你" })
        XCTAssertEqual(app.buttons["ENTER"].frame.maxY - app.buttons["1"].frame.minY,
                       fullHeight, accuracy: 1)

        // Opening settings and changing appearance must retain the current candidate target.
        app.buttons["keyboard.smart-cell.1"].tap()
        let candidate = app.buttons["第 1 個候選，你"]
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        let lastLeftNumber = split.candidateSplit - 1
        let lastLeft = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(lastLeftNumber) 個候選，")).firstMatch
        let firstRight = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(lastLeftNumber + 1) 個候選，")).firstMatch
        XCTAssertTrue(lastLeft.exists)
        XCTAssertTrue(firstRight.exists)
        let leftEdgeKey = "keyboard.split.punctuation.0"
        XCTAssertEqual(lastLeft.frame.maxX, app.buttons[leftEdgeKey].frame.maxX, accuracy: 1)
        XCTAssertEqual(firstRight.frame.minX, app.buttons["6"].frame.minX, accuracy: 1)
        selectLayoutProfile(.aligned)
        XCTAssertTrue(candidate.waitForExistence(timeout: 3))
        candidate.tap()
        XCTAssertEqual(field("default").value as? String, "你")
        selectLayoutProfile(.alignedSplit)
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
        assertAppRotation(.landscapeLeft, relativeToPortrait: portraitFrame)
        XCTAssertTrue(app.buttons["keyboard.space.right"].waitForExistence(timeout: 3))
        assertSplitKeyboardGeometry(orientation: .landscape)
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let evidence = XCTAttachment(screenshot: screen.screenshot())
            evidence.name = "split-landscape-twelve-columns-screen-\(index)"
            evidence.lifetime = .keepAlways
            add(evidence)
        }
        XCUIDevice.shared.orientation = .portrait
        assertAppRotation(.portrait, relativeToPortrait: portraitFrame)
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
        XCTAssertTrue(app.segmentedControls["keyboard.layout-profile"].buttons[KeyboardLayoutProfile.alignedSplit.displayName].isSelected)
        app.buttons["完成"].tap()
        selectLayoutProfile(.aligned)
        XCTAssertFalse(app.buttons["keyboard.space.right"].exists)
    }

    func testSmartCandidateCancellationReturnsEditingToTailAtCurrentPose() throws {
        // The current pose stays unchanged: this is candidate-cursor handoff,
        // not a rotation or layout matrix.
        launchHostApp(geometryProbe: true)
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode(ChineseInputMethod.smart.displayName)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"]
            .buttons[BopomofoKeyboardLayout.standard.displayName].tap()
        closeKeyboardSettings()
        selectLayoutOptions(layout: .alignedSplit, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)
        let emptyValue = try XCTUnwrap(output.value as? String)
        let firstCell = app.buttons["keyboard.smart-cell.1"]
        let editableCells = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個組字，"))
        let candidates = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個候選，"))
        let backspace = app.buttons["BACKSPACE"]
        attachSimulatorGeometry(name: "candidate-cancel-current-pose-before")

        func typeReading(_ keys: String) {
            for key in keys { app.buttons[String(key)].tap() }
        }
        func openFirstCellCandidates() {
            XCTAssertTrue(firstCell.waitForExistence(timeout: 3))
            firstCell.tap()
            XCTAssertTrue(candidates.firstMatch.waitForExistence(timeout: 3))
        }
        func assertClosed(with text: String) {
            XCTAssertTrue(waitForLayout {
                output.value as? String == text && candidates.count == 0
            }, "取消候選不得選字、送字或清除原組字")
        }

        typeReading("su3")
        XCTAssertTrue(waitForLayout { output.value as? String == "你" })
        openFirstCellCandidates()
        firstCell.tap() // Cancel by tapping the same composition cell; do not select a candidate.
        assertClosed(with: "你")
        backspace.tap()
        XCTAssertTrue(waitForLayout {
            output.value as? String == emptyValue && editableCells.count == 0 && candidates.count == 0
        }, "同格取消候選後，立即刪除必須刪掉末音節，不能停在候選目標前")
        attachStripClearingQA(font: .normal, stage: "candidate-toggle-backspace-cleared")

        typeReading("g4su3")
        XCTAssertTrue(waitForLayout { output.value as? String == "是你" })
        openFirstCellCandidates() // The target is the first syllable, not the sentence tail.
        firstCell.tap()
        assertClosed(with: "是你")
        typeReading("cl3")
        XCTAssertTrue(waitForLayout { output.value as? String == "是你好" },
                      "取消句中候選後，下一音節必須接在句尾")
        backspace.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "是你" })
        attachStripClearingQA(font: .normal, stage: "candidate-toggle-tail-editing")

        openFirstCellCandidates()
        let close = app.buttons["keyboard.candidates.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 3), "對齊分離的候選列必須提供關閉鍵")
        XCTAssertTrue(close.isHittable)
        close.tap()
        assertClosed(with: "是你")
        backspace.tap()
        XCTAssertTrue(waitForLayout { output.value as? String == "是" },
                      "取消候選後的刪除應修改句尾，不可刪錯句中目標或完全無效")
        let coverage = XCTAttachment(string:
            "Covered same-cell cancellation and the explicit candidate-close button.")
        coverage.name = "candidate-cancellation-paths-current-pose"
        coverage.lifetime = .keepAlways
        add(coverage)
        backspace.tap()
        XCTAssertTrue(waitForLayout {
            output.value as? String == emptyValue && editableCells.count == 0 && candidates.count == 0
        })
        attachStripClearingQA(font: .normal, stage: "candidate-cancellation-final-cleared")
        attachSimulatorGeometry(name: "candidate-cancel-current-pose-after")
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.alignedSplit)
        let profile = KeyboardLayoutProfile.alignedSplit
        let split = try XCTUnwrap(profile.splitGeometry)
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
            let close = app.buttons["keyboard.candidates.close"]
            XCTAssertTrue(close.isHittable)
            let controls = [app.buttons["上一頁"]] + (1...KeyboardInput.candidatesPerPage).map { index in
                self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(index) 個候選，")).firstMatch
            } + [app.buttons["下一頁"], close]
            let splitIndex = split.candidateSplit
            let orientation: KeyboardLayoutProfile.Orientation = rotating
                ? (directions[index].isLandscape ? .landscape : .portrait) : try currentPoseOrientation()
            let rowKeys = profile.rows(orientation: orientation, plane: .bopomofo, shifted: false)[1]
            let leftWidth = app.buttons[rowKeys[0]].frame.width
            let rightStart = app.buttons[rowKeys[split.keySplit - 1]]
            XCTAssertEqual(leftWidth, rightStart.frame.width, accuracy: 1)
            let rowY = controls[0].frame.minY
            for control in controls {
                XCTAssertTrue(control.exists)
                XCTAssertEqual(control.frame.width, leftWidth, accuracy: 1)
                XCTAssertEqual(control.frame.minY, rowY, accuracy: 1)
            }
            XCTAssertEqual(controls[splitIndex - 1].frame.maxX,
                           app.buttons["keyboard.split.punctuation.1"].frame.maxX, accuracy: 1)
            XCTAssertEqual(controls[splitIndex].frame.minX, rightStart.frame.minX, accuracy: 1)
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
        selectLayoutProfile(.aligned)
        selectLayoutProfile(.alignedSplit)
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
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.alignedSplit)
        let initialOrientation: KeyboardLayoutProfile.Orientation = rotating ? .portrait : try currentPoseOrientation()
        for _ in 0..<9 { for key in "su3" { app.buttons[String(key)].tap() } }
        XCTAssertTrue(waitForLayout { output.value as? String == String(repeating: "你", count: 9) })
        XCTAssertEqual(app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個組字，")).count, 9)
        XCTAssertEqual(app.buttons["keyboard.smart-cell.9"].label, "第 9 個組字，你")
        app.buttons["s"].tap()
        // Switch both appearance and orientation while the tenth reading is unfinished.
        selectLayoutProfile(.aligned)
        selectLayoutProfile(.alignedSplit)
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
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.alignedSplit)
        let profile = KeyboardLayoutProfile.alignedSplit
        let split = try XCTUnwrap(profile.splitGeometry)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "對齊分離必須提供每側六格及標點欄")
        assertSplitKeyboardGeometry()
        for index in split.punctuation.indices {
            let punctuation = app.buttons["keyboard.split.punctuation.\(index)"]
            XCTAssertTrue(punctuation.isHittable)
            XCTAssertEqual(punctuation.label, split.punctuation[index])
            punctuation.tap()
        }
        let prefix = split.punctuation.joined()
        XCTAssertEqual(output.value as? String, prefix)
        let visibleReadingCount = split.compositionSplit + 1
        for _ in 0..<visibleReadingCount { for key in "su3" { app.buttons[String(key)].tap() } }
        XCTAssertTrue(waitForLayout { output.value as? String == prefix + String(repeating: "你", count: visibleReadingCount) })
        let sixth = app.buttons["keyboard.smart-cell.\(split.compositionSplit)"]
        let seventh = app.buttons["keyboard.smart-cell.\(split.compositionSplit + 1)"]
        XCTAssertTrue(sixth.isHittable)
        XCTAssertTrue(seventh.isHittable)
        XCTAssertEqual(sixth.frame.maxX, app.buttons["keyboard.split.punctuation.0"].frame.maxX, accuracy: 1)
        XCTAssertEqual(seventh.frame.minX, app.buttons["6"].frame.minX, accuracy: 1)
        XCTAssertFalse(app.buttons["keyboard.smart-cell.\(profile.compositionCellCount + 1)"].exists)
        let hide = app.buttons["keyboard.dismiss"]
        XCTAssertEqual(hide.frame.width, app.buttons["1"].frame.width, accuracy: 1)
        var expected = prefix + String(repeating: "你", count: visibleReadingCount)
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
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.alignedSplit)
        let split = try XCTUnwrap(KeyboardLayoutProfile.alignedSplit.splitGeometry)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "對齊分離必須提供每側六格及標點欄")
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
        let candidates = (1...KeyboardInput.candidatesPerPage).map { index in
            self.app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "第 \(index) 個候選，")).firstMatch
        }
        let controls = [app.buttons["上一頁"]] + candidates + [app.buttons["下一頁"], close]
        XCTAssertEqual(controls.count, KeyboardInput.candidatesPerPage + 3)
        for control in controls {
            XCTAssertTrue(control.exists)
            XCTAssertEqual(control.frame.width, controls[0].frame.width, accuracy: 1)
            XCTAssertEqual(control.frame.minY, controls[0].frame.minY, accuracy: 1)
        }
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(controls[0].frame.minX, numberLeft.minX, accuracy: 1)
        XCTAssertEqual(controls[split.candidateSplit - 1].frame.maxX, leftBoundary, accuracy: 1)
        XCTAssertEqual(controls[split.candidateSplit].frame.minX, rightBoundary, accuracy: 1)
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
        selectLayoutProfile(.aligned)
        XCTAssertFalse(close.isHittable)
        XCTAssertTrue(first.isHittable)
        XCTAssertEqual(first.label, candidateBeforeProfileSwitch)
        selectLayoutProfile(.alignedSplit)
        XCTAssertTrue(close.isHittable)
        XCTAssertEqual(first.label, candidateBeforeProfileSwitch)
        close.tap()
        XCTAssertEqual(output.value as? String, "你好你")
        selectLayoutProfile(.aligned)
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
        selectLayoutProfile(.alignedSplit)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "對齊分離必須提供每側六格及標點欄")
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
        selectLayoutProfile(.aligned)
    }

    private func selectLayoutProfile(_ profile: KeyboardLayoutProfile) {
        selectLayoutOptions(layout: profile)
    }

    private func assertSplitKeyboardGeometry(orientation: KeyboardLayoutProfile.Orientation = .portrait) {
        let profile = KeyboardLayoutProfile.alignedSplit
        let geometry = profile.splitGeometry!
        assertProfileKeysReachable(profile, orientation: orientation)
        let keys = profile.rows(orientation: orientation, plane: .bopomofo, shifted: false)[0]
        let left = app.buttons["keyboard.split.punctuation.0"].frame
        let right = app.buttons[keys[geometry.keySplit - 1]].frame
        XCTAssertGreaterThan(right.minX, left.maxX, "分離樣式必須保留中央空隙")
        let lastLeft = app.buttons["SPACE"]
        let firstRight = app.buttons["keyboard.space.right"]
        XCTAssertTrue(firstRight.isHittable)
        XCTAssertTrue(app.buttons["keyboard.dismiss"].isHittable)
        XCTAssertEqual(app.buttons[keys[0]].frame.width, right.width, accuracy: 1)
        let mode = app.buttons["MODE"].frame
        XCTAssertEqual(app.buttons["SYMBOL"].frame.width / mode.width,
            profile.functionWeight(for: "SYMBOL") / profile.functionWeight(for: "MODE"), accuracy: 0.03)
        XCTAssertEqual(lastLeft.frame.width / mode.width,
            profile.functionWeight(for: "SPACE") / profile.functionWeight(for: "MODE"), accuracy: 0.03)
        XCTAssertEqual(lastLeft.frame.maxX, left.maxX, accuracy: 1)
        XCTAssertEqual(firstRight.frame.minX, right.minX, accuracy: 1)
        let punctuation = geometry.punctuation.indices.map { "keyboard.split.punctuation.\($0)" }
        let identifiers = Set(profile.rows(orientation: orientation, plane: .bopomofo, shifted: false).flatMap { $0 }
            + profile.functionKeys + punctuation)
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
        selectLayoutProfile(.aligned)
        let portraitFrame = app.frame
        assertProfileKeysReachable(.aligned)
        XCUIDevice.shared.orientation = .landscapeLeft
        assertAppRotation(.landscapeLeft, relativeToPortrait: portraitFrame)
        assertProfileKeysReachable(.aligned, orientation: .landscape)
        XCUIDevice.shared.orientation = .portrait
        assertAppRotation(.portrait, relativeToPortrait: portraitFrame)
        assertProfileKeysReachable(.aligned)
    }

    func testLayoutOptionsKeepReadingAndCandidates() throws {
        XCUIDevice.shared.orientation = .portrait
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode(ChineseInputMethod.smart.displayName)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        closeKeyboardSettings()
        selectLayoutOptions(layout: .standard, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)

        let emptyValue = output.value as? String
        let initialHeight = profileKeyBounds(.standard, orientation: .portrait, plane: .bopomofo).height
        app.buttons["s"].tap()
        selectLayoutOptions(layout: .alignedSplit, spacing: .large, fontSize: .medium,
                            deletePosition: .leftOfEnter)
        assertProfileKeysReachable(.alignedSplit)
        XCTAssertEqual(profileKeyBounds(.alignedSplit, orientation: .portrait, plane: .bopomofo).height,
                       initialHeight, accuracy: 1)
        XCTAssertEqual(output.value as? String, emptyValue,
                       "變更版面、間隔、字體與刪除位置不可把未完成注音送進輸入框")
        selectLayoutOptions(fontSize: .extraLarge)
        XCTAssertEqual(profileKeyBounds(.alignedSplit, orientation: .portrait, plane: .bopomofo).height,
                       initialHeight, accuracy: 1)
        XCTAssertEqual(output.value as? String, emptyValue,
                       "改為特大字體不可確認或取消未完成注音")
        for key in "u3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你" },
                      "變更外觀後，未完成音節仍應接得上")

        app.buttons["keyboard.smart-cell.1"].tap()
        let first = app.buttons.matching(NSPredicate(
            format: "label BEGINSWITH %@", "第 1 個候選，"
        )).firstMatch
        XCTAssertTrue(first.waitForExistence(timeout: 3))
        let candidateLabel = first.label
        selectLayoutOptions(layout: .aligned, spacing: .medium,
                            deletePosition: .aboveEnter)
        let candidateBounds = profileKeyBounds(.aligned, orientation: .portrait, plane: .bopomofo)
        for font in KeyboardKeyFontSize.allCases {
            selectLayoutOptions(fontSize: font)
            XCTAssertTrue(first.waitForExistence(timeout: 3))
            XCTAssertEqual(first.label, candidateLabel, "字體不可改變候選目標：\(font.displayName)")
            XCTAssertEqual(output.value as? String, "你", "字體切換不可額外送字：\(font.displayName)")
            let bounds = profileKeyBounds(.aligned, orientation: .portrait, plane: .bopomofo)
            XCTAssertEqual(bounds.minY, candidateBounds.minY, accuracy: 1, font.displayName)
            XCTAssertEqual(bounds.height, candidateBounds.height, accuracy: 1, font.displayName)
            // Visual QA evidence only: no golden image or duplicate text-fitting algorithm.
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "candidate-and-composition-font-\(font.rawValue)"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        first.tap()
        XCTAssertEqual(output.value as? String, "你")
        selectLayoutOptions(layout: .standard, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)
    }

    func testFourFontLevelsClearCompositionAndCandidatesAtCurrentPose() throws {
        // Run again after an external pose change. This intentionally does not
        // claim preservation of a composition across rotation in the same session.
        launchHostApp(geometryProbe: true)
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode(ChineseInputMethod.smart.displayName)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"]
            .buttons[BopomofoKeyboardLayout.standard.displayName].tap()
        closeKeyboardSettings()
        let profile = KeyboardLayoutProfile.aligned
        selectLayoutOptions(layout: profile, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)
        let orientation = try currentPoseOrientation()
        let emptyValue = output.value as? String
        let composition = app.buttons["keyboard.smart-cell.1"]
        let editableCells = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "個組字，"))
        let candidatePrefix = "第 1 個候選，"
        let first = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", candidatePrefix)).firstMatch
        attachSimulatorGeometry(name: "strip-clearing-current-pose-before")

        for font in KeyboardKeyFontSize.allCases {
            selectLayoutOptions(fontSize: font)
            assertProfileKeysReachable(profile, orientation: orientation)
            for key in "su3" { app.buttons[String(key)].tap() }
            XCTAssertTrue(composition.waitForExistence(timeout: 3))
            let completed = output.value as? String
            XCTAssertNotEqual(completed, emptyValue, "必須先有完成組字，才能驗證刪除")
            composition.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 3))
            let candidateLabel = first.label
            attachStripClearingQA(font: font, stage: "candidates-visible")

            let close = app.buttons["keyboard.candidates.close"]
            if close.isHittable { close.tap() } else { composition.tap() }
            XCTAssertTrue(waitForLayout { !first.exists })
            XCTAssertEqual(output.value as? String, completed, "關閉候選不可確認或清空組字")
            composition.tap()
            XCTAssertTrue(first.waitForExistence(timeout: 3))
            XCTAssertEqual(first.label, candidateLabel, "重開候選不可改變目標或排序")
            let selectedText = String(candidateLabel.dropFirst(candidatePrefix.count))
            XCTAssertFalse(selectedText.isEmpty)
            first.tap()
            XCTAssertTrue(waitForLayout { output.value as? String == selectedText },
                          "選字須使用實際候選內容，不固定第一候選的文字")
            XCTAssertTrue(waitForLayout { !first.exists })
            let editableCount = editableCells.count
            XCTAssertGreaterThan(editableCount, 0)
            for _ in 0..<editableCount { app.buttons["BACKSPACE"].tap() }
            XCTAssertTrue(waitForLayout {
                output.value as? String == emptyValue && editableCells.count == 0 && !first.exists
            }, "刪除完成組字後，輸入框、可編輯組字與候選皆須清空")
            attachStripClearingQA(font: font, stage: "completed-cleared")

            app.buttons["s"].tap()
            XCTAssertEqual(output.value as? String, emptyValue, "未完成注音不可直接送進輸入框")
            attachStripClearingQA(font: font, stage: "pending-reading")
            app.buttons["BACKSPACE"].tap()
            XCTAssertTrue(waitForLayout {
                output.value as? String == emptyValue && editableCells.count == 0 && !first.exists
            }, "刪除未完成注音後，不可留下可提交內容")
            attachStripClearingQA(font: font, stage: "pending-cleared")
            app.buttons["SPACE"].tap()
            XCTAssertTrue(waitForLayout { output.value as? String == " " }, "無組字時空白鍵應直接送空白，不能仍處理殘留讀音")
            app.buttons["BACKSPACE"].tap()
            XCTAssertTrue(waitForLayout { output.value as? String == emptyValue })
        }
        selectLayoutOptions(fontSize: .normal)
        attachSimulatorGeometry(name: "strip-clearing-current-pose-after")
    }

    private func attachStripClearingQA(font: KeyboardKeyFontSize, stage: String) {
        // AX emptiness verifies the input contract, not stale native UILabel
        // pixels. The native UIKit renderer regression owns that visual gate.
        // Preserve every display for manual QA; a black capture is not visual proof.
        for (index, screen) in XCUIScreen.screens.enumerated() {
            let attachment = XCTAttachment(screenshot: screen.screenshot())
            attachment.name = "strip-clearing-\(font.rawValue)-\(stage)-screen-\(index)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }

    // Explicit manual device matrix; excluded from the default functional plan.
    func testTypographyMatrixPortrait() throws {
        try measureTypographyMatrix(direction: .portrait, orientation: .portrait)
    }

    func testTypographyMatrixLandscape() throws {
        try measureTypographyMatrix(direction: .landscapeLeft, orientation: .landscape)
    }

    private func measureTypographyMatrix(direction: UIDeviceOrientation,
                                         orientation: KeyboardLayoutProfile.Orientation) throws {
        XCUIDevice.shared.orientation = .portrait
        app = XCUIApplication()
        let request = UUID().uuidString + ":\(orientation)"
        app.launchArguments = ["-KeyKeyInputFieldTest", "-KeyKeyTypographyMeasurement", request]
        app.launch()
        XCTAssertTrue(app.navigationBars["輸入欄位測試"].waitForExistence(timeout: 8))
        let portraitFrame = app.frame
        XCUIDevice.shared.orientation = direction
        assertAppRotation(direction, relativeToPortrait: portraitFrame)
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        let measurement = app.staticTexts["keyboard.typography-measurement"]
        XCTAssertTrue(measurement.waitForExistence(timeout: 8),
            "此手動矩陣須以 -D KEYKEY_TYPOGRAPHY_MEASUREMENT 建置 App 與 extension")
        XCTAssertTrue(waitForLayout(timeout: 180) {
            (measurement.value as? String)?.hasPrefix("{") == true
        })
        let json = try XCTUnwrap(measurement.value as? String)
        let data = Data(json.utf8)
        let report = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let attachment = XCTAttachment(data: data, uniformTypeIdentifier: "public.json")
        attachment.name = "typography-matrix-\(orientation)-432-cases"
        attachment.lifetime = .keepAlways
        add(attachment)
        XCTAssertEqual(report["request"] as? String, request)
        XCTAssertEqual(report["caseCount"] as? Int, 432)
        XCTAssertEqual(report["failures"] as? [String], [])
        print("TYPOGRAPHY_MATRIX_COMPLETED \(orientation) \(report["caseCount"] ?? 0) cases")
        try selectKeyboardPlane(.bopomofo)
        captureTypographyLevels(orientation: orientation)
        XCUIDevice.shared.orientation = .portrait
    }

    func testTypographyLandscapeScreenCaptures() throws {
        XCUIDevice.shared.orientation = .portrait
        launchHostApp()
        let portrait = app.frame
        XCUIDevice.shared.orientation = .landscapeLeft
        assertAppRotation(.landscapeLeft, relativeToPortrait: portrait)
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectKeyboardPlane(.bopomofo)
        captureTypographyLevels(orientation: .landscape)
        XCUIDevice.shared.orientation = .portrait
    }

    private func captureTypographyLevels(orientation: KeyboardLayoutProfile.Orientation) {
        for profile in KeyboardLayoutProfile.available {
            for font in KeyboardKeyFontSize.allCases {
                selectLayoutOptions(layout: font == .normal ? profile : nil,
                    spacing: font == .normal ? .small : nil, fontSize: font,
                    deletePosition: font == .normal ? .aboveEnter : nil)
                // App.screenshot can apply the landscape transform twice on a
                // physical iPhone. Preserve the screen's native capture instead.
                let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
                screenshot.name = "typography-\(orientation)-\(profile.id)-\(font.rawValue)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
        }
    }

    func testRepresentativeLayoutOptionsKeepKeysReachableWhenRotating() throws {
        XCUIDevice.shared.orientation = .portrait
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode(ChineseInputMethod.smart.displayName)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        closeKeyboardSettings()
        let originalValue = output.value as? String
        let portraitFrame = app.frame
        // FE smoke samples cover both axes and all five planes. The engine unit
        // suite owns the complete independent-options geometry matrix.
        let samples: [(KeyboardLayoutProfile, UIDeviceOrientation,
                       KeyboardLayoutProfile.Orientation, KeyboardLayoutProfile.Plane,
                       KeyboardKeycapArea, KeyboardKeyFontSize, KeyboardDeleteShiftPosition)] = [
            (.standard, .portrait, .portrait, .cangjie, .small, .medium, .aboveEnter),
            (.aligned, .portrait, .portrait, .bopomofo, .medium, .normal, .leftOfEnter),
            (.alignedSplit, .portrait, .portrait, .english, .large, .large, .aboveEnter),
            (.standard, .landscapeLeft, .landscape, .simplex, .large, .extraLarge, .leftOfEnter),
            (.aligned, .landscapeLeft, .landscape, .numberSymbols, .small, .medium, .aboveEnter),
            (.aligned, .landscapeLeft, .landscape, .bopomofo, .medium, .medium, .leftOfEnter)
        ]
        var baselines: [(KeyboardLayoutProfile.Orientation, CGRect)] = []
        for (layout, direction, orientation, plane, spacing, font, delete) in samples {
            XCUIDevice.shared.orientation = direction
            assertAppRotation(direction, relativeToPortrait: portraitFrame)
            try selectKeyboardPlane(plane)
            selectLayoutOptions(layout: layout, spacing: spacing, fontSize: font,
                                deletePosition: delete)
            assertProfileKeysReachable(layout, orientation: orientation, plane: plane)
            if orientation == .landscape && plane == .bopomofo {
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "compact-bopomofo-font-\(font.rawValue)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
            }
            if layout == .standard && (plane == .cangjie || plane == .simplex) {
                let heavy = app.buttons["z"]
                let secondColumn = app.buttons["2"]
                XCTAssertEqual(heavy.label, "重")
                XCTAssertEqual(heavy.frame.minX, secondColumn.frame.minX, accuracy: 1,
                               "倉頡與簡易標準版面的重須位於原難的欄位")
                XCTAssertEqual(heavy.frame.width, secondColumn.frame.width, accuracy: 1)
                XCTAssertFalse(app.buttons["/"].exists, "僅此版面的字根底列移除斜線鍵")
            }
            let bounds = profileKeyBounds(layout, orientation: orientation, plane: plane)
            if let baseline = baselines.first(where: { $0.0 == orientation })?.1 {
                XCTAssertEqual(bounds.minY, baseline.minY, accuracy: 1, layout.displayName)
                XCTAssertEqual(bounds.height, baseline.height, accuracy: 1, layout.displayName)
            } else {
                baselines.append((orientation, bounds))
            }
            XCTAssertEqual(output.value as? String, originalValue,
                           "切換方向、擺法或外觀選項不能自行送字")
        }
        XCUIDevice.shared.orientation = .portrait
        assertAppRotation(.portrait, relativeToPortrait: portraitFrame)
        try selectKeyboardPlane(.bopomofo)
        selectLayoutOptions(layout: .standard, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)
    }

    func testLayoutOptionsFollowCandidateColorAndPersistIndependently() throws {
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        let appScroll = app.scrollViews.containing(.segmentedControl,
                                                  identifier: "app-settings.candidate-color").firstMatch
        assertLayoutOptionsFollowCandidateColor(prefix: "app-settings.",
            color: app.segmentedControls["app-settings.candidate-color"], scroll: appScroll)
        assertFontSizeChoices(prefix: "app-settings.", scroll: appScroll)
        selectAppearanceOptions(prefix: "app-settings.", scroll: appScroll,
                                layout: .aligned, spacing: .large, fontSize: .normal,
                                deletePosition: .leftOfEnter)
        for font in KeyboardKeyFontSize.allCases {
            selectAppearanceOptions(prefix: "app-settings.", scroll: appScroll, fontSize: font)
            assertAppearanceOptions(prefix: "app-settings.", layout: .aligned,
                                    spacing: .large, fontSize: font, deletePosition: .leftOfEnter)
        }
        selectAppearanceOptions(prefix: "app-settings.", scroll: appScroll, fontSize: .extraLarge)
        // Selecting a different layout must not replace the other three preferences.
        for layout in KeyboardLayoutProfile.available {
            selectAppearanceOptions(prefix: "app-settings.", scroll: appScroll, layout: layout)
            assertAppearanceOptions(prefix: "app-settings.", layout: layout,
                                    spacing: .large, fontSize: .extraLarge, deletePosition: .leftOfEnter)
        }
        selectAppearanceOptions(prefix: "app-settings.", scroll: appScroll, layout: .standard)

        app.terminate()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        assertAppearanceOptions(prefix: "app-settings.", layout: .standard,
                                spacing: .large, fontSize: .extraLarge, deletePosition: .leftOfEnter)

        // Verify the App's publication reaches the extension, and that both
        // settings entrances put the same four independent controls in order.
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        app.buttons["SETTINGS"].tap()
        let keyboardScroll = app.scrollViews["keyboard-settings.scroll"]
        assertLayoutOptionsFollowCandidateColor(prefix: "keyboard.",
            color: app.segmentedControls["candidate-color"], scroll: keyboardScroll)
        assertFontSizeChoices(prefix: "keyboard.", scroll: keyboardScroll)
        assertAppearanceOptions(prefix: "keyboard.", layout: .standard,
                                spacing: .large, fontSize: .extraLarge, deletePosition: .leftOfEnter)
        selectAppearanceOptions(prefix: "keyboard.", scroll: keyboardScroll, spacing: .medium)
        assertAppearanceOptions(prefix: "keyboard.", layout: .standard,
                                spacing: .medium, fontSize: .extraLarge, deletePosition: .leftOfEnter)
        selectAppearanceOptions(prefix: "keyboard.", scroll: keyboardScroll, fontSize: .medium)
        assertAppearanceOptions(prefix: "keyboard.", layout: .standard,
                                spacing: .medium, fontSize: .medium, deletePosition: .leftOfEnter)
        selectAppearanceOptions(prefix: "keyboard.", scroll: keyboardScroll, layout: .alignedSplit)
        assertAppearanceOptions(prefix: "keyboard.", layout: .alignedSplit,
                                spacing: .medium, fontSize: .medium, deletePosition: .leftOfEnter)
        for placement in KeyboardDeleteShiftPosition.allCases {
            selectAppearanceOptions(prefix: "keyboard.", scroll: keyboardScroll, deletePosition: placement)
            closeKeyboardSettings()
            let delete = app.buttons["BACKSPACE"].frame
            let enter = app.buttons["ENTER"].frame
            if placement == .aboveEnter {
                XCTAssertLessThanOrEqual(delete.maxY, enter.minY + 1)
            } else {
                XCTAssertEqual(delete.midY, enter.midY, accuracy: 1)
                XCTAssertLessThanOrEqual(delete.maxX, enter.minX + 1)
            }
            app.buttons["SETTINGS"].tap()
        }
        selectAppearanceOptions(prefix: "keyboard.", scroll: keyboardScroll,
                                layout: .standard, spacing: .small, fontSize: .normal,
                                deletePosition: .aboveEnter)
        closeKeyboardSettings()

        // Restore the App's own publication as well as the extension's private values.
        app.terminate()
        app = XCUIApplication()
        app.launch()
        app.buttons["open-input-method-settings"].tap()
        let restoreScroll = app.scrollViews.containing(.segmentedControl,
                                                      identifier: "app-settings.candidate-color").firstMatch
        selectAppearanceOptions(prefix: "app-settings.", scroll: restoreScroll,
                                layout: .standard, spacing: .small, fontSize: .normal,
                                deletePosition: .aboveEnter)
    }

    func testWideSplitDismissAndReopenWithoutReplayingReading() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        let output = field("default")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        try selectCompositionMode(ChineseInputMethod.smart.displayName)
        app.buttons["SETTINGS"].tap()
        app.segmentedControls["bopomofo-keyboard-layout"].buttons["標準"].tap()
        closeKeyboardSettings()
        selectLayoutOptions(layout: .alignedSplit, spacing: .small, fontSize: .normal,
                            deletePosition: .aboveEnter)
        XCTAssertTrue(app.buttons["keyboard.split.punctuation.0"].waitForExistence(timeout: 3),
                      "對齊分離必須提供每側六格及標點欄")
        func assertTopDismiss() {
            let hide = app.buttons["keyboard.dismiss"]
            XCTAssertTrue(hide.waitForExistence(timeout: 3))
            XCTAssertTrue(hide.isHittable)
            XCTAssertTrue(hide.isEnabled)
            XCTAssertLessThanOrEqual(hide.frame.maxY, app.buttons["q"].frame.minY + 1)
        }
        assertTopDismiss()
        for key in "su3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你" })
        app.buttons["c"].tap() // Keep an unfinished ㄏ after the completed character.
        app.buttons["keyboard.dismiss"].tap()
        XCTAssertTrue(waitForLayout(timeout: 5) { !self.app.buttons["SETTINGS"].exists })
        XCTAssertEqual(output.value as? String, "你", "收鍵盤只確認完成文字，未完成注音須取消")
        tapInputField(output)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        assertTopDismiss()
        XCTAssertEqual(output.value as? String, "你")
        for key in "cl3" { app.buttons[String(key)].tap() }
        XCTAssertTrue(waitForLayout { output.value as? String == "你好" },
                      "重新開啟不可重播已確認文字或先前未完成注音")
        // The existing top control also remains available in restricted fields.
        XCTAssertTrue(revealField("email"))
        let email = field("email")
        tapInputField(email)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        XCTAssertTrue(waitForStableKeyboardFrames(identifiers: ["keyboard.dismiss", "ENTER"]))
        assertTopDismiss()
        app.buttons["keyboard.dismiss"].tap()
        XCTAssertTrue(waitForLayout(timeout: 5) { !self.app.buttons["SETTINGS"].exists })
        tapInputField(email)
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        assertTopDismiss()
        selectLayoutOptions(layout: .standard)
        XCTAssertFalse(app.buttons["keyboard.dismiss"].exists)
    }

    func testSettingsLongPressDoesNotOpenLayoutMenu() throws {
        launchHostApp()
        XCTAssertTrue(revealField("default"))
        tapInputField(field("default"))
        XCTAssertTrue(selectKeyKeyKeyboard(), keyboardActivationFailureMessage)
        app.buttons["SETTINGS"].press(forDuration: 1)
        for layout in KeyboardLayoutProfile.available {
            let menu = app.collectionViews.containing(.button, identifier: layout.displayName).firstMatch
            XCTAssertFalse(menu.waitForExistence(timeout: 1), "長按設不可開啟版面選單")
        }
        // A normal button release may open Settings; this remains an allowed action.
        if app.scrollViews["keyboard-settings.scroll"].exists { closeKeyboardSettings() }
        XCTAssertTrue(app.buttons["SETTINGS"].isHittable)
        XCTAssertEqual(app.state, .runningForeground)
    }

    private func assertLayoutOptionsFollowCandidateColor(prefix: String, color: XCUIElement,
                                                         scroll: XCUIElement) {
        revealSetting(color, in: scroll)
        // Segmented controls are stable AX elements; do not enumerate transient
        // scroll indicators or compare the clipped frames of offscreen rows.
        let identifiers = scroll.descendants(matching: .segmentedControl)
            .allElementsBoundByIndex.map(\.identifier)
        let expected = [color.identifier] + [
            "layout-profile", "keycap-area", "key-font-size", "delete-position"
        ].map { prefix + $0 }
        guard let colorIndex = identifiers.firstIndex(of: color.identifier) else {
            XCTFail("設定頁找不到候選字底色")
            return
        }
        XCTAssertEqual(Array(identifiers.dropFirst(colorIndex).prefix(expected.count)), expected,
                       "四個獨立外觀設定須緊接候選字底色，且順序一致")
    }

    private func assertFontSizeChoices(prefix: String, scroll: XCUIElement) {
        let control = app.segmentedControls[prefix + "key-font-size"]
        revealSetting(control, in: scroll)
        XCTAssertEqual(control.buttons.count, KeyboardKeyFontSize.allCases.count)
        for font in KeyboardKeyFontSize.allCases {
            XCTAssertTrue(control.buttons[font.displayName].exists, "找不到字體選項：\(font.displayName)")
        }
    }

    private func selectAppearanceOptions(prefix: String, scroll: XCUIElement,
                                         layout: KeyboardLayoutProfile? = nil,
                                         spacing: KeyboardKeycapArea? = nil,
                                         fontSize: KeyboardKeyFontSize? = nil,
                                         deletePosition: KeyboardDeleteShiftPosition? = nil) {
        let selections: [(String, String?)] = [
            ("layout-profile", layout?.displayName),
            ("keycap-area", spacing?.displayName),
            ("key-font-size", fontSize?.displayName),
            ("delete-position", deletePosition?.displayName)
        ]
        for (name, title) in selections {
            guard let title else { continue }
            let control = app.segmentedControls[prefix + name]
            revealSetting(control, in: scroll)
            let option = control.buttons[title]
            XCTAssertTrue(option.exists, "找不到外觀選項：\(title)")
            if !option.isSelected { option.tap() }
            XCTAssertTrue(option.isSelected, title)
        }
    }

    private func assertAppearanceOptions(prefix: String, layout: KeyboardLayoutProfile,
                                         spacing: KeyboardKeycapArea, fontSize: KeyboardKeyFontSize,
                                         deletePosition: KeyboardDeleteShiftPosition) {
        let expected = [
            ("layout-profile", layout.displayName),
            ("keycap-area", spacing.displayName),
            ("key-font-size", fontSize.displayName),
            ("delete-position", deletePosition.displayName)
        ]
        for (name, title) in expected {
            XCTAssertTrue(app.segmentedControls[prefix + name].buttons[title].isSelected,
                          "外觀選項未獨立保留：\(name)=\(title)")
        }
    }

    private func selectLayoutOptions(layout: KeyboardLayoutProfile? = nil,
                                      spacing: KeyboardKeycapArea? = nil,
                                      fontSize: KeyboardKeyFontSize? = nil,
                                      deletePosition: KeyboardDeleteShiftPosition? = nil) {
        app.buttons["SETTINGS"].tap()
        selectAppearanceOptions(prefix: "keyboard.", scroll: app.scrollViews["keyboard-settings.scroll"],
                                layout: layout, spacing: spacing, fontSize: fontSize,
                                deletePosition: deletePosition)
        closeKeyboardSettings()
    }

    private func closeKeyboardSettings() {
        let close = app.windows.containing(.scrollView, identifier: "keyboard-settings.scroll")
            .firstMatch.buttons["完成"]
        XCTAssertTrue(close.waitForExistence(timeout: 3))
        close.tap()
        XCTAssertTrue(app.buttons["SETTINGS"].waitForExistence(timeout: 3))
    }

    private func selectKeyboardPlane(_ plane: KeyboardLayoutProfile.Plane) throws {
        let mode: KeyboardInput.InputMode
        switch plane {
        case .bopomofo:
            try selectCompositionMode(ChineseInputMethod.smart.displayName)
            mode = .bopomofo
        case .cangjie:
            try selectCompositionMode(ChineseInputMethod.cangjie.displayName)
            mode = .bopomofo
        case .simplex:
            try selectCompositionMode(ChineseInputMethod.simplex.displayName)
            mode = .bopomofo
        case .english: mode = .english
        case .numberSymbols: mode = .number
        }
        for _ in 0...KeyboardInput.InputMode.allCases.count {
            let q = app.buttons["q"]
            let matches: Bool
            switch mode {
            case .bopomofo: matches = q.exists && q.label != "q"
            case .english: matches = q.exists && q.label == "q"
            case .number: matches = app.buttons["!"].exists && app.buttons["+"].exists
            }
            if matches { return }
            app.buttons["MODE"].tap()
        }
        XCTFail("無法切換到擺法：\(plane)")
    }

    private func profileKeyBounds(_ profile: KeyboardLayoutProfile,
                                  orientation: KeyboardLayoutProfile.Orientation,
                                  plane: KeyboardLayoutProfile.Plane) -> CGRect {
        let representatives = profile.rows(orientation: orientation, plane: plane, shifted: false)
            .compactMap(\.first)
        return Set(representatives + ["MODE", "SPACE", "BACKSPACE", "ENTER"])
            .reduce(CGRect.null) { $0.union(app.buttons[$1].frame) }
    }

    private func revealSetting(_ element: XCUIElement, in scroll: XCUIElement) {
        XCTAssertTrue(element.waitForExistence(timeout: 3), element.debugDescription)
        XCTAssertTrue(scroll.exists)
        for _ in 0..<20 {
            if element.isHittable { return }
            let velocity = XCUIGestureVelocity(rawValue: 100)
            if element.frame.midY < scroll.frame.midY {
                scroll.swipeDown(velocity: velocity)
            } else {
                scroll.swipeUp(velocity: velocity)
            }
        }
        XCTAssertTrue(element.isHittable, element.debugDescription)
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
                                            orientation: KeyboardLayoutProfile.Orientation = .portrait,
                                            plane: KeyboardLayoutProfile.Plane = .bopomofo) {
        let rows = profile.rows(orientation: orientation, plane: plane, shifted: false)
        let firstRow = rows.first ?? []
        let anchors = [firstRow.first, firstRow.last].compactMap { $0 } + ["ENTER"]
        let framesStable = waitForStableKeyboardFrames(identifiers: anchors)
        if !framesStable {
            var evidence = ["app.frame=\(app.frame)"]
            for identifier in Set(anchors).sorted() {
                let key = app.buttons[identifier]
                let exists = key.exists
                let frame = exists ? String(describing: key.frame) : "unavailable"
                evidence.append("\(identifier): exists=\(exists), frame=\(frame)")
            }
            for identifier in ["app.geometry", "extension.geometry"] {
                let probe = app.staticTexts[identifier]
                if probe.exists {
                    evidence.append("\(identifier)=\(probe.value ?? "nil")")
                }
            }
            let attachment = XCTAttachment(string: evidence.joined(separator: "\n"))
            attachment.name = "Keyboard geometry did not stabilize - \(profile.id)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        XCTAssertTrue(framesStable,
                      "鍵盤按鍵幾何尚未穩定：\(profile.displayName)")
        let representatives = rows.compactMap { $0.first }
        // These four actions are input affordances, not a fixed visual grid.
        for identifier in Set(representatives + ["MODE", "SPACE", "BACKSPACE", "ENTER"]).sorted() {
            XCTAssertTrue(app.buttons[identifier].exists, "方向切換後找不到按鍵：\(identifier)")
            XCTAssertTrue(app.buttons[identifier].isHittable, "方向切換後按鍵不可點：\(identifier)")
        }
    }

    private func waitForStableKeyboardFrames(identifiers: [String]) -> Bool {
        var previousFrames: [CGRect]?
        return waitForLayout(timeout: 5) {
            let appFrame = self.app.frame
            var frames = [appFrame]
            // Across windows/displays, App AX and keyboard frames may use different
            // coordinate spaces, so the App frame cannot establish containment.
            for identifier in Set(identifiers).sorted() {
                let key = self.app.buttons[identifier]
                guard key.exists else {
                    previousFrames = nil
                    return false
                }
                let frame = key.frame
                guard [frame.minX, frame.minY, frame.width, frame.height].allSatisfy(\.isFinite),
                      !frame.isEmpty else {
                    previousFrames = nil
                    return false
                }
                frames.append(frame)
            }
            // The App can finish rotating before the keyboard's AX coordinates do.
            // Require two valid, stable snapshots before hit testing.
            let stable = previousFrames.map { previous in
                zip(previous, frames).allSatisfy { old, new in
                    abs(old.minX - new.minX) <= 1 && abs(old.minY - new.minY) <= 1
                        && abs(old.width - new.width) <= 1 && abs(old.height - new.height) <= 1
                }
            } ?? false
            previousFrames = frames
            return stable
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
        // Smart mode hides the empty candidate/status row. The settings key
        // identifies the extension in either composition mode and layout.
        let status = app.buttons["SETTINGS"]
        if status.exists { return true }
        dismissSystemKeyboardTip()
        if status.waitForExistence(timeout: 8) { return true }

        if let globe = nextKeyboardButton(), globe.identifier != KeyboardLayout.inputModeSwitchKey {
            let nextName = globe.value as? String ?? ""
            if nextName.contains("琦琦輸入法") || nextName.localizedCaseInsensitiveContains("KeyKey") {
                // Native keyboards can name the next input method without exposing a picker.
                if status.exists { return true }
                globe.tap()
                dismissSystemKeyboardTip()
                if status.waitForExistence(timeout: 5) { return true }
            } else {
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

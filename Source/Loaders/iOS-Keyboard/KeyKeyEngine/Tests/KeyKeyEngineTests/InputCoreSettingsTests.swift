import Foundation
import Testing

@testable import KeyKeyEngine

@Suite("Input core settings")
struct InputCoreSettingsTests {
    @Test("unknown or absent backend preferences preserve the Swift fallback")
    func unknownPreference() {
        let name = "keykey.core-settings.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let settings = InputCoreSettings(defaults: defaults)
        #expect(settings.core == .swift)
        defaults.set("future-backend", forKey: InputCoreSettings.key)
        #expect(settings.core == .swift)
    }

    @Test("App core revisions reach each surface without unrelated changes erasing private choices")
    func sharedCoreRevision() {
        let names = (0..<3).map { _ in "keykey.core-revisions.\(UUID().uuidString)" }
        let stores = names.map { UserDefaults(suiteName: $0)! }
        defer { for (name, store) in zip(names, stores) { store.removePersistentDomain(forName: name) } }
        let app = InputCoreSettings(defaults: stores[0], sharedDefaults: stores[2], writesShared: true)
        let keyboard = InputCoreSettings(defaults: stores[0], sharedDefaults: stores[2])
        let editor = InputCoreSettings(defaults: stores[1], sharedDefaults: stores[2])
        app.setCore(.guanyinma)
        #expect(keyboard.core == .guanyinma)
        #expect(editor.core == .guanyinma)
        keyboard.setCore(.swift)
        ChineseInputMethodSettings(sharedDefaults: stores[2], writesShared: true).setMethod(.cangjie)
        #expect(keyboard.core == .swift)
        #expect(editor.core == .guanyinma)
        app.setCore(.guanyinma)
        #expect(keyboard.core == .guanyinma)
        #expect(InputCoreSettings(defaults: stores[1], sharedDefaults: stores[2]).core == .guanyinma)
    }

    @Test("learning resets are independent, once-only, and retried after storage failure")
    func independentLearningResets() {
        let names = (0..<2).map { _ in "keykey.core-reset.\(UUID().uuidString)" }
        let stores = names.map { UserDefaults(suiteName: $0)! }
        defer { for (name, store) in zip(names, stores) { store.removePersistentDomain(forName: name) } }
        let swift = KeyboardLearningResetRequest(localDefaults: stores[0], sharedDefaults: stores[1])
        let rust = KeyboardLearningResetRequest(core: .guanyinma, localDefaults: stores[0], sharedDefaults: stores[1])
        var swiftCalls = 0
        var rustCalls = 0
        swift.request()
        #expect(stores[1].string(forKey: "smartMandarinLearningResetRequest") != nil)
        #expect(!rust.applyIfNeeded { rustCalls += 1 })
        rust.request()
        #expect(!rust.applyIfNeeded { throw CocoaError(.fileWriteNoPermission) })
        #expect(rust.applyIfNeeded { rustCalls += 1 })
        #expect(!rust.applyIfNeeded { rustCalls += 1 })
        #expect(swift.applyIfNeeded { swiftCalls += 1 })
        #expect(!swift.applyIfNeeded { swiftCalls += 1 })
        #expect(swiftCalls == 1)
        #expect(rustCalls == 1)
    }

}

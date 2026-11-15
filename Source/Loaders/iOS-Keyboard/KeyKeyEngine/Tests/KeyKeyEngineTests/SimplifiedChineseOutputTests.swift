import Foundation
import Testing

@testable import KeyKeyEngine

struct SimplifiedChineseOutputTests {
    private func converter() throws -> TraditionalToSimplified {
        let table = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../../../Linux-IME/data/tc2sc.cin")
        return TraditionalToSimplified(cin: try String(contentsOf: table, encoding: .utf8))
    }

    @Test func convertsHanOnceAndPreservesOtherScalars() throws {
        let converter = try converter()
        #expect(converter.convert("臺灣、體驗、岡 ∕≦ㄅＡ𠮷👩‍💻") == "台湾、体验、冈 ∕≦ㄅＡ𠮷👩‍💻")
    }

    @Test func appAndKeyboardUseExistingPreferencePrecedence() throws {
        let localName = "keykey.simplified.local.\(UUID())"
        let sharedName = "keykey.simplified.shared.\(UUID())"
        let local = try #require(UserDefaults(suiteName: localName))
        let shared = try #require(UserDefaults(suiteName: sharedName))
        defer {
            local.removePersistentDomain(forName: localName)
            shared.removePersistentDomain(forName: sharedName)
        }
        let keyboard = SimplifiedChineseOutputSettings(defaults: local, sharedDefaults: shared)
        let app = SimplifiedChineseOutputSettings(sharedDefaults: shared, writesShared: true)
        #expect(!app.enabled && !keyboard.enabled)
        #expect(keyboard.convertOutputText("臺灣") == "臺灣")
        app.setEnabled(true)
        #expect(app.enabled && keyboard.enabled)
        keyboard.setEnabled(false)
        #expect(app.enabled && !keyboard.enabled)
        app.setEnabled(true)
        #expect(keyboard.enabled)
    }

    @Test func touchOverflowKeepsOnlyTheSimplifiedTailEditable() throws {
        let converter = try converter()
        var state = TouchSmartHostTextState()
        #expect(state.update(to: converter.convert("岡繁體")) == .init(
            deleteCount: 0, insertion: "冈繁体"
        ))
        #expect(state.update(to: converter.convert("繁體字"), evictedPrefix: converter.convert("岡")) == .init(
            deleteCount: 0, insertion: "字"
        ))
        #expect(state.editableText == "繁体字")
        #expect(state.update(to: converter.convert("繁體")) == .init(deleteCount: 1, insertion: ""))
        #expect(state.finish(with: converter.convert("繁體")).isEmpty)
        #expect(state.editableText.isEmpty)
    }
}

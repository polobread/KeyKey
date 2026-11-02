import Foundation
import Testing
@testable import KeyKeyEngine

struct CangjieProfileSettingsTests {
    @Test("Virtual preferences preserve legacy physical options and independent app-group revisions")
    func settings() throws {
        let localName = "PrefixSettings." + UUID().uuidString
        let sharedName = "PrefixShared." + UUID().uuidString
        let local = try #require(UserDefaults(suiteName: localName))
        let shared = try #require(UserDefaults(suiteName: sharedName))
        defer { local.removePersistentDomain(forName: localName); shared.removePersistentDomain(forName: sharedName) }
        let settings = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(!settings.options(for: .cangjie).composeWhileTyping)
        #expect(!settings.options(for: .cangjie).prefixCandidates)
        var hardware = settings.options(for: .cangjie)
        settings.setOptions(hardware, for: .cangjie)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        var virtual = settings.options(for: .cangjie, virtualKeyboard: true)
        virtual.composeWhileTyping = false
        virtual.prefixCandidates = false
        settings.setOptions(virtual, for: .cangjie, virtualKeyboard: true)
        hardware.composeWhileTyping = true
        hardware.prefixCandidates = true
        settings.setOptions(hardware, for: .cangjie)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(settings.options(for: .cangjie).composeWhileTyping)
        #expect(settings.options(for: .cangjie).prefixCandidates)
        let app = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared, writesShared: true)
        var appVirtual = app.options(for: .cangjie, virtualKeyboard: true)
        appVirtual.prefixCandidates = true
        app.setOptions(appVirtual, for: .cangjie, virtualKeyboard: true)
        #expect(settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        let reopened = ChineseInputMethodSettings(defaults: local, sharedDefaults: shared)
        #expect(reopened.options(for: .cangjie).prefixCandidates)
        #expect(reopened.options(for: .cangjie).composeWhileTyping)
        var toggled = reopened.options(for: .cangjie)
        toggled.toggle("clear")
        #expect(toggled.clearOnError)
        #expect(toggled.switches(for: .cangjie).contains { $0.key == "prefix" })
        // An App physical edit cannot override an extension-local virtual choice.
        var localVirtual = settings.options(for: .cangjie, virtualKeyboard: true)
        localVirtual.composeWhileTyping = false
        localVirtual.prefixCandidates = false
        settings.setOptions(localVirtual, for: .cangjie, virtualKeyboard: true)
        var appHardware = app.options(for: .cangjie)
        appHardware.composeWhileTyping = false
        appHardware.prefixCandidates = false
        app.setOptions(appHardware, for: .cangjie)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(!settings.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        // Legacy explicit false remains false on virtual migration; new prefix defaults on.
        let oldName = "PrefixLegacy." + UUID().uuidString
        let old = try #require(UserDefaults(suiteName: oldName))
        defer { old.removePersistentDomain(forName: oldName) }
        old.set(try JSONEncoder().encode(TableInputOptions(method: .cangjie)), forKey: "tableOptions.cangjie")
        let migrated = ChineseInputMethodSettings(defaults: old)
        #expect(!migrated.options(for: .cangjie, virtualKeyboard: true).composeWhileTyping)
        #expect(migrated.options(for: .cangjie, virtualKeyboard: true).prefixCandidates)
        #expect(!migrated.options(for: .simplex, virtualKeyboard: true).composeWhileTyping)
        var legacyEnabled = TableInputOptions(method: .cangjie)
        legacyEnabled.composeWhileTyping = true
        old.set(try JSONEncoder().encode(legacyEnabled), forKey: "tableOptions.cangjie")
        var migratedVirtual = migrated.options(for: .cangjie, virtualKeyboard: true)
        migratedVirtual.composeWhileTyping = false
        migrated.setOptions(migratedVirtual, for: .cangjie, virtualKeyboard: true)
        #expect(migrated.options(for: .cangjie).composeWhileTyping)
    }
}

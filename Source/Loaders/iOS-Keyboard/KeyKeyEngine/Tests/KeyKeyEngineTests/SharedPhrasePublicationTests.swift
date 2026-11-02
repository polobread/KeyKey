import Foundation
import Testing
@testable import KeyKeyEngine

struct SharedPhrasePublicationTests {
    @Test func editorNormalizationUsesRustCodec() throws {
        let glyphs = try #require(SharedPhrasePublication.query(for: "ㄋㄧˇ ㄏㄠˇ"))
        #expect(SharedPhrasePublication.query(for: "su3cl3") == glyphs)
        #expect(SharedPhrasePublication.query(for: "SU3，CL3") == glyphs)
        #expect(SharedPhrasePublication.reading(for: glyphs) == "ㄋㄧˇ ㄏㄠˇ")
        #expect(SharedPhrasePublication.query(for: "ㄅㄆ") == nil)
        #expect(SharedPhrasePublication.query(for: "ˇ") == nil)
        #expect(SharedPhrasePublication.reading(for: "x") == nil)
    }

    @Test func appPublicationSupportsReadonlyExtensionAndPhraseExchange() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let path = root.appendingPathComponent("GuanyinmaUserPhrase.db")
        let extensionReader = try SharedPhrasePublication(phrasesURL: path, writablePhrases: false)
        #expect(extensionReader.userPhrases().isEmpty)
        #expect(!FileManager.default.fileExists(atPath: path.path))
        let app = try SharedPhrasePublication(phrasesURL: path, writablePhrases: true)
        try app.savePhrase(text: "你好", reading: "su3cl3")
        #expect(extensionReader.userPhrases().map(\.text) == ["你好"])
        #expect(throws: SmartMandarinUserDataError.self) {
            try extensionReader.savePhrase(text: "妳好", reading: "su3cl3")
        }
        let exported = app.exportPhrases()
        let imported = try app.importPhrases(exported)
        #expect(imported.imported == 0 && imported.skipped == 1)
        let phrase = try #require(app.userPhrases().first)
        try app.savePhrase(id: phrase.id, text: "妳好", reading: phrase.reading)
        #expect(extensionReader.userPhrases().map(\.text) == ["妳好"])
        try app.deletePhrase(id: phrase.id)
        #expect(extensionReader.userPhrases().isEmpty)
    }

    @Test func malformedExistingPublicationThrowsWithoutChangingBytes() throws {
        let path = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".db")
        defer { try? FileManager.default.removeItem(at: path) }
        let bytes = Data("invalid publication".utf8)
        try bytes.write(to: path)
        #expect(throws: (any Error).self) {
            _ = try SharedPhrasePublication(phrasesURL: path, writablePhrases: false)
        }
        #expect(try Data(contentsOf: path) == bytes)
    }
}

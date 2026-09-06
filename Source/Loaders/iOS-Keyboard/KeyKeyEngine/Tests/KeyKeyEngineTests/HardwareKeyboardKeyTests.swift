import Testing
@testable import KeyKeyEngine

struct HardwareKeyboardKeyTests {
    @Test("maps letters by physical US key position")
    func mapsLetters() {
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x14) == .character("q"))
        #expect(StandardHardwareKeyMapper.key(
            forHIDUsage: 0x14, modifiers: [.shift]
        ) == .character("Q"))
        #expect(StandardHardwareKeyMapper.key(
            forHIDUsage: 0x14, modifiers: [.capsLock]
        ) == .character("Q"))
        #expect(StandardHardwareKeyMapper.key(
            forHIDUsage: 0x14, modifiers: [.shift, .capsLock]
        ) == .character("q"))
    }

    @Test("maps number row and punctuation shift planes")
    func mapsNumberAndPunctuation() {
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x1E) == .character("1"))
        #expect(StandardHardwareKeyMapper.key(
            forHIDUsage: 0x1E, modifiers: [.shift]
        ) == .character("!"))
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x36) == .character(","))
        #expect(StandardHardwareKeyMapper.key(
            forHIDUsage: 0x36, modifiers: [.shift]
        ) == .character("<"))
    }

    @Test("maps navigation and editing keys")
    func mapsSpecialKeys() {
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x28) == .returnKey)
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x58) == .returnKey)
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x2A) == .backspace)
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x4B) == .pageUp)
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0x52) == .upArrow)
        #expect(StandardHardwareKeyMapper.key(forHIDUsage: 0xE0) == nil)
    }

    @Test("recognizes Control-C and Command-C copy shortcuts")
    func recognizesCopyShortcuts() {
        #expect(StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x06, modifiers: [.control]
        ))
        #expect(StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x06, modifiers: [.command]
        ))
        #expect(StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x06, modifiers: [.control, .capsLock]
        ))
        #expect(!StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x06, modifiers: []
        ))
        #expect(!StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x06, modifiers: [.control, .shift]
        ))
        #expect(!StandardHardwareKeyMapper.isCopyShortcut(
            forHIDUsage: 0x07, modifiers: [.command]
        ))
    }

    @Test("recognizes Control-S and Command-S share shortcuts")
    func recognizesShareShortcuts() {
        #expect(StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x16, modifiers: [.control]
        ))
        #expect(StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x16, modifiers: [.command]
        ))
        #expect(StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x16, modifiers: [.command, .capsLock]
        ))
        #expect(!StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x16, modifiers: []
        ))
        #expect(!StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x16, modifiers: [.control, .shift]
        ))
        #expect(!StandardHardwareKeyMapper.isShareShortcut(
            forHIDUsage: 0x06, modifiers: [.command]
        ))
    }

    @Test("recognizes Control-K and Command-K clear shortcuts")
    func recognizesClearShortcuts() {
        #expect(StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x0E, modifiers: [.control]
        ))
        #expect(StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x0E, modifiers: [.command]
        ))
        #expect(StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x0E, modifiers: [.control, .capsLock]
        ))
        #expect(!StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x0E, modifiers: []
        ))
        #expect(!StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x0E, modifiers: [.command, .shift]
        ))
        #expect(!StandardHardwareKeyMapper.isClearShortcut(
            forHIDUsage: 0x16, modifiers: [.control]
        ))
    }

    @Test("candidate shortcuts distinguish ordinary and associated candidates")
    func mapsCandidateShortcuts() {
        #expect(StandardHardwareKeyMapper.candidateIndex(
            forHIDUsage: 0x1E, modifiers: [], showingAssociatedPhrases: false
        ) == 0)
        #expect(StandardHardwareKeyMapper.candidateIndex(
            forHIDUsage: 0x26, modifiers: [.shift], showingAssociatedPhrases: true
        ) == 8)
        #expect(StandardHardwareKeyMapper.candidateIndex(
            forHIDUsage: 0x1E, modifiers: [.shift], showingAssociatedPhrases: false
        ) == nil)
        #expect(StandardHardwareKeyMapper.candidateIndex(
            forHIDUsage: 0x1E, modifiers: [], showingAssociatedPhrases: true
        ) == nil)
        #expect(StandardHardwareKeyMapper.candidateIndex(
            forHIDUsage: 0x1E, modifiers: [.control], showingAssociatedPhrases: false
        ) == nil)

        let shiftedSymbols = Array("!@#$%^&*()")
        for index in 0..<9 {
            let usage = 0x1E + index
            #expect(StandardHardwareKeyMapper.key(
                forHIDUsage: usage, modifiers: [.shift]
            ) == .character(shiftedSymbols[index]))
            #expect(StandardHardwareKeyMapper.candidateIndex(
                forHIDUsage: usage,
                modifiers: [.shift],
                showingAssociatedPhrases: true
            ) == index)
        }
    }
}

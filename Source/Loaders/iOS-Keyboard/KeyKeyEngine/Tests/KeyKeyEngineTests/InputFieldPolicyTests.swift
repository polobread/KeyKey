import Testing

@testable import KeyKeyEngine

@Suite("Input field policy")
struct InputFieldPolicyTests {
    @Test("all UIKit keyboard hints have a usable preferred mode")
    func mappings() {
        let hints: [KeyboardTypeHint] = [
            .default, .asciiCapable, .numbersAndPunctuation, .url, .numberPad,
            .phonePad, .namePhonePad, .emailAddress, .decimalPad, .webSearch,
            .asciiCapableNumberPad
        ]
        for hint in hints {
            let policy = InputFieldPolicy(hint: hint)
            #expect(policy.allowedModes.contains(policy.preferredMode))
        }
    }

    @Test("number pad only accepts digits")
    func numberPad() {
        let policy = InputFieldPolicy(hint: .numberPad)
        #expect(policy.isKeyEnabled("8", mode: .number, shifted: false))
        #expect(!policy.isKeyEnabled(".", mode: .number, shifted: false))
        #expect(!policy.isKeyEnabled("SHIFT", mode: .number, shifted: false))
        #expect(!policy.isKeyEnabled("MODE", mode: .number, shifted: false))
    }

    @Test("decimal and phone pads expose only their useful punctuation")
    func specialisedNumbers() {
        let decimal = InputFieldPolicy(hint: .decimalPad)
        #expect(decimal.isKeyEnabled(".", mode: .number, shifted: false))
        #expect(!decimal.isKeyEnabled("-", mode: .number, shifted: false))

        let phone = InputFieldPolicy(hint: .phonePad)
        #expect(phone.isKeyEnabled("+", mode: .number, shifted: false))
        #expect(phone.isKeyEnabled("#", mode: .number, shifted: false))
        #expect(!phone.isKeyEnabled("@", mode: .number, shifted: false))
    }

    @Test("ASCII fields skip Bopomofo and disable non-ASCII panels")
    func ascii() {
        let policy = InputFieldPolicy(hint: .asciiCapable)
        #expect(policy.allowedModes == [.english, .number])
        #expect(policy.preferredMode == .english)
        #expect(policy.modeCaption(for: .english) == "數")
        #expect(!policy.isKeyEnabled("EMOJI", mode: .english, shifted: false))
        #expect(!policy.isKeyEnabled("，", mode: .english, shifted: false))
    }

    @Test("key previews describe the state the restricted policy will enter")
    func restrictedPreviews() {
        let policy = InputFieldPolicy(hint: .asciiCapable)
        #expect(policy.modePreviewCaption(for: .english, temporaryEnglish: false) == "數")
        #expect(policy.modePreviewCaption(for: .number, temporaryEnglish: false) == "英")
        #expect(policy.shiftPreviewCaption(
            for: .number, shifted: false, temporaryEnglish: false
        ) == "符二")
        #expect(policy.shiftPreviewCaption(
            for: .number, shifted: true, temporaryEnglish: false
        ) == "符一")
    }

    @Test("temporary English previews return to the state the engine will enter")
    func temporaryEnglishPreviews() {
        let policy = InputFieldPolicy.default
        #expect(policy.modePreviewCaption(for: .english, temporaryEnglish: true) == "英")
        #expect(policy.shiftPreviewCaption(
            for: .english, shifted: false, temporaryEnglish: true
        ) == "ㄅ")
    }
}

/// UIKit keyboard types translated into a platform-neutral hint so the policy
/// remains unit-testable outside an iOS simulator.
public enum KeyboardTypeHint: Sendable {
    case `default`, asciiCapable, numbersAndPunctuation, url, numberPad
    case phonePad, namePhonePad, emailAddress, decimalPad, webSearch
    case asciiCapableNumberPad
}

public struct InputFieldPolicy: Sendable, Equatable {
    private enum Kind: Sendable { case general, ascii, punctuation, url, number, phone, namePhone, email, decimal }

    public static let `default` = InputFieldPolicy(hint: .default)

    public let allowedModes: Set<BopomofoEngine.InputMode>
    public let preferredMode: BopomofoEngine.InputMode
    private let kind: Kind

    public init(hint: KeyboardTypeHint) {
        switch hint {
        case .default, .webSearch:
            kind = .general
            allowedModes = Set(BopomofoEngine.InputMode.allCases)
            preferredMode = .bopomofo
        case .asciiCapable:
            kind = .ascii
            allowedModes = [.english, .number]
            preferredMode = .english
        case .numbersAndPunctuation:
            kind = .punctuation
            allowedModes = [.number]
            preferredMode = .number
        case .url:
            kind = .url
            allowedModes = [.english, .number]
            preferredMode = .english
        case .numberPad, .asciiCapableNumberPad:
            kind = .number
            allowedModes = [.number]
            preferredMode = .number
        case .phonePad:
            kind = .phone
            allowedModes = [.number]
            preferredMode = .number
        case .namePhonePad:
            kind = .namePhone
            allowedModes = [.english, .number]
            preferredMode = .english
        case .emailAddress:
            kind = .email
            allowedModes = [.english, .number]
            preferredMode = .english
        case .decimalPad:
            kind = .decimal
            allowedModes = [.number]
            preferredMode = .number
        }
    }

    public func modeCaption(for mode: BopomofoEngine.InputMode) -> String {
        if allowedModes.count == 1 { return symbol(mode) }
        if allowedModes.count == 2 { return symbol(nextMode(after: mode)) }
        switch mode {
        case .bopomofo: return "英/數"
        case .english: return "數/ㄅ"
        case .number: return "ㄅ/英"
        }
    }

    /// The state a press on MODE will actually enter. Temporary English is a
    /// one-shot layer: MODE only makes it persistent instead of advancing to
    /// the number plane.
    public func modePreviewCaption(
        for mode: BopomofoEngine.InputMode, temporaryEnglish: Bool
    ) -> String {
        temporaryEnglish ? symbol(mode) : symbol(nextMode(after: mode))
    }

    /// A concise description of the state a press on SHIFT will enter.
    public func shiftPreviewCaption(
        for mode: BopomofoEngine.InputMode, shifted: Bool, temporaryEnglish: Bool
    ) -> String {
        if temporaryEnglish { return symbol(.bopomofo) }
        switch mode {
        case .bopomofo:
            return allowedModes.contains(.english) ? symbol(.english) : symbol(.bopomofo)
        case .english:
            return shifted ? "小寫" : "大寫"
        case .number:
            return shifted ? "符一" : "符二"
        }
    }

    public func isKeyEnabled(
        _ key: String, mode: BopomofoEngine.InputMode, shifted: Bool
    ) -> Bool {
        switch key {
        case KeyboardLayout.inputModeSwitchKey, "SETTINGS", "BACKSPACE", "ENTER":
            return true
        case "MODE":
            return allowedModes.count > 1
        case "SYMBOL", "EMOJI", "，", "。":
            return kind == .general
        case "SPACE":
            return allows(" ")
        case "SHIFT":
            if mode == .bopomofo { return allowedModes.contains(.english) }
            let rows = KeyboardLayout.rows(mode: mode, shifted: !shifted)
            return rows.flatMap { $0 }.contains { $0.count == 1 && allows($0) }
        default:
            guard allowedModes.contains(mode) else { return false }
            if mode == .bopomofo { return true }
            return key.count == 1 && allows(key)
        }
    }

    private func allows(_ value: String) -> Bool {
        guard value.unicodeScalars.count == 1, let scalar = value.unicodeScalars.first else {
            return false
        }
        let character = Character(value)
        let ascii = scalar.value >= 0x20 && scalar.value <= 0x7e
        switch kind {
        case .general: return true
        case .ascii: return ascii
        case .punctuation:
            return ascii && (!character.isLetter)
        case .url, .email:
            return ascii && scalar.value > 0x20
        case .number:
            return character.isNumber
        case .phone:
            return character.isNumber || "+-#*() ".contains(character)
        case .namePhone:
            return character.isASCII && (character.isLetter || character.isNumber
                || "+-#*() .,' ".contains(character))
        case .decimal:
            return character.isNumber || character == "."
        }
    }

    private func nextMode(after current: BopomofoEngine.InputMode) -> BopomofoEngine.InputMode {
        var candidate = current
        repeat {
            switch candidate {
            case .bopomofo: candidate = .english
            case .english: candidate = .number
            case .number: candidate = .bopomofo
            }
        } while !allowedModes.contains(candidate)
        return candidate
    }

    private func symbol(_ mode: BopomofoEngine.InputMode) -> String {
        switch mode {
        case .bopomofo: return "ㄅ"
        case .english: return "英"
        case .number: return "數"
        }
    }
}

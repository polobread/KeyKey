/// Platform-neutral representation of the physical keys used by the in-app
/// hardware-keyboard editor. UIKit reports USB HID usage values, but keeping
/// the mapping here lets it be tested without an iOS runtime.
public enum HardwareKeyboardKey: Equatable, Sendable {
    case character(Character)
    case returnKey
    case escape
    case backspace
    case tab
    case space
    case pageUp
    case pageDown
    case rightArrow
    case leftArrow
    case downArrow
    case upArrow
}

public struct HardwareKeyboardModifiers: OptionSet, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let shift = Self(rawValue: 1 << 0)
    public static let control = Self(rawValue: 1 << 1)
    public static let option = Self(rawValue: 1 << 2)
    public static let command = Self(rawValue: 1 << 3)
    public static let capsLock = Self(rawValue: 1 << 4)
}

public enum StandardHardwareKeyMapper {
    /// Copy is tied to the physical C key so Caps Lock does not change the
    /// shortcut. Other modified C combinations remain available to iOS.
    public static func isCopyShortcut(
        forHIDUsage usage: Int,
        modifiers: HardwareKeyboardModifiers
    ) -> Bool {
        guard usage == 0x06,
              !modifiers.contains(.shift),
              !modifiers.contains(.option)
        else { return false }
        return modifiers.contains(.control) || modifiers.contains(.command)
    }

    /// Share is tied to the physical S key so Caps Lock does not change the
    /// shortcut. Other modified S combinations remain available to iOS.
    public static func isShareShortcut(
        forHIDUsage usage: Int,
        modifiers: HardwareKeyboardModifiers
    ) -> Bool {
        guard usage == 0x16,
              !modifiers.contains(.shift),
              !modifiers.contains(.option)
        else { return false }
        return modifiers.contains(.control) || modifiers.contains(.command)
    }

    /// Clear-all is tied to the physical K key so Caps Lock does not change
    /// the shortcut. Confirmation is handled by the editor before deletion.
    public static func isClearShortcut(
        forHIDUsage usage: Int,
        modifiers: HardwareKeyboardModifiers
    ) -> Bool {
        guard usage == 0x0E,
              !modifiers.contains(.shift),
              !modifiers.contains(.option)
        else { return false }
        return modifiers.contains(.control) || modifiers.contains(.command)
    }

    /// Returns a zero-based candidate position for the physical number row.
    /// Ordinary candidates use 1–9; associated phrases deliberately require
    /// Shift+1–9 while keeping the visible labels unchanged.
    public static func candidateIndex(
        forHIDUsage usage: Int,
        modifiers: HardwareKeyboardModifiers,
        showingAssociatedPhrases: Bool
    ) -> Int? {
        guard (0x1E...0x26).contains(usage),
              !modifiers.contains(.control),
              !modifiers.contains(.option),
              !modifiers.contains(.command)
        else { return nil }

        let shifted = modifiers.contains(.shift)
        guard shifted == showingAssociatedPhrases else { return nil }
        return usage - 0x1E
    }

    /// Maps the USB HID keyboard page used by `UIKey.keyCode` to the US key
    /// positions that KeyKey's Standard Bopomofo layout expects.
    public static func key(
        forHIDUsage usage: Int,
        modifiers: HardwareKeyboardModifiers = []
    ) -> HardwareKeyboardKey? {
        switch usage {
        case 0x28, 0x58: return .returnKey
        case 0x29: return .escape
        case 0x2A: return .backspace
        case 0x2B: return .tab
        case 0x2C: return .space
        case 0x4B: return .pageUp
        case 0x4E: return .pageDown
        case 0x4F: return .rightArrow
        case 0x50: return .leftArrow
        case 0x51: return .downArrow
        case 0x52: return .upArrow
        default: break
        }

        if (0x04...0x1D).contains(usage) {
            let offset = usage - 0x04
            let lower = Character(String(UnicodeScalar(0x61 + offset)!))
            let upper = modifiers.contains(.shift) != modifiers.contains(.capsLock)
            return .character(upper ? Character(String(lower).uppercased()) : lower)
        }

        if (0x1E...0x27).contains(usage) {
            let offset = usage - 0x1E
            let unshifted = Array("1234567890")
            let shifted = Array("!@#$%^&*()")
            return .character(modifiers.contains(.shift) ? shifted[offset] : unshifted[offset])
        }

        if (0x59...0x62).contains(usage) {
            let keypad = Array("1234567890")
            let index = usage == 0x62 ? 9 : usage - 0x59
            return .character(keypad[index])
        }

        let punctuation: [Int: (Character, Character)] = [
            0x2D: ("-", "_"),
            0x2E: ("=", "+"),
            0x2F: ("[", "{"),
            0x30: ("]", "}"),
            0x31: ("\\", "|"),
            0x33: (";", ":"),
            0x34: ("'", "\""),
            0x35: ("`", "~"),
            0x36: (",", "<"),
            0x37: (".", ">"),
            0x38: ("/", "?")
        ]
        guard let pair = punctuation[usage] else { return nil }
        return .character(modifiers.contains(.shift) ? pair.1 : pair.0)
    }
}

import KeyKeyEngine
import UIKit

/// The keyboard palette. Light values are the Android ones so the two touch
/// keyboards look like one product; Android has no dark mode, so the dark
/// values are new here rather than ported.
enum Palette {
    static let background = dynamic(light: 0xDA_DF_E8, dark: 0x2A_2E_36)
    static let normalKey = dynamic(light: 0xFF_FF_FF, dark: 0x3A_3F_47)
    static let specialKey = dynamic(light: 0xC6_CF_DE, dark: 0x22_26_2C)
    static let candidateCell = dynamic(light: 0xF4_F7_FC, dark: 0x33_38_3F)
    static let primaryText = dynamic(light: 0x18_1F_2C, dark: 0xF2_F4_F8)
    static let hintText = dynamic(light: 0x5C_66_77, dark: 0xA8_B0_BD)
    /// Purple is the macOS default and remains the keyboard's control accent.
    static let highlight = colour(0x80_00_80)
    static let surface = dynamic(light: 0xF4_F7_FC, dark: 0x1E_22_28)

    static func candidateHighlight(for color: CandidateColor) -> UIColor {
        switch color {
        case .purple: colour(0x80_00_80)
        case .green: colour(0x3B_AD_1F)
        case .yellow: colour(0xEB_B5_00)
        case .red: colour(0xBF_00_29)
        }
    }

    static func candidateHighlightText(for color: CandidateColor) -> UIColor {
        color == .yellow ? colour(0x00_00_00) : colour(0xFF_FF_FF)
    }

    private static func dynamic(light: Int, dark: Int) -> UIColor {
        UIColor { traits in
            colour(traits.userInterfaceStyle == .dark ? dark : light)
        }
    }

    private static func colour(_ value: Int) -> UIColor {
        UIColor(
            red: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }
}

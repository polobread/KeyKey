import Foundation

/// The App Group setting is shared by the App and editor. The keyboard may
/// override it in its private preferences, even without Full Access.
public struct SimplifiedChineseOutputSettings {
    public static let displayName = "繁體中文轉簡體"
    private static let key = "simplifiedChineseOutput"
    private let store: KeyboardPreferenceStore

    public init(
        defaults: UserDefaults = .standard, sharedDefaults: UserDefaults? = nil,
        writesShared: Bool = false
    ) {
        store = KeyboardPreferenceStore(
            defaults: defaults, sharedDefaults: sharedDefaults, writesShared: writesShared
        )
    }

    public var enabled: Bool { store.object(forKey: Self.key) as? Bool ?? false }
    public func setEnabled(_ enabled: Bool) { store.set(enabled, forKey: Self.key) }

    /// Filters engine text at the host-output boundary.
    public func convertOutputText(_ text: String) -> String {
        guard !text.isEmpty, enabled else { return text }
        return TraditionalToSimplified.bundled.convert(text)
    }
}

/// Matches the desktop HanConvert character mapping for committed Han text.
struct TraditionalToSimplified: Sendable {
    static let bundled: Self = {
        let cin = Bundle.main.url(forResource: "tc2sc", withExtension: "cin")
            .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        return Self(cin: cin ?? "")
    }()

    private let mapping: [Unicode.Scalar: Unicode.Scalar]

    init(cin: String) {
        let rows = cin.split(whereSeparator: \.isNewline)
            .drop(while: { $0 != "%chardef begin" }).dropFirst()
            .prefix(while: { $0 != "%chardef end" })
        var mapping: [Unicode.Scalar: Unicode.Scalar] = [:]
        for row in rows {
            let fields = row.split(separator: "\t")
            guard fields.count == 2,
                  fields[0].unicodeScalars.count == 1, fields[1].unicodeScalars.count == 1,
                  let source = fields[0].unicodeScalars.first,
                  let target = fields[1].unicodeScalars.first,
                  (0x3400...0x9FFF).contains(source.value) || (0xF900...0xFAFF).contains(source.value)
            else { continue }
            mapping[source] = target
        }
        self.mapping = mapping
    }

    func convert(_ text: String) -> String {
        String(String.UnicodeScalarView(text.unicodeScalars.map { mapping[$0] ?? $0 }))
    }
}

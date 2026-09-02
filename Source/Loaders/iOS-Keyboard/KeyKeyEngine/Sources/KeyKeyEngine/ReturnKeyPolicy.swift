/// UIKit return-key hints translated into a platform-neutral policy so the
/// keyboard caption can be tested without importing UIKit.
public enum ReturnKeyHint: Sendable, Equatable, CaseIterable {
    case `default`, done, go, next, search, send, join, route, `continue`
    case emergencyCall, google, yahoo
}

public struct ReturnKeyPolicy: Sendable, Equatable {
    public let hint: ReturnKeyHint

    public init(hint: ReturnKeyHint) {
        self.hint = hint
    }

    /// The default return key retains the familiar arrow. Other actions use a
    /// short title so their purpose remains visible on a narrow function row.
    public var title: String? {
        switch hint {
        case .default: return nil
        case .done: return "完成"
        case .go: return "前往"
        case .next: return "下一個"
        case .search, .google, .yahoo: return "搜尋"
        case .send: return "傳送"
        case .join: return "加入"
        case .route: return "路線"
        case .continue: return "繼續"
        case .emergencyCall: return "緊急"
        }
    }

    public var accessibilityLabel: String {
        title ?? "換行"
    }
}

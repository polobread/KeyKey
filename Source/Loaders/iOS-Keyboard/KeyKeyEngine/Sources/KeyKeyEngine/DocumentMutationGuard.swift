/// Coalesces callbacks produced by document-proxy mutations. A completion from
/// an older mutation must not make a newer mutation look external.
public struct DocumentMutationGuard: Sendable {
    public private(set) var isActive = false
    private var generation: UInt = 0

    public init() {}

    @discardableResult
    public mutating func begin() -> UInt {
        generation &+= 1
        isActive = true
        return generation
    }

    public mutating func end(ifCurrent token: UInt) {
        guard generation == token else { return }
        isActive = false
    }

    /// Invalidates every queued completion, for example when the host changes
    /// to another text document while the previous mutation is still pending.
    public mutating func invalidate() {
        generation &+= 1
        isActive = false
    }
}

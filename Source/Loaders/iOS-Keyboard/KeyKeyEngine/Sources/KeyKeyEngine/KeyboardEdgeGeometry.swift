import Foundation

/// Positions measured up from the keyboard's usable bottom, as fractions of
/// the current layout's default height. This keeps preferences portable
/// between layouts while each drag changes only the selected edge.
public struct KeyboardEdgeGeometry: Equatable, Sendable {
    public enum Edge: Equatable, Sendable { case top, bottom }

    private static let minimumHeight = 0.75
    private static let maximumHeight = 1.35
    public static let maximumTop = 1.40
    private static let maximumBottom = 0.25

    public let top: Double
    public let bottom: Double

    public init(top: Double = 1, bottom: Double = 0) {
        let safeTop = min(Self.maximumTop, max(Self.minimumHeight, top.isFinite ? top : 1))
        let bottomMin = max(0, safeTop - Self.maximumHeight)
        let bottomMax = min(Self.maximumBottom, safeTop - Self.minimumHeight)
        self.top = safeTop
        self.bottom = min(bottomMax, max(bottomMin, bottom.isFinite ? bottom : 0))
    }

    public func moving(_ edge: Edge, by delta: Double) -> Self {
        guard delta.isFinite else { return self }
        switch edge {
        case .top:
            let lowerBound = bottom + Self.minimumHeight
            let upperBound = min(Self.maximumTop, bottom + Self.maximumHeight)
            return Self(top: min(upperBound, max(lowerBound, top + delta)), bottom: bottom)
        case .bottom:
            return Self(top: top, bottom: bottom + delta)
        }
    }
}

/// This setting is written by the keyboard extension, in its own sandbox.
public struct KeyboardHeightSettings {
    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public func geometry(for orientation: KeyboardLayoutProfile.Orientation) -> KeyboardEdgeGeometry {
        guard let edges = defaults.array(forKey: key(for: orientation)) as? [Double],
              edges.count == 2 else { return KeyboardEdgeGeometry() }
        return KeyboardEdgeGeometry(top: edges[0], bottom: edges[1])
    }

    public func setGeometry(_ geometry: KeyboardEdgeGeometry, for orientation: KeyboardLayoutProfile.Orientation) {
        defaults.set([geometry.top, geometry.bottom], forKey: key(for: orientation))
    }

    private func key(for orientation: KeyboardLayoutProfile.Orientation) -> String {
        orientation == .portrait ? "keyboardHeightPortraitEdges" : "keyboardHeightLandscapeEdges"
    }
}

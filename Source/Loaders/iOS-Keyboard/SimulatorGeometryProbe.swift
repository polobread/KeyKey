#if DEBUG && targetEnvironment(simulator) && compiler(>=6.4)
import UIKit

/// Local simulator measurements only. Never records document or key contents.
@available(iOS 27.1, *)
@MainActor
final class SimulatorGeometryProbe {
    private weak var view: UIView?
    private weak var observedWindow: UIWindow?
    private var timer: Timer?
    private var lastSnapshot = ""
    private var hingeEvents = 0
    private var hingeState: [String: Any] = [:]
    private let scope: String
    private let diagnosticLabel = UILabel()

    static let preferenceKey = "simulatorGeometryProbeEnabled"

    init(view: UIView, scope: String) {
        self.view = view
        self.scope = scope
        diagnosticLabel.frame = CGRect(x: 1, y: 1, width: 1, height: 1)
        diagnosticLabel.text = " "
        diagnosticLabel.isUserInteractionEnabled = false
        diagnosticLabel.isAccessibilityElement = true
        diagnosticLabel.accessibilityIdentifier = "\(scope).geometry"
        diagnosticLabel.accessibilityLabel = "模擬器版面診斷"
        view.addSubview(diagnosticLabel)
        view.addInteraction(UIHingeInteraction { [weak self] _, update in
            self?.recordHinge(update, source: "view")
        })
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] timer in
            guard self != nil else { timer.invalidate(); return }
            MainActor.assumeIsolated { self?.sample() }
        }
        sample()
    }

    private func recordHinge(_ update: UIHingeInteraction.Update, source: String) {
        hingeEvents += 1
        hingeState[source] = update.hinge.map {
            ["status": $0.status.rawValue, "angle": $0.angle] as [String: Any]
        } ?? ["unavailable": true]
        sample()
    }

    private func sample() {
        guard let view else { timer?.invalidate(); timer = nil; return }
        if let window = view.window, observedWindow !== window, window !== view {
            observedWindow = window
            window.addInteraction(UIHingeInteraction { [weak self] _, update in
                self?.recordHinge(update, source: "window")
            })
        }
        func rect(_ r: CGRect) -> [Double] { [r.minX, r.minY, r.width, r.height].map(Double.init) }
        func insets(_ i: UIEdgeInsets) -> [Double] { [i.top, i.left, i.bottom, i.right].map(Double.init) }
        func regions(_ view: UIView, _ kind: UIView.ReservedRegion.Kind) -> [[String: Any]] {
            view.reservedRegions(kind: kind, options: .includeInactive).map {
                ["frame": rect($0.frame), "active": $0.isActive]
            }
        }
        var snapshot: [String: Any] = [
            "scope": scope, "bounds": rect(view.bounds), "safeArea": insets(view.safeAreaInsets),
            "horizontalSizeClass": view.traitCollection.horizontalSizeClass.rawValue,
            "verticalSizeClass": view.traitCollection.verticalSizeClass.rawValue,
            "idiom": view.traitCollection.userInterfaceIdiom.rawValue,
            "division": regions(view, .division), "occlusion": regions(view, .occlusion),
            "hingeEvents": hingeEvents, "hinge": hingeState
        ]
        if let window = view.window {
            snapshot["windowBounds"] = rect(window.bounds)
            snapshot["windowSafeArea"] = insets(window.safeAreaInsets)
            snapshot["windowDivision"] = regions(window, .division)
        }
        if let controller = view.next as? UIInputViewController {
            snapshot["needsInputModeSwitchKey"] = controller.needsInputModeSwitchKey
        }
        guard let data = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
              let value = String(data: data, encoding: .utf8), value != lastSnapshot else { return }
        lastSnapshot = value
        diagnosticLabel.accessibilityValue = value
        snapshot["time"] = Date().timeIntervalSince1970
        snapshot["pid"] = ProcessInfo.processInfo.processIdentifier
        guard let record = try? JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys]),
              let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appendingPathComponent("geometry-probe.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        if let file = try? FileHandle(forWritingTo: url) {
            defer { try? file.close() }
            _ = try? file.seekToEnd()
            try? file.write(contentsOf: record + Data([10]))
        }
    }
}
#endif

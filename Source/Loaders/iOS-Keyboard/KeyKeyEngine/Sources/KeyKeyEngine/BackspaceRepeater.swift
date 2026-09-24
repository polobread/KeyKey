import Foundation

/// Repeats one delete at a controlled rate after the caller handles key down.
/// Both the touch keyboard and the in-app hardware editor use the same pace.
@MainActor
public final class BackspaceRepeater {
    public static let initialDelayMilliseconds = 450

    public static func intervalMilliseconds(afterRepeatCount count: Int) -> Int {
        if count <= 8 { return 115 }
        if count <= 24 { return 90 }
        return 70
    }

    private var timer: Timer?
    private var action: (() -> Void)?
    private var repeatCount = 0
    private var generation = 0

    public init() {}

    public func start(_ action: @escaping () -> Void) {
        stop()
        self.action = action
        schedule(afterMilliseconds: Self.initialDelayMilliseconds)
    }

    public func stop() {
        generation += 1
        timer?.invalidate()
        timer = nil
        action = nil
        repeatCount = 0
    }

    private func schedule(afterMilliseconds milliseconds: Int) {
        let scheduledGeneration = generation
        let timer = Timer(timeInterval: Double(milliseconds) / 1_000, repeats: false) {
            [weak self] _ in
            Task { @MainActor [weak self] in self?.fire(ifGeneration: scheduledGeneration) }
        }
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func fire(ifGeneration scheduledGeneration: Int) {
        guard generation == scheduledGeneration, let action else { return }
        let currentGeneration = generation
        action()
        guard generation == currentGeneration else { return }
        repeatCount += 1
        schedule(afterMilliseconds: Self.intervalMilliseconds(afterRepeatCount: repeatCount))
    }
}

import KeyKeyEngine
import UIKit

/// Temporary controls over the live keyboard. Only the controls intercept
/// touches, so ordinary keys outside their bounds remain available to try.
final class KeyboardHeightEditor: UIView {
    enum DragPhase { case began, changed, ended, cancelled }

    var onDrag: ((KeyboardEdgeGeometry.Edge, DragPhase, CGFloat) -> Void)?
    var onStep: ((KeyboardEdgeGeometry.Edge, Double) -> Void)?
    var onReset: (() -> Void)?
    var onCancel: (() -> Void)?
    var onDone: (() -> Void)?

    private let topHandle = EdgeHandle(configuration: .filled())
    private let bottomHandle = EdgeHandle(configuration: .filled())
    private var bottomConstraint: NSLayoutConstraint?

    init() {
        super.init(frame: .zero)
        let cancel = actionButton("取消", identifier: "cancel", action: #selector(cancelTapped))
        let reset = actionButton("恢復預設", identifier: "reset", action: #selector(resetTapped))
        let done = actionButton("完成", identifier: "done", action: #selector(doneTapped))
        configure(topHandle, edge: .top, title: "拖曳上緣")
        configure(bottomHandle, edge: .bottom, title: "往上拉下緣")

        let toolbar = UIStackView(arrangedSubviews: [cancel, topHandle, reset, done])
        toolbar.alignment = .fill
        toolbar.spacing = 4
        toolbar.translatesAutoresizingMaskIntoConstraints = false
        bottomHandle.translatesAutoresizingMaskIntoConstraints = false
        addSubview(toolbar)
        addSubview(bottomHandle)
        let bottom = bottomHandle.bottomAnchor.constraint(equalTo: bottomAnchor, constant: -3)
        bottomConstraint = bottom
        NSLayoutConstraint.activate([
            toolbar.centerXAnchor.constraint(equalTo: centerXAnchor),
            toolbar.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 3),
            toolbar.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -3),
            toolbar.topAnchor.constraint(equalTo: topAnchor, constant: 3),
            toolbar.heightAnchor.constraint(equalToConstant: 44),
            bottomHandle.centerXAnchor.constraint(equalTo: centerXAnchor),
            bottomHandle.heightAnchor.constraint(equalToConstant: 44),
            bottom
        ])
    }

    required init?(coder: NSCoder) { fatalError("not used") }

    func update(geometry: KeyboardEdgeGeometry, bottomGap: CGFloat) {
        if bottomConstraint?.constant != -3 - bottomGap {
            bottomConstraint?.constant = -3 - bottomGap
        }
        topHandle.accessibilityValue = "\(Int(((geometry.top - geometry.bottom) * 100).rounded()))%"
        let isFlush = bottomGap < 0.5
        let title = isFlush ? "往上拉下緣" : "拖曳下緣"
        if bottomHandle.configuration?.title != title {
            bottomHandle.configuration?.title = title
        }
        bottomHandle.accessibilityLabel = isFlush ? "下緣已貼齊底部，可往上拉" : "拖曳下緣"
        bottomHandle.accessibilityValue = isFlush ? "貼齊" : "\(Int(bottomGap.rounded())) 點"
    }

    override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
        let hit = super.hitTest(point, with: event)
        return hit === self ? nil : hit
    }

    private func configure(_ handle: EdgeHandle, edge: KeyboardEdgeGeometry.Edge, title: String) {
        handle.configuration?.title = title
        handle.configuration?.buttonSize = .small
        handle.accessibilityIdentifier = edge == .top ? "keyboard-height.top" : "keyboard-height.bottom"
        handle.accessibilityLabel = title
        handle.accessibilityTraits = .adjustable
        handle.tintColor = Palette.highlight
        handle.onStep = { [weak self] direction in self?.onStep?(edge, direction * 0.05) }
        handle.onDrag = { [weak self] phase, y in self?.onDrag?(edge, phase, y) }
    }

    private func actionButton(_ title: String, identifier: String, action: Selector) -> UIButton {
        var configuration = UIButton.Configuration.filled()
        configuration.title = title
        configuration.buttonSize = .small
        let button = UIButton(configuration: configuration)
        button.tintColor = Palette.highlight
        button.accessibilityIdentifier = "keyboard-height." + identifier
        button.addTarget(self, action: action, for: .touchUpInside)
        return button
    }

    @objc private func cancelTapped() { onCancel?() }
    @objc private func resetTapped() { onReset?() }
    @objc private func doneTapped() { onDone?() }
}

private final class EdgeHandle: UIButton {
    var onStep: ((Double) -> Void)?
    var onDrag: ((KeyboardHeightEditor.DragPhase, CGFloat) -> Void)?

    override func beginTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        guard let y = screenY(of: touch), super.beginTracking(touch, with: event) else { return false }
        onDrag?(.began, y)
        return true
    }

    override func continueTracking(_ touch: UITouch, with event: UIEvent?) -> Bool {
        _ = super.continueTracking(touch, with: event)
        if let y = screenY(of: touch) { onDrag?(.changed, y) }
        // Resizing moves the control's frame under the touch.
        return true
    }

    override func endTracking(_ touch: UITouch?, with event: UIEvent?) {
        super.endTracking(touch, with: event)
        if let touch, let y = screenY(of: touch) { onDrag?(.ended, y) }
        else { onDrag?(.cancelled, 0) }
    }

    override func cancelTracking(with event: UIEvent?) {
        super.cancelTracking(with: event)
        onDrag?(.cancelled, 0)
    }

    private func screenY(of touch: UITouch) -> CGFloat? {
        guard let window else { return nil }
        // The extension window moves during resize. Measure both the initial
        // touch and each update in the same fixed screen coordinate space.
        let local = touch.location(in: window)
        return window.windowScene.map { window.convert(local, to: $0.screen.coordinateSpace).y } ?? local.y
    }

    override func accessibilityIncrement() { onStep?(1) }
    override func accessibilityDecrement() { onStep?(-1) }
}

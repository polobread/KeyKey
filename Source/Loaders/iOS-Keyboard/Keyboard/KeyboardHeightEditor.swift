import KeyKeyEngine
import UIKit

/// Temporary controls over the live keyboard. Only the controls intercept
/// touches, so ordinary keys outside their bounds remain available to try.
final class KeyboardHeightEditor: UIView {
    var onDrag: ((KeyboardEdgeGeometry.Edge, UIGestureRecognizer.State, CGFloat) -> Void)?
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
        let pan = UIPanGestureRecognizer(target: self, action: #selector(dragged(_:)))
        pan.maximumNumberOfTouches = 1
        handle.addGestureRecognizer(pan)
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

    @objc private func dragged(_ gesture: UIPanGestureRecognizer) {
        guard let window else { return }
        // The extension's own bounds move when iOS changes the keyboard
        // height. Use a stable screen coordinate for both handles.
        let local = gesture.location(in: window)
        let y = window.windowScene.map { window.convert(local, to: $0.screen.coordinateSpace).y } ?? local.y
        let edge: KeyboardEdgeGeometry.Edge = gesture.view === topHandle ? .top : .bottom
        onDrag?(edge, gesture.state, y)
    }
}

private final class EdgeHandle: UIButton {
    var onStep: ((Double) -> Void)?

    override func accessibilityIncrement() { onStep?(1) }
    override func accessibilityDecrement() { onStep?(-1) }
}

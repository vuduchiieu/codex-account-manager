import AppKit
import SwiftUI

struct WindowCornerConfigurator: NSViewRepresentable {
    let radius: CGFloat

    func makeNSView(context: Context) -> CornerConfigurationView {
        CornerConfigurationView(radius: radius)
    }

    func updateNSView(_ view: CornerConfigurationView, context: Context) {
        view.radius = radius
        view.applyCornerRadius()
    }
}

final class CornerConfigurationView: NSView {
    var radius: CGFloat

    init(radius: CGFloat) {
        self.radius = radius
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        applyCornerRadius()
    }

    func applyCornerRadius() {
        guard let window, let contentView = window.contentView else { return }
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        contentView.wantsLayer = true
        contentView.layer?.cornerCurve = .continuous
        contentView.layer?.cornerRadius = radius
        contentView.layer?.masksToBounds = true
    }
}

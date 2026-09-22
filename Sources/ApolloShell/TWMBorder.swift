import ApolloShellCore
import ApolloWM
import AppKit
import SwiftUI

/// A colored frame around the focused window while the TWM runs, so it is
/// clear which window the keys act on. Follows `TilingEngine.onActiveWindowChanged`
/// (and glides along with the window). The color shows the key mode: the
/// theme's accent normally, orange while resizing by keys, green while
/// choosing a desktop to send the window to.
@MainActor
final class TWMBorder {
    private let engine: TilingEngine
    private let panel = BorderPanel()
    private var active: TilingEngine.ActiveWindow?

    var width: CGFloat = 2 { didSet { panel.model.width = width; show(active) } }
    var radius: CGFloat = 16 { didSet { panel.model.radius = radius } }
    var mode: KeyBindings.Mode = .normal { didSet { panel.model.mode = mode } }

    init(engine: TilingEngine) {
        self.engine = engine
        engine.onActiveWindowChanged = { [weak self] active in self?.show(active) }
        show(engine.activeWindow())
    }

    func close() {
        engine.onActiveWindowChanged = nil
        panel.orderOut(nil)
    }

    private func show(_ active: TilingEngine.ActiveWindow?) {
        self.active = active
        guard let active, width > 0 else {
            panel.orderOut(nil)
            return
        }
        let height = NSScreen.screens.first?.frame.height ?? 0
        // The stroke lies just outside the window.
        let frame = active.frame.insetBy(dx: -width, dy: -width)
        let rect = NSRect(x: frame.minX, y: height - frame.maxY, width: frame.width, height: frame.height)
        if rect != panel.frame { panel.setFrame(rect, display: false) }
        // Re-ordering is a window-server round trip: on a new window, and a
        // few times a second in case the window was raised over the border.
        let now = CACurrentMediaTime()
        if !panel.isVisible {
            panel.orderFrontRegardless()
        } else if active.windowID == orderedAbove, now - lastOrdered < 0.25 {
            return
        }
        panel.order(.above, relativeTo: Int(active.windowID))
        orderedAbove = active.windowID
        lastOrdered = now
    }
    private var orderedAbove: CGWindowID?
    private var lastOrdered: CFTimeInterval = 0
}

@MainActor
@Observable
private final class BorderModel {
    var width: CGFloat = 2
    var radius: CGFloat = 16
    var mode: KeyBindings.Mode = .normal
}

/// Normal level, ordered right above the focused window; clicks go through.
@MainActor
private final class BorderPanel: ShellPanel {
    let model = BorderModel()

    init() {
        super.init(level: .normal, behavior: [.ignoresCycle, .transient], mayLeaveScreen: true)
        ignoresMouseEvents = true
        contentView = NSHostingView(rootView: BorderView(model: model).shellTheme())
    }
}

private struct BorderView: View {
    let model: BorderModel
    @Environment(\.shellStyle) private var style

    var body: some View {
        RoundedRectangle(cornerRadius: model.radius + model.width, style: .continuous)
            .strokeBorder(color, lineWidth: model.width)
            .animation(.easeOut(duration: 0.15), value: model.mode)
    }

    private var color: Color {
        switch model.mode {
        case .normal: style.accent
        case .resize: .orange
        case .send: .green
        }
    }
}

import ApolloShellCore
import ApolloWM
import AppKit
import SwiftUI

/// A colored frame around the focused window while the TWM runs, so it is
/// clear which window the keys act on. Follows `TilingEngine.onActiveWindowChanged`
/// (and glides along with the window), in the theme's accent.
@MainActor
final class TWMBorder {
    private let engine: TilingEngine
    private let panel = BorderPanel()
    private var active: TilingEngine.ActiveWindow?

    var width: CGFloat = 2 { didSet { panel.model.width = width; show(active) } }
    /// The corner radius of windows of apps built with the macOS 26 SDK.
    var radius: CGFloat = 16 { didSet { show(active) } }

    /// Apps built with an older SDK keep the pre-26 window corners.
    private static let legacyRadius: CGFloat = 10
    /// Whether an app (by process) was built with a pre-26 SDK, read once.
    private var legacyApps: [pid_t: Bool] = [:]
    private var clicks: Any?

    init(engine: TilingEngine) {
        self.engine = engine
        engine.onActiveWindowChanged = { [weak self] active in self?.show(active) }
        // A click raises the clicked window to the top - over the border,
        // which then hides the window's corners behind it. Put it back on top.
        clicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp]) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                MainActor.assumeIsolated { self?.raise() }
            }
        }
        show(engine.activeWindow())
    }

    func close() {
        engine.onActiveWindowChanged = nil
        if let clicks { NSEvent.removeMonitor(clicks) }
        clicks = nil
        panel.orderOut(nil)
    }

    private func raise() {
        guard let active, panel.isVisible else { return }
        panel.order(.above, relativeTo: Int(active.windowID))
        orderedAbove = active.windowID
        lastOrdered = CACurrentMediaTime()
    }

    /// The corner radius of `id`'s app: old SDK, old corners.
    private func cornerRadius(of id: CGWindowID) -> CGFloat {
        guard let pid = engine.windows[id]?.pid else { return radius }
        let legacy = legacyApps[pid] ?? {
            let executable = NSRunningApplication(processIdentifier: pid)?.executableURL
            let legacy = (executable.flatMap(MachOSDK.major(ofExecutableAt:)) ?? 26) < 26
            legacyApps[pid] = legacy
            return legacy
        }()
        return legacy ? Self.legacyRadius : radius
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
        // The panel lives on the desktop it was ordered in on. After a
        // desktop switch, or with the focus on another display, it has to be
        // ordered in anew there - reordering alone leaves it behind.
        // The screen AppKit files it under: the one holding most of it.
        let screen = NSScreen.screens.max { a, b in
            let overlapA = a.frame.intersection(rect), overlapB = b.frame.intersection(rect)
            return overlapA.width * overlapA.height < overlapB.width * overlapB.height
        }
        if panel.isVisible, !panel.isOnActiveSpace || screen != panel.screen {
            panel.orderOut(nil)
        }
        let corner = cornerRadius(of: active.windowID)
        if panel.model.radius != corner { panel.model.radius = corner }
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
            .strokeBorder(style.accent, lineWidth: model.width)
    }
}

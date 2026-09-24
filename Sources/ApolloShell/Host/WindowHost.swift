import AppKit
import SwiftUI
import ApolloConfig
import ApolloRuntime

@MainActor
final class WindowHost: SurfaceHosting {
    let model = SurfaceHost()
    var context: RenderContext?
    var screens: [String: ShellScreen] = [:]
    var log: (String) -> Void = { _ in }
    private(set) var windows: [String: SurfaceWindow] = [:]

    static let windowKinds: Set<String> = ["panel"]

    func surfaceAdded(_ surface: SurfaceInstance) {
        model.surfaceAdded(surface)
        show(surface)
    }

    func surfaceChanged(_ surface: SurfaceInstance) {
        model.surfaceChanged(surface)
        windows[SurfaceHost.key(surface.id, surface.screenKey)]?.update(surface, screen: screens[surface.screenKey])
    }

    func surfaceReplaced(_ surface: SurfaceInstance) {
        model.surfaceReplaced(surface)
        let key = SurfaceHost.key(surface.id, surface.screenKey)
        windows[key]?.close()
        windows[key] = nil
        show(surface)
    }

    func surfaceRemoved(id: String, screenKey: String) {
        model.surfaceRemoved(id: id, screenKey: screenKey)
        let key = SurfaceHost.key(id, screenKey)
        windows[key]?.close()
        windows[key] = nil
    }

    private func show(_ surface: SurfaceInstance) {
        guard Self.windowKinds.contains(surface.ir.kind), let context else { return }
        guard let screen = screens[surface.screenKey] else {
            log("surface \(surface.id): no screen \(surface.screenKey)")
            return
        }
        let window = SurfaceWindow(surface: surface, context: context)
        windows[SurfaceHost.key(surface.id, surface.screenKey)] = window
        window.update(surface, screen: screen)
        log("surface \(surface.id) on \(surface.screenKey): frame \(window.panel.frame) level \(window.panel.level.rawValue) visible \(window.panel.isVisible)")
    }
}

@MainActor
final class SurfaceWindow {
    let panel: ShellPanel
    let hosting: NSHostingView<AnyView>
    private let context: RenderContext
    private var pinned = false

    init(surface: SurfaceInstance, context: RenderContext) {
        self.context = context
        let layer: String? = if case .string(let name) = surface.property("layer") { name } else { nil }
        let keyboard: Bool = if case .bool(let flag) = surface.property("keyboard") { flag } else { surface.ir.kind == "popup" }
        panel = ShellPanel(
            level: SurfaceWindowKind.level(layer, kind: surface.ir.kind),
            behavior: SurfaceWindowKind.behavior(kind: surface.ir.kind),
            takesKeyboard: keyboard
        )
        hosting = NSHostingView(rootView: AnyView(SurfaceView(surface: surface, context: context)))
        hosting.sizingOptions = []
        panel.contentView = hosting
    }

    static func isVisible(_ surface: SurfaceInstance) -> Bool {
        if case .bool(false) = surface.property("visible") { return false }
        return true
    }

    static func isSticky(_ surface: SurfaceInstance) -> Bool {
        if case .bool(false) = surface.property("sticky") { return false }
        return true
    }

    func update(_ surface: SurfaceInstance, screen: ShellScreen?) {
        guard let screen else { return }
        let style = context.styles.resolve(StyleResolver.subject(for: surface), ancestors: [], parent: nil)
        let placement = SurfacePlacement(property: surface.property, style: style)
        let frame = placement.frame(screen: screen.frame, visible: screen.visibleFrame, fitting: hosting.fittingSize)
        panel.setFrame(frame, display: true)
        guard Self.isVisible(surface) else {
            panel.orderOut(nil)
            surface.isVisible = false
            return
        }
        panel.orderFrontRegardless()
        surface.isVisible = true
        if !pinned, Self.isSticky(surface) {
            StickySpace.pin(panel)
            pinned = true
        }
    }

    func close() {
        panel.orderOut(nil)
        panel.contentView = nil
        panel.close()
    }
}

import AppKit
import SwiftUI

@MainActor
final class StatusItemHostWindow: HostWindow {
    let item: NSStatusItem
    let hosting: FirstMouseHosting
    var onCloseRequest: (@MainActor () -> Void)?
    var onKey: (@MainActor (String) -> Bool)?
    var onResize: (@MainActor () -> Void)?
    var onOcclusion: (@MainActor (Bool) -> Void)?
    var onFittingChange: (@MainActor () -> Void)?

    init(content: AnyView, statusBar: NSStatusBar = .system) {
        item = statusBar.statusItem(withLength: NSStatusItem.variableLength)
        item.isVisible = false
        hosting = FirstMouseHosting(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
        if let button = item.button {
            hosting.frame = button.bounds
            hosting.autoresizingMask = [.width, .height]
            button.addSubview(hosting)
        }
        hosting.onInvalidate = { [weak self] in self?.onFittingChange?() }
    }

    var frame: CGRect {
        guard let button = item.button, let window = button.window else { return .zero }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }

    var isShown: Bool { item.isVisible }
    var fittingSize: CGSize { hosting.fittingSize }
    var windowNumber: Int { item.button?.window?.windowNumber ?? 0 }

    func apply(_ spec: SurfaceWindowSpec) {}
    func setLevel(_ level: NSWindow.Level) {}
    func setMinSize(_ size: CGSize) {}
    func setIgnoresMouse(_ ignores: Bool) {}
    func restoreFrame() -> Bool { false }

    func setFrame(_ frame: CGRect, glide: Bool) {
        let width = max(ceil(hosting.fittingSize.width), 1)
        if item.length != width { item.length = width }
        if let button = item.button { hosting.frame = button.bounds }
    }

    func setContent(_ view: AnyView) {
        hosting.rootView = view
        setFrame(.zero, glide: false)
    }

    func setContent(_ view: AnyView, frame: CGRect, glide: Bool) {
        setContent(view)
    }

    func show(focus: Bool) {
        item.isVisible = true
        setFrame(.zero, glide: false)
    }

    func hide() {
        item.isVisible = false
    }

    func animate(opening: Bool, focus: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void) {
        opening ? show(focus: focus) : hide()
        completion()
    }

    func close() {
        item.statusBar?.removeStatusItem(item)
    }
}

import AppKit
import SwiftUI
import ApolloRuntime

@MainActor
protocol HostWindow: AnyObject {
    var frame: CGRect { get }
    var isShown: Bool { get }
    var fittingSize: CGSize { get }
    var onCloseRequest: (@MainActor () -> Void)? { get set }
    var onKey: (@MainActor (String) -> Bool)? { get set }
    var windowNumber: Int { get }
    func apply(_ spec: SurfaceWindowSpec)
    func setLevel(_ level: NSWindow.Level)
    func setFrame(_ frame: CGRect)
    func setContent(_ view: AnyView)
    func show(focus: Bool)
    func hide()
    func animate(opening: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void)
    func close()
}

@MainActor
protocol HostWindowFactory: AnyObject {
    func make(spec: SurfaceWindowSpec, content: AnyView) -> any HostWindow
    func makeAuxiliary(content: AnyView) -> any HostWindow
}

@MainActor
final class AppKitWindowFactory: HostWindowFactory {
    func make(spec: SurfaceWindowSpec, content: AnyView) -> any HostWindow {
        AppKitHostWindow(spec: spec, content: content)
    }

    func makeAuxiliary(content: AnyView) -> any HostWindow {
        var spec = SurfaceWindowSpec(kind: "overlay", property: { _ in .null })
        spec.clickThrough = .on
        return AppKitHostWindow(spec: spec, content: content)
    }
}

final class HostPanel: ShellPanel {
    var onEscape: () -> Bool = { false }
    var onKey: (NSEvent) -> Bool = { _ in false }

    override func cancelOperation(_ sender: Any?) {
        if !onEscape() { super.cancelOperation(sender) }
    }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }
}

final class HostTitledWindow: NSWindow {
    var onKey: (NSEvent) -> Bool = { _ in false }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }
}

final class FirstMouseHosting: NSHostingView<AnyView> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
}

@MainActor
final class AppKitHostWindow: NSObject, HostWindow, NSWindowDelegate {
    let window: NSWindow
    let container: NSView
    let hosting: FirstMouseHosting
    private var spec: SurfaceWindowSpec
    private var scrimWindow: ScrimPanel?
    private var outsideMonitor: Any?
    private var leaveTimer: Timer?
    private var generation = 0
    private var pinned = false
    private var previousApp: NSRunningApplication?
    var onCloseRequest: (@MainActor () -> Void)?
    var onKey: (@MainActor (String) -> Bool)?

    init(spec: SurfaceWindowSpec, content: AnyView) {
        self.spec = spec
        container = NSView()
        container.wantsLayer = true
        hosting = FirstMouseHosting(rootView: content)
        hosting.sizingOptions = []
        hosting.autoresizingMask = [.width, .height]
        container.addSubview(hosting)
        if spec.kind == "window" {
            let titled = HostTitledWindow(contentRect: .zero, styleMask: spec.styleMask, backing: .buffered, defer: true)
            titled.isReleasedWhenClosed = false
            titled.level = spec.level
            titled.collectionBehavior = spec.behavior
            window = titled
        } else {
            window = HostPanel(level: spec.level, behavior: spec.behavior, takesKeyboard: spec.keyboard, mayLeaveScreen: spec.overhang || spec.animates)
        }
        super.init()
        window.contentView = container
        window.delegate = self
        if let panel = window as? HostPanel {
            panel.onEscape = { [weak self] in
                MainActor.assumeIsolated { self?.escape() ?? false }
            }
            panel.onKey = { [weak self] event in
                MainActor.assumeIsolated { self?.key(event) ?? false }
            }
        } else if let titled = window as? HostTitledWindow {
            titled.onKey = { [weak self] event in
                MainActor.assumeIsolated { self?.key(event) ?? false }
            }
        }
        apply(spec)
    }

    var frame: CGRect { window.frame }
    var isShown: Bool { window.isVisible }
    var fittingSize: CGSize { hosting.fittingSize }
    var windowNumber: Int { window.windowNumber }

    func apply(_ spec: SurfaceWindowSpec) {
        self.spec = spec
        if window.level != spec.level { window.level = spec.level }
        if window.collectionBehavior != spec.behavior { window.collectionBehavior = spec.behavior }
        window.ignoresMouseEvents = spec.clickThrough == .on
        if spec.kind == "window" {
            window.title = spec.title
            window.titleVisibility = spec.titleVisible ? .visible : .hidden
            if window.styleMask != spec.styleMask { window.styleMask = spec.styleMask }
            if let autosave = spec.autosave, window.frameAutosaveName != autosave { window.setFrameAutosaveName(autosave) }
        }
    }

    func setLevel(_ level: NSWindow.Level) {
        if window.level != level { window.level = level }
    }

    func setFrame(_ frame: CGRect) {
        guard window.frame != frame else { return }
        window.setFrame(frame, display: true)
        container.frame = CGRect(origin: .zero, size: frame.size)
        hosting.frame = container.bounds
    }

    func setContent(_ view: AnyView) {
        hosting.rootView = view
    }

    func show(focus: Bool) {
        generation += 1
        if spec.kind == "window" {
            previousApp = NSWorkspace.shared.frontmostApplication
            NSApp.activate()
            window.makeKeyAndOrderFront(nil)
        } else if focus && spec.keyboard {
            window.makeKeyAndOrderFront(nil)
        } else {
            window.orderFrontRegardless()
        }
        if !pinned, spec.kind == "panel", spec.sticky {
            StickySpace.pin(window)
            pinned = true
        }
        window.alphaValue = 1
        armCloseTriggers()
    }

    func hide() {
        generation += 1
        disarmCloseTriggers()
        window.orderOut(nil)
        scrimWindow?.orderOut(nil)
        if spec.kind == "window", let previousApp {
            previousApp.activate()
            self.previousApp = nil
        }
    }

    func animate(opening: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void) {
        generation += 1
        let current = generation
        guard let layer = container.layer else {
            opening ? show(focus: true) : hide()
            completion()
            return
        }
        let closed = animator.closedTransform(geometry)
        let from = layer.presentation()?.sublayerTransform ?? (opening && !window.isVisible ? closed : layer.sublayerTransform)
        let target = opening ? CATransform3DIdentity : closed
        if opening {
            if !window.isVisible { window.alphaValue = 0 }
            show(focus: true)
            window.alphaValue = window.isVisible ? window.alphaValue : 0
            generation = current
        } else {
            disarmCloseTriggers()
        }
        if let scrim {
            let shade = scrimWindow ?? ScrimPanel(level: NSWindow.Level(rawValue: spec.level.rawValue - 1))
            shade.onClick = { [weak self] in self?.onCloseRequest?() }
            scrimWindow = shade
            shade.setFrame(screen, display: false)
            if opening {
                if !shade.isVisible { shade.alphaValue = 0 }
                shade.orderFrontRegardless()
            }
            let fade = animator.fade(opening: opening)
            NSAnimationContext.runAnimationGroup { context in
                context.duration = fade.duration
                context.timingFunction = fade.curve
                shade.animator().alphaValue = opening ? scrim : 0
            }
        }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.sublayerTransform = target
        CATransaction.commit()
        if let animation = animator.transformAnimation(opening: opening) as? CAPropertyAnimation {
            if let basic = animation as? CABasicAnimation {
                basic.fromValue = NSValue(caTransform3D: from)
                basic.toValue = NSValue(caTransform3D: target)
            }
            layer.add(animation, forKey: "surface.motion")
        } else {
            layer.removeAnimation(forKey: "surface.motion")
        }
        let fade = animator.fade(opening: opening)
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = fade.duration
            context.timingFunction = fade.curve
            window.animator().alphaValue = opening ? 1 : 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.generation == current else { return }
                if !opening {
                    self.window.orderOut(nil)
                    self.scrimWindow?.orderOut(nil)
                }
                completion()
            }
        })
    }

    func close() {
        generation += 1
        disarmCloseTriggers()
        window.delegate = nil
        window.orderOut(nil)
        scrimWindow?.orderOut(nil)
        scrimWindow?.close()
        window.contentView = nil
        window.close()
    }

    private func escape() -> Bool {
        if onKey?("escape") == true { return true }
        guard spec.closeOn.contains(.escape) else { return false }
        onCloseRequest?()
        return true
    }

    private func key(_ event: NSEvent) -> Bool {
        guard let chord = KeyEventChord.chord(event) else { return false }
        return onKey?(chord) ?? false
    }

    private func armCloseTriggers() {
        disarmCloseTriggers()
        if spec.closeOn.contains(.outsideClick) {
            outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self, !self.window.frame.contains(NSEvent.mouseLocation) else { return }
                    self.onCloseRequest?()
                }
            }
        }
        if spec.closeOn.contains(.mouseLeave) {
            let margin = spec.hoverMargin
            var entered = false
            leaveTimer = .scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    let inside = self.window.frame.insetBy(dx: -margin, dy: -margin).contains(NSEvent.mouseLocation)
                    if inside { entered = true } else if entered { self.onCloseRequest?() }
                }
            }
        }
    }

    private func disarmCloseTriggers() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if spec.closeOn.contains(.focusLoss) { onCloseRequest?() }
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool {
        onCloseRequest?()
        return false
    }
}

final class ScrimPanel: ShellPanel {
    var onClick: () -> Void = {}

    init(level: NSWindow.Level) {
        super.init(level: level, behavior: [.canJoinAllSpaces, .transient, .ignoresCycle, .fullScreenAuxiliary])
        backgroundColor = .black
        contentView = ScrimClickView { [weak self] in self?.onClick() }
    }
}

private final class ScrimClickView: NSView {
    private let action: () -> Void

    init(action: @escaping () -> Void) {
        self.action = action
        super.init(frame: .zero)
    }

    required init?(coder: NSCoder) { nil }

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override func mouseDown(with event: NSEvent) { action() }
}

enum KeyEventChord {
    static func chord(_ event: NSEvent) -> String? {
        guard let key = KeyNameTable.name(for: UInt32(event.keyCode)) else { return nil }
        var parts: [String] = []
        let flags = event.modifierFlags
        if flags.contains(.command) { parts.append("cmd") }
        if flags.contains(.control) { parts.append("ctrl") }
        if flags.contains(.option) { parts.append("alt") }
        if flags.contains(.shift) { parts.append("shift") }
        return (parts + [key]).joined(separator: "+")
    }
}

import AppKit
import SwiftUI
import ApolloRuntime
import ApolloShellCore

@MainActor
protocol HostWindow: AnyObject {
    var frame: CGRect { get }
    var isShown: Bool { get }
    var fittingSize: CGSize { get }
    var onCloseRequest: (@MainActor () -> Void)? { get set }
    var onKey: (@MainActor (String) -> Bool)? { get set }
    var onResize: (@MainActor () -> Void)? { get set }
    var onOcclusion: (@MainActor (Bool) -> Void)? { get set }
    var onFittingChange: (@MainActor () -> Void)? { get set }
    var windowNumber: Int { get }
    func apply(_ spec: SurfaceWindowSpec)
    func setLevel(_ level: NSWindow.Level)
    func setFrame(_ frame: CGRect, glide: Bool)
    func setMinSize(_ size: CGSize)
    func setIgnoresMouse(_ ignores: Bool)
    func restoreFrame() -> Bool
    func setContent(_ view: AnyView)
    func setContent(_ view: AnyView, frame: CGRect, glide: Bool)
    func show(focus: Bool)
    func hide()
    func animate(opening: Bool, focus: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void)
    func close()
    func watchFitting(_ on: Bool)
    func setClip(top: CGFloat)
}

extension HostWindow {
    func watchFitting(_ on: Bool) {}
    func setClip(top: CGFloat) {}
    func setFrame(_ frame: CGRect) { setFrame(frame, glide: false) }
}

@MainActor
protocol WindowStage: AnyObject {
    func front(_ window: NSWindow, key: Bool)
    func out(_ window: NSWindow)
    func isVisible(_ window: NSWindow) -> Bool
    func fade(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void)
    func glide(_ window: NSWindow, to frame: CGRect, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void)
    func pin(_ window: NSWindow)
    func activateApp()
}

@MainActor
final class SystemStage: WindowStage {
    static let shared = SystemStage()

    func front(_ window: NSWindow, key: Bool) {
        if key { window.makeKeyAndOrderFront(nil) } else { window.orderFrontRegardless() }
    }

    func out(_ window: NSWindow) { window.orderOut(nil) }
    func isVisible(_ window: NSWindow) -> Bool { window.isVisible }

    func fade(_ window: NSWindow, to alpha: CGFloat, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = duration
            context.timingFunction = curve
            window.animator().alphaValue = alpha
        }, completionHandler: {
            MainActor.assumeIsolated { completion() }
        })
    }

    func glide(_ window: NSWindow, to frame: CGRect, duration: TimeInterval, curve: CAMediaTimingFunction, completion: @escaping @MainActor () -> Void) {
        NSAnimationContext.runAnimationGroup { context in
            context.duration = duration
            context.timingFunction = curve
            window.animator().setFrame(frame, display: true)
        } completionHandler: {
            MainActor.assumeIsolated { completion() }
        }
    }

    func pin(_ window: NSWindow) { StickySpace.pin(window) }
    func activateApp() { NSApp.activate() }
}

@MainActor
protocol HostWindowFactory: AnyObject {
    func make(spec: SurfaceWindowSpec, content: AnyView) -> any HostWindow
    func makeAuxiliary(content: AnyView) -> any HostWindow
}

@MainActor
final class AppKitWindowFactory: HostWindowFactory {
    let stage: any WindowStage

    init(stage: any WindowStage = SystemStage.shared) {
        self.stage = stage
    }

    func make(spec: SurfaceWindowSpec, content: AnyView) -> any HostWindow {
        if spec.kind == "status-item" { return StatusItemHostWindow(content: content) }
        return AppKitHostWindow(spec: spec, content: content, stage: stage)
    }

    func makeAuxiliary(content: AnyView) -> any HostWindow {
        var spec = SurfaceWindowSpec(kind: "overlay", property: { _ in .null })
        spec.clickThrough = .on
        return AppKitHostWindow(spec: spec, content: content, stage: stage)
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

    override func sendEvent(_ event: NSEvent) {
        if event.type == .keyDown, event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty, onEscape() { return }
        super.sendEvent(event)
    }
}

final class HostTitledWindow: NSWindow {
    var onKey: (NSEvent) -> Bool = { _ in false }

    override func keyDown(with event: NSEvent) {
        if !onKey(event) { super.keyDown(with: event) }
    }
}

final class FirstMouseHostingView<Content: View>: NSHostingView<Content> {
    var onInvalidate: (@MainActor () -> Void)?
    var watchesLayout = false

    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func layout() {
        LayoutCounter.passed()
        super.layout()
        if watchesLayout { onInvalidate?() }
    }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        onInvalidate?()
    }
}

typealias FirstMouseHosting = FirstMouseHostingView<AnyView>

@MainActor
final class AppKitHostWindow: NSObject, HostWindow, NSWindowDelegate {
    let window: NSWindow
    private var glideTarget: CGRect?
    let container: NSView
    private let clipper = NSView()
    let hosting: FirstMouseHosting
    private var spec: SurfaceWindowSpec
    private var scrimWindow: ScrimPanel?
    private var outsideMonitor: Any?
    private var escapeKey: GlobalHotKey?
    private var leaveTimer: Timer?
    private var generation = 0
    private var pinned = false
    private var clipTop: CGFloat = 0
    private var previousApp: NSRunningApplication?
    let stage: any WindowStage
    var onCloseRequest: (@MainActor () -> Void)?
    var onKey: (@MainActor (String) -> Bool)?
    var onResize: (@MainActor () -> Void)?
    var onOcclusion: (@MainActor (Bool) -> Void)?
    var onFittingChange: (@MainActor () -> Void)?

    init(spec: SurfaceWindowSpec, content: AnyView, stage: any WindowStage = SystemStage.shared) {
        self.spec = spec
        self.stage = stage
        container = NSView()
        container.wantsLayer = true
        clipper.wantsLayer = true
        container.autoresizingMask = [.width, .height]
        clipper.addSubview(container)
        hosting = FirstMouseHosting(rootView: content)
        hosting.sizingOptions = [.intrinsicContentSize]
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
        window.contentView = clipper
        window.delegate = self
        hosting.onInvalidate = { [weak self] in
            self?.onFittingChange?()
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.restoreFocus() } }
        }
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

    func setIgnoresMouse(_ ignores: Bool) {
        if window.ignoresMouseEvents != ignores { window.ignoresMouseEvents = ignores }
    }

    func apply(_ spec: SurfaceWindowSpec) {
        self.spec = spec
        if let panel = window as? ShellPanel {
            panel.takesKeyboard = spec.keyboard
            panel.mayLeaveScreen = spec.overhang || spec.animates
        }
        if window.level != spec.level { window.level = spec.level }
        if window.collectionBehavior != spec.behavior { window.collectionBehavior = spec.behavior }
        if spec.clickThrough != .auto { window.ignoresMouseEvents = spec.clickThrough == .on }
        window.acceptsMouseMovedEvents = spec.clickThrough == .auto
        if spec.kind == "window" {
            window.title = spec.title
            window.titleVisibility = spec.titleVisible && spec.titlebar ? .visible : .hidden
            window.titlebarAppearsTransparent = !spec.titlebar
            window.isMovableByWindowBackground = !spec.titlebar
            if window.styleMask != spec.styleMask { window.styleMask = spec.styleMask }
            if let autosave = spec.autosave, window.frameAutosaveName != autosave { window.setFrameAutosaveName(autosave) }
        }
        if stage.isVisible(window) { pinIfSticky() }
    }

    private func pinIfSticky() {
        guard !pinned, spec.kind == "panel", spec.sticky else { return }
        stage.pin(window)
        pinned = true
    }

    func setLevel(_ level: NSWindow.Level) {
        if window.level != level { window.level = level }
    }

    func setFrame(_ frame: CGRect, glide: Bool) {
        guard (glideTarget ?? window.frame) != frame else { return }
        if glide, stage.isVisible(window) {
            glideTarget = frame
            stage.glide(window, to: frame, duration: MotionCurve.spatialDuration, curve: .shellSpatial) { [weak self] in
                guard let self, self.glideTarget == frame else { return }
                self.glideTarget = nil
            }
        } else {
            glideTarget = nil
            window.setFrame(frame, display: true)
        }
        clipper.frame = CGRect(origin: .zero, size: frame.size)
        container.frame = clipper.bounds
        hosting.frame = container.bounds
        updateClip()
    }

    func setClip(top: CGFloat) {
        guard clipTop != top else { return }
        clipTop = top
        updateClip()
    }

    private func updateClip() {
        guard let layer = clipper.layer else { return }
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        if clipTop > 0 {
            let mask = layer.mask ?? CALayer()
            mask.backgroundColor = CGColor(gray: 0, alpha: 1)
            mask.frame = CGRect(x: 0, y: 0, width: clipper.bounds.width, height: max(0, clipper.bounds.height - clipTop))
            layer.mask = mask
        } else if layer.mask != nil {
            layer.mask = nil
        }
        CATransaction.commit()
    }

    func watchFitting(_ on: Bool) {
        hosting.watchesLayout = on
    }

    func setMinSize(_ size: CGSize) {
        if window.contentMinSize != size { window.contentMinSize = size }
    }

    func restoreFrame() -> Bool {
        guard let autosave = spec.autosave, !autosave.isEmpty else { return false }
        return window.setFrameUsingName(autosave)
    }

    func setContent(_ view: AnyView) {
        hosting.rootView = view
    }

    func setContent(_ view: AnyView, frame: CGRect, glide: Bool) {
        window.disableScreenUpdatesUntilFlush()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        hosting.rootView = view
        if !glide {
            hosting.frame = CGRect(origin: .zero, size: frame.size)
            hosting.layoutSubtreeIfNeeded()
            hosting.displayIfNeeded()
        }
        setFrame(frame, glide: glide)
        hosting.layoutSubtreeIfNeeded()
        CATransaction.commit()
    }

    func show(focus: Bool) {
        generation += 1
        reveal(focus: focus)
        window.alphaValue = 1
    }

    private func reveal(focus: Bool) {
        if spec.kind == "window" {
            if !stage.isVisible(window) { previousApp = NSWorkspace.shared.frontmostApplication }
            WindowMainMenu.install()
            stage.activateApp()
            stage.front(window, key: true)
        } else {
            stage.front(window, key: focus && spec.keyboard)
        }
        pinIfSticky()
        armCloseTriggers()
    }

    func hide() {
        generation += 1
        disarmCloseTriggers()
        stage.out(window)
        if let scrimWindow { stage.out(scrimWindow) }
        if spec.kind == "window", let previousApp {
            previousApp.activate()
            self.previousApp = nil
        }
    }

    func animate(opening: Bool, focus: Bool, animator: any SurfaceAnimator, geometry: MotionGeometry, scrim: Double?, screen: CGRect, completion: @escaping @MainActor () -> Void) {
        generation += 1
        let current = generation
        guard let layer = container.layer else {
            opening ? show(focus: focus) : hide()
            completion()
            return
        }
        let closed = animator.closedTransform(geometry)
        let from = layer.presentation()?.sublayerTransform ?? (opening && !stage.isVisible(window) ? closed : layer.sublayerTransform)
        let target = opening ? CATransform3DIdentity : closed
        if opening {
            if !stage.isVisible(window) { window.alphaValue = 0 }
            reveal(focus: focus)
        } else {
            disarmCloseTriggers()
        }
        if let scrim {
            let shade = scrimWindow ?? ScrimPanel(level: NSWindow.Level(rawValue: spec.level.rawValue - 1))
            shade.onClick = { [weak self] in self?.onCloseRequest?() }
            scrimWindow = shade
            shade.setFrame(screen, display: false)
            if opening {
                if !stage.isVisible(shade) { shade.alphaValue = 0 }
                stage.front(shade, key: false)
            }
            let fade = animator.fade(opening: opening)
            stage.fade(shade, to: opening ? scrim : 0, duration: fade.duration, curve: fade.curve) {}
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
        let run: @MainActor () -> Void = { [weak self] in
            guard let self, self.generation == current else { return }
            self.stage.fade(self.window, to: opening ? 1 : 0, duration: fade.duration, curve: fade.curve) { [weak self] in
                guard let self, self.generation == current else { return }
                if !opening {
                    self.stage.out(self.window)
                    if let scrim = self.scrimWindow { self.stage.out(scrim) }
                }
                completion()
            }
        }
        let delay = animator.fadeDelay(opening: opening)
        if delay > 0 {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { MainActor.assumeIsolated { run() } }
        } else {
            run()
        }
    }

    func close() {
        generation += 1
        disarmCloseTriggers()
        window.delegate = nil
        stage.out(window)
        if let scrimWindow { stage.out(scrimWindow) }
        scrimWindow?.close()
        window.contentView = nil
        window.close()
    }

    func restoreFocus() {
        guard spec.keyboard, spec.kind != "window", stage.isVisible(window) else { return }
        let r = window.firstResponder
        let stale = r == nil || r === window || ((r as? NSView).map { $0.window !== window || !$0.isDescendant(of: hosting) } ?? false)
        if stale, r !== hosting { window.makeFirstResponder(hosting) }
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
        if spec.closeOn.contains(.globalEscape), case .success(let k) = GlobalHotKey.register(HotKey(keyCode: HotKeyKey.escape), action: { [weak self] in self?.onCloseRequest?() }) {
            escapeKey = k
        }
        if spec.closeOn.contains(.mouseLeave) {
            let margin = spec.hoverMargin
            var entered = false
            leaveTimer = ShellTimer.repeating(0.1) { [weak self] in
                guard let self else { return }
                let inside = self.window.frame.insetBy(dx: -margin, dy: -margin).contains(NSEvent.mouseLocation)
                if inside { entered = true } else if entered { self.onCloseRequest?() }
            }
        }
    }

    private func disarmCloseTriggers() {
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        outsideMonitor = nil
        escapeKey?.unregister()
        escapeKey = nil
        leaveTimer?.invalidate()
        leaveTimer = nil
    }

    func windowDidResignKey(_ notification: Notification) {
        if spec.closeOn.contains(.focusLoss) { onCloseRequest?() }
    }

    func windowDidChangeOcclusionState(_ notification: Notification) {
        onOcclusion?(window.occlusionState.contains(.visible))
    }

    func windowDidResize(_ notification: Notification) {
        onResize?()
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

enum ShellTimer {
    static func repeating(_ interval: TimeInterval, _ tick: @escaping @MainActor () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { tick() } }
        timer.tolerance = interval * 0.2
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
}

enum WindowMainMenu {
    static func make() -> NSMenu {
        let main = NSMenu()
        let app = NSMenu(title: "ApolloShell")
        main.addItem(submenu(app))
        let file = NSMenu(title: "File")
        file.addItem(withTitle: "Close Window", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        main.addItem(submenu(file))
        let edit = NSMenu(title: "Edit")
        edit.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
        let redo = edit.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "z")
        redo.keyEquivalentModifierMask = [.command, .shift]
        edit.addItem(.separator())
        edit.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
        edit.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
        edit.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
        edit.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")
        main.addItem(submenu(edit))
        return main
    }

    private static func submenu(_ menu: NSMenu) -> NSMenuItem {
        let item = NSMenuItem(title: menu.title, action: nil, keyEquivalent: "")
        item.submenu = menu
        return item
    }

    static func install() {
        if NSApp.mainMenu?.item(withTitle: "Edit") == nil { NSApp.mainMenu = make() }
    }
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

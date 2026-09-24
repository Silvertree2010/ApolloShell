import AppKit

class ShellPanel: NSPanel {
    var takesKeyboard: Bool
    var mayLeaveScreen: Bool

    init(size: NSSize = .zero, level: NSWindow.Level, behavior: NSWindow.CollectionBehavior,
         takesKeyboard: Bool = false, mayLeaveScreen: Bool = false, deferred: Bool = true) {
        self.takesKeyboard = takesKeyboard
        self.mayLeaveScreen = mayLeaveScreen
        super.init(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: deferred
        )
        self.level = level
        collectionBehavior = behavior
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        hidesOnDeactivate = false
        isMovable = false
        isReleasedWhenClosed = false
        becomesKeyOnlyIfNeeded = false
        animationBehavior = .none
    }

    override var canBecomeKey: Bool { takesKeyboard }
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        mayLeaveScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

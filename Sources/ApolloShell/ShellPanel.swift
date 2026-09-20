import AppKit

/// The basic setting of all windows of the shell: borderless and transparent,
/// does not bring the app forward, stays put when another app becomes active,
/// animates nothing by itself (the shell does the motion) and has no window
/// shadow - macOS works that out from the window shape, and because the glass
/// is rendered by the window manager itself, an almost square second frame
/// came about around the round glass. The edge and the depth come with the glass.
///
/// What differs is said by every place itself: the level, the behavior on
/// spaces, whether it takes the keyboard and whether it may stick out over the
/// screen edge.
class ShellPanel: NSPanel {
    private let takesKeyboard: Bool
    private let mayLeaveScreen: Bool

    /// `mayLeaveScreen`: macOS otherwise pushes windows back onto the screen -
    /// but edge windows should have their glass corners outside.
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

    #if DEBUG
    /// The self-test of the edit mode (`--selftest-edit`): every panel of the
    /// shell stays transparent and lets clicks through - the test runs next to
    /// the real ApolloShell without showing anything on the screen.
    override var alphaValue: CGFloat {
        get { super.alphaValue }
        set { super.alphaValue = EditModeSelfTest.invisible ? 0 : newValue }
    }

    override var ignoresMouseEvents: Bool {
        get { EditModeSelfTest.invisible || super.ignoresMouseEvents }
        set { super.ignoresMouseEvents = newValue }
    }
    #endif

    #if DEBUG
    // The self-test: never the key window - otherwise keys of the real app
    // would land in the invisible panel.
    override var canBecomeKey: Bool { takesKeyboard && !EditModeSelfTest.invisible }
    #else
    override var canBecomeKey: Bool { takesKeyboard }
    #endif
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        mayLeaveScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

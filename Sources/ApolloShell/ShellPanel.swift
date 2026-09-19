import AppKit

/// Grundeinstellung aller Fenster der Shell: randlos und durchsichtig, holt
/// die App nicht nach vorne, bleibt stehen, wenn eine andere App aktiv wird,
/// animiert nicht von selbst (die Bewegungen macht die Shell) und hat keinen
/// Fensterschatten - den berechnet macOS aus der Fensterform, und weil das
/// Glas vom Fenstermanager selbst gerendert wird, entstand ein fast eckiger
/// zweiter Rahmen um das runde Glas. Kante und Tiefe bringt das Glas mit.
///
/// Was sich unterscheidet, sagt jede Stelle selbst: Ebene, Verhalten auf
/// Spaces, ob es Tastatur annimmt und ob es ueber den Bildschirmrand ragen
/// darf.
class ShellPanel: NSPanel {
    private let takesKeyboard: Bool
    private let mayLeaveScreen: Bool

    /// `mayLeaveScreen`: macOS schiebt Fenster sonst zurueck auf den
    /// Bildschirm - Kantenfenster sollen ihre Glasecken aber draussen haben.
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
    /// Selbsttest des Bearbeitungsmodus (`--selftest-edit`): jedes Panel der
    /// Shell bleibt durchsichtig und laesst Klicks durch - der Test laeuft
    /// neben der echten ApolloShell, ohne auf dem Bildschirm etwas zu zeigen.
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
    // Selbsttest: nie Schluesselfenster - sonst landeten Tasten der echten
    // App im unsichtbaren Panel.
    override var canBecomeKey: Bool { takesKeyboard && !EditModeSelfTest.invisible }
    #else
    override var canBecomeKey: Bool { takesKeyboard }
    #endif
    override var canBecomeMain: Bool { false }

    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        mayLeaveScreen ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}

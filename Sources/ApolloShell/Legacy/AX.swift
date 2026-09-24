import AppKit
import ApplicationServices

/// Duenne Huelle um die C-Schnittstelle der Bedienungshilfen - fuer die
/// Fensterwache, das Dock-Menue, die Zaehler und Apples Dock. Jeder Zugriff
/// ist eine Anfrage an die andere App und wartet bis zu ihrem Timeout; nur
/// wo das nichts kostet, auf dem Hauptthread.
enum AX {
    /// Keine oeffentlichen Konstanten dafuer, die Namen sind aber seit Jahren
    /// stabil und werden von allen Fenster-Tools so benutzt.
    static let fullScreenAttribute = "AXFullScreen"
    static let enhancedUserInterfaceAttribute = "AXEnhancedUserInterface"

    static func pid(of element: AXUIElement) -> pid_t {
        var pid: pid_t = 0
        AXUIElementGetPid(element, &pid)
        return pid
    }

    static func copy(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success else { return nil }
        return value
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        copy(element, attribute) as? String
    }

    static func bool(_ element: AXUIElement, _ attribute: String) -> Bool? {
        copy(element, attribute) as? Bool
    }

    static func element(_ element: AXUIElement, _ attribute: String) -> AXUIElement? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXUIElementGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXUIElement.self)
    }

    static func elements(_ element: AXUIElement, _ attribute: String) -> [AXUIElement] {
        (copy(element, attribute) as? [AXUIElement]) ?? []
    }

    /// Rahmen in Bedienungshilfen-Koordinaten: Position ist die linke obere
    /// Ecke, gemessen ab der linken oberen Ecke des Hauptbildschirms.
    static func frame(of window: AXUIElement) -> CGRect? {
        var origin = CGPoint.zero
        var size = CGSize.zero
        guard let position = axValue(window, kAXPositionAttribute),
              let extent = axValue(window, kAXSizeAttribute),
              AXValueGetValue(position, .cgPoint, &origin),
              AXValueGetValue(extent, .cgSize, &size)
        else { return nil }
        return CGRect(origin: origin, size: size)
    }

    private static func axValue(_ element: AXUIElement, _ attribute: String) -> AXValue? {
        guard let value = copy(element, attribute), CFGetTypeID(value) == AXValueGetTypeID() else { return nil }
        return unsafeDowncast(value, to: AXValue.self)
    }

    static func isSettable(_ element: AXUIElement, _ attribute: String) -> Bool {
        var settable: DarwinBoolean = false
        return AXUIElementIsAttributeSettable(element, attribute as CFString, &settable) == .success
            && settable.boolValue
    }

    @discardableResult
    static func setPosition(_ window: AXUIElement, _ point: CGPoint) -> AXError {
        var point = point
        guard let value = AXValueCreate(.cgPoint, &point) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXPositionAttribute as CFString, value)
    }

    @discardableResult
    static func setSize(_ window: AXUIElement, _ size: CGSize) -> AXError {
        var size = size
        guard let value = AXValueCreate(.cgSize, &size) else { return .failure }
        return AXUIElementSetAttributeValue(window, kAXSizeAttribute as CFString, value)
    }

    @discardableResult
    static func setBool(_ element: AXUIElement, _ attribute: String, _ value: Bool) -> AXError {
        AXUIElementSetAttributeValue(element, attribute as CFString, (value ? kCFBooleanTrue : kCFBooleanFalse) as CFTypeRef)
    }
}

/// Die Symbole in Apples Dock, wie die Bedienungshilfen sie zeigen: eine
/// AXList mit AXApplicationDockItem-Kindern, jedes mit Titel und AXURL auf
/// die App (gemessen 14.09.). Apples Dock ist ausgeblendet, fuehrt sie aber
/// weiter - fuer Zaehler und Menues.
enum AppleDockItems {
    /// Leer ohne Freigabe oder ohne laufendes Dock.
    static func all(timeout: Float) -> [AXUIElement] {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return [] }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, timeout)
        guard let list = AX.elements(app, kAXChildrenAttribute)
            .first(where: { AX.string($0, kAXRoleAttribute) == kAXListRole as String })
        else { return [] }
        return AX.elements(list, kAXChildrenAttribute)
    }

    /// Die App hinter einem Symbol, ueber seine AXURL.
    static func bundleID(of item: AXUIElement) -> String? {
        (AX.copy(item, kAXURLAttribute) as? URL).flatMap { Bundle(url: $0)?.bundleIdentifier }
    }
}

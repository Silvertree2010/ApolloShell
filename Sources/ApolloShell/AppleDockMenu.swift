import AppKit
import ApolloShellCore
import ApplicationServices
import os

/// Liest das Dock-Menue, das **Apples** Dock fuer eine App zeigt, und gibt es
/// als Baum zurueck.
///
/// Warum dieser Umweg: Was in diesem Menue steht, liefert die App selbst an
/// das Dock (`applicationDockMenu(_:)`, NSDockTilePlugIn) - zuletzt benutzte
/// Dokumente, "Neues privates Fenster", was auch immer sie anbietet. Dieser
/// Weg steht nur Apples Dock offen; von aussen gibt es keine Schnittstelle
/// dafuer. Selbst geratene Eintraege aus der Menueleiste sind deshalb immer
/// eine Naeherung.
///
/// Was aber geht: Apples Dock den Menuebaum aufbauen lassen und ihn ueber die
/// Bedienungshilfen lesen. Damit bekommt jede App genau ihre eigenen
/// Eintraege, samt "Optionen" mit allem, was Apple dort hineinlegt.
///
/// Zwei Dinge sind dabei ungeprueft und werden beim ersten Lauf gemessen
/// (Protokoll `dockmenu`):
/// - ob `AXShowMenu` auch dann traegt, wenn Apples Dock ausgeblendet ist
///   (ApolloShell blendet es aus, solange es laeuft),
/// - ob dabei kurz etwas auf dem Bildschirm aufblitzt.
///
/// Traegt es nicht, bleibt das selbst gebaute Menue (`DockMenu`) bestehen.
@MainActor
enum AppleDockMenu {
    /// Ein Eintrag aus Apples Menue.
    struct Item {
        let title: String
        let enabled: Bool
        /// Das Zeichen, mit dem Apple den Eintrag markiert (Haken beim
        /// vordersten Fenster); leer, wenn er unmarkiert ist.
        let mark: String
        let separator: Bool
        let children: [Item]
        /// Der Weg zu diesem Eintrag, ueber die Titel: So wird er beim
        /// Ausfuehren wiedergefunden, denn die Elemente selbst gelten nur,
        /// solange Apples Menue offen ist.
        let path: [String]
    }

    private static let log = Logger(subsystem: AppIdentity.logSubsystem, category: "dockmenu")

    /// Tiefe, bis zu der Untermenues gelesen werden. "Optionen" ist eine
    /// Ebene, mehr hat Apples Dock-Menue nicht.
    private static let maximumDepth = 2

    /// Das Menue einer App, wie Apples Dock es zeigt. Leer, wenn es dieses
    /// Symbol dort nicht gibt oder das Menue nicht gelesen werden konnte.
    static func snapshot(bundleID: String) -> [Item] {
        guard let item = dockItem(bundleID: bundleID) else {
            log.notice("kein Dock-Symbol fuer \(bundleID, privacy: .public)")
            return []
        }
        guard AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success else {
            log.notice("AXShowMenu abgelehnt fuer \(bundleID, privacy: .public)")
            return []
        }
        defer { dismiss(item) }
        guard let menu = openMenu(of: item) else {
            log.notice("kein Menue nach AXShowMenu fuer \(bundleID, privacy: .public)")
            return []
        }
        let items = read(menu, path: [], depth: 0)
        log.notice("Apples Dock-Menue fuer \(bundleID, privacy: .public): \(items.count) Eintraege")
        return items
    }

    /// Fuehrt einen Eintrag aus: Apples Menue noch einmal oeffnen, den Weg
    /// ueber die Titel nachlaufen, druecken.
    static func press(path: [String], bundleID: String) -> Bool {
        guard !path.isEmpty, let item = dockItem(bundleID: bundleID),
              AXUIElementPerformAction(item, kAXShowMenuAction as CFString) == .success,
              let menu = openMenu(of: item)
        else { return false }
        var current = menu
        for (index, title) in path.enumerated() {
            let children = DockMenuAX.value(current, kAXChildrenAttribute) as? [AXUIElement] ?? []
            guard let match = children.first(where: { DockMenuAX.string($0, kAXTitleAttribute) == title }) else {
                dismiss(item)
                return false
            }
            if index == path.count - 1 {
                let pressed = AXUIElementPerformAction(match, kAXPressAction as CFString) == .success
                if !pressed { dismiss(item) }
                return pressed
            }
            // Untermenue: dessen Menue liegt als Kind des Eintrags.
            guard let submenu = (DockMenuAX.value(match, kAXChildrenAttribute) as? [AXUIElement])?.first else {
                dismiss(item)
                return false
            }
            current = submenu
        }
        dismiss(item)
        return false
    }

    // MARK: - Lesen

    private static func read(_ menu: AXUIElement, path: [String], depth: Int) -> [Item] {
        guard depth < maximumDepth else { return [] }
        let children = DockMenuAX.value(menu, kAXChildrenAttribute) as? [AXUIElement] ?? []
        return children.map { child in
            let title = DockMenuAX.string(child, kAXTitleAttribute) ?? ""
            let submenu = (DockMenuAX.value(child, kAXChildrenAttribute) as? [AXUIElement])?.first
            return Item(
                title: title,
                enabled: (DockMenuAX.value(child, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? true,
                mark: DockMenuAX.string(child, kAXMenuItemMarkCharAttribute) ?? "",
                // Apple meldet Trenner als Eintrag ohne Titel.
                separator: title.isEmpty && submenu == nil,
                children: submenu.map { read($0, path: path + [title], depth: depth + 1) } ?? [],
                path: path + [title]
            )
        }
    }

    /// Das Menue, das nach `AXShowMenu` als Kind des Symbols haengt. Der Dock
    /// baut es nicht sofort auf, deshalb ein paar kurze Versuche.
    private static func openMenu(of item: AXUIElement) -> AXUIElement? {
        for _ in 0..<20 {
            let children = DockMenuAX.value(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
            if let menu = children.first(where: { DockMenuAX.string($0, kAXRoleAttribute) == kAXMenuRole as String }) {
                return menu
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.01))
        }
        return nil
    }

    /// Apples Menue wieder schliessen. Ohne das bliebe es offen stehen.
    private static func dismiss(_ item: AXUIElement) {
        let children = DockMenuAX.value(item, kAXChildrenAttribute) as? [AXUIElement] ?? []
        for child in children where DockMenuAX.string(child, kAXRoleAttribute) == kAXMenuRole as String {
            AXUIElementPerformAction(child, kAXCancelAction as CFString)
        }
    }

    /// Das Symbol dieser App in Apples Dock - gefunden ueber die AXURL, wie
    /// schon bei den Zaehlern (`DockBadges`).
    private static func dockItem(bundleID: String) -> AXUIElement? {
        guard AXIsProcessTrusted(),
              let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first
        else { return nil }
        let app = AXUIElementCreateApplication(dock.processIdentifier)
        AXUIElementSetMessagingTimeout(app, 0.5)
        let lists = DockMenuAX.value(app, kAXChildrenAttribute) as? [AXUIElement] ?? []
        guard let list = lists.first(where: { DockMenuAX.string($0, kAXRoleAttribute) == kAXListRole as String }) else { return nil }
        for item in DockMenuAX.value(list, kAXChildrenAttribute) as? [AXUIElement] ?? [] {
            guard let url = DockMenuAX.value(item, kAXURLAttribute) as? URL,
                  Bundle(url: url)?.bundleIdentifier == bundleID
            else { continue }
            return item
        }
        return nil
    }
}

/// Dieselben zwei Lesezugriffe wie in SidebarDockInteraction, hier fuer
/// Apples Dock. Eigener Name, weil `AX` in WindowGuard schon vergeben ist.
private enum DockMenuAX {
    static func value(_ element: AXUIElement, _ attribute: String) -> CFTypeRef? {
        var value: CFTypeRef?
        return AXUIElementCopyAttributeValue(element, attribute as CFString, &value) == .success ? value : nil
    }

    static func string(_ element: AXUIElement, _ attribute: String) -> String? {
        value(element, attribute) as? String
    }
}

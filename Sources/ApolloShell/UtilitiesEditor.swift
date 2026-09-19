import ApolloShellCore
import SwiftUI

// MARK: - Wach halten (Nexus > Allgemein)

/// „Wach halten auch zugeklappt“ - frueher auf Nexus > Schnellaktionen, seit
/// dem globalen Bearbeitungsmodus auf Nexus > Allgemein (die Schnellaktionen-
/// Seite hatte nur noch diesen Schalter). Bewusst nicht im Popover der Karte
/// im Bearbeitungsmodus: der Schalter legt sofort eine Systemregel mit
/// Administrator-Frage an und liesse sich mit „Abbrechen“ nicht zuruecknehmen.
struct NexusKeepAwakeSection: View {
    @Bindable var store: ShellSettingsStore
    /// Liegt die Regel ohne Passwort fuer den Deckel-Teil auf diesem Mac?
    @State private var lidRuleInstalled = false
    @State private var removingLidRule = false

    /// Der Deckel-Teil braucht root (pmset disablesleep). Beim ersten
    /// Einschalten fragt macOS einmal nach einem Administrator und legt dabei
    /// die Regel ohne Passwort an - das soll man vorher lesen koennen, und
    /// man soll sie hier wieder loswerden.
    var body: some View {
        Section {
            NexusToggle(title: "Auch bei zugeklapptem Deckel",
                        subtitle: "Solange „Wach halten“ läuft, schläft der Mac auch zugeklappt nicht",
                        isOn: $store.settings.keepAwake.lidClosed)
            if lidRuleInstalled {
                LabeledContent {
                    Button("Entfernen …") { removeLidRule() }
                        .disabled(removingLidRule)
                } label: {
                    Text("Regel ohne Passwort")
                    Text("Erlaubt nur, diesen Ruhezustand ohne Passwort umzuschalten")
                }
            }
        } header: {
            Text("Wach halten")
        } footer: {
            Text("Braucht einmal Administratorrechte: Beim ersten Einschalten fragt macOS nach dem Passwort, und ApolloShell legt eine Regel an, die nur das Umschalten dieses Ruhezustands ohne Passwort erlaubt. Danach fragt niemand mehr. Wer ablehnt, bekommt „Wach halten“ nur aufgeklappt. Im Akkubetrieb endet es bei \(LidAwake.batteryFloor) % von selbst.")
        }
        // Die Regel entsteht im Hintergrund, sobald die Frage beantwortet
        // ist; solange die Seite offen ist, alle 2 s nachsehen (ein stat).
        .task {
            while !Task.isCancelled {
                lidRuleInstalled = LidAwakeRule.isInstalled
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func removeLidRule() {
        removingLidRule = true
        LidAwakeRule.remove { _ in
            removingLidRule = false
            lidRuleInstalled = LidAwakeRule.isInstalled
        }
    }
}

// MARK: - Vorschau-Modell

/// Festes Modell, das nichts liest und nichts schaltet - bis Task 7 fuer
/// `UtilitiesEditorPreview` (Nexus, entfernt), seither fuer die Karten
/// waehrend der Bearbeitung im Kontrollzentrum-Panel selbst
/// (`UtilitiesEditOverlay.swift`: `KeepAwakeCard`/`UtilitiesAudioCard` mit
/// abgeschalteter Bedienung). Neutrale Beispielgeraete.
@MainActor
enum UtilitiesEditorPreviewModel {
    static let model = UtilitiesModel.preview(
        keepAwakeSince: nil, wifiOn: true, micMuted: false, bluetoothOn: true, darkMode: true, nightShift: false,
        volume: 0.6,
        audioDevices: [
            UtilitiesAudioDevice(id: 1, name: "Lautsprecher", outputStreams: 1, inputStreams: 0,
                                 canBeDefaultOutput: true, canBeDefaultInput: false, hidden: false),
            UtilitiesAudioDevice(id: 2, name: "Mikrofon", outputStreams: 0, inputStreams: 1,
                                 canBeDefaultOutput: false, canBeDefaultInput: true, hidden: false),
        ],
        defaultOutput: 1, defaultInput: 2
    )
}

// MARK: - Texte und Farben

/// Name, Zeichen und Farbe eines Knopfs - fuer die Galerie
/// (`EditGallery.swift`) und die Bearbeitungsflaeche des Kontrollzentrums
/// (`UtilitiesEditOverlay.swift`). Bis Task 7 auch fuer Nexus' alten Baukasten
/// gebraucht (Raster, Optionen, Vorlagen-Rueckfrage) - der ist seither weg.
@MainActor
enum UtilitiesEditorText {
    /// Name im Raster: eigener Titel, sonst App-Name, Adresse oder Name des
    /// Kurzbefehls, sonst der Name der Art.
    static func title(_ entry: UtilitiesToggleEntry) -> String {
        let own: String? = switch entry.toggle {
        case .openApp(let o): nonEmpty(o.title) ?? BarApps.info(for: o.bundleID)?.name
        case .openLink(let o): nonEmpty(o.title) ?? UtilitiesLink.url(from: o.url).map(UtilitiesLink.displayText)
        case .runShortcut(let o): nonEmpty(o.title) ?? nonEmpty(o.name)
        default: nil
        }
        return own ?? entry.kind.title
    }

    /// Dasselbe Zeichen wie im Panel, ohne Zustand (WLAN immer "wifi").
    static func icon(_ entry: UtilitiesToggleEntry) -> UtilitiesToggleItem.Icon {
        let look: QuickToggleLook = switch entry.toggle {
        case .openApp(let o): QuickToggles.openApp(o, appName: BarApps.info(for: o.bundleID)?.name)
        case .openLink(let o): QuickToggles.openLink(o)
        case .runShortcut(let o): QuickToggles.runShortcut(o)
        default: QuickToggleLook(symbol: entry.kind.symbol, active: false, enabled: true, help: "")
        }
        return UtilitiesToggleItem.icon(for: entry.toggle, look: look)
    }

    private static func nonEmpty(_ text: String) -> String? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}

extension UtilitiesToggleGroup {
    /// Kachelfarbe in der Galerie und im Options-Popover.
    var tint: Color {
        switch self {
        case .switches: .blue
        case .actions: .indigo
        case .custom: .orange
        }
    }
}

/// Farbige Kachel wie `NexusTile`, aber mit dem Zeichen des Knopfs (auch
/// der Bluetooth-Rune und dem App-Symbol) - im Options-Popover
/// (`UtilitiesEditOverlay.swift`). Bis Task 7 auch in Nexus' altem Raster und
/// seiner Galerie gebraucht.
struct UtilitiesEditorGlyphTile: View {
    let icon: UtilitiesToggleItem.Icon
    let tint: Color
    var size: CGFloat = 24

    var body: some View {
        if case .app = icon {
            UtilitiesToggleGlyph(icon: icon, scale: size / 28)
                .frame(width: size, height: size)
                .accessibilityHidden(true)
        } else {
            RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
                .fill(tint.gradient)
                .frame(width: size, height: size)
                .overlay {
                    UtilitiesToggleGlyph(icon: icon, scale: size / 34)
                        .foregroundStyle(.white)
                }
                .accessibilityHidden(true)
        }
    }
}

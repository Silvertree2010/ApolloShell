import AppKit
import ApolloShellCore
import SwiftUI

/// Nexus > Updates: Stand, die beiden Schalter und "Jetzt prüfen".
///
/// Die Seite sieht in beiden Faellen gleich aus, zeigt aber je nach Herkunft
/// der Installation andere Knoepfe: Die DMG-Fassung erneuert sich selbst, die
/// Homebrew-Fassung bekommt den Befehl zum Kopieren (siehe `InstallKind`).
struct NexusUpdatesPage: View {
    @Bindable var store: ShellSettingsStore
    let updates: UpdateController

    var body: some View {
        NexusPageForm(page: .updates) {
            Section {
                LabeledContent("Installierte Fassung", value: NexusUpdatesPage.installedVersion)
                LabeledContent("Letzte Prüfung", value: lastCheck)
                NexusUpdateStatusRow(updates: updates)
            } header: {
                Text("Stand")
            }

            if updates.canUpdateItself {
                Section {
                    NexusToggle(title: "Automatisch nach Updates suchen",
                                subtitle: "Einmal täglich im Hintergrund",
                                isOn: $store.settings.updates.checkAutomatically)
                    NexusToggle(title: "Updates automatisch einspielen",
                                subtitle: "Beim Beenden, also spätestens beim nächsten Abmelden",
                                isOn: $store.settings.updates.installAutomatically)
                } header: {
                    Text("Automatik")
                } footer: {
                    Text("Beides ist ab Werk an. Ein Update tauscht die ganze Shell aus: Leiste, Dock und Fenster verschwinden kurz und kommen neu.")
                }
            } else {
                Section {
                    NexusToggle(title: "Automatisch nach Updates suchen",
                                subtitle: "Einmal täglich im Hintergrund",
                                isOn: $store.settings.updates.checkAutomatically)
                    LabeledContent("Aktualisieren") {
                        HStack(spacing: 8) {
                            Text(updates.upgradeCommand)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Kopieren") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(updates.upgradeCommand, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Homebrew")
                } footer: {
                    Text("Diese Installation gehört Homebrew. ApolloShell erneuert sich deshalb nicht selbst, sondern meldet nur, dass es etwas Neues gibt.")
                }
            }

            Section {
                Button("Jetzt prüfen") { updates.checkNow() }
                if updates.isReadyToInstall {
                    Button("Jetzt neu starten") { updates.installNowIfReady() }
                }
            } footer: {
                Text("Alle Fassungen stehen auf der Releases-Seite.")
            }

            Section {
                Link("Releases auf GitHub",
                     destination: URL(string: "https://github.com/Silvertree2010/ApolloShell/releases")!)
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .onChange(of: store.settings.updates) { updates.applySettings() }
        .onAppear { updates.checkInBackgroundIfDue() }
    }

    /// "0.1.2 (41)"; ohne Bundle (swift run) ein Gedankenstrich.
    static var installedVersion: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String
        switch (short, build) {
        case let (short?, build?): return "\(short) (\(build))"
        case let (short?, nil): return short
        default: return "–"
        }
    }

    private var lastCheck: String {
        guard let date = updates.lastCheck else { return String(localized: "noch nie") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Eine Zeile, die den Stand der letzten Pruefung in Worte fasst.
private struct NexusUpdateStatusRow: View {
    let updates: UpdateController

    var body: some View {
        switch updates.status {
        case .idle:
            LabeledContent("Stand", value: String(localized: "Noch nicht geprüft"))
        case .checking:
            LabeledContent("Stand") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Wird geprüft …")
                }
            }
        case .upToDate:
            LabeledContent("Stand", value: String(localized: "Aktuell"))
        case let .found(version, page):
            LabeledContent(String(localized: "Neue Fassung")) {
                HStack(spacing: 8) {
                    Text(version)
                    if let page { Link("Notizen", destination: page).controlSize(.small) }
                }
            }
        case let .ready(version):
            LabeledContent(String(localized: "Bereit"), value: String(localized: "\(version) wird beim Beenden eingespielt"))
        case let .failed(message):
            LabeledContent(String(localized: "Fehlgeschlagen"), value: message)
        case .unavailable:
            LabeledContent("Stand", value: String(localized: "Diese Fassung kann sich nicht selbst erneuern"))
        }
    }
}

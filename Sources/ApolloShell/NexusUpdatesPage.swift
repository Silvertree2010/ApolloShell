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
                LabeledContent("Installed version", value: NexusUpdatesPage.installedVersion)
                LabeledContent("Last check", value: lastCheck)
                NexusUpdateStatusRow(updates: updates)
            } header: {
                Text("Status")
            }

            if updates.canUpdateItself {
                Section {
                    NexusToggle(title: "Check for updates automatically",
                                subtitle: "Once a day in the background",
                                isOn: $store.settings.updates.checkAutomatically)
                    NexusToggle(title: "Install updates automatically",
                                subtitle: "When you quit, so at the latest when you next log out",
                                isOn: $store.settings.updates.installAutomatically)
                } header: {
                    Text("Automatic")
                } footer: {
                    Text("Both are on by default. An update replaces the whole shell: the bar, the dock and the windows disappear for a moment and come back.")
                }
            } else {
                Section {
                    NexusToggle(title: "Check for updates automatically",
                                subtitle: "Once a day in the background",
                                isOn: $store.settings.updates.checkAutomatically)
                    LabeledContent("Upgrade") {
                        HStack(spacing: 8) {
                            Text(updates.upgradeCommand)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                            Button("Copy") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(updates.upgradeCommand, forType: .string)
                            }
                            .controlSize(.small)
                        }
                    }
                } header: {
                    Text("Homebrew")
                } footer: {
                    Text("This copy belongs to Homebrew, so ApolloShell does not replace itself. It only says when there is something new.")
                }
            }

            Section {
                Button("Check now") { updates.checkNow() }
                if updates.isReadyToInstall {
                    Button("Restart now") { updates.installNowIfReady() }
                }
            } footer: {
                Text("Every version is on the releases page.")
            }

            Section {
                Link("Releases on GitHub",
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
        guard let date = updates.lastCheck else { return String(localized: "never") }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}

/// Eine Zeile, die den Stand der letzten Pruefung in Worte fasst.
private struct NexusUpdateStatusRow: View {
    let updates: UpdateController

    var body: some View {
        switch updates.status {
        case .idle:
            LabeledContent("Status", value: String(localized: "Not checked yet"))
        case .checking:
            LabeledContent("Status") {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking…")
                }
            }
        case .upToDate:
            LabeledContent("Status", value: String(localized: "Up to date"))
        case let .found(version, page):
            LabeledContent(String(localized: "New version")) {
                HStack(spacing: 8) {
                    Text(version)
                    if let page { Link("Notes", destination: page).controlSize(.small) }
                }
            }
        case let .ready(version):
            LabeledContent(String(localized: "Ready"), value: String(localized: "\(version) will be installed when you quit"))
        case let .failed(message):
            LabeledContent(String(localized: "Failed"), value: message)
        case .unavailable:
            LabeledContent("Status", value: String(localized: "This build cannot update itself"))
        }
    }
}

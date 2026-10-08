import AppKit
import ApolloShellCore
import SwiftUI

/// Nexus > Updates: Stand, die beiden Schalter und "Check now".
///
/// Die Seite sieht in beiden Faellen gleich aus, zeigt aber je nach Herkunft
/// der Installation andere Knoepfe: Die DMG-Fassung erneuert sich selbst, die
/// Homebrew-Fassung bekommt den Befehl zum Kopieren (siehe `InstallKind`).
struct NexusUpdatesPage: View {
    @Bindable var store: ShellSettingsStore
    let updates: UpdateController

    var body: some View {
        Group {
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
                                isOn: $store.settings.updates.checkAutomatically)
                    NexusToggle(title: "Install updates automatically",
                                tip: "When you quit, at the latest when you next log out. The bar and windows disappear for a moment during the update.",
                                isOn: $store.settings.updates.installAutomatically)
                } header: {
                    Text("Automatic")
                }
            } else {
                Section {
                    NexusToggle(title: "Check for updates automatically",
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
                    NexusTipHeader(title: "Homebrew", tip: "This copy belongs to Homebrew, so it does not replace itself. It only tells you about new versions.")
                }
            }

            Section {
                Picker("Send crash reports", selection: $store.settings.crashReports.mode) {
                    Text("Ask each time").tag(CrashReportSettings.Mode.ask)
                    Text("Always").tag(CrashReportSettings.Mode.always)
                    Text("Never").tag(CrashReportSettings.Mode.never)
                }
            } header: {
                NexusTipHeader(title: "Crash reports", tip: "Sends the ApolloShell and macOS versions, the Mac model and where in the code it crashed. No files, names or device IDs.")
            }

            Section {
                Button("Check now") { updates.checkNow() }
                if updates.isReadyToInstall {
                    Button("Restart now") { updates.installNowIfReady() }
                }
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

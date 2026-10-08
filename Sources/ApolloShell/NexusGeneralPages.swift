import AppKit
import ApolloShellCore
import SwiftUI

// Die Seiten "General" und "Keyboard Shortcuts" - was jemand einstellen muss,
// der die Shell zum ersten Mal auf seinem Mac hat.

/// Allgemein: Sprache, Start bei der Anmeldung und die Freigaben.
struct NexusGeneralPage: View {
    static let watcher = "nexus"

    @Bindable var store: ShellSettingsStore
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    var providers: NexusProvidersModel?

    var body: some View {
        NexusPageForm(page: .general) {
            Section {
                OnboardingAutostartToggle(model: autostart, caption: false)
            } header: {
                Text("Start")
            } footer: {
                if let note = autostart.state.note { Text(note) }
            }
            Section {
                NexusToggle(title: "Hide Apple's Dock while ApolloShell is running",
                            tip: "If ApolloShell is force-quit, Apple's Dock stays hidden until ApolloShell starts and quits normally again.",
                            isOn: $store.settings.appleDockHiding.hideWhileRunning)
            }
            Section {
                OnboardingAccessibilityRow(permissions: permissions)
                OnboardingSystemEventsRow()
            } header: {
                Text("Permissions")
            }
            if let providers { NexusFileManagerSection(store: store, model: providers) }
        }
        .animation(.snappy, value: permissions.accessibility)
        .onAppear {
            autostart.refresh()
            permissions.watch(true, by: Self.watcher)
        }
        .onDisappear { permissions.watch(false, by: Self.watcher) }
    }
}

/// Haelt die Sprachwahl (UserDefaults der App) und stoesst den Neustart an.
/// Restarting ApolloShell - the decision how is in `AppRestart`
/// (ApolloShellCore, tested), here only the doing.
@MainActor
@Observable
final class AppRestartModel {
/// Startet ApolloShell neu - ueber den eigenen launchd-Agenten, wenn es
    /// einen gibt (sonst liefe die App danach doppelt), sonst durch einen
    /// Hilfsprozess, der kurz wartet und das Bundle neu oeffnet.
    func restart() {
        let plan = AppRestart.plan(environment: ProcessInfo.processInfo.environment, bundlePath: Bundle.main.bundlePath)
        switch plan {
        case .launchd(let label):
            Subprocess.launch("/usr/bin/launchctl", AppRestart.launchctlArguments(label: label, uid: Int32(getuid())))
        case .relaunch(let bundlePath):
            Subprocess.launch("/bin/sh", AppRestart.relaunchArguments(bundlePath: bundlePath))
            NSApp.terminate(nil)
        }
    }
}

/// Tastenkürzel: die vier globalen Kuerzel mit Aufnahmefeld, dazu Vorlagen.
struct NexusHotKeysPage: View {
    @Bindable var store: ShellSettingsStore
    let center: HotKeyCenter

    var body: some View {
        NexusPageForm(page: .hotKeys) {
            Section {
                ForEach(HotKeyAction.allCases) { action in
                    HotKeyRow(center: center, store: store, action: action, tint: NexusPage.hotKeys.tint)
                }
            } header: {
                NexusTipHeader(title: "Global", tip: "Click a field and press the new combination. ⎋ cancels, ⌫ removes the shortcut.")
            }
            Section {
                HStack(spacing: 8) {
                    Menu("Load Preset…") {
                        Button("Default – \(Self.summary(.firstLaunch))") { store.settings.hotKeys = .firstLaunch }
                        Button("Hyper Key – \(Self.summary(.existingInstall))") { store.settings.hotKeys = .existingInstall }
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                }
            } header: {
                NexusTipHeader(title: "Presets", tip: "“Hyper Key” suits tools like Karabiner-Elements that turn a free key into F20 or ⌃⌥⇧⌘.")
            }
            NexusRestoreSection(title: "Restore Default Shortcuts",
                                message: "All shortcuts go back to their defaults.") {
                store.settings.hotKeys = .firstLaunch
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .onDisappear { center.cancelRecording() }
    }

    private static func summary(_ hotKeys: HotKeySettings) -> String {
        HotKeyAction.allCases.compactMap { hotKeys[$0].map(HotKeyKeyboard.display) }.joined(separator: ", ")
    }
}

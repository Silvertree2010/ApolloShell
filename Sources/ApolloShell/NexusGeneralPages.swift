import AppKit
import ApolloShellCore
import SwiftUI

// Die Seiten "Allgemein" und "Tastenkürzel" - was jemand einstellen muss,
// der die Shell zum ersten Mal auf seinem Mac hat.

/// Allgemein: Start bei der Anmeldung und die Freigaben.
struct NexusGeneralPage: View {
    static let watcher = "nexus"

    @Bindable var store: ShellSettingsStore
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions

    var body: some View {
        NexusPageForm(page: .general) {
            Section {
                OnboardingAutostartToggle(model: autostart)
            } header: {
                Text("Start")
            } footer: {
                if let note = autostart.state.note { Text(note) }
            }
            Section {
                NexusToggle(title: "Hide Apple's Dock while ApolloShell is running",
                            isOn: $store.settings.appleDockHiding.hideWhileRunning)
            } footer: {
                Text("The bar's own Dock is unaffected. A SIGKILL leaves Apple's Dock hidden until ApolloShell starts and ends normally again.")
            }
            NexusKeepAwakeSection(store: store)
            Section {
                OnboardingAccessibilityRow(permissions: permissions)
                OnboardingSystemEventsRow()
            } header: {
                Text("Permissions")
            } footer: {
                Text("Both can be revoked at any time under Privacy & Security.")
            }
        }
        .animation(.snappy, value: permissions.accessibility)
        .onAppear {
            autostart.refresh()
            permissions.watch(true, by: Self.watcher)
        }
        .onDisappear { permissions.watch(false, by: Self.watcher) }
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
                Text("Global")
            } footer: {
                Text("Apply in any app, immediately. To change, click the field and press the new combination – ⎋ cancels, ⌫ removes the shortcut. Spotlight stays on ⌘Space.")
            }
            Section {
                HStack(spacing: 8) {
                    Menu("Vorlage laden …") {
                        Button("Default – \(Self.summary(.firstLaunch))") { store.settings.hotKeys = .firstLaunch }
                        Button("Hyper Key – \(Self.summary(.existingInstall))") { store.settings.hotKeys = .existingInstall }
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("“Hyper Key” fits keyboard tools like Karabiner-Elements that turn a free key into F20, or held into ⌃⌥⇧⌘.")
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .onDisappear { center.cancelRecording() }
    }

    private static func summary(_ hotKeys: HotKeySettings) -> String {
        HotKeyAction.allCases.compactMap { hotKeys[$0].map(HotKeyKeyboard.display) }.joined(separator: ", ")
    }
}

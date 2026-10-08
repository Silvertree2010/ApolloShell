import AppKit
import ApolloShellCore
import SwiftUI
import UniformTypeIdentifiers

struct NexusRestoreSection: View {
    let title: LocalizedStringKey
    let message: LocalizedStringKey
    let action: () -> Void
    @State private var ask = false

    var body: some View {
        Section {
            Button(title, role: .destructive) { ask = true }
        }
        .alert(title, isPresented: $ask) {
            Button("Restore", role: .destructive, action: action)
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(message)
        }
    }
}

struct NexusAdvancedSections: View {
    @Bindable var store: ShellSettingsStore
    @State private var lo = LauncherOnlyFlag.isOn { UserDefaults.standard.object(forKey: $0) }
    @State private var startLo = LauncherOnlyFlag.isOn { UserDefaults.standard.object(forKey: $0) }
    @State private var pendingImport: ShellSettings?
    @State private var importFailed = false
    @State private var askReset = false

    var body: some View {
        Section {
            NexusToggle(title: "Launcher Only", subtitle: "Only the launcher runs: no bar, Dashboard, Quick Actions or toasts",
                        isOn: Binding(get: { lo }, set: { v in
                            lo = v
                            UserDefaults.standard.set(v, forKey: LauncherOnlyFlag.key)
                            UserDefaults.standard.removeObject(forKey: LauncherOnlyFlag.legacyKey)
                        }))
            if lo != startLo {
                HStack {
                    Text("Takes effect after a restart.")
                        .foregroundStyle(.secondary)
                    Spacer()
                    Button("Restart Now") { AppRestartModel().restart() }
                }
            }
        } header: {
            Text("Advanced")
        }
        Section {
            Button("Export Settings…") { export() }
            Button("Import Settings…") { pick() }
        } header: {
            Text("Backup")
        } footer: {
            Text("A JSON file with every setting, for a backup or another Mac. Themes and pinned launcher apps are not included.")
        }
        Section {
            Button("Reset All Settings…", role: .destructive) { askReset = true }
        } footer: {
            Text("Bar, Dashboard, Quick Actions, shortcuts, toasts and everything else go back to their defaults. The introduction is not shown again.")
        }
        .alert("Reset all settings?", isPresented: $askReset) {
            Button("Reset All", role: .destructive) { store.settings = store.settings.restored }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone. Export your settings first if you might want them back.")
        }
        .alert("Import these settings?", isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } })) {
            Button("Import", role: .destructive) {
                if let s = pendingImport { store.settings = s }
                pendingImport = nil
            }
            Button("Cancel", role: .cancel) { pendingImport = nil }
        } message: {
            Text("Your current settings are replaced.")
        }
        .alert("Not a settings file", isPresented: $importFailed) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("The file could not be read as ApolloShell settings.")
        }
    }

    private func export() {
        let p = NSSavePanel()
        p.allowedContentTypes = [.json]
        p.nameFieldStringValue = "ApolloShell Settings.json"
        NSApp.activate()
        guard p.runModal() == .OK, let url = p.url else { return }
        try? store.settings.encoded().write(to: url, options: .atomic)
    }

    private func pick() {
        let p = NSOpenPanel()
        p.allowedContentTypes = [.json]
        p.allowsMultipleSelection = false
        NSApp.activate()
        guard p.runModal() == .OK, let url = p.url else { return }
        if let d = try? Data(contentsOf: url), let s = ShellSettings.importing(d) {
            pendingImport = s
        } else {
            importFailed = true
        }
    }
}

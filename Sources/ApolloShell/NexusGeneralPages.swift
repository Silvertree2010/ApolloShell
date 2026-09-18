import AppKit
import ApolloShellCore
import SwiftUI

// Die Seiten "Allgemein" und "Tastenkürzel" - was jemand einstellen muss,
// der die Shell zum ersten Mal auf seinem Mac hat.

/// Allgemein: Sprache, Start bei der Anmeldung und die Freigaben.
struct NexusGeneralPage: View {
    static let watcher = "nexus"

    @Bindable var store: ShellSettingsStore
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    @State private var language = LanguagePreferenceModel()

    var body: some View {
        NexusPageForm(page: .general) {
            Section {
                LanguagePicker(model: language)
            } header: {
                Text("Sprache")
            } footer: {
                Text("Gilt nach einem Neustart von ApolloShell.")
            }
            Section {
                OnboardingAutostartToggle(model: autostart)
            } header: {
                Text("Start")
            } footer: {
                if let note = autostart.state.note { Text(note) }
            }
            Section {
                NexusToggle(title: "Apple-Dock ausblenden, solange ApolloShell läuft",
                            isOn: $store.settings.appleDockHiding.hideWhileRunning)
            } footer: {
                Text("Das eigene Dock der Leiste bleibt davon unberührt. Ein Abbruch per SIGKILL lässt Apples Dock versteckt, bis ApolloShell wieder normal startet und endet.")
            }
            Section {
                OnboardingAccessibilityRow(permissions: permissions)
                OnboardingSystemEventsRow()
            } header: {
                Text("Freigaben")
            } footer: {
                Text("Beide lassen sich jederzeit unter Datenschutz & Sicherheit widerrufen.")
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

/// Haelt die Sprachwahl (UserDefaults der App) und stoesst den Neustart an.
/// Die Entscheidung, wie neu gestartet wird, steht in `AppRestart`
/// (ApolloShellCore, getestet); hier nur das Ausfuehren.
@MainActor
@Observable
final class LanguagePreferenceModel {
    var language: AppLanguage {
        didSet {
            guard language != oldValue else { return }
            if let codes = language.appleLanguages {
                defaults.set(codes, forKey: AppLanguage.defaultsKey)
            } else {
                defaults.removeObject(forKey: AppLanguage.defaultsKey)
            }
        }
    }

    @ObservationIgnored private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        language = AppLanguage(appleLanguages: defaults.array(forKey: AppLanguage.defaultsKey) as? [String])
    }

    /// Startet ApolloShell neu - ueber den eigenen launchd-Agenten, wenn es
    /// einen gibt (sonst liefe die App danach doppelt), sonst durch einen
    /// Hilfsprozess, der kurz wartet und das Bundle neu oeffnet.
    func restart() {
        let plan = AppRestart.plan(environment: ProcessInfo.processInfo.environment, bundlePath: Bundle.main.bundlePath)
        switch plan {
        case .launchd(let label):
            Subprocess.launch("/usr/bin/launchctl", AppRestart.launchctlArguments(label: label, uid: Int32(getuid())))
        case .relaunch(let bundlePath):
            Subprocess.launch("/bin/sh", ["-c", AppRestart.relaunchCommand(bundlePath: bundlePath)])
            NSApp.terminate(nil)
        }
    }
}

/// Picker "System / Deutsch / English" plus Knopf zum Neustarten.
/// Sprachnamen sind Eigennamen (wie bei Apples eigener Sprachwahl) und bleiben
/// in jeder Sprache gleich - deshalb `Text(verbatim:)` statt eines
/// Uebersetzungsschluessels.
struct LanguagePicker: View {
    @Bindable var model: LanguagePreferenceModel

    var body: some View {
        Picker(selection: $model.language) {
            ForEach(AppLanguage.allCases) { option in
                Text(verbatim: title(for: option)).tag(option)
            }
        } label: {
            Text("Sprache")
        }
        Button("Jetzt neu starten") { model.restart() }
    }

    private func title(for language: AppLanguage) -> String {
        switch language {
        case .system: "System"
        case .german: "Deutsch"
        case .english: "English"
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
                Text("Global")
            } footer: {
                Text("Gelten in jeder App und sofort. Zum Ändern ins Feld klicken und die neue Kombination drücken – ⎋ bricht ab, ⌫ entfernt das Kürzel. Spotlight bleibt auf ⌘Space.")
            }
            Section {
                HStack(spacing: 8) {
                    Menu("Vorlage laden …") {
                        Button("Standard – \(Self.summary(.firstLaunch))") { store.settings.hotKeys = .firstLaunch }
                        Button("Hyper-Taste – \(Self.summary(.existingInstall))") { store.settings.hotKeys = .existingInstall }
                    }
                    .fixedSize()
                    Spacer(minLength: 8)
                }
            } header: {
                Text("Vorlagen")
            } footer: {
                Text("„Hyper-Taste“ passt zu Tastatur-Werkzeugen wie Karabiner-Elements, die eine freie Taste zu F20 oder gehalten zu ⌃⌥⇧⌘ machen.")
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
        .onDisappear { center.cancelRecording() }
    }

    private static func summary(_ hotKeys: HotKeySettings) -> String {
        HotKeyAction.allCases.compactMap { hotKeys[$0].map(HotKeyKeyboard.display) }.joined(separator: ", ")
    }
}

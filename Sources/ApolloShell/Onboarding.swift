import AppKit
import ApolloShellCore
import Observation
import SwiftUI

/// Einfuehrung beim ersten Start: was ApolloShell ist, die Freigaben, das
/// Launcher-Kuerzel, Autostart. Erscheint von selbst nur bei frischen
/// Installationen (`OnboardingRule`), sonst ueber Nexus > Über.
///
/// Ein normales Fenster in der Bildschirmmitte, wie Nexus: Die App ist eine
/// Accessory-App und nie aktiv - ohne `NSApp.activate()` bekaeme das Fenster
/// keine Tastatur (Aufnahmefeld, Enter fuer "Weiter"). Beim Schliessen
/// bekommt die vorher vordere App den Fokus zurueck.
///
/// Schliessen (Knopf, ⌘W), "Überspringen" und "Fertig" zaehlen gleich:
/// erledigt. Wer sie wieder will, findet sie in Nexus. Beenden der App zaehlt
/// NICHT - wer mittendrin beendet, sieht sie beim naechsten Start wieder
/// (sonst fragte danach nur noch macOS' nackte Bedienungshilfen-Abfrage).
/// Deshalb markiert `windowShouldClose` (nur bei Schliessen durch den Nutzer)
/// und nicht `windowWillClose` (kommt auch beim Beenden).
@MainActor
final class Onboarding: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 620, height: 560)
    private static let watcher = "onboarding"

    private let state = OnboardingState()
    private let settings: ShellSettingsStore
    private let hotKeys: HotKeyCenter
    private let autostart: OnboardingAutostartModel
    private let permissions: OnboardingPermissions
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?

    init(settings: ShellSettingsStore, hotKeys: HotKeyCenter, autostart: OnboardingAutostartModel,
         permissions: OnboardingPermissions) {
        self.settings = settings
        self.hotKeys = hotKeys
        self.autostart = autostart
        self.permissions = permissions
        super.init()
    }

    func show() {
        let window = self.window ?? makeWindow()
        if !window.isVisible {
            state.step = .welcome
            autostart.refresh()
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            window.center()
        }
        permissions.watch(true, by: Self.watcher)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow() -> NSWindow {
        // NexusWindow: kennt ⌘W und die Bearbeitungs-Kuerzel ohne Menueleiste.
        let window = NexusWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Einführung")
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isMovableByWindowBackground = true
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.delegate = self
        let view = OnboardingView(state: state, store: settings, hotKeys: hotKeys, autostart: autostart,
                                  permissions: permissions) { [weak self, weak window] in
            self?.markCompleted()
            window?.close()
        }
        window.contentViewController = NSHostingController(rootView: view)
        window.setContentSize(Self.size)
        self.window = window
        return window
    }

    /// Nur wenn der Nutzer schliesst (Knopf, ⌘W ueber performClose), nicht
    /// bei `close()` oder beim Beenden der App.
    func windowShouldClose(_ sender: NSWindow) -> Bool {
        markCompleted()
        return true
    }

    func windowWillClose(_ notification: Notification) {
        hotKeys.cancelRecording()
        permissions.watch(false, by: Self.watcher)
        previousApp?.activate()
        previousApp = nil
    }

    private func markCompleted() {
        if !settings.settings.onboarding.completed { settings.settings.onboarding.completed = true }
    }
}

@MainActor
@Observable
final class OnboardingState {
    var step: OnboardingStep = .welcome
}

/// Die Einfuehrung selbst: ein Schritt pro Seite, unten Überspringen, Punkte,
/// Zurück und Weiter - ruhig wie der Einrichtungsassistent von macOS.
struct OnboardingView: View {
    @Bindable var state: OnboardingState
    let store: ShellSettingsStore
    let hotKeys: HotKeyCenter
    let autostart: OnboardingAutostartModel
    let permissions: OnboardingPermissions
    let onFinish: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .top) {
                page(state.step)
                    .id(state.step)
                    .transition(.opacity)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 44)
            .padding(.top, 40)
            footer
        }
        .frame(width: Onboarding.size.width, height: Onboarding.size.height)
        .animation(.easeInOut(duration: 0.2), value: state.step)
    }

    @ViewBuilder private func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: OnboardingWelcomePage()
        case .permissions: OnboardingPermissionsPage(permissions: permissions)
        case .hotKeys: OnboardingHotKeysPage(store: store, hotKeys: hotKeys)
        case .finish: OnboardingFinishPage(store: store, autostart: autostart)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !state.step.isLast {
                Button("Überspringen", action: onFinish)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let previous = state.step.previous {
                Button("Zurück") { state.step = previous }
                    .controlSize(.large)
            }
            Button {
                if let next = state.step.next { state.step = next } else { onFinish() }
            } label: {
                Text(state.step.primaryButton)
                    .frame(minWidth: 72)
            }
            .controlSize(.large)
            // Ausdruecklich hervorgehoben: der Standardknopf bekaeme die
            // Akzentfarbe sonst nur, solange das Fenster Schluesselfenster ist.
            .buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
        }
        .overlay { OnboardingDots(current: state.step) }
        .padding(.horizontal, 24)
        .padding(.vertical, 20)
    }
}

/// Punkte fuer die Schritte, der aktuelle kraeftiger.
struct OnboardingDots: View {
    let current: OnboardingStep

    var body: some View {
        HStack(spacing: 7) {
            ForEach(OnboardingStep.allCases) { step in
                Circle()
                    .fill(Color.primary.opacity(step == current ? 0.7 : 0.18))
                    .frame(width: 7, height: 7)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Schritt \(current.rawValue + 1) von \(OnboardingStep.allCases.count)")
    }
}

/// Kopf jeder Seite: Kachel, Titel, ein bis zwei Saetze.
struct OnboardingHeader: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String

    var body: some View {
        VStack(spacing: 10) {
            NexusTile(symbol: symbol, tint: tint, size: 60)
                .padding(.bottom, 4)
            Text(title)
                .font(.title.weight(.bold))
            Text(text)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 460)
        }
        .frame(maxWidth: .infinity)
    }
}

/// Gruppierte Flaeche wie ein Abschnitt der Systemeinstellungen.
struct OnboardingCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.primary.opacity(0.045)))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(Color.primary.opacity(0.08)))
    }
}

/// Graue Fussnote unter einer Karte.
struct OnboardingFootnote: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 4)
    }
}

// MARK: - Seiten

struct OnboardingWelcomePage: View {
    private let features: [(symbol: String, tint: Color, title: String, text: String)] = [
        ("sidebar.left", .blue, String(localized: "Leiste"), String(localized: "Spaces, Dock, Uhr und Status am linken Rand")),
        ("magnifyingglass", .purple, "Launcher", String(localized: "Apps suchen und öffnen – mit einem Tastenkürzel")),
        ("square.grid.2x2.fill", .indigo, "Dashboard", String(localized: "Wetter, Kalender, Medien und Leistung")),
        ("slider.horizontal.3", .green, String(localized: "Schnellaktionen"), String(localized: "Wach halten, Ton und Schnellschalter unten rechts")),
    ]

    var body: some View {
        VStack(spacing: 26) {
            OnboardingHeader(
                symbol: "sidebar.left", tint: .indigo, title: OnboardingStep.welcome.title,
                text: String(localized: "Eine Desktop-Shell für macOS nach dem Vorbild von Caelestia. Sie ergänzt den Mac, statt ihn zu ersetzen – alles lässt sich in Nexus einstellen.")
            )
            VStack(alignment: .leading, spacing: 16) {
                ForEach(features, id: \.title) { feature in
                    HStack(spacing: 14) {
                        Image(systemName: feature.symbol)
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(feature.tint)
                            .frame(width: 34)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(feature.title)
                                .fontWeight(.semibold)
                            Text(feature.text)
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: 400, alignment: .leading)
        }
    }
}

struct OnboardingPermissionsPage: View {
    let permissions: OnboardingPermissions

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "hand.raised.fill", tint: .blue, title: OnboardingStep.permissions.title,
                text: String(localized: "Zwei Freigaben von macOS. Beide lassen sich jederzeit unter Datenschutz & Sicherheit widerrufen.")
            )
            VStack(spacing: 8) {
                OnboardingCard {
                    OnboardingAccessibilityRow(permissions: permissions)
                    Divider()
                    OnboardingSystemEventsRow()
                }
                OnboardingFootnote(text: String(localized: "Ohne Bedienungshilfen läuft alles andere trotzdem; die Leiste bleibt dann auch im Vollbild sichtbar, und Fenster können unter sie rutschen."))
            }
        }
        .animation(.snappy, value: permissions.accessibility)
    }
}

struct OnboardingHotKeysPage: View {
    let store: ShellSettingsStore
    let hotKeys: HotKeyCenter

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "command", tint: .purple, title: OnboardingStep.hotKeys.title,
                text: String(localized: "Der Launcher öffnet mit einem Kürzel, in jeder App. Zum Ändern ins Feld klicken und die neue Kombination drücken.")
            )
            VStack(spacing: 8) {
                OnboardingCard {
                    HotKeyRow(center: hotKeys, store: store, action: .launcher)
                }
                OnboardingCard {
                    ForEach([HotKeyAction.dashboard, .utilities, .nexus]) { action in
                        HStack {
                            Text(action.title)
                            Spacer()
                            Text(store.settings.hotKeys[action].map(HotKeyKeyboard.display) ?? HotKeyText.none)
                                .foregroundStyle(.secondary)
                        }
                        .font(.callout)
                    }
                }
                OnboardingFootnote(text: String(localized: "Spotlight bleibt auf ⌘Space. Alle Kürzel lassen sich in Nexus unter „Tastenkürzel“ ändern oder entfernen."))
            }
        }
    }
}

struct OnboardingFinishPage: View {
    let store: ShellSettingsStore
    let autostart: OnboardingAutostartModel

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "checkmark", tint: .green, title: OnboardingStep.finish.title,
                text: settingsHint
            )
            VStack(spacing: 8) {
                OnboardingCard {
                    OnboardingAutostartToggle(model: autostart)
                }
                if let note = autostart.state.note {
                    OnboardingFootnote(text: note)
                }
                OnboardingFootnote(text: String(localized: "Diese Einführung ist unter Nexus › Über jederzeit wieder da."))
            }
        }
    }

    private var settingsHint: String {
        guard let key = store.settings.hotKeys.nexus else {
            return String(localized: "Einstellungen gibt es in Nexus – über das Zahnrad im Panel Schnellaktionen.")
        }
        return String(localized: "Einstellungen gibt es in Nexus – mit \(HotKeyKeyboard.display(key)) oder über das Zahnrad im Panel Schnellaktionen.")
    }
}

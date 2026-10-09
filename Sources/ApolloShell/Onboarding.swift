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
/// keine Tastatur (Aufnahmefeld, Enter fuer "Continue"). Beim Schliessen
/// bekommt die vorher vordere App den Fokus zurueck.
///
/// Schliessen (Knopf, ⌘W), "Skip" und "Done" zaehlen gleich:
/// erledigt. Wer sie wieder will, findet sie in Nexus. Beenden der App zaehlt
/// NICHT - wer mittendrin beendet, sieht sie beim naechsten Start wieder
/// (sonst fragte danach nur noch macOS' nackte Bedienungshilfen-Abfrage).
/// Deshalb markiert `windowShouldClose` (nur bei Schliessen durch den Nutzer)
/// und nicht `windowWillClose` (kommt auch beim Beenden).
@MainActor
final class Onboarding: NSObject, NSWindowDelegate {
    static let size = NSSize(width: 680, height: 600)
    private static let watcher = "onboarding"

    private let state = OnboardingState()
    private let settings: ShellSettingsStore
    private let hotKeys: HotKeyCenter
    private let autostart: OnboardingAutostartModel
    private let permissions: OnboardingPermissions
    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    var onComplete: () -> Void = {}

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
            state.fwd = true
            state.step = .welcome
            state.first = !settings.settings.onboarding.completed
            autostart.refresh()
            let front = NSWorkspace.shared.frontmostApplication
            previousApp = front?.processIdentifier == ProcessInfo.processInfo.processIdentifier ? nil : front
            window.center()
        }
        permissions.watch(true, by: Self.watcher)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        window.orderFrontRegardless()
    }

    private func makeWindow() -> NSWindow {
        // NexusWindow: kennt ⌘W und die Bearbeitungs-Kuerzel ohne Menueleiste.
        let window = NexusWindow(
            contentRect: NSRect(origin: .zero, size: Self.size),
            styleMask: [.titled, .closable, .fullSizeContentView],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Introduction")
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
        // Auch die Einfuehrung folgt dem Theme (Farbton und Flaeche).
        window.contentViewController = NSHostingController(rootView: view.shellTheme())
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
        guard !settings.settings.onboarding.completed else { return }
        settings.settings.onboarding.completed = true
        onComplete()
    }
}

@MainActor
@Observable
final class OnboardingState {
    var step: OnboardingStep = .welcome
    var fwd = true
    var first = false

    func go(_ s: OnboardingStep) {
        fwd = s.rawValue > step.rawValue
        step = s
    }
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
                    .padding(.horizontal, 44)
                    .transition(.asymmetric(
                        insertion: .offset(x: state.fwd ? 40 : -40).combined(with: .opacity),
                        removal: .offset(x: state.fwd ? -40 : 40).combined(with: .opacity)
                    ))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.top, 40)
            .clipped()
            footer
        }
        .frame(width: Onboarding.size.width, height: Onboarding.size.height)
        .animation(.smooth(duration: 0.32), value: state.step)
    }

    @ViewBuilder private func page(_ step: OnboardingStep) -> some View {
        switch step {
        case .welcome: OnboardingWelcomePage()
        case .permissions: OnboardingPermissionsPage(permissions: permissions)
        case .hotKeys: OnboardingHotKeysPage(store: store, hotKeys: hotKeys)
        case .finish: OnboardingFinishPage(store: store, autostart: autostart, first: state.first)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            if !state.step.isLast {
                Button("Skip", action: onFinish)
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if let previous = state.step.previous {
                Button("Back") { state.go(previous) }
                    .controlSize(.large)
                    .keyboardShortcut(.leftArrow, modifiers: .command)
            }
            Button {
                if let next = state.step.next { state.go(next) } else { onFinish() }
            } label: {
                Text(state.step.isLast && state.first ? String(localized: "Start ApolloShell") : state.step.primaryButton)
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
        .accessibilityLabel("Step \(current.rawValue + 1) of \(OnboardingStep.allCases.count)")
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

    @Environment(\.shellStyle) private var style

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            let shape = RoundedRectangle(cornerRadius: style.cardRadius(12), style: .continuous)
            if style.paintsCard {
                shape.fill(style.cardFill)
            } else {
                shape.fill(Color.primary.opacity(0.045))
            }
        }
        .overlay {
            let shape = RoundedRectangle(cornerRadius: style.cardRadius(12), style: .continuous)
            if let border = style.color(.border) {
                shape.strokeBorder(border, lineWidth: style.borderWidth(1))
            } else {
                shape.strokeBorder(Color.primary.opacity(0.08))
            }
        }
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
    private let fs: [(sym: String, tint: Color, title: String, text: String)] = [
        ("sidebar.left", .blue, String(localized: "Bar"), String(localized: "Spaces, clock and status icons on the left edge. Hover an icon for Wi-Fi, sound or Bluetooth.")),
        ("dock.rectangle", .orange, "Dock", String(localized: "Your apps in the bar. With many apps, related ones share a group.")),
        ("magnifyingglass", .purple, "Launcher", String(localized: "Apps and files, = for sums, > for actions, : for the clipboard.")),
        ("square.grid.2x2.fill", .indigo, "Dashboard", String(localized: "Weather, calendar, media and performance from the top edge.")),
        ("slider.horizontal.3", .green, String(localized: "Quick Actions"), String(localized: "Keep Awake, sound and toggles from the bottom right corner.")),
        ("gearshape.fill", .gray, "Nexus", String(localized: "Every setting, theme and shortcut in one window.")),
    ]

    @State private var on = false

    var body: some View {
        VStack(spacing: 24) {
            OnboardingHeader(
                symbol: "sidebar.left", tint: .indigo, title: OnboardingStep.welcome.title,
                text: String(localized: "A desktop shell for macOS modelled on Caelestia. It sits on top of the Mac instead of replacing it. The next steps set it up; the shell starts when you are done.")
            )
            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                ForEach(Array(fs.enumerated()), id: \.offset) { i, f in
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: f.sym)
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(f.tint)
                            .frame(width: 26, height: 22)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(f.title)
                                .fontWeight(.semibold)
                            Text(f.text)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(12)
                    .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
                    .background(Color.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .opacity(on ? 1 : 0)
                    .offset(y: on ? 0 : 8)
                    .animation(.smooth(duration: 0.4).delay(0.15 + Double(i) * 0.05), value: on)
                }
            }
        }
        .onAppear { on = true }
    }
}

struct OnboardingPermissionsPage: View {
    let permissions: OnboardingPermissions

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "hand.raised.fill", tint: .blue, title: OnboardingStep.permissions.title,
                text: String(localized: "Two permissions from macOS. Both can be revoked at any time under Privacy & Security.")
            )
            VStack(spacing: 8) {
                OnboardingCard {
                    OnboardingAccessibilityRow(permissions: permissions)
                    Divider()
                    OnboardingSystemEventsRow()
                }
                OnboardingFootnote(text: String(localized: "Without Accessibility everything else still works; the bar then also stays visible in full screen, and windows can slide underneath it."))
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
                text: String(localized: "The launcher opens with a shortcut, in any app. To change it, click the field and press the new combination.")
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
                OnboardingFootnote(text: String(localized: "Spotlight stays on ⌘Space. All shortcuts can be changed or removed in Nexus under “Keyboard Shortcuts”."))
            }
        }
    }
}

struct OnboardingFinishPage: View {
    @Bindable var store: ShellSettingsStore
    let autostart: OnboardingAutostartModel
    let first: Bool

    var body: some View {
        VStack(spacing: 22) {
            OnboardingHeader(
                symbol: "checkmark", tint: .green, title: OnboardingStep.finish.title,
                text: settingsHint
            )
            VStack(spacing: 8) {
                OnboardingCard {
                    OnboardingAutostartToggle(model: autostart)
                    Divider()
                    HStack(spacing: 12) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Hide Apple's Dock")
                            Text("While ApolloShell runs; it comes back when you quit")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 12)
                        Toggle("Hide Apple's Dock", isOn: $store.settings.appleDockHiding.hideWhileRunning)
                            .toggleStyle(.switch)
                            .labelsHidden()
                    }
                }
                if let note = autostart.state.note {
                    OnboardingFootnote(text: note)
                }
                OnboardingFootnote(text: String(localized: "This introduction is always available again under Nexus › About."))
            }
        }
    }

    private var settingsHint: String {
        let lead = first ? String(localized: "The bar appears on the left once you start. ") : ""
        return lead + nexusHint
    }

    private var nexusHint: String {
        guard let key = store.settings.hotKeys.nexus else {
            return String(localized: "Settings live in Nexus – via the gear icon in the Quick Actions panel.")
        }
        return String(localized: "Settings live in Nexus – with \(HotKeyKeyboard.display(key)) or via the gear icon in the Quick Actions panel.")
    }
}

import AppKit
import ApolloShellCore
import ApplicationServices
import Observation
import ServiceManagement
import SwiftUI

/// Stand der Bedienungshilfen-Freigabe, live. macOS meldet nicht, wenn man
/// sie in den Systemeinstellungen erteilt - also nachsehen, solange jemand
/// hinschaut (Einfuehrung, Nexus > Allgemein). AXIsProcessTrusted ist billig.
@MainActor
@Observable
final class OnboardingPermissions {
    private(set) var accessibility: Bool

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var timer: Timer?
    /// Wer gerade hinschaut; der Timer laeuft, solange einer da ist.
    @ObservationIgnored private var watchers: Set<String> = []
    @ObservationIgnored private var asked = false

    init() {
        live = true
        accessibility = AXIsProcessTrusted()
    }

    private init(preview accessibility: Bool) {
        live = false
        self.accessibility = accessibility
    }

    /// Fuer Bildproben: fester Stand, fragt nie das System.
    static func preview(accessibility: Bool) -> OnboardingPermissions {
        OnboardingPermissions(preview: accessibility)
    }

    func watch(_ on: Bool, by watcher: String) {
        guard live else { return }
        if on { watchers.insert(watcher) } else { watchers.remove(watcher) }
        if watchers.isEmpty {
            timer?.invalidate()
            timer = nil
        } else if timer == nil {
            refresh()
            timer = .repeating(every: 1, tolerance: 0.2, owner: self) { $0.refresh() }
        }
    }

    private func refresh() {
        let now = AXIsProcessTrusted()
        if now != accessibility {
            withAnimation(.snappy) { accessibility = now }
        }
    }

    /// Einmal pro Start die Systemfrage: sie traegt ApolloShell in die Liste
    /// der Bedienungshilfen ein, sonst muesste man die App dort selbst
    /// suchen. Dazu direkt der richtige Bereich der Systemeinstellungen.
    func openAccessibilitySettings() {
        guard live else { return }
        if !accessibility, !asked {
            asked = true
            // Wert von kAXTrustedCheckOptionPrompt (siehe WindowGuard).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        NexusSystemSettings.open(.accessibility)
    }
}

/// Bei der Anmeldung starten, ueber SMAppService.mainApp - das
/// Anmeldeobjekt, das macOS unter Allgemein > Anmeldeobjekte zeigt.
@MainActor
@Observable
final class OnboardingAutostartModel {
    private(set) var status: OnboardingAutostart.Status
    private(set) var error: String?

    @ObservationIgnored let launchdLabel: String?
    @ObservationIgnored let isAppBundle: Bool
    @ObservationIgnored private let live: Bool

    var state: OnboardingAutostart.State {
        OnboardingAutostart.state(status: status, launchdLabel: launchdLabel, isAppBundle: isAppBundle)
    }

    init() {
        live = true
        launchdLabel = OnboardingAutostart.launchdLabel(environment: ProcessInfo.processInfo.environment)
        isAppBundle = Bundle.main.bundleURL.pathExtension == "app"
        status = Self.read()
    }

    private init(preview status: OnboardingAutostart.Status, launchdLabel: String?, isAppBundle: Bool) {
        live = false
        self.status = status
        self.launchdLabel = launchdLabel
        self.isAppBundle = isAppBundle
    }

    /// Fuer Bildproben: liest und schaltet nichts.
    static func preview(status: OnboardingAutostart.Status = .notRegistered, launchdLabel: String? = nil,
                        isAppBundle: Bool = true) -> OnboardingAutostartModel {
        OnboardingAutostartModel(preview: status, launchdLabel: launchdLabel, isAppBundle: isAppBundle)
    }

    /// Nach aussen kann es sich aendern (Systemeinstellungen) - beim Zeigen
    /// frisch lesen.
    func refresh() {
        guard live else { return }
        let now = Self.read()
        if now != status { status = now }
    }

    /// Nur, wenn der Schalter bedienbar ist: nie aus einem Entwicklungs-Build
    /// und nie zusaetzlich zu einem eigenen launchd-Agenten.
    func setEnabled(_ on: Bool) {
        guard live, state.canToggle, on != state.isOn else { return }
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            error = nil
        } catch {
            self.error = String(localized: "macOS declined: \(error.localizedDescription)")
        }
        refresh()
    }

    func openLoginItems() {
        guard live else { return }
        SMAppService.openSystemSettingsLoginItems()
    }

    private static func read() -> OnboardingAutostart.Status {
        switch SMAppService.mainApp.status {
        case .enabled: .enabled
        case .requiresApproval: .requiresApproval
        case .notRegistered: .notRegistered
        case .notFound: .notFound
        @unknown default: .notFound
        }
    }
}

// MARK: - Bausteine fuer Einfuehrung und Nexus

/// Schalter "Bei der Anmeldung starten" samt Hinweisen.
struct OnboardingAutostartToggle: View {
    let model: OnboardingAutostartModel

    var body: some View {
        let state = model.state
        // Eigene Zeile statt NexusToggle: ausserhalb eines Form (Einfuehrung)
        // saesse der Schalter sonst direkt am Text statt am rechten Rand.
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("Start at Login")
                Text("ApolloShell starts on its own after login")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 12)
            Toggle("Start at Login", isOn: Binding(get: { state.isOn }, set: { model.setEnabled($0) }))
                .toggleStyle(.switch)
                .labelsHidden()
        }
        .disabled(!state.canToggle)
        if state.needsApproval {
            Button("Open Login Items…") { model.openLoginItems() }
        }
        if let error = model.error {
            Label(error, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
        }
    }
}

/// Bedienungshilfen: wozu, Stand (live) und der Weg in die Einstellungen.
struct OnboardingAccessibilityRow: View {
    let permissions: OnboardingPermissions

    var body: some View {
        OnboardingPermissionRow(
            symbol: "accessibility", tint: .blue, title: String(localized: "Accessibility"),
            text: String(localized: "So windows don't slide under the bar, the bar makes room in full screen, and the Dock knows an app's windows.")
        ) {
            if permissions.accessibility {
                Label("Erteilt", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .fontWeight(.medium)
                    .transition(.scale.combined(with: .opacity))
            } else {
                Button("Grant…") { permissions.openAccessibilitySettings() }
                    .help("Opens Privacy & Security > Accessibility")
            }
        }
    }
}

/// System Events: fragt macOS selbst, beim ersten Abmelden, Neustarten oder
/// Ausschalten. Hier absichtlich nicht ausloesen - eine Frage ohne Anlass
/// waere nur verwirrend.
struct OnboardingSystemEventsRow: View {
    var body: some View {
        OnboardingPermissionRow(
            symbol: "gearshape.2.fill", tint: .gray, title: "System Events",
            text: String(localized: "For Log Out, Restart and Shut Down in the session menu. macOS asks by itself the first time – nothing to do now.")
        ) {
            Label("The first time", systemImage: "clock")
                .foregroundStyle(.secondary)
        }
    }
}

struct OnboardingPermissionRow<Status: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let text: String
    @ViewBuilder let status: Status

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            NexusTile(symbol: symbol, tint: tint, size: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.medium)
                Text(text)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            status
                .font(.callout)
                .fixedSize()
        }
    }
}

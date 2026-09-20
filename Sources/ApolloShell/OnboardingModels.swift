import AppKit
import ApolloShellCore
import ApplicationServices
import Observation
import ServiceManagement
import SwiftUI

/// The state of the accessibility permission, live. macOS does not report when
/// one grants it in System Settings - so look while somebody is watching (the
/// introduction, Nexus > General). AXIsProcessTrusted is cheap.
@MainActor
@Observable
final class OnboardingPermissions {
    private(set) var accessibility: Bool

    @ObservationIgnored private let live: Bool
    @ObservationIgnored private var timer: Timer?
    /// Who is watching right now; the timer runs while there is one.
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

    /// For image samples: a fixed state, never asks the system.
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

    /// The system prompt once per start: it puts ApolloShell into the list of
    /// the accessibility permissions, otherwise one would have to look for the
    /// app there oneself. Plus the right area of System Settings straight away.
    func openAccessibilitySettings() {
        guard live else { return }
        if !accessibility, !asked {
            asked = true
            // The value of kAXTrustedCheckOptionPrompt (see WindowGuard).
            _ = AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
        }
        NexusSystemSettings.open(.accessibility)
    }
}

/// Start at login, through SMAppService.mainApp - the login item macOS shows
/// under General > Login Items.
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

    /// For image samples: reads and switches nothing.
    static func preview(status: OnboardingAutostart.Status = .notRegistered, launchdLabel: String? = nil,
                        isAppBundle: Bool = true) -> OnboardingAutostartModel {
        OnboardingAutostartModel(preview: status, launchdLabel: launchdLabel, isAppBundle: isAppBundle)
    }

    /// It can change from outside (System Settings) - read it fresh when
    /// showing it.
    func refresh() {
        guard live else { return }
        let now = Self.read()
        if now != status { status = now }
    }

    /// Only when the switch can be used: never from a development build and
    /// never on top of a launchd agent of our own.
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

// MARK: - Building blocks for the introduction and Nexus

/// The switch "Start at Login" together with its notes.
struct OnboardingAutostartToggle: View {
    let model: OnboardingAutostartModel

    var body: some View {
        let state = model.state
        // A row of its own instead of NexusToggle: outside a Form (the
        // introduction) the switch would sit right at the text, not at the edge.
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

/// Accessibility: what for, the state (live) and the way into the settings.
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

/// System Events: macOS asks by itself, on the first logout, restart or shut
/// down. Deliberately not set off here - a prompt without a reason would only
/// be confusing.
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

import AppKit
import ApolloShellCore
import SwiftUI
import SystemConfiguration

// Die Seite "Leiste" (Baukasten) steht in NexusBarEditor.swift.

// MARK: - Schreibtisch

/// Caelestia: background.desktopClock (in Nexus unter "Wallpaper & style").
/// Das Hintergrundbild selbst regelt macOS.
struct NexusDesktopPage: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        NexusPageForm(page: .desktop) {
            Section("Clock") {
                NexusToggle(title: "Desktop Clock", subtitle: "Bottom right, behind all windows",
                            isOn: $store.settings.background.desktopClock)
            }
            Section("Background") {
                NexusSystemLink(title: "Wallpaper", subtitle: "System Settings",
                                symbol: "photo.fill", tint: .cyan, pane: .wallpaper)
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
    }
}

// MARK: - Kurzmeldungen

/// Caelestia: Services > Notifications > "Toast events". Nur die
/// Ereignisse, die unsere Shell kennt; Mitteilungen von Apps sind Sache von macOS.
struct NexusToastsPage: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        NexusPageForm(page: .toasts) {
            Section {
                NexusToggle(title: "Charger", subtitle: "Connected or unplugged",
                            isOn: $store.settings.toasts.chargingChanged)
                NexusToggle(title: "Battery Warnings", subtitle: "On battery, at 20, 10 and 5%",
                            isOn: $store.settings.toasts.batteryWarnings)
                NexusToggle(title: "Audio Output", subtitle: "A different output device is chosen",
                            isOn: $store.settings.toasts.audioOutputChanged)
                NexusToggle(title: "Audio Input", subtitle: "A different microphone is chosen",
                            isOn: $store.settings.toasts.audioInputChanged)
            } header: {
                Text("Events")
            } footer: {
                Text("Toasts appear at the bottom right, disappear after 5 seconds, and stay off in full screen.")
            }
            Section {
                NexusSystemLink(title: "Notifications from Apps", subtitle: "System Settings",
                                symbol: "bell.fill", tint: .red, pane: .notifications)
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
    }
}

// MARK: - Systemeinstellungen

/// Caelestias Seiten, die auf macOS das System uebernimmt, als Spruenge -
/// gruppiert wie dort (appearance, connectivity, system).
struct NexusSystemPage: View {
    var body: some View {
        NexusPageForm(page: .system) {
            Section("Style") {
                NexusSystemLink(title: "Wallpaper", symbol: "photo.fill", tint: .cyan, pane: .wallpaper)
                NexusSystemLink(title: "Appearance", subtitle: "Light, dark, accent color",
                                symbol: "circle.lefthalf.filled", tint: .gray, pane: .appearance)
            }
            Section("Connectivity") {
                NexusSystemLink(title: "Network", subtitle: "Wi-Fi, Ethernet, VPN",
                                symbol: "network", tint: .blue, pane: .network)
                NexusSystemLink(title: "Connected Devices", subtitle: "Bluetooth, pairing",
                                symbol: "dot.radiowaves.left.and.right", tint: .blue, pane: .bluetooth)
                NexusSystemLink(title: "Sound", subtitle: "Output, input, volume",
                                symbol: "speaker.wave.2.fill", tint: .pink, pane: .sound)
            }
            Section("System") {
                NexusSystemLink(title: "Software Update", symbol: "arrow.clockwise", tint: .gray, pane: .softwareUpdate)
                NexusSystemLink(title: "Language & Region", subtitle: "Language, units, time format",
                                symbol: "globe", tint: .blue, pane: .language)
            }
            Section {
                NexusSystemLink(title: "Open System Settings", symbol: "gearshape.fill", tint: .gray, pane: nil)
            }
        }
    }
}

// MARK: - Ueber

/// Was Nexus ueber das System weiss. Einmal beim Oeffnen gelesen (sysctl,
/// Bruchteile einer Millisekunde); nur die Laufzeit tickt.
struct NexusSystemInfo: Sendable {
    var computerName: String
    var model: String
    var chip: String
    var macOS: String
    var kernel: String
    var bootDate: Date?
    var version: String
    /// Quelltext-Ordner, beim Bauen festgehalten (`#filePath`); `nil`, wenn
    /// es ihn auf diesem Mac nicht (mehr) gibt.
    var sourceFolder: URL?

    static func read() -> NexusSystemInfo {
        let info = Bundle.main.infoDictionary
        let os = ProcessInfo.processInfo.operatingSystemVersion
        var macOS = "macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion)"
        if let build = sysctlString("kern.osversion") { macOS += " (\(build))" }
        return NexusSystemInfo(
            // Nicht ProcessInfo.hostName: das kann auf eine DNS-Antwort warten.
            computerName: (SCDynamicStoreCopyComputerName(nil, nil) as String?) ?? "–",
            model: sysctlString("hw.model") ?? "–",
            chip: sysctlString("machdep.cpu.brand_string") ?? "–",
            macOS: macOS,
            kernel: sysctlString("kern.osrelease").map { "Darwin \($0)" } ?? "–",
            bootDate: bootDate(),
            version: NexusText.version(short: info?["CFBundleShortVersionString"] as? String,
                                       build: info?["CFBundleVersion"] as? String),
            sourceFolder: sourceFolder()
        )
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return nil }
        let text = String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
        return text.isEmpty ? nil : text
    }

    /// Wie `uptime`: seit dem Einschalten, Ruhezustand eingerechnet
    /// (`ProcessInfo.systemUptime` zaehlt den nicht mit).
    private static func bootDate() -> Date? {
        var time = timeval()
        var size = MemoryLayout<timeval>.size
        guard sysctlbyname("kern.boottime", &time, &size, nil, 0) == 0, time.tv_sec > 0 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(time.tv_sec) + TimeInterval(time.tv_usec) / 1_000_000)
    }

    /// Sources/Launcher/NexusPages.swift -> drei Ebenen hoch.
    private static func sourceFolder(file: String = #filePath) -> URL? {
        let url = URL(fileURLWithPath: file)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return FileManager.default.fileExists(atPath: url.appendingPathComponent("Package.swift").path) ? url : nil
    }
}

/// Caelestia: AboutPage (Logo und Version, "System", "Software").
struct NexusAboutPage: View {
    let system: NexusSystemInfo
    var showOnboarding: @MainActor () -> Void = {}

    var body: some View {
        NexusPageForm(page: .about, title: "ApolloShell", subtitle: system.version) {
            Section("System") {
                LabeledContent("Computer Name", value: system.computerName)
                LabeledContent("Device", value: system.model)
                LabeledContent("Chip", value: system.chip)
                LabeledContent("Operating System", value: system.macOS)
                LabeledContent("Kernel", value: system.kernel)
                if let boot = system.bootDate {
                    // Jede Minute neu; Sekunden zeigt die Laufzeit nicht.
                    TimelineView(.everyMinute) { context in
                        LabeledContent("Uptime", value: NexusText.uptime(context.date.timeIntervalSince(boot)))
                    }
                }
            }
            // Die Version steht schon in der Kopfkarte, deshalb hier nicht nochmal.
            Section("Software") {
                if let folder = system.sourceFolder {
                    LabeledContent("Source Code") {
                        HStack(spacing: 8) {
                            Text((folder.path as NSString).abbreviatingWithTildeInPath)
                                .textSelection(.enabled)
                            Button("Show in Finder") {
                                NSWorkspace.shared.activateFileViewerSelecting([folder])
                            }
                            .controlSize(.small)
                        }
                    }
                }
                LabeledContent("Based On") {
                    Link("Caelestia Shell", destination: URL(string: "https://github.com/caelestia-dots/shell")!)
                }
            }
            Section {
                Button("Show Introduction…") { showOnboarding() }
            } footer: {
                Text("The steps from the first launch: permissions, launcher shortcut, start at login.")
            }
            Section {
                NexusSystemLink(title: "About This Mac", subtitle: "System Settings",
                                symbol: "laptopcomputer", tint: .gray, pane: .about)
            }
        }
    }
}

/// Dezente Zeile, falls eine Datei nicht geschrieben werden konnte - sonst
/// saehe der Schalter aus, als haette er gewirkt, und nach dem Neustart
/// waere er wieder zurueck.
struct NexusSaveWarning: View {
    let failed: Bool
    var file = "settings.json"

    var body: some View {
        if failed {
            Section {
                Label("\(file) could not be saved. The change only applies until the next restart.",
                      systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            }
        }
    }
}

import AppKit
import ApolloShellCore
import SwiftUI
import SystemConfiguration

// Die Seite "Bar" (Baukasten) steht in NexusBarEditor.swift.

// MARK: - Schreibtisch

/// Caelestia: background.desktopClock (in Nexus unter "Wallpaper & style").
/// Das Hintergrundbild selbst regelt macOS.
struct NexusDesktopPage: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        NexusPageForm(page: .desktop) {
            Section("Clock") {
                NexusToggle(title: "Desktop Clock",
                            isOn: $store.settings.background.desktopClock)
            }
            NexusToastsPage(store: store)
            NexusRestoreSection(title: "Restore Desktop Defaults",
                                message: "The desktop clock and all toast events go back to their defaults.") {
                store.settings.background = .init()
                store.settings.toasts = .init()
            }
        }
    }
}

// MARK: - Kurzmeldungen

/// Caelestia: Services > Notifications > "Toast events". Nur die
/// Ereignisse, die unsere Shell kennt; Mitteilungen von Apps sind Sache von macOS.
struct NexusToastsPage: View {
    @Bindable var store: ShellSettingsStore

    var body: some View {
        Group {
            Section {
                NexusToggle(title: "Charger",
                            isOn: $store.settings.toasts.chargingChanged)
                NexusToggle(title: "Battery Warnings", tip: "On battery, at 20, 10 and 5 %.",
                            isOn: $store.settings.toasts.batteryWarnings)
                NexusToggle(title: "Audio Output",
                            isOn: $store.settings.toasts.audioOutputChanged)
                NexusToggle(title: "Audio Input",
                            isOn: $store.settings.toasts.audioInputChanged)
            } header: {
                Text("Toasts")
            }
            NexusSaveWarning(failed: store.saveFailed)
        }
    }
}

// MARK: - Systemeinstellungen

/// Caelestias Seiten, die auf macOS das System uebernimmt, als Spruenge -
/// gruppiert wie dort (appearance, connectivity, system).
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
    var store: ShellSettingsStore?
    var updates: UpdateController?
    var showOnboarding: @MainActor () -> Void = {}

    var body: some View {
        NexusPageForm(page: .about, title: "ApolloShell", subtitle: system.version) {
            if let store, let updates { NexusUpdatesPage(store: store, updates: updates) }
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
            }
            if let store { NexusAdvancedSections(store: store) }
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

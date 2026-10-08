import AppKit
import CoreWLAN
import Observation

struct WifiNet: Identifiable, Equatable, Sendable {
    let ssid: String
    var id: String { ssid }
}

@MainActor
@Observable
final class WifiNetworks {
    private(set) var nets: [WifiNet] = []
    private(set) var loading = false
    private(set) var joining: String?
    private(set) var failed: String?
    @ObservationIgnored private var last = Date.distantPast

    func load(force: Bool = false) {
        guard !loading, force || Date().timeIntervalSince(last) > 30,
              let iface = CWWiFiClient.shared().interface()?.interfaceName else { return }
        loading = true
        Task.detached {
            let r = Self.run(["-listpreferredwirelessnetworks", iface]).out
                .split(separator: "\n").dropFirst()
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .filter { !$0.isEmpty }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.loading = false
                self.last = Date()
                self.nets = r.map { WifiNet(ssid: $0) }
            }
        }
    }

    func join(_ n: WifiNet) {
        guard let iface = CWWiFiClient.shared().interface()?.interfaceName else { return }
        joining = n.ssid
        failed = nil
        Task.detached {
            let r = Self.run(["-setairportnetwork", iface, n.ssid])
            let t = r.out.lowercased()
            let ok = r.code == 0 && !t.contains("error") && !t.contains("could not") && !t.contains("failed")
            await MainActor.run { [weak self] in
                self?.joining = nil
                if !ok { self?.failed = n.ssid }
            }
        }
    }

    nonisolated private static func run(_ args: [String]) -> (code: Int32, out: String) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
        p.arguments = args
        let o = Pipe()
        p.standardOutput = o
        p.standardError = o
        guard (try? p.run()) != nil else { return (-1, "") }
        let d = o.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus, String(decoding: d, as: UTF8.self))
    }
}

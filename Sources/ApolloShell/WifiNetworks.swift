import AppKit
import CoreLocation
import CoreWLAN
import Observation

struct WifiNet: Identifiable, Equatable, Sendable {
    let ssid: String
    let rssi: Int
    let secure: Bool
    let known: Bool
    var id: String { ssid }
}

@MainActor
@Observable
final class WifiNetworks: NSObject, CLLocationManagerDelegate {
    private(set) var nets: [WifiNet] = []
    private(set) var scanning = false
    private(set) var joining: String?
    private(set) var failed: String?
    private(set) var auth: CLAuthorizationStatus
    @ObservationIgnored private let loc = CLLocationManager()
    @ObservationIgnored private var lastScan = Date.distantPast

    override init() {
        auth = loc.authorizationStatus
        super.init()
        loc.delegate = self
    }

    var allowed: Bool { auth == .authorizedAlways || auth == .authorized }
    var denied: Bool { auth == .denied || auth == .restricted }

    nonisolated func locationManagerDidChangeAuthorization(_ m: CLLocationManager) {
        let a = m.authorizationStatus
        MainActor.assumeIsolated {
            auth = a
            if allowed { scan(force: true) }
        }
    }

    func requestAccess() {
        NSApp.activate()
        loc.requestWhenInUseAuthorization()
    }

    func scan(force: Bool = false) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 10 else { return }
        scanning = true
        Task.detached {
            let r = Self.read()
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.scanning = false
                self.lastScan = Date()
                if !r.isEmpty || self.nets.isEmpty { self.nets = r }
            }
        }
    }

    nonisolated private static func read() -> [WifiNet] {
        guard let i = CWWiFiClient.shared().interface(), i.powerOn() else { return [] }
        let known = Set((i.configuration()?.networkProfiles.array as? [CWNetworkProfile] ?? []).compactMap(\.ssid))
        let current = i.ssid()
        guard let found = try? i.scanForNetworks(withName: nil) else { return [] }
        var best: [String: WifiNet] = [:]
        for n in found {
            guard let s = n.ssid, !s.isEmpty, s != current else { continue }
            let secure = !n.supportsSecurity(.none)
            let w = WifiNet(ssid: s, rssi: n.rssiValue, secure: secure, known: known.contains(s))
            if let b = best[s], b.rssi >= w.rssi { continue }
            best[s] = w
        }
        return best.values.sorted { a, b in a.known != b.known ? a.known : a.rssi > b.rssi }
    }

    func join(_ n: WifiNet, afterAsk: Bool = false) {
        var pw: String?
        if n.secure && (!n.known || afterAsk) {
            guard let p = Self.askPassword(n.ssid) else { return }
            pw = p
        }
        guard let iface = CWWiFiClient.shared().interface()?.interfaceName else { return }
        joining = n.ssid
        failed = nil
        Task.detached {
            let ok: Bool
            if let pw {
                let i = CWWiFiClient.shared().interface()
                let net = (try? i?.scanForNetworks(withName: n.ssid))?.first
                if let i, let net {
                    ok = (try? i.associate(to: net, password: pw)) != nil
                } else {
                    ok = false
                }
            } else {
                let p = Process()
                p.executableURL = URL(fileURLWithPath: "/usr/sbin/networksetup")
                p.arguments = ["-setairportnetwork", iface, n.ssid]
                let out = Pipe()
                p.standardOutput = out
                p.standardError = out
                try? p.run()
                let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
                p.waitUntilExit()
                ok = p.terminationStatus == 0 && !text.localizedCaseInsensitiveContains("error") && !text.localizedCaseInsensitiveContains("could not")
            }
            await MainActor.run { [weak self] in
                guard let self else { return }
                self.joining = nil
                if ok {
                    self.scan(force: true)
                } else if n.secure && !afterAsk && n.known {
                    self.join(n, afterAsk: true)
                } else {
                    self.failed = n.ssid
                }
            }
        }
    }

    private static func askPassword(_ ssid: String) -> String? {
        let a = NSAlert()
        a.messageText = String(localized: "Join “\(ssid)”")
        a.informativeText = String(localized: "Enter the network password.")
        let f = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        a.accessoryView = f
        a.addButton(withTitle: String(localized: "Join"))
        a.addButton(withTitle: String(localized: "Cancel"))
        NSApp.activate()
        a.window.initialFirstResponder = f
        guard a.runModal() == .alertFirstButtonReturn, !f.stringValue.isEmpty else { return nil }
        return f.stringValue
    }
}

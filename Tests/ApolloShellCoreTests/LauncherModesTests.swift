import Foundation
import ApolloShellCore
import Testing

@Suite("Launcher: Rechner, Modi, Aktionen")
struct LauncherModesTests {
    @Test("Rechner", arguments: [
        ("1+2*3", 7.0), ("(1+2)*3", 9.0), ("2^3^2", 512.0), ("-2^2", -4.0), ("10/4", 2.5),
        ("7%3", 1.0), ("3 × 4", 12.0), ("1,5+1", 2.5), ("-(2+3)", -5.0),
    ])
    func calc(input: String, value: Double) {
        #expect(LauncherCalc.evaluate(input) == value)
    }

    @Test("ungueltig ergibt nil", arguments: ["", "1/0", "2+", "(1+2", "abc", "1..2", "5%0"])
    func invalid(input: String) {
        #expect(LauncherCalc.evaluate(input) == nil)
    }

    @Test("Mathe erkennen ohne Praefix")
    func looks() {
        #expect(LauncherCalc.looksLikeMath("12*4"))
        #expect(!LauncherCalc.looksLikeMath("12"))
        #expect(!LauncherCalc.looksLikeMath("safari"))
        #expect(!LauncherCalc.looksLikeMath("1-"))
    }

    @Test("Formatieren")
    func format() {
        #expect(LauncherCalc.format(7) == "7")
        #expect(LauncherCalc.format(2.5) == "2.5")
        #expect(LauncherCalc.format(1.0 / 3).hasPrefix("0.333"))
    }

    @Test("Praefixe")
    func modes() {
        #expect(LauncherMode.parse("=1+1") == .calc("1+1"))
        #expect(LauncherMode.parse("> lock") == .actions("lock"))
        #expect(LauncherMode.parse(":foo") == .clipboard("foo"))
        #expect(LauncherMode.parse("safari") == .apps("safari"))
    }

    @Test("Aktionen filtern, auch deutsch")
    func actions() {
        #expect(LauncherAction.matching("sperr") == [.lock])
        #expect(LauncherAction.matching("").count == LauncherAction.allCases.count)
    }
}

@Suite("Speedtest")
struct SpeedResultTests {
    @Test("networkQuality-JSON lesen")
    func parse() throws {
        let j = #"{"dl_throughput": 412345678, "ul_throughput": 38123456, "responsiveness": 950.4, "base_rtt": 18.2, "interface_name": "en0"}"#
        let r = try #require(SpeedResult.parse(Data(j.utf8)))
        #expect(SpeedResult.mbit(r.down) == "412 Mbit/s")
        #expect(SpeedResult.mbit(r.up) == "38.1 Mbit/s")
        #expect(r.responsiveness?.hasPrefix("High") == true)
        #expect(SpeedResult.parse(Data("{}".utf8)) == nil)
    }

    @Test("Live-Zeilen und Zusammenfassung")
    func live() throws {
        let l = try #require(SpeedResult.live("\u{1B}[2KDownlink: 8.914 Mbps, 258 RPM - Uplink: 39.128 Mbps, 258 RPM"))
        #expect(SpeedResult.mbit(l.down) == "8.9 Mbit/s")
        #expect(SpeedResult.mbit(l.up) == "39.1 Mbit/s")
        #expect(l.rpm == 258)
        #expect(SpeedResult.live("^D") == nil)
        let s = try #require(SpeedResult.summary("==== SUMMARY ====\nUplink capacity: 45.845 Mbps\nDownlink capacity: 9.903 Mbps\nResponsiveness: Low (666.643 milliseconds | 90 RPM)\n", last: l))
        #expect(SpeedResult.mbit(s.down) == "9.9 Mbit/s")
        #expect(s.rpm == 90)
    }
}

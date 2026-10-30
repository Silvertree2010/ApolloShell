import Foundation
import Testing
@testable import ApolloShellCore

@Suite("OSD: Medientasten und Abschaltbares")
struct SystemKeyTests {
    @Test("Tastencode aus data1", arguments: [
        (0x000A00, SystemKey.volumeUp), (0x010A00, .volumeDown), (0x070A00, .mute),
        (0x020A00, .brightnessUp), (0x030A00, .brightnessDown),
    ])
    func keyCodes(data1: Int, key: SystemKey) {
        #expect(SystemKey(data1: data1) == key)
        #expect(SystemKey.isDown(data1: data1))
        #expect(!SystemKey.isDown(data1: data1 & 0xFFFF0000 | 0x0B00))
    }

    @Test("Wiedergabe und Tastaturbeleuchtung gehoeren macOS")
    func otherKeysPass() {
        #expect(SystemKey(data1: 16 << 16) == nil)
        #expect(SystemKey(data1: 21 << 16) == nil)
    }

    @Test("Schritte rasten ein und bleiben in 0...1")
    func stepping() {
        let d = SystemKey.step(fine: false)
        #expect(SystemKey.stepped(0.5, by: d) == 0.5625)
        #expect(SystemKey.stepped(0.53, by: d) == 0.5625)
        #expect(SystemKey.stepped(0.53, by: -d) == 0.4375)
        #expect(SystemKey.stepped(1, by: d) == 1)
        #expect(SystemKey.stepped(0, by: -d) == 0)
        #expect(SystemKey.stepped(0.5, by: SystemKey.step(fine: true)) == 0.515625)
    }

    @Test("features: fehlt = alles an, einzelne Schalter lesbar")
    func features() {
        #expect(ShellSettings.load(from: Data("{}".utf8)).features == .init())
        let s = ShellSettings.load(from: Data(#"{"features":{"osd":false,"utilitiesHover":false}}"#.utf8))
        #expect(!s.features.osd && !s.features.utilitiesHover)
        #expect(s.features.replaceSystemOSD && s.features.dashboardHover)
        let back = ShellSettings.load(from: s.encoded())
        #expect(back.features == s.features)
    }
}

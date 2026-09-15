import Testing
@testable import ApolloShellCore

@Suite("Lautstaerke-Anzeige")
struct VolumeGlyphsTests {
    @Test("Symbol nach Lautstaerke", arguments: [
        (Float(0), "speaker.slash.fill"), (Float(0.2), "speaker.wave.1.fill"),
        (Float(0.5), "speaker.wave.2.fill"), (Float(0.9), "speaker.wave.3.fill"),
    ])
    func symbol(volume: Float, expected: String) {
        #expect(VolumeGlyphs.symbol(volume: volume, muted: false) == expected)
    }

    @Test("stumm ist immer durchgestrichen, auch bei voller Lautstaerke")
    func mutedAlwaysSlash() {
        #expect(VolumeGlyphs.symbol(volume: 1, muted: true) == "speaker.slash.fill")
    }

    @Test("Prozent gerundet und begrenzt")
    func percent() {
        #expect(VolumeGlyphs.percent(0.456) == 46)
        #expect(VolumeGlyphs.percent(1.4) == 100)
        #expect(VolumeGlyphs.percent(-0.2) == 0)
    }
}

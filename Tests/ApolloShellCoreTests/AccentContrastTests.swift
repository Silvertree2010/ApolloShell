import ApolloShellCore
import Testing

@Suite("Text on the accent color")
struct AccentContrastTests {
    @Test("Yellow gets dark text")
    func yellowIsDark() {
        #expect(AccentContrast.prefersDarkForeground(red: 1, green: 0.773, blue: 0))
        #expect(AccentContrast.prefersDarkForeground(red: 1, green: 0.839, blue: 0.039))
    }

    @Test("Blue, green, orange, red and graphite keep white text")
    func otherAccentsAreLight() {
        #expect(!AccentContrast.prefersDarkForeground(red: 0, green: 0.478, blue: 1))
        #expect(!AccentContrast.prefersDarkForeground(red: 0.204, green: 0.780, blue: 0.349))
        #expect(!AccentContrast.prefersDarkForeground(red: 1, green: 0.584, blue: 0))
        #expect(!AccentContrast.prefersDarkForeground(red: 1, green: 0.231, blue: 0.188))
        #expect(!AccentContrast.prefersDarkForeground(red: 0.557, green: 0.557, blue: 0.576))
    }

    @Test("Edge values")
    func extremes() {
        #expect(AccentContrast.luminance(red: 0, green: 0, blue: 0) == 0)
        #expect(abs(AccentContrast.luminance(red: 1, green: 1, blue: 1) - 1) < 1e-9)
        #expect(AccentContrast.prefersDarkForeground(red: 1, green: 1, blue: 1))
        #expect(!AccentContrast.prefersDarkForeground(red: 0, green: 0, blue: 0))
    }
}

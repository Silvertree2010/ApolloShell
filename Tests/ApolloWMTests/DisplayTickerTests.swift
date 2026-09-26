import Testing
@testable import ApolloWM

@MainActor
@Suite("Animationstakt")
struct DisplayTickerTests {
    @Test("frame-rate unter 60 startet den Takt ohne Absturz", arguments: [1, 30, 59.5] as [Float])
    func lowFrameRate(_ rate: Float) {
        let ticker = DisplayTicker(frameRate: rate) {}
        ticker.start()
        ticker.stop()
    }
}

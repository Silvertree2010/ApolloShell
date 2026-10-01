import Testing
import Foundation
@testable import ApolloShell

@MainActor
@Suite("Render: Wetter-Widget liest place-id", .serialized)
struct WeatherPlaceIdRenderTests {
    private func render(_ config: String, _ fixture: String, _ out: String, id: String?) throws -> Data {
        let root = PackageResources.root
        let source = try String(contentsOf: root.appendingPathComponent("Resources/render/\(config)/shell.kdl"), encoding: .utf8)
        let shell = source.replacingOccurrences(of: " place-id=\"zurich\"", with: id.map { " place-id=\"\($0)\"" } ?? "")
        let folder = try RenderProbe.folder(["shell.kdl": Data(shell.utf8)])
        let output = folder.appendingPathComponent(out)
        let arguments = ["x", "--render", output.path, "--fixture", root.appendingPathComponent("Resources/render/\(fixture)/fixture.kdl").path,
                         "--config", folder.path, "--resources", root.appendingPathComponent("Resources").path, "--appearance", "light", "--scale", "1"]
        try RenderCommand.render(try RenderCommand.options(arguments, executable: URL(fileURLWithPath: "/tmp/x")))
        let name = try #require(try FileManager.default.contentsOfDirectory(atPath: output.path).first)
        return try Data(contentsOf: output.appendingPathComponent(name))
    }

    @Test("place-id wählt den Ort aus by-place, unbekannte id fällt auf den gewählten Favoriten zurück")
    func placeId() throws {
        let chosen = try render("widget-weather-placeid", "widget-weather-placeid", "a", id: "zurich")
        let selected = try render("widget-weather-placeid", "widget-weather-placeid", "b", id: nil)
        let unknown = try render("widget-weather-placeid", "widget-weather-placeid", "c", id: "nowhere")
        #expect(chosen != selected)
        #expect(unknown == selected)
    }
}

import Testing
import Foundation
import AppKit
@testable import ApolloShell

@MainActor
@Suite("Render: --render für alle Oberflächen (testing.md 3.1)", .serialized)
struct RenderCommandTests {
    @Test("jede Oberfläche wird gezeichnet, --theme färbt, dunkel im Namen")
    func allSurfaces() throws {
        let config = try RenderProbe.folder([
            "shell.kdl": Data("""
            style "style.css"
            panel "left-bar" anchor="left" { stack class="a" }
            popup "card" { stack class="a" }
            """.utf8),
            "style.css": Data(".a { width: 20px; height: 20px; background: var(--apollo-accent-color, #000000); }".utf8),
            "theme.css": Data(":root { --apollo-accent-color: #ff0000; }".utf8),
        ])
        let output = config.appendingPathComponent("out")
        let root = PackageResources.root
        let arguments = ["x", "--render", output.path, "--fixture", root.appendingPathComponent("Resources/render/fixture.kdl").path,
                         "--config", config.path, "--resources", root.appendingPathComponent("Resources").path,
                         "--theme", config.appendingPathComponent("theme.css").path, "--appearance", "dark", "--scale", "1"]
        let options = try RenderCommand.options(arguments, executable: URL(fileURLWithPath: "/tmp/x"))
        try RenderCommand.render(options)
        let files = try FileManager.default.contentsOfDirectory(atPath: output.path).sorted()
        #expect(files == ["card-dark.png", "left-bar-dark.png"])
        let rep = try #require(NSBitmapImageRep(data: try Data(contentsOf: output.appendingPathComponent("left-bar-dark.png"))))
        let color = try #require(rep.colorAt(x: 10, y: 10)?.usingColorSpace(.sRGB))
        #expect(color.redComponent > 0.8 && color.greenComponent < 0.2)
    }

    @Test("Oberfläche mit Flyout kehrt unter der festen Uhr aus render.sh zurück")
    func flyoutUnderFixedClock() throws {
        let config = try RenderProbe.folder([
            "shell.kdl": Data("""
            style "style.css"
            var open #true
            panel "bar" anchor="left" shape="fused" {
                stack id="hook" class="a"
                flyout anchor="hook" side="right" open="{var.open}" { stack class="a" }
            }
            """.utf8),
            "style.css": Data(".a { width: 20px; height: 20px; background: #ff0000; }".utf8),
        ])
        let output = config.appendingPathComponent("out")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = [PackageResources.root.appendingPathComponent("scripts/render/render.sh").path, output.path, "light"]
        var environment = ProcessInfo.processInfo.environment
        environment["APOLLO_RENDER_EXTRA"] = "--config \(config.path)"
        process.environment = environment
        process.standardError = FileHandle.nullDevice
        process.standardOutput = FileHandle.nullDevice
        try process.run()
        let deadline = Date().addingTimeInterval(60)
        while process.isRunning, Date() < deadline { usleep(100_000) }
        let hung = process.isRunning
        if hung {
            process.terminate()
            let kill = Process()
            kill.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
            kill.arguments = ["-f", output.path]
            try? kill.run()
            kill.waitUntilExit()
        }
        #expect(!hung)
        #expect(FileManager.default.fileExists(atPath: output.appendingPathComponent("bar-light.png").path))
    }
}

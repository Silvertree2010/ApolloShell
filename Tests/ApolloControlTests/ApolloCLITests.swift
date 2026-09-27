import Testing
import Foundation
import ApolloConfig
@testable import ApolloControl

@Suite("apollo gegen einen Socket-Server im Testprozess", .serialized)
struct ApolloCLITests {
    @Test("check läuft lokal, auch ohne Shell")
    func checkIsLocal() throws {
        let harness = try CLIHarness()
        let ok = harness.run(["check", "/some/config"], socket: harness.folder.url.appendingPathComponent("none").path)
        #expect(ok.exitCode == 0)
        let broken = harness.run(["check", "broken"], socket: harness.folder.url.appendingPathComponent("none").path)
        #expect(broken.exitCode == 1)
        #expect(broken.stdout == ["error: broken"])
        #expect(harness.checkCalls == [["/some/config"], ["broken"]])
        #expect(harness.shell.calls.isEmpty)
    }

    @Test("reload gibt Diagnosen aus, Exit 1 nur bei Fehlern")
    func reload() throws {
        let harness = try CLIHarness()
        harness.shell.reloadSummary = DiagnosticSummary(text: "warning: old theme", errors: 0, warnings: 1)
        let warn = harness.run(["reload"])
        #expect(warn.exitCode == 0)
        #expect(warn.stdout == ["warning: old theme"])
        harness.shell.reloadSummary = DiagnosticSummary(text: "error: broken", errors: 1, warnings: 0)
        #expect(harness.run(["reload"]).exitCode == 1)
        #expect(harness.shell.calls == ["reload", "reload"])
    }

    @Test("open, close und toggle wie die Aktionen")
    func surfaces() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["open", "launcher"]).exitCode == 0)
        #expect(harness.run(["close", "dashboard"]).exitCode == 0)
        #expect(harness.run(["toggle", "launcher"]).exitCode == 0)
        #expect(harness.shell.calls == ["open launcher", "close dashboard", "toggle launcher"])
        let missing = harness.run(["open", "missing"])
        #expect(missing.exitCode == 1)
        #expect(missing.stderr == ["apollo: no surface named 'missing'"])
        #expect(harness.run(["open"]).exitCode == 2)
    }

    @Test("run schickt den KDL-Schnipsel unverändert")
    func run() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["run", "audio.set-volume 0.5"]).exitCode == 0)
        #expect(harness.shell.calls == ["run audio.set-volume 0.5"])
        #expect(harness.run(["run"]).exitCode == 2)
    }

    @Test("eval gibt JSON aus, NaN als null")
    func evaluate() throws {
        let harness = try CLIHarness()
        let result = harness.run(["eval", "{1 + 1}"])
        #expect(result.exitCode == 0)
        #expect(result.stdout == [#"{"sum":2,"bad":null}"#])
        #expect(harness.shell.calls == ["eval {1 + 1}"])
    }

    @Test("watch liefert bei drei Änderungen drei JSON-Zeilen")
    func watch() throws {
        let harness = try CLIHarness()
        let capture = OutputCapture()
        let cli = harness.cli()
        let finished = DispatchSemaphore(value: 0)
        let exit = LockedBox<Int32>(-1)
        Thread.detachNewThread {
            exit.value = cli.run(["watch", "{battery.percent}"], out: capture.out, err: capture.err)
            finished.signal()
        }
        #expect(waitUntil { harness.shell.probe.hasSubscriber })
        for value in [0.1, 0.2, 0.3] {
            harness.shell.probe.yield(.number(value))
        }
        #expect(waitUntil { capture.stdout.count == 3 })
        harness.server.stop()
        #expect(finished.wait(timeout: .now() + 5) == .success)
        #expect(capture.stdout == ["0.1", "0.2", "0.3"])
        #expect(exit.value == 0)
    }

    @Test("get und set lesen und schreiben var als JSON")
    func getAndSet() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["get", "index"]).stdout == ["3"])
        #expect(harness.run(["set", "index", "7"]).exitCode == 0)
        #expect(harness.run(["get", "index"]).stdout == ["7"])
        #expect(harness.run(["set", "mode", #""dark""#]).exitCode == 0)
        let bad = harness.run(["set", "mode", "dark"])
        #expect(bad.exitCode == 2)
        #expect(bad.stderr.first?.contains("JSON") == true)
        #expect(harness.run(["get", "nope"]).exitCode == 1)
        #expect(harness.shell.calls == ["set index 7", #"set mode "dark""#])
    }

    @Test("emit schickt user-Ereignisse mit JSON oder null")
    func emit() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["emit", "ping"]).exitCode == 0)
        #expect(harness.run(["emit", "ping", #"{"n":1}"#]).exitCode == 0)
        #expect(harness.run(["emit", "user.ping"]).exitCode == 0)
        #expect(harness.shell.calls == ["emit user.ping null", #"emit user.ping {"n":1}"#, "emit user.ping null"])
    }

    @Test("fork der Config user kopiert nur die Config-Dateien, nicht \\$CONFIG samt configs, state und settings in sich selbst")
    func forkUserConfig() throws {
        let harness = try CLIHarness()
        let files = FileManager.default
        let root = harness.paths.userConfig
        try "panel \"mine\"\n".write(to: root.appendingPathComponent("shell.kdl"), atomically: true, encoding: .utf8)
        try "bar {}\n".write(to: root.appendingPathComponent("bar.css"), atomically: true, encoding: .utf8)
        try files.createDirectory(at: root.appendingPathComponent("state"), withIntermediateDirectories: true)
        try "x 1\n".write(to: root.appendingPathComponent("state/user.kdl"), atomically: true, encoding: .utf8)
        try files.createDirectory(at: root.appendingPathComponent("configs/other"), withIntermediateDirectories: true)
        try "panel \"other\"\n".write(to: root.appendingPathComponent("configs/other/shell.kdl"), atomically: true, encoding: .utf8)
        let run = harness.run(["config", "fork", "user", "copy"])
        #expect(run.exitCode == 0, "\(run.stderr)")
        let copy = root.appendingPathComponent("configs/copy")
        #expect(files.fileExists(atPath: copy.appendingPathComponent("shell.kdl").path))
        #expect(files.fileExists(atPath: copy.appendingPathComponent("bar.css").path))
        #expect(!files.fileExists(atPath: copy.appendingPathComponent("configs").path))
        #expect(!files.fileExists(atPath: copy.appendingPathComponent("state").path))
        #expect(!files.fileExists(atPath: copy.appendingPathComponent("themes").path))
        #expect(!files.fileExists(atPath: copy.appendingPathComponent("settings.kdl").path))
        #expect(harness.settings.settings.config == "copy")
    }

    @Test("config list, select, fork und path")
    func configs() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["config", "list"]).stdout == ["* apolloshell-default (built in)", "  launcher-only (built in)"])
        #expect(harness.run(["config", "path"]).stdout == [harness.paths.builtinConfigs.appendingPathComponent("apolloshell-default").path])
        #expect(harness.run(["config", "select", "launcher-only"]).exitCode == 0)
        #expect(harness.settings.settings.config == "launcher-only")
        #expect(harness.run(["config", "select", "nope"]).exitCode == 1)
        #expect(harness.settings.settings.config == "launcher-only")
        #expect(harness.run(["config", "fork", "apolloshell-default", "mine"]).exitCode == 0)
        let forked = harness.paths.userConfig.appendingPathComponent("configs/mine/shell.kdl")
        #expect(try String(contentsOf: forked, encoding: .utf8) == "panel \"apolloshell-default\"\n")
        #expect(harness.settings.settings.config == "mine")
        #expect(harness.run(["config", "list"]).stdout == ["  apolloshell-default (built in)", "  launcher-only (built in)", "* mine"])
        #expect(harness.run(["config", "fork", "apolloshell-default", "mine"]).exitCode == 1)
        #expect(harness.run(["config", "fork", "apolloshell-default", "../escape"]).exitCode == 1)
        #expect(harness.run(["config", "fork", "apolloshell-default", "launcher-only"]).exitCode == 1)
        #expect(harness.run(["config"]).exitCode == 2)
        #expect(harness.run(["config", "select"]).exitCode == 2)
    }

    @Test("theme list und select, $CONFIG vor dem alten Ordner")
    func themes() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["theme", "list"]).stdout == ["  Nord", "  Old (Application Support)"])
        #expect(harness.run(["theme", "select", "Old"]).exitCode == 0)
        #expect(harness.settings.settings.theme == "Old")
        #expect(harness.run(["theme", "list"]).stdout == ["  Nord", "* Old (Application Support)"])
        #expect(harness.run(["theme", "select", "Missing"]).exitCode == 1)
        #expect(harness.run(["theme", "select", "--none"]).exitCode == 0)
        #expect(harness.settings.settings.theme == nil)
    }

    @Test("wm reicht die Befehle wie twmctl durch")
    func windowManager() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["wm", "focus", "left"]).exitCode == 0)
        #expect(harness.run(["wm", "windows"]).stdout == [#"[{"id":1}]"#])
        #expect(harness.shell.calls == ["wm focus left", "wm windows"])
        #expect(harness.run(["wm"]).exitCode == 2)
    }

    @Test("schema liest die Registry lokal")
    func schema() throws {
        let harness = try CLIHarness()
        let socketless = harness.folder.url.appendingPathComponent("none").path
        let text = harness.run(["schema", "text"], socket: socketless)
        #expect(text.exitCode == 0)
        #expect(text.stdout.first?.hasPrefix("text") == true)
        let json = harness.run(["schema", "--json", "text"], socket: socketless)
        #expect(json.exitCode == 0)
        #expect(json.stdout.first.flatMap(JSONText.decode) != nil)
        let markdown = harness.run(["schema", "--markdown", "text"], socket: socketless)
        #expect(markdown.stdout.first?.hasPrefix("### `text`") == true)
        #expect(harness.run(["schema"], socket: socketless).stdout.count > 20)
        #expect(harness.run(["schema", "no-such-thing"], socket: socketless).exitCode == 1)
        let typo = harness.run(["schema", "colum"], socket: socketless)
        #expect(typo.exitCode == 1)
        #expect(typo.stderr == ["apollo: nothing in the registry is named 'colum', did you mean 'column'?"])
        #expect(harness.run(["schema", "--yaml"], socket: socketless).exitCode == 2)
    }

    @Test("providers, tree, command-center, stats, restart, quit")
    func remainingCommands() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["providers"]).stdout == [#"{"battery":{"percent":0.5}}"#])
        #expect(harness.run(["tree"]).stdout == [#"["panel#sidebar"]"#])
        #expect(harness.run(["tree", "sidebar"]).exitCode == 0)
        #expect(harness.run(["command-center"]).exitCode == 0)
        let stats = harness.run(["stats"])
        #expect(stats.exitCode == 1)
        #expect(stats.stderr == ["apollo: stats need the start argument --perf-probe"])
        #expect(harness.run(["restart"]).exitCode == 0)
        #expect(harness.run(["quit"]).exitCode == 0)
        #expect(harness.shell.calls == ["providers", "tree -", "tree sidebar", "command-center", "restart", "quit"])
    }

    @Test("version nennt CLI und laufende Shell, ohne Shell nur die CLI")
    func version() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["version"]).stdout == ["apollo 0.2.0-cli", "ApolloShell 0.2.0-test"])
        let alone = harness.run(["version"], socket: harness.folder.url.appendingPathComponent("none").path)
        #expect(alone.exitCode == 0)
        #expect(alone.stdout == ["apollo 0.2.0-cli"])
    }

    @Test("unbekannte Unterbefehle gehen unverändert an den Socket")
    func unknownGoesToSocket() throws {
        let harness = try CLIHarness()
        let result = harness.run(["frobnicate", "a", "b c"])
        #expect(result.exitCode == 0)
        #expect(result.stdout == ["custom ok"])
        #expect(harness.shell.calls == [#"custom frobnicate {"argv":["a","b c"]}"#])
    }

    @Test("ohne laufende Shell: klare Meldung und Exit 3")
    func notRunning() throws {
        let harness = try CLIHarness()
        let result = harness.run(["reload"], socket: harness.folder.url.appendingPathComponent("none").path)
        #expect(result.exitCode == 3)
        #expect(result.stderr.first?.contains("not running") == true)
    }

    @Test("Hilfe und falsche Benutzung")
    func usage() throws {
        let harness = try CLIHarness()
        #expect(harness.run(["help"]).exitCode == 0)
        #expect(harness.run(["--help"]).stdout.first?.hasPrefix("usage: apollo") == true)
        #expect(harness.run([]).exitCode == 2)
    }
}

final class LockedBox<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T

    init(_ value: T) { stored = value }

    var value: T {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

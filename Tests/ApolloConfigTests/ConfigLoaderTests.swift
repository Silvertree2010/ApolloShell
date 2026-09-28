import Testing
import Foundation
import ApolloBase
import ApolloConfig

enum LoaderHarness {
    static let paths = ConfigPaths(
        builtinConfigs: URL(fileURLWithPath: "/builtin"),
        userConfig: URL(fileURLWithPath: "/config"),
        applicationSupport: URL(fileURLWithPath: "/support")
    )
    static let location = ConfigLocation(id: "mine", root: URL(fileURLWithPath: "/config"), isBuiltin: false)

    static func loader(_ fileSystem: any ConfigFileSystem, shellVersion: String = "0.2.0") -> ConfigLoader {
        ConfigLoader(fileSystem: fileSystem, paths: paths, registry: .builtin, filters: .builtin, shellVersion: shellVersion)
    }

    static func load(_ files: [String: String], shellVersion: String = "0.2.0") -> ConfigLoadResult {
        loader(MemoryFileSystem(files), shellVersion: shellVersion).load(location)
    }

    static func loadNotingThread(_ files: [String: String]) -> (ConfigLoadResult, Bool) {
        (load(files), Thread.isMainThread)
    }

    static func syntheticDefaultConfig() -> [String: String] {
        var files: [String: String] = [:]
        var shell = "require \"0.2.0\"\nvar gap 8\nvar radius 12\nvar tab \"media\" persist=#true\nvar modules type=\"list\"\n"
        shell += "define \"card\" {\n    param \"title\"\n    param \"icon\" default=\"bar-power\"\n    column class=\"card\" {\n        icon \"{icon}\"\n        text \"{title | upper}\"\n        slot\n    }\n}\n"
        for index in 1...11 {
            shell += "include \"part\(index).kdl\"\n"
            var part = "panel \"surface-\(index)\" anchor=\"left\" {\n"
            for row in 0..<9 {
                part += "    row id=\"row-\(index)-\(row)\" style=\"gap: {var.gap}px\" {\n"
                part += "        text \"{perf.cpu | percent} · {battery.percent | percent}\" tooltip=\"{clock.now | date 'HH:mm'}\"\n"
                part += "        button class=\"{self.hover ? 'hot' : ''}\" {\n"
                part += "            on-click { toggle \"surface-\(index)\" }\n"
                part += "            icon \"bar-\(row)\"\n"
                part += "        }\n"
                part += "        use \"card\" title=\"Row {var.tab} \(row)\" {\n"
                part += "            text \"{var.radius + \(row)}\"\n"
                part += "        }\n"
                part += "        each app in=\"{apps.running}\" key=\"{app.bundle-id}\" index=\"i\" {\n"
                part += "            text \"{i + 1}. {app.name}\"\n"
                part += "        }\n"
                part += "        when \"{var.tab == 'media'}\" {\n"
                part += "            text \"{media.title ?? ''}\"\n"
                part += "        }\n"
                part += "        else {\n"
                part += "            text \"Idle\"\n"
                part += "        }\n"
                part += "    }\n"
            }
            part += "}\n"
            files["/config/part\(index).kdl"] = part
        }
        shell += "bind \"alt+space\" { toggle \"surface-1\" }\n"
        files["/config/shell.kdl"] = shell
        return files
    }
}

@Suite("ConfigLoader")
struct ConfigLoaderTests {
    @Test("gueltige Config liefert IR, Dateien und keine Diagnosen")
    func loadsValidConfig() throws {
        let result = LoaderHarness.load([
            "/config/shell.kdl": "include \"bar.kdl\"\nbind \"alt+space\" { toggle \"bar\" }\n",
            "/config/bar.kdl": "panel \"bar\" {\n    text \"{clock.now | date 'HH:mm'}\"\n}\n",
        ])
        #expect(result.diagnostics.isEmpty)
        #expect(result.files == [URL(fileURLWithPath: "/config/shell.kdl"), URL(fileURLWithPath: "/config/bar.kdl")])
        let ir = try #require(result.ir)
        #expect(ir.id == "mine" && ir.files == result.files)
        #expect(ir.surfaces.map(\.id) == ["bar"] && ir.binds.map(\.id) == ["alt+space"])
    }

    @Test("Fehler verhindern die IR, Warnungen nicht")
    func errorsSuppressTheIR() {
        let broken = LoaderHarness.load(["/config/shell.kdl": "panel \"bar\" {\n    buton\n}\n"])
        #expect(broken.ir == nil)
        #expect(broken.diagnostics.map(\.message) == ["unknown node 'buton'"])
        let warned = LoaderHarness.load(["/config/shell.kdl": "panel \"bar\" override=#true {\n}\n"])
        #expect(warned.ir != nil)
        #expect(warned.diagnostics.map(\.severity) == [.warning], "\(warned.diagnostics.map(\.message))")
    }

    @Test("Fehler beim Einbinden brechen vor der Schema-Pruefung ab")
    func includeErrorsStopTheLoad() {
        let result = LoaderHarness.load(["/config/shell.kdl": "include \"missing.kdl\"\npanel \"bar\" {\n    buton\n}\n"])
        #expect(result.ir == nil)
        #expect(result.diagnostics.map(\.message) == ["included file 'missing.kdl' does not exist"])
    }

    @Test("fehlende shell.kdl ist genau ein Fehler")
    func missingEntryFile() {
        let result = LoaderHarness.load([:])
        #expect(result.ir == nil)
        #expect(result.diagnostics.count == 1)
        #expect(result.files.isEmpty)
    }

    @Test("zu alte Shell bricht mit genau einem Fehler ab")
    func requireStopsTheLoad() {
        let result = LoaderHarness.load(["/config/shell.kdl": "require \"0.3.0\"\npanel \"bar\" {\n    buton\n}\n"])
        #expect(result.ir == nil)
        #expect(result.diagnostics.map(\.message) == ["this config needs ApolloShell 0.3.0 or newer"])
    }

    @Test("let gibt es nicht mehr, eine var liest andere var")
    func letIsGone() {
        let result = LoaderHarness.load(["/config/shell.kdl": "let gap=8\n"])
        #expect(result.ir == nil)
        #expect(result.diagnostics.map(\.message) == ["unknown node 'let'"])
        let vars = LoaderHarness.load(["/config/shell.kdl": "var gap 8\nvar wide \"{var.gap * 2}\"\npanel \"bar\" {\n    text \"{var.wide}\"\n}\n"])
        #expect(vars.diagnostics.isEmpty, "\(vars.diagnostics.map(\.message))")
        #expect(vars.ir?.vars.map(\.name) == ["gap", "wide"])
    }

    @Test("feature und require feature= gibt es nicht mehr")
    func featureIsGone() {
        let block = LoaderHarness.load(["/config/shell.kdl": "feature \"wm\" {\n    panel \"bar\" {}\n}\n"])
        #expect(block.ir == nil)
        #expect(block.diagnostics.map(\.message) == ["unknown node 'feature'"])
        let required = LoaderHarness.load(["/config/shell.kdl": "require \"0.2.0\" feature=\"wm\"\n"])
        #expect(required.ir == nil)
        #expect(required.diagnostics.count == 1 && required.diagnostics[0].message.contains("'feature'"), "\(required.diagnostics.map(\.message))")
    }

    @Test("Laden ist deterministisch und laeuft ausserhalb des Main Threads")
    func deterministicOffMainThread() async {
        let files = LoaderHarness.syntheticDefaultConfig()
        let first = await Task.detached { LoaderHarness.loadNotingThread(files) }.value
        let second = await Task.detached { LoaderHarness.load(files) }.value
        #expect(first.1 == false)
        #expect(first.0.diagnostics.isEmpty, "\(first.0.diagnostics.map(\.message))")
        #expect(first.0.ir != nil)
        #expect(first.0.ir == second.ir)
        #expect(first.0.diagnostics == second.diagnostics)
    }

    @Test("Schachtelung 64 ueber use und include endet ohne Stack-Ueberlauf")
    func deepNestingThroughUseAndInclude() {
        var shell = "define \"d0\" {\n    column {\n        slot\n    }\n}\n"
        for level in 1...40 {
            shell += "define \"d\(level)\" {\n    column {\n        use \"d\(level - 1)\" {\n            slot\n        }\n    }\n}\n"
        }
        shell += "panel \"bar\" {\n    use \"d40\" {\n        include \"deep.kdl\"\n    }\n}\n"
        var deep = ""
        for level in 0..<30 {
            deep += String(repeating: "    ", count: level) + "column {\n"
        }
        for level in (0..<30).reversed() {
            deep += String(repeating: "    ", count: level) + "}\n"
        }
        let result = LoaderHarness.load(["/config/shell.kdl": shell, "/config/deep.kdl": deep])
        #expect(result.ir == nil)
        #expect(result.diagnostics.contains { $0.message.contains("nested deeper than 64") })
        let shallow = LoaderHarness.load(["/config/shell.kdl": shell.replacingOccurrences(of: "include \"deep.kdl\"", with: "text \"leaf\""), "/config/deep.kdl": deep])
        #expect(shallow.diagnostics.isEmpty, "\(shallow.diagnostics.map(\.message))")
        #expect(shallow.ir != nil)
    }

    @Test("include-Kette steht innerste zuerst, auch bei Lesefehlern")
    func includeChainInnermostFirst() {
        let files = [
            "/config/shell.kdl": "include \"a.kdl\"\n",
            "/config/a.kdl": "\ninclude \"b.kdl\"\n",
            "/config/b.kdl": "\n\ninclude \"c.kdl\"\n",
            "/config/c.kdl": "panel \"p\" surprise=#true {\n}\n",
        ]
        let schema = LoaderHarness.load(files)
        #expect(schema.diagnostics.first?.notes.map(\.message) == [
            "included from /config/b.kdl:3:1",
            "included from /config/a.kdl:2:1",
            "included from /config/shell.kdl:1:1",
        ])
        var missing = files
        missing["/config/c.kdl"] = nil
        let include = LoaderHarness.load(missing)
        #expect(include.diagnostics.first?.notes.map(\.message) == [
            "included from /config/a.kdl:2:1",
            "included from /config/shell.kdl:1:1",
        ])
    }

    @Test("Diagnosen der Pipeline als Golden File")
    func pipelineGolden() {
        let root = URL(fileURLWithPath: DiagnosticGolden.file("pipeline", "shell.kdl")).deletingLastPathComponent()
        let loader = ConfigLoader(fileSystem: DiskFileSystem(), paths: LoaderHarness.paths, registry: .builtin, filters: .builtin, shellVersion: "0.2.0")
        let result = loader.load(ConfigLocation(id: "pipeline", root: root, isBuiltin: false))
        #expect(result.ir == nil)
        DiagnosticGolden.verify("pipeline", diagnostics: result.diagnostics)
    }

    @Test("Config in Groesse der Default-Config laedt im Zeitbudget")
    func loadsDefaultSizedConfigInBudget() {
        let files = LoaderHarness.syntheticDefaultConfig()
        let loader = LoaderHarness.loader(MemoryFileSystem(files))
        var durations: [Double] = []
        for _ in 0..<20 {
            let start = ContinuousClock.now
            let result = loader.load(LoaderHarness.location)
            let elapsed = ContinuousClock.now - start
            #expect(result.ir != nil)
            durations.append(Double(elapsed.components.attoseconds) / 1e15 + Double(elapsed.components.seconds) * 1000)
        }
        let median = durations.sorted()[durations.count / 2]
        print("config-loader-median-ms \(median)")
        #expect(median <= 150)
    }
}

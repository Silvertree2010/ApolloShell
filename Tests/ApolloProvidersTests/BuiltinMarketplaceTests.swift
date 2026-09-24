import Foundation
import Testing
import ApolloBase
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
@Suite("Eingebauter Marketplace (Resources/builtin)")
struct BuiltinMarketplaceTests {
    static let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    static let resources = repo.appendingPathComponent("Resources")
    static let builtin = resources.appendingPathComponent("builtin")
    static let paths = ConfigPaths(builtinConfigs: resources.appendingPathComponent("configs"), userConfig: FileManager.default.temporaryDirectory.appendingPathComponent("no-config"), applicationSupport: FileManager.default.temporaryDirectory)
    static let inventory = repo.deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("private/specs/0.2-framework/anhang-inventar-0.1.4.2.md")

    static func loadBuiltin() -> ConfigLoadResult {
        BuiltinSurfaces.load(paths: paths, fileSystem: DiskFileSystem(), shellVersion: ShellVersion.current)
    }

    static func loadConfig(_ shell: String) -> ConfigLoadResult {
        let root = URL(fileURLWithPath: "/config")
        let loader = ConfigLoader(fileSystem: MemoryFileSystem(["/config/shell.kdl": shell, "/config/style.css": ""]), paths: ConfigPaths(builtinConfigs: root, userConfig: root, applicationSupport: root), registry: .builtin, filters: .builtin, shellVersion: ShellVersion.current)
        return loader.load(ConfigLocation(id: "mine", root: root, isBuiltin: false))
    }

    static func merged(_ shell: String) -> ConfigLoadResult {
        BuiltinSurfaces.apply(loadConfig(shell)) { loadBuiltin() }
    }

    @Test("lädt ohne jede Diagnose, eine Oberfläche window \"marketplace\" mit Titel und Autosave")
    func loadsClean() throws {
        let result = Self.loadBuiltin()
        #expect(result.diagnostics.isEmpty, "\(result.diagnostics.map(\.message))")
        let ir = try #require(result.ir)
        #expect(ir.surfaces.map(\.id) == ["marketplace"])
        let surface = try #require(ir.surface("marketplace"))
        #expect(surface.kind == "window")
        #expect(surface.properties["title"]?.template == .whole(.literal(.string("Marketplace"))))
        #expect(surface.properties["autosave"]?.template == .whole(.literal(.string("Marketplace"))))
        #expect(ir.styleSheets.map(\.url.lastPathComponent) == ["marketplace.css"])
        #expect(ir.vars.allSatisfy { $0.name.hasPrefix("marketplace-") })
        #expect(ir.defines.keys.allSatisfy { $0.hasPrefix("marketplace-") })
    }

    @Test("apollo check der eingebauten Oberfläche: keine Diagnose, auch mit Fixture")
    func check() throws {
        let plain = CheckCommand.run(arguments: [Self.builtin.path], environment: ["HOME": NSTemporaryDirectory()], fileSystem: DiskFileSystem(), executableURL: Self.resources.appendingPathComponent("bin/apollo"))
        #expect(plain.exitCode == CheckCommand.Exit.ok, "\(plain.output)")
        #expect(plain.output.isEmpty, "\(plain.output)")
        let ir = try #require(Self.loadBuiltin().ir)
        let fixture = ProviderFixture.load(Self.builtin.appendingPathComponent("fixture.kdl"))
        #expect(fixture.diagnostics.isEmpty, "\(fixture.diagnostics.map(\.message))")
        let diagnostics = FixtureFieldCheck.run(ir, fixture: fixture)
        #expect(diagnostics.isEmpty, "\(diagnostics.map(\.message))")
    }

    @Test("theme-preview theme= nimmt String oder Record (Fund 11-12)")
    func themePreviewType() throws {
        let property = try #require(SchemaRegistry.builtin.node("theme-preview")?.properties.first { $0.name == "theme" })
        #expect(property.type == .oneOf([.string, .record]))
    }

    @Test("Grösse aus CSS: 780×620, min 640×480, per #marketplace überschreibbar")
    func size() throws {
        let css = try String(contentsOf: Self.builtin.appendingPathComponent("marketplace.css"), encoding: .utf8)
        #expect(css.contains("#marketplace { width: 780px; height: 620px; min-width: 640px; min-height: 480px; }"))
    }

    @Test("Zusammenführen: Stylesheet zuerst, Config gewinnt bei Oberfläche und var, enabled=#false lädt nichts")
    func merge() throws {
        let merged = try #require(Self.merged("window \"settings\" { }\nstyle \"style.css\"\n").ir)
        #expect(merged.surfaces.map(\.id) == ["settings", "marketplace"])
        #expect(merged.styleSheets.map(\.url.lastPathComponent) == ["marketplace.css", "style.css"])
        let off = try #require(Self.merged("marketplace enabled=#false\nwindow \"settings\" { }\n").ir)
        #expect(!BuiltinSurfaces.marketplaceEnabled(off))
        #expect(off.surface("marketplace") == nil)
        let own = try #require(Self.merged("var marketplace-tab \"mine\"\nwindow \"marketplace\" title=\"Mine\" { }\n").ir)
        #expect(own.surfaces.filter { $0.id == "marketplace" }.count == 1)
        #expect(own.surface("marketplace")?.properties["title"]?.template == .whole(.literal(.string("Mine"))))
        #expect(own.vars.filter { $0.name == "marketplace-tab" }.count == 1)
        let on = try #require(Self.merged("marketplace enabled=#true\n").ir)
        #expect(on.surface("marketplace") != nil)
    }

    static func texts(_ roots: [ElementInstance]) -> [String] {
        var out: [String] = []
        var stack = Array(roots.reversed())
        while let element = stack.popLast() {
            if element.kind == "text", case .string(let text)? = element.arguments.first?.value { out.append(text) }
            stack.append(contentsOf: element.children.reversed())
            for slot in element.slotChildren.values { stack.append(contentsOf: slot.reversed()) }
        }
        return out
    }

    @MainActor
    struct View {
        let session: FixtureFieldCheck.Session

        init() throws {
            let ir = try #require(BuiltinMarketplaceTests.loadBuiltin().ir)
            let fixture = ProviderFixture.load(BuiltinMarketplaceTests.builtin.appendingPathComponent("fixture.kdl"))
            session = FixtureFieldCheck.session(ir, fixture: fixture)
            session.runtime.open("marketplace", screenKey: nil)
            session.flush()
        }

        func set(_ name: String, _ value: String) {
            _ = session.vars.set(name, .string(value))
            session.flush()
        }

        var texts: [String] {
            BuiltinMarketplaceTests.texts(session.runtime.surface("marketplace", screenKey: "main")?.root ?? [])
        }
    }

    static let mapping: [String: [(String, String)]] = [
        "MP-01": [("file", "window \"marketplace\" title=\"Marketplace\" autosave=\"Marketplace\"")],
        "MP-02": [("browse", "Browse"), ("browse", "My themes"), ("browse", "Review (1)")],
        "MP-03": [("file", "Marketplace unavailable"), ("file", "Try again"), ("file", "No themes yet"), ("file", "progress class=\"marketplace-spinner\"")],
        "MP-04": [("browse", "Dusk"), ("browse", "by octo"), ("file", "theme-preview theme=\"{item}\"")],
        "MP-05": [("detail", "by arctic · version 1"), ("detail", "License: CC0-1.0 · Based on Nord (MIT)"), ("detail", "Report…"), ("detail", "Remove"), ("detail", "Close"), ("detail", "Light"), ("detail", "Dark")],
        "MP-06": [("browse", "Get"), ("browse", "Use"), ("file", "text \"Update\"")],
        "MP-07": [("file", "marketplace.get \"{item.id}\""), ("file", "marketplace.update \"{item.id}\"")],
        "MP-08": [("file", "marketplace.use \"{item.id}\"")],
        "MP-09": [("file", "marketplace.remove \"{item.id}\"")],
        "MP-10": [("report", "Report this theme"), ("report", "For content that is illegal, offensive or copies someone else's work. A theme reported three times is hidden until it is reviewed.")],
        "MP-11": [("file", "text \"{marketplace.sign-in.code}\""), ("file", "marketplace.copy-code"), ("file", "text \"Copy\""), ("file", "Sign in with GitHub"), ("file", "Connecting to GitHub…")],
        "MP-12": [("file", "marketplace.cancel-sign-in")],
        "MP-13": [("browse", "@octo"), ("file", "item \"Sign out\""), ("file", "item \"Delete account and themes…\""), ("delete-account", "Delete your Marketplace account?")],
        "MP-14": [("source", "Sources/ApolloShell/Marketplace/MarketplaceKeychain.swift|.marketplace"), ("source", "Sources/ApolloShell/Marketplace/MarketplaceKeychain.swift|\"session\"")],
        "MP-15": [("submit", "Submit a theme"), ("submit", "Give it a name first: --apollo-theme-name in the file."), ("file", "This theme uses images. The Marketplace takes plain CSS themes only for now."), ("file", "There is nothing in this theme the shell knows.")],
        "MP-16": [("submit", "I made this theme or may share it, and publish it under CC0 (free for anyone to use). I agree to the Terms."), ("file", "accept-terms=\"{var.marketplace-agreed}\"")],
        "MP-17": [("mine", "Not accepted"), ("mine", "Copy of Nord"), ("file", "Waiting for review · version {own.version}"), ("file", "Live · version {own.version}"), ("file", "text \"Hidden\"")],
        "MP-18": [("mine", "New version…"), ("mine", "Delete"), ("file", "marketplace.delete \"{own.id}\"")],
        "MP-19": [("review", "Ember"), ("review", "Update: name or description changed."), ("review", "Report: spam"), ("review", "by flame · version 1 · waiting")],
        "MP-20": [("review", "Approve"), ("review", "Reject…"), ("review", "Hide…"), ("review", "Ban author…"), ("file", "Show again"), ("reason", "The author sees this reason.")],
        "MP-21": [("browse", "Terms"), ("browse", "Privacy"), ("browse", "Done"), ("file", "https://silvertree2010.github.io/ApolloShell/terms.html"), ("file", "https://silvertree2010.github.io/ApolloShell/privacy.html")],
        "MP-22": [("source", "Sources/ApolloShell/Marketplace/SystemMarketplaceHost.swift|\"MarketplaceURL\"")],
        "MP-23": [("file", "Something went wrong")],
        "MP-24": [("browse", "Thanks. The report was sent.")],
    ]

    @Test("Zuordnung MP-01 bis MP-24: jede Inventarzeile hat einen Beleg")
    func mapping() throws {
        let inventory = try String(contentsOf: Self.inventory, encoding: .utf8)
        let rows = inventory.split(separator: "\n").compactMap { line -> String? in
            guard line.hasPrefix("| MP-") else { return nil }
            return String(line.dropFirst(2).prefix(5))
        }
        #expect(rows == (1...24).map { String(format: "MP-%02d", $0) })
        #expect(Set(Self.mapping.keys) == Set(rows))
        let file = try String(contentsOf: Self.builtin.appendingPathComponent("marketplace.kdl"), encoding: .utf8)
        let view = try View()
        var screens: [String: [String]] = ["browse": view.texts]
        view.set("marketplace-tab", "mine")
        screens["mine"] = view.texts
        view.set("marketplace-tab", "review")
        screens["review"] = view.texts
        view.set("marketplace-tab", "browse")
        view.set("marketplace-detail", "t2")
        screens["detail"] = view.texts
        view.set("marketplace-detail", "")
        for sheet in ["report", "reason", "delete-account"] {
            view.set("marketplace-sheet", sheet)
            screens[sheet] = view.texts
        }
        view.set("marketplace-choice", "nameless")
        view.set("marketplace-sheet", "submit")
        screens["submit"] = view.texts
        for (row, evidence) in Self.mapping.sorted(by: { $0.key < $1.key }) {
            for (place, needle) in evidence {
                switch place {
                case "file":
                    #expect(file.contains(needle), "\(row): \(needle) fehlt in marketplace.kdl")
                case "source":
                    let parts = needle.split(separator: "|", maxSplits: 1).map(String.init)
                    let text = try String(contentsOf: Self.repo.appendingPathComponent(parts[0]), encoding: .utf8)
                    #expect(text.contains(parts[1]), "\(row): \(parts[1]) fehlt in \(parts[0])")
                default:
                    #expect(screens[place]?.contains(needle) == true, "\(row): \"\(needle)\" nicht in \(place): \(screens[place] ?? [])")
                }
            }
        }
        #expect(view.session.diagnostics.isEmpty, "\(view.session.diagnostics.map(\.message))")
    }
}

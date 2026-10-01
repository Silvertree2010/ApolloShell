import AppKit
import UniformTypeIdentifiers
import ApolloBase
import ApolloConfig
import ApolloControl
import ApolloProviders
import ApolloRuntime
import ApolloShellCore

@MainActor
final class GlobalActionEffects {
    var openURL: @MainActor (URL) -> Bool = { NSWorkspace.shared.open($0) }
    var openFile: @MainActor (URL, String?) -> Bool = { file, app in
        guard let app else { return NSWorkspace.shared.open(file) }
        guard let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: app) ?? GlobalActionEffects.appPath(app) else { return false }
        NSWorkspace.shared.open([file], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        return true
    }
    var reveal: @MainActor (URL) -> Void = { NSWorkspace.shared.activateFileViewerSelecting([$0]) }
    var copy: @MainActor (String) -> Void = { text in
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
    var pick: @MainActor (_ folders: Bool, _ types: [String]) -> URL? = { folders, types in
        let panel = NSOpenPanel()
        panel.canChooseDirectories = folders
        panel.canChooseFiles = !folders
        panel.allowsMultipleSelection = false
        if !types.isEmpty { panel.allowedContentTypes = types.compactMap { .init(filenameExtension: $0) } }
        NSApp.activate()
        return panel.runModal() == .OK ? panel.url : nil
    }
    var sound: @MainActor (String) -> Bool = { name in
        guard let sound = NSSound(named: NSSound.Name(name)) else { return false }
        sound.play()
        return true
    }

    static func appPath(_ text: String) -> URL? {
        let url = URL(fileURLWithPath: (text as NSString).expandingTildeInPath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}

extension LiveShell {
    func registerGlobalActions(_ assembly: ShellAssembly) {
        let effects = globalEffects
        func text(_ call: ResolvedActionCall, _ index: Int, _ what: String) throws -> String {
            guard index < call.arguments.count, let value = call.arguments[index].plainText, !value.isEmpty else {
                throw ActionFailure("\(call.name) needs \(what)")
            }
            return value
        }
        func path(_ call: ResolvedActionCall) throws -> URL {
            URL(fileURLWithPath: (try text(call, 0, "a path") as NSString).expandingTildeInPath)
        }
        func register(_ name: String, _ body: @escaping @MainActor (ResolvedActionCall) throws -> Void) {
            assembly.actions.register(name, ClosureAction(body))
        }
        register("open-url") { call in
            let raw = try text(call, 0, "a URL")
            guard let url = URL(string: raw), url.scheme != nil else { throw ActionFailure("open-url: \"\(raw)\" is not a URL") }
            if !effects.openURL(url) { throw ActionFailure("open-url: nothing opens \"\(raw)\"") }
        }
        register("open-file") { call in
            let file = try path(call)
            if !effects.openFile(file, call.properties["app"]?.plainText) { throw ActionFailure("open-file: could not open \(file.path)") }
        }
        register("reveal-file") { call in effects.reveal(try path(call)) }
        register("clipboard.copy") { call in
            guard let value = call.arguments.first else { throw ActionFailure("clipboard.copy needs a text") }
            effects.copy(value.plainText ?? value.stringified)
        }
        register("sound") { call in
            let name = try text(call, 0, "a sound name")
            if !effects.sound(name) { throw ActionFailure("sound: there is no system sound \"\(name)\"") }
        }
        register("pick-file") { [weak self] call in
            let name = try text(call, 0, "a var name")
            var types: [String] = []
            if case .list(let list)? = call.properties["types"] { types = list.compactMap(\.plainText) }
            guard let url = effects.pick(call.properties["folders"] == .bool(true), types) else { return }
            _ = self?.assembly?.vars.set(name, .string(url.path), for: nil)
        }
        register("exec") { [weak self] call in
            let command = try text(call, 0, "a command")
            self?.exec(command, timeout: RuntimeDuration.seconds(call.properties["timeout"]) ?? 30)
        }
        register("run-shortcut") { [weak assembly] call in
            guard let provider = assembly?.providers.provider("shortcuts") else { throw ActionFailure("run-shortcut: the shortcuts provider is missing") }
            let arguments = call.arguments
            let properties = call.properties
            Task { @MainActor in _ = try? await provider.perform("run-shortcut", arguments: arguments, properties: properties) }
        }
        register("config.select") { [weak self] call in
            guard let self else { return }
            let id = try text(call, 0, "a config id")
            do { try catalog.select(id) } catch { throw ActionFailure("\(error)") }
            reload()
        }
        register("theme.select") { [weak self] call in
            guard let self else { return }
            let id = call.arguments.first.flatMap(\.plainText).flatMap { $0.isEmpty ? nil : $0 }
            do { try ThemeCatalog(paths: paths, settings: settings).select(id) } catch { throw ActionFailure("\(error)") }
            reload()
        }
        register("shell.reload-config") { [weak self] _ in self?.reload() }
        register("shell.restart") { [weak self] _ in self?.perform(.restart) }
        register("shell.quit") { [weak self] _ in self?.perform(.quit) }
        register("shell.about") { [weak self] _ in self?.perform(.about) }
        register("shell.check-updates") { [weak self] _ in self?.perform(.checkForUpdates) }
        register("shell.install-update") { [weak self] _ in self?.perform(.installUpdate) }
        func flag(_ call: ResolvedActionCall) throws -> Bool {
            guard case .bool(let on)? = call.arguments.first else { throw ActionFailure("\(call.name) needs #true or #false") }
            return on
        }
        register("shell.set-auto-check") { [weak self] call in self?.perform(.setAutoCheck(try flag(call))) }
        register("shell.set-auto-install") { [weak self] call in self?.perform(.setAutoInstall(try flag(call))) }
        register("shell.set-crash-reports") { [weak self] call in
            let raw = try text(call, 0, "ask, always or never")
            guard let mode = CrashReportSettings.Mode(rawValue: raw) else { throw ActionFailure("shell.set-crash-reports: \"\(raw)\" is not ask, always or never") }
            self?.perform(.crashReports(mode))
        }
        register("theme.import") { [weak self] _ in self?.perform(.addTheme) }
        register("theme.open-folder") { [weak self] _ in self?.perform(.openThemesFolder) }
        register("shell.open-config-folder") { [weak self] _ in
            guard let self, let location else { return }
            if location.isBuiltin {
                notice("\(location.id) is built in", "Use Copy to Own Config… in the command center to edit it.")
            } else {
                openFolder(location.root)
            }
        }
        register("shell.edit") { [weak self] call in
            guard let self else { return }
            let file = try path(call)
            let line = call.properties["line"].flatMap { if case .number(let number) = $0, number.isFinite { Int(min(max(number, -1_000_000_000), 1_000_000_000)) } else { nil } } ?? 1
            openInEditor(Diagnostic(.note, "edit", span: SourceSpan(file: file.path, start: SourcePosition(offset: 0, line: line, column: 1), end: SourcePosition(offset: 0, line: line, column: 1))))
        }
    }

    func exec(_ command: String, timeout: Double) {
        let runner = SystemScriptRunner(socketPath: socketPath)
        var finished = false
        let handle = runner.run(command) { [weak self] status, _ in
            finished = true
            if status != 0 { self?.overlay.add(Diagnostic(.warning, "exec \"\(command)\" ended with status \(status)", code: .actionFailed)) }
        }
        guard let handle else {
            overlay.add(Diagnostic(.warning, "exec could not start \"\(command)\"", code: .actionFailed))
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, timeout)) {
            MainActor.assumeIsolated {
                guard !finished else { return }
                handle.terminate()
            }
        }
    }
}

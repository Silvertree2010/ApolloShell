import Foundation
import ApolloConfig

public struct ControlRouter: ControlService {
    public let shell: any ShellControl
    public let configs: ConfigCatalog
    public let themes: ThemeCatalog

    public init(shell: any ShellControl, configs: ConfigCatalog, themes: ThemeCatalog) {
        self.shell = shell
        self.configs = configs
        self.themes = themes
    }

    public func reply(to request: ControlRequest) async -> ControlReply {
        do {
            return try await route(request)
        } catch let error as ShellControlError {
            return .failure(error.message)
        } catch let error as SettingsStoreError {
            return .failure(error.message)
        } catch {
            return .failure("\(error)")
        }
    }

    private func route(_ request: ControlRequest) async throws -> ControlReply {
        let args = Arguments(command: request.cmd, record: request.args)
        switch request.cmd {
        case "reload":
            let summary = await shell.reload()
            return .success(.record(Record([
                ("errors", .number(Double(summary.errors))),
                ("warnings", .number(Double(summary.warnings))),
                ("text", .string(summary.text)),
            ])))
        case "open", "close", "toggle":
            try await shell.surface(SurfaceOperation(rawValue: request.cmd)!, args.string("surface"))
            return .success(.null)
        case "run":
            return .success(FiniteValues.clean(try await shell.run(args.string("actions"))))
        case "eval":
            return .success(FiniteValues.clean(try await shell.evaluate(args.string("expression"))))
        case "watch":
            let stream = try await shell.watch(args.string("expression"))
            return .stream(AsyncStream { continuation in
                let task = Task {
                    for await value in stream {
                        continuation.yield(FiniteValues.clean(value))
                    }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            })
        case "get":
            return .success(FiniteValues.clean(try await shell.variable(args.string("name"))))
        case "set":
            try await shell.setVariable(args.string("name"), to: FiniteValues.clean(try args.value("value")))
            return .success(.null)
        case "emit":
            let name = try args.string("name")
            try await shell.emit(name.hasPrefix("user.") ? name : "user." + name, event: FiniteValues.clean(args.optionalValue("event") ?? .null))
            return .success(.null)
        case "config.list":
            return .success(.list(configs.list().map { entry in
                .record(Record([
                    ("id", .string(entry.id)),
                    ("active", .bool(entry.isActive)),
                    ("builtin", .bool(entry.isBuiltin)),
                    ("path", .string(entry.root.path)),
                ]))
            }))
        case "config.select":
            try configs.select(args.string("id"))
            return .success(.null)
        case "config.fork":
            try configs.fork(args.string("id"), as: args.string("new-id"))
            return .success(.null)
        case "config.path":
            return .success(.string(configs.active.root.path))
        case "theme.list":
            return .success(.list(themes.list().map { entry in
                .record(Record([
                    ("id", .string(entry.id)),
                    ("title", .string(entry.title)),
                    ("active", .bool(entry.isActive)),
                    ("issues", .number(Double(entry.issueCount))),
                    ("legacy-location", .bool(entry.isLegacyLocation)),
                ]))
            }))
        case "theme.select":
            try themes.select(args.optionalString("id"))
            return .success(.null)
        case "wm":
            return .success(FiniteValues.clean(try await shell.windowManager(args.strings("argv"))))
        case "providers":
            return .success(FiniteValues.clean(await shell.providers()))
        case "tree":
            return .success(FiniteValues.clean(try await shell.tree(args.optionalString("surface"))))
        case "command-center":
            await shell.openCommandCenter()
            return .success(.null)
        case "stats":
            return .success(FiniteValues.clean(try await shell.stats()))
        case "restart":
            await shell.restart()
            return .success(.null)
        case "quit":
            await shell.quit()
            return .success(.null)
        case "version":
            return .success(.string(shell.shellVersion))
        default:
            return await shell.custom(request)
        }
    }
}

struct Arguments {
    let command: String
    let record: Record

    func string(_ key: String) throws -> String {
        guard case .string(let text)? = record[key] else {
            throw ShellControlError("'\(command)' needs a string '\(key)'")
        }
        return text
    }

    func optionalString(_ key: String) throws -> String? {
        switch record[key] {
        case nil, .null?: return nil
        case .string(let text)?: return text
        default: throw ShellControlError("'\(command)' expects '\(key)' to be a string")
        }
    }

    func value(_ key: String) throws -> Value {
        guard let value = record[key] else {
            throw ShellControlError("'\(command)' needs '\(key)'")
        }
        return value
    }

    func optionalValue(_ key: String) -> Value? {
        record[key]
    }

    func strings(_ key: String) throws -> [String] {
        guard case .list(let items)? = record[key] else {
            throw ShellControlError("'\(command)' needs a list '\(key)'")
        }
        return try items.map { item in
            guard case .string(let text) = item else { throw ShellControlError("'\(command)' expects '\(key)' to hold strings") }
            return text
        }
    }
}

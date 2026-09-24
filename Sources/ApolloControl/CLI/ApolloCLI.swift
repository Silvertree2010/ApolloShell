import Foundation
import ApolloConfig

public struct ApolloCLI: Sendable {
    public typealias Check = @Sendable ([String]) -> (output: String, exitCode: Int32)

    public static let usage = """
        usage: apollo <command> [arguments]

          check [<folder>]                 load and check a config without applying it
          reload                           hot-reload the config and print diagnostics
          open|close|toggle <surface>      like the actions
          run '<actions>'                  run a KDL snippet of actions
          eval '<expression>'              evaluate an expression, print JSON
          watch '<expression>'             print the value as a JSON line on every change
          get <var> | set <var> <json>     read and write a var
          emit <name> [<json>]             send the event user.<name>
          config list|select <id>|fork <id> <new-id>|path
          theme list|select <id>|select --none
          wm <command ...>                 window manager commands like twmctl
          schema [--json|--markdown] [<name>]
          providers                        every provider field with its current value
          tree [<surface>]                 element tree with identities
          command-center                   open the command center menu
          stats                            counters (only with --perf-probe)
          restart | quit | version

        Unknown commands go unchanged to the running shell.
        """

    public enum Exit {
        public static let ok: Int32 = 0
        public static let failure: Int32 = 1
        public static let usage: Int32 = 2
        public static let notRunning: Int32 = 3
    }

    public let version: String
    public let transport: any ControlTransport
    public let check: Check
    public let registry: SchemaRegistry

    public init(version: String, transport: any ControlTransport, check: @escaping Check, registry: SchemaRegistry = .builtin) {
        self.version = version
        self.transport = transport
        self.check = check
        self.registry = registry
    }

    public func run(_ arguments: [String], out: @escaping (String) -> Void, err: @escaping (String) -> Void) -> Int32 {
        guard let command = arguments.first else {
            err(Self.usage)
            return Exit.usage
        }
        let rest = Array(arguments.dropFirst())
        let context = Context(transport: transport, out: out, err: err)
        switch command {
        case "help", "--help", "-h":
            out(Self.usage)
            return Exit.ok
        case "check":
            let result = check(rest)
            let text = result.output.hasSuffix("\n") ? String(result.output.dropLast()) : result.output
            if !text.isEmpty { out(text) }
            return result.exitCode
        case "schema":
            return schema(rest, out: out, err: err)
        case "version":
            out("apollo \(version)")
            if case .success(.string(let shell))? = try? transport.call("version", Record()) {
                out("ApolloShell \(shell)")
            }
            return Exit.ok
        case "reload":
            guard rest.isEmpty else { return context.usage("reload takes no arguments") }
            return context.call("reload", Record()) { result in
                guard case .record(let summary) = result else { return Exit.ok }
                if case .string(let text)? = summary["text"], !text.isEmpty { out(text) }
                if case .number(let errors)? = summary["errors"], errors > 0 { return Exit.failure }
                return Exit.ok
            }
        case "open", "close", "toggle":
            guard rest.count == 1 else { return context.usage("\(command) needs exactly one surface") }
            return context.call(command, Record([("surface", .string(rest[0]))]), print: .json)
        case "run":
            guard !rest.isEmpty else { return context.usage("run needs actions, for example: apollo run 'audio.set-volume 0.5'") }
            return context.call("run", Record([("actions", .string(rest.joined(separator: " ")))]), print: .json)
        case "eval":
            guard !rest.isEmpty else { return context.usage("eval needs an expression") }
            return context.call("eval", Record([("expression", .string(rest.joined(separator: " ")))]), print: .json)
        case "watch":
            guard !rest.isEmpty else { return context.usage("watch needs an expression") }
            return context.stream("watch", Record([("expression", .string(rest.joined(separator: " ")))]))
        case "get":
            guard rest.count == 1 else { return context.usage("get needs exactly one var name") }
            return context.call("get", Record([("name", .string(rest[0]))]), print: .json)
        case "set":
            guard rest.count == 2 else { return context.usage("set needs a var name and a JSON value") }
            guard let value = JSONText.decode(rest[1]) else {
                return context.usage("'\(rest[1])' is not JSON; quote strings like '\"dark\"'")
            }
            return context.call("set", Record([("name", .string(rest[0])), ("value", value)]), print: .json)
        case "emit":
            guard rest.count == 1 || rest.count == 2 else { return context.usage("emit needs a name and optionally a JSON value") }
            var args = Record([("name", .string(rest[0]))])
            if rest.count == 2 {
                guard let value = JSONText.decode(rest[1]) else { return context.usage("'\(rest[1])' is not JSON") }
                args["event"] = value
            }
            return context.call("emit", args, print: .json)
        case "config":
            return config(rest, context: context)
        case "theme":
            return theme(rest, context: context)
        case "wm":
            guard !rest.isEmpty else { return context.usage("wm needs a command, for example: apollo wm focus left") }
            return context.call("wm", Record([("argv", .list(rest.map(Value.string)))]), print: .json)
        case "providers", "command-center", "stats", "restart", "quit":
            guard rest.isEmpty else { return context.usage("\(command) takes no arguments") }
            return context.call(command, Record(), print: .json)
        case "tree":
            guard rest.count <= 1 else { return context.usage("tree takes at most one surface") }
            return context.call("tree", Record(rest.first.map { [("surface", .string($0))] } ?? []), print: .json)
        default:
            return context.call(command, Record([("argv", .list(rest.map(Value.string)))]), print: .plain)
        }
    }

    private func config(_ rest: [String], context: Context) -> Int32 {
        switch rest.first {
        case "list" where rest.count == 1:
            return context.call("config.list", Record()) { result in
                for entry in Self.records(result) {
                    let marker = entry["active"] == .bool(true) ? "* " : "  "
                    let builtin = entry["builtin"] == .bool(true) ? " (built in)" : ""
                    context.out(marker + Self.string(entry["id"]) + builtin)
                }
                return Exit.ok
            }
        case "select" where rest.count == 2:
            return context.call("config.select", Record([("id", .string(rest[1]))]), print: .json)
        case "fork" where rest.count == 3:
            return context.call("config.fork", Record([("id", .string(rest[1])), ("new-id", .string(rest[2]))]), print: .json)
        case "path" where rest.count == 1:
            return context.call("config.path", Record(), print: .plain)
        default:
            return context.usage("config list | select <id> | fork <id> <new-id> | path")
        }
    }

    private func theme(_ rest: [String], context: Context) -> Int32 {
        switch rest.first {
        case "list" where rest.count == 1:
            return context.call("theme.list", Record()) { result in
                for entry in Self.records(result) {
                    let marker = entry["active"] == .bool(true) ? "* " : "  "
                    let legacy = entry["legacy-location"] == .bool(true) ? " (Application Support)" : ""
                    context.out(marker + Self.string(entry["id"]) + legacy)
                }
                return Exit.ok
            }
        case "select" where rest.count == 2:
            let id: Value = rest[1] == "--none" ? .null : .string(rest[1])
            return context.call("theme.select", Record([("id", id)]), print: .json)
        default:
            return context.usage("theme list | select <id> | select --none")
        }
    }

    private func schema(_ rest: [String], out: (String) -> Void, err: (String) -> Void) -> Int32 {
        var format = SchemaFormat.text
        var name: String?
        for argument in rest {
            switch argument {
            case "--json": format = .json
            case "--markdown": format = .markdown
            case _ where argument.hasPrefix("-"):
                err("apollo: unknown option \(argument)\n\n" + Self.usage)
                return Exit.usage
            default:
                guard name == nil else {
                    err("apollo: schema takes at most one name")
                    return Exit.usage
                }
                name = argument
            }
        }
        guard let lines = SchemaText.render(registry, name: name, format: format) else {
            err("apollo: nothing in the registry is named '\(name ?? "")'")
            return Exit.failure
        }
        lines.forEach(out)
        return Exit.ok
    }

    static func records(_ value: Value) -> [Record] {
        guard case .list(let items) = value else { return [] }
        return items.compactMap { item in
            if case .record(let record) = item { return record }
            return nil
        }
    }

    static func string(_ value: Value?) -> String {
        if case .string(let text)? = value { return text }
        return ""
    }
}

private struct Context {
    enum Printing { case json, plain }

    let transport: any ControlTransport
    let out: (String) -> Void
    let err: (String) -> Void

    func usage(_ message: String) -> Int32 {
        err("apollo: \(message)")
        return ApolloCLI.Exit.usage
    }

    func call(_ cmd: String, _ args: Record, print printing: Printing) -> Int32 {
        call(cmd, args) { result in
            switch (result, printing) {
            case (.null, _):
                break
            case (.string(let text), .plain):
                out(text)
            default:
                out(JSONText.encode(result))
            }
            return ApolloCLI.Exit.ok
        }
    }

    func call(_ cmd: String, _ args: Record, handle: (Value) -> Int32) -> Int32 {
        do {
            switch try transport.call(cmd, args) {
            case .success(let result):
                return handle(result)
            case .failure(let message):
                err("apollo: \(message)")
                return ApolloCLI.Exit.failure
            }
        } catch {
            return report(error)
        }
    }

    func stream(_ cmd: String, _ args: Record) -> Int32 {
        var code = ApolloCLI.Exit.ok
        do {
            try transport.stream(cmd, args) { outcome in
                switch outcome {
                case .success(let value):
                    out(JSONText.encode(value))
                    return true
                case .failure(let message):
                    err("apollo: \(message)")
                    code = ApolloCLI.Exit.failure
                    return false
                }
            }
        } catch {
            return report(error)
        }
        return code
    }

    func report(_ error: any Error) -> Int32 {
        if case ControlSocketError.notRunning = error {
            err("apollo: \(error)")
            return ApolloCLI.Exit.notRunning
        }
        err("apollo: \(error)")
        return ApolloCLI.Exit.failure
    }
}

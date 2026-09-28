import ApolloBase
import ApolloKDL

public struct ShellSettingsFile: Sendable, Hashable {
    public var config: String?
    public var theme: String?
    public var autoCheckUpdates: Bool
    public var autoInstallUpdates: Bool
    public var crashReports: String
    public var editor: String?

    public init(
        config: String? = nil,
        theme: String? = nil,
        autoCheckUpdates: Bool = true,
        autoInstallUpdates: Bool = true,
        crashReports: String = "ask",
        editor: String? = nil
    ) {
        self.config = config
        self.theme = theme
        self.autoCheckUpdates = autoCheckUpdates
        self.autoInstallUpdates = autoInstallUpdates
        self.crashReports = crashReports
        self.editor = editor
    }

    static let knownNodes: Set<String> = ["config", "theme", "updates", "crash-reports", "editor"]

    public static func parse(_ text: String, file: String) -> (ShellSettingsFile, [Diagnostic]) {
        var result = ShellSettingsFile()
        guard let document = try? KDLDocument.parse(text, file: file) else {
            return (result, [Diagnostic(.warning, "settings.kdl could not be parsed, using defaults", span: .synthetic(file), code: .settingsSyntax)])
        }
        var diagnostics: [Diagnostic] = []
        var seen: Set<String> = []
        for node in document.nodes {
            if seen.contains(node.name) {
                diagnostics.append(Diagnostic(.warning, "duplicate '\(node.name)' node in settings.kdl, using the last one", span: node.span, code: .settingsDuplicate))
            }
            seen.insert(node.name)
            switch node.name {
            case "config":
                if case .string(let id)? = node.arguments.first?.scalar {
                    result.config = id
                } else {
                    diagnostics.append(Diagnostic(.warning, "'config' expects a string argument", span: node.span, code: .settingsValue))
                }
            case "theme":
                switch node.arguments.first?.scalar {
                case .null, nil:
                    result.theme = nil
                case .string(let name):
                    result.theme = name
                default:
                    diagnostics.append(Diagnostic(.warning, "'theme' expects a string or #null", span: node.span, code: .settingsValue))
                }
            case "updates":
                if case .bool(let value)? = node.property("auto-check")?.value.scalar {
                    result.autoCheckUpdates = value
                }
                if case .bool(let value)? = node.property("auto-install")?.value.scalar {
                    result.autoInstallUpdates = value
                }
            case "crash-reports":
                if case .string(let mode)? = node.arguments.first?.scalar {
                    result.crashReports = mode
                } else {
                    diagnostics.append(Diagnostic(.warning, "'crash-reports' expects a string argument", span: node.span, code: .settingsValue))
                }
            case "editor":
                if case .string(let command)? = node.arguments.first?.scalar {
                    result.editor = command
                } else {
                    diagnostics.append(Diagnostic(.warning, "'editor' expects a string argument", span: node.span, code: .settingsValue))
                }
            default:
                diagnostics.append(Diagnostic(.warning, "unknown settings.kdl node '\(node.name)'", span: node.nameSpan, code: .settingsUnknown))
            }
        }
        return (result, diagnostics)
    }

    public static func updating(_ text: String, file: String, set changes: ShellSettingsChange) throws -> String {
        let document = try KDLDocument.parse(text, file: file)
        var editor = KDLEditor(document)
        switch changes {
        case .config(let id):
            if let id {
                try upsert(configNode(id), name: "config", editor: &editor)
            } else if let index = lastIndex(editor, named: "config") {
                try editor.remove(at: [index])
            }
        case .theme(let name):
            if let name {
                try upsert(themeNode(.string(name)), name: "theme", editor: &editor)
            } else if let index = lastIndex(editor, named: "theme") {
                try editor.replace(at: [index], with: themeNode(.null))
            }
        case .updates(let autoCheck, let autoInstall):
            try upsert(updatesNode(autoCheck: autoCheck, autoInstall: autoInstall), name: "updates", editor: &editor)
        case .crashReports(let mode):
            try upsert(crashReportsNode(mode), name: "crash-reports", editor: &editor)
        case .editor(let command):
            if let command {
                try upsert(editorNode(command), name: "editor", editor: &editor)
            } else if let index = lastIndex(editor, named: "editor") {
                try editor.remove(at: [index])
            }
        }
        return editor.text
    }

    static func lastIndex(_ editor: KDLEditor, named name: String) -> Int? {
        editor.document.nodes.lastIndex { $0.name == name }
    }

    static func upsert(_ node: KDLNode, name: String, editor: inout KDLEditor) throws {
        if let index = lastIndex(editor, named: name) {
            try editor.replace(at: [index], with: node)
        } else {
            try editor.insert(node, intoChildrenOf: nil, at: editor.document.nodes.count)
        }
    }

    static func configNode(_ id: String) -> KDLNode {
        KDLNode(name: "config", arguments: [KDLValue(.string(id))])
    }

    static func themeNode(_ scalar: KDLScalar) -> KDLNode {
        KDLNode(name: "theme", arguments: [KDLValue(scalar)])
    }

    static func updatesNode(autoCheck: Bool, autoInstall: Bool) -> KDLNode {
        KDLNode(
            name: "updates",
            properties: [
                KDLProperty(name: "auto-check", value: KDLValue(.bool(autoCheck))),
                KDLProperty(name: "auto-install", value: KDLValue(.bool(autoInstall))),
            ]
        )
    }

    static func crashReportsNode(_ mode: String) -> KDLNode {
        KDLNode(name: "crash-reports", arguments: [KDLValue(.string(mode))])
    }

    static func editorNode(_ command: String) -> KDLNode {
        KDLNode(name: "editor", arguments: [KDLValue(.string(command))])
    }
}

public enum ShellSettingsChange: Sendable, Hashable {
    case config(String?)
    case theme(String?)
    case updates(autoCheck: Bool, autoInstall: Bool)
    case crashReports(String)
    case editor(String?)
}

import Foundation

public struct CommandLineToolInstaller: Sendable {
    public let home: URL
    public let helper: URL

    public init(home: URL, helper: URL) {
        self.home = home
        self.helper = helper
    }

    public var link: URL {
        home.appendingPathComponent(".local/bin/apollo")
    }

    public var isInstalled: Bool {
        guard let target = try? FileManager.default.destinationOfSymbolicLink(atPath: link.path) else { return false }
        return URL(fileURLWithPath: target).standardizedFileURL.path == helper.standardizedFileURL.path
    }

    public func install() throws {
        let files = FileManager.default
        if (try? files.destinationOfSymbolicLink(atPath: link.path)) != nil {
            try files.removeItem(at: link)
        } else if files.fileExists(atPath: link.path) {
            throw ShellControlError("\(link.path) exists and is not a link; remove it first")
        }
        do {
            try files.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
            try files.createSymbolicLink(atPath: link.path, withDestinationPath: helper.path)
        } catch {
            throw ShellControlError("could not link \(link.path): \(error.localizedDescription)")
        }
    }

    public static func pathHint(path: String, shell: String, home: URL) -> String? {
        let wanted = home.appendingPathComponent(".local/bin").standardizedFileURL.path
        let entries = path.split(separator: ":").map { entry -> String in
            let text = String(entry)
            let expanded = text.hasPrefix("~/") ? home.path + text.dropFirst(1) : text
            return URL(fileURLWithPath: expanded).standardizedFileURL.path
        }
        guard !entries.contains(wanted) else { return nil }
        let line = "export PATH=\"$HOME/.local/bin:$PATH\""
        switch URL(fileURLWithPath: shell).lastPathComponent {
        case "fish": return "fish_add_path ~/.local/bin"
        case "bash": return "Add to ~/.bash_profile: \(line)"
        default: return "Add to ~/.zshrc: \(line)"
        }
    }
}

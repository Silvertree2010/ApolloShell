import Foundation

public enum HomebrewUpgrade {
    public static let formula = "apolloshell"

    public struct Install: Equatable, Sendable {
        public let prefix: String

        public init(prefix: String) {
            self.prefix = prefix
        }

        public var brew: String { prefix + "/bin/brew" }
        public var optBundlePath: String { prefix + "/opt/\(HomebrewUpgrade.formula)/ApolloShell.app" }
    }

    public static func locate(bundlePath: String,
                              resolve: (String) -> String = { URL(fileURLWithPath: $0).resolvingSymlinksInPath().path },
                              isExecutable: (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) }) -> Install? {
        let real = resolve(bundlePath)
        let marker = "/Cellar/\(formula)/"
        if let r = real.range(of: marker) {
            let i = Install(prefix: String(real[..<r.lowerBound]))
            if isExecutable(i.brew) { return i }
        }
        for p in ["/opt/homebrew", "/usr/local"] {
            let i = Install(prefix: p)
            if isExecutable(i.brew) { return i }
        }
        return nil
    }

    public static func arguments() -> [String] {
        ["upgrade", "--formula", formula]
    }

    public static func environment(base: [String: String], install: Install) -> [String: String] {
        var e: [String: String] = [:]
        for k in ["HOME", "USER", "LOGNAME", "TMPDIR", "LANG", "SSH_AUTH_SOCK"] {
            if let v = base[k] { e[k] = v }
        }
        e["PATH"] = "\(install.prefix)/bin:\(install.prefix)/sbin:/usr/bin:/bin:/usr/sbin:/sbin"
        e["HOMEBREW_NO_INSTALL_CLEANUP"] = "1"
        e["HOMEBREW_NO_ENV_HINTS"] = "1"
        e["HOMEBREW_NO_COLOR"] = "1"
        e["NONINTERACTIVE"] = "1"
        return e
    }

    public enum Outcome: Equatable, Sendable {
        case upgraded(AppVersion)
        case unchanged
        case failed(String)
    }

    public static func outcome(status: Int32, output: String, current: AppVersion?, installed: AppVersion?) -> Outcome {
        if let installed, let current, installed > current { return .upgraded(installed) }
        if let installed, current == nil, status == 0 { return .upgraded(installed) }
        guard status == 0 else {
            let tail = output.split(whereSeparator: \.isNewline)
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .last { $0.hasPrefix("Error:") } ?? "brew upgrade exited with status \(status)"
            return .failed(String(tail))
        }
        return .unchanged
    }
}

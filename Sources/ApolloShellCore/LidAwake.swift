import Foundation

public enum LidAwake {
    public static let batteryFloor = 10

    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    public static let osascript = "/usr/bin/osascript"
    static let visudo = "/usr/sbin/visudo"
    public static let sudoersFile = "/etc/sudoers.d/apolloshell"

    public static func sleepDisabled(pmsetOutput: String) -> Bool? {
        for line in pmsetOutput.split(separator: "\n") {
            let parts = line.split(whereSeparator: \.isWhitespace)
            if parts.count >= 2, parts[0] == "SleepDisabled" { return parts[1] == "1" }
        }
        return nil
    }

    public static func shouldStop(battery: BatteryState?) -> Bool {
        guard let battery, !battery.onAC else { return false }
        return battery.level <= batteryFloor
    }

    public static func sudoArguments(disableSleep: Bool) -> [String] {
        ["-n", pmset, "-a", "disablesleep", disableSleep ? "1" : "0"]
    }

    public static func adminScript(disableSleep: Bool, installRuleFor user: String? = nil) -> String {
        var command = "\(pmset) -a disablesleep \(disableSleep ? "1" : "0")"
        let install = disableSleep ? user.flatMap(installRuleCommand(user:)) : nil
        if let install { command += " && { \(install); true; }" }
        let prompt: String
        if !disableSleep {
            prompt = String(localized: "ApolloShell would like to allow sleep with the lid closed again.")
        } else if install != nil {
            prompt = String(localized: "ApolloShell would like to suspend sleep with the lid closed while “Keep Awake” is on. So this works without a password from now on, it adds a rule that allows only this one command.")
        } else {
            prompt = String(localized: "ApolloShell would like to suspend sleep with the lid closed while “Keep Awake” is on.")
        }
        return shellScript(command, prompt: prompt)
    }

    public static func osascriptArguments(disableSleep: Bool, installRuleFor user: String? = nil) -> [String] {
        ["-e", adminScript(disableSleep: disableSleep, installRuleFor: user)]
    }

    public static func removeRuleArguments() -> [String] {
        let prompt = String(localized: "ApolloShell would like to remove its rule that switches lid-closed sleep without a password.")
        return ["-e", shellScript("/bin/rm -f \(sudoersFile)", prompt: prompt)]
    }

    static func isSafeUserName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    public static func sudoersRule(user: String) -> String? {
        guard isSafeUserName(user) else { return nil }
        let allowed = [true, false]
            .map { sudoArguments(disableSleep: $0).dropFirst().joined(separator: " ") }
            .joined(separator: ", ")
        return """
        # Written by ApolloShell: lets Keep Awake switch lid sleep without a password.
        # Allows only the two commands below. Remove it in Nexus or with: sudo rm \(sudoersFile)
        \(user) ALL=(root) NOPASSWD: \(allowed)

        """
    }

    static func installRuleCommand(user: String) -> String? {
        guard let rule = sudoersRule(user: user) else { return nil }
        let lines = rule.split(separator: "\n").map { "'\($0)'" }.joined(separator: " ")
        return [
            "t=$(/usr/bin/mktemp /private/tmp/apolloshell-sudoers.XXXXXX)",
            "/usr/bin/printf '%s\\n' \(lines) > \"$t\"",
            "\(visudo) -cf \"$t\" >/dev/null",
            "/usr/sbin/chown root:wheel \"$t\"",
            "/bin/chmod 0440 \"$t\"",
            "/bin/mv -f \"$t\" \(sudoersFile)",
        ].joined(separator: " && ") + "; /bin/rm -f \"$t\""
    }

    static func shellScript(_ command: String, prompt: String) -> String {
        "do shell script \"\(appleScriptEscaped(command))\" "
            + "with prompt \"\(appleScriptEscaped(prompt))\" with administrator privileges"
    }

    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

public struct KeepAwakeSettings: Codable, Equatable, Sendable {
    public var lidClosed: Bool

    public init(lidClosed: Bool) {
        self.lidClosed = lidClosed
    }

    public static let firstLaunch = KeepAwakeSettings(lidClosed: false)
    public static let existingInstall = KeepAwakeSettings(lidClosed: true)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lidClosed = (try? c.decodeIfPresent(Bool.self, forKey: .lidClosed)) ?? false
    }
}

public struct AppleDockHidingSettings: Codable, Equatable, Sendable {
    public var hideWhileRunning: Bool

    public init(hideWhileRunning: Bool) {
        self.hideWhileRunning = hideWhileRunning
    }

    public static let firstLaunch = AppleDockHidingSettings(hideWhileRunning: false)
    public static let existingInstall = AppleDockHidingSettings(hideWhileRunning: true)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        hideWhileRunning = (try? c.decodeIfPresent(Bool.self, forKey: .hideWhileRunning)) ?? false
    }
}

public enum KeepAwakeLid: Equatable, Sendable {
    case off
    case on
    case pending
    case declined
}

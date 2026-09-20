import Foundation

/// "Keep Awake" with the lid closed too.
///
/// The power assertion only keeps the Mac awake while it is idle; closing the
/// lid sends it to sleep all the same. Only `pmset -a disablesleep 1`
/// prevents that, and that needs root. Amphetamine does it the same way
/// ("Closed-Display Mode").
///
/// First `sudo -n` (without a prompt, which only works with password-free
/// sudo). Otherwise macOS asks for an administrator through AppleScript. On
/// the first switch-on the same prompt sets up a narrowly limited sudo rule
/// (`sudoersRule`): after that both work without a password, the reset on quit
/// and on the battery guard included, when nobody is there to answer a
/// prompt. Whoever refuses gets "Keep Awake" without the lid part.
/// ohne den Deckel-Teil.
public enum LidAwake {
    /// On battery, "Keep Awake" ends by itself from this charge on: a closed
    /// Mac in a bag should not run empty or get hot.
    public static let batteryFloor = 10

    public static let pmset = "/usr/bin/pmset"
    public static let sudo = "/usr/bin/sudo"
    public static let osascript = "/usr/bin/osascript"
    static let visudo = "/usr/sbin/visudo"
    /// The rule ApolloShell puts down once. macOS reads the folder through
    /// `#includedir /private/etc/sudoers.d` in /etc/sudoers.
    public static let sudoersFile = "/etc/sudoers.d/apolloshell"

    /// The value of "SleepDisabled" out of `pmset -g`; `nil` when the line is missing.
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

    /// `sudo -n pmset -a disablesleep 1|0`: without a password or not at all,
    /// never waits for input.
    public static func sudoArguments(disableSleep: Bool) -> [String] {
        ["-n", pmset, "-a", "disablesleep", disableSleep ? "1" : "0"]
    }

    /// The same with an administrator prompt from macOS. The text says what
    /// for - a bare password dialog without a reason would look suspicious.
    ///
    /// `installRuleFor`: on the switch-on, also put down the rule without a
    /// password for this user. A name that does not safely fit into a sudoers
    /// line leaves the rule out.
    public static func adminScript(disableSleep: Bool, installRuleFor user: String? = nil) -> String {
        var command = "\(pmset) -a disablesleep \(disableSleep ? "1" : "0")"
        let install = disableSleep ? user.flatMap(installRuleCommand(user:)) : nil
        if let install { command += " && { \(install); true; }" }
        // Shown in macOS' own password dialog (osascript "with prompt") - no
        // SwiftUI text.
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

    /// Remove the rule again (Nexus).
    public static func removeRuleArguments() -> [String] {
        let prompt = String(localized: "ApolloShell would like to remove its rule that switches lid-closed sleep without a password.")
        return ["-e", shellScript("/bin/rm -f \(sudoersFile)", prompt: prompt)]
    }

    // MARK: The rule without a password

    /// Only ordinary short names: the name ends up unchanged in a sudoers line
    /// and in a shell command. Everything else (spaces, commas, quotes,
    /// `%group`, umlauts) leaves the rule out.
    static func isSafeUserName(_ name: String) -> Bool {
        guard let first = name.unicodeScalars.first, first != "-" else { return false }
        return name.unicodeScalars.allSatisfy { scalar in
            scalar.isASCII && (CharacterSet.alphanumerics.contains(scalar) || "._-".unicodeScalars.contains(scalar))
        }
    }

    /// Allows exactly the two calls out of `sudoArguments`, only as root and
    /// only for this user. No quotes and no backslash: the text stands in
    /// single quotes of the shell and in an AppleScript string.
    ///
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

    /// Runs as root: write the rule into a file of its own, check it with
    /// visudo, set the permissions and only then move it into place. A faulty
    /// rule never reaches the folder sudo reads that way.
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

    /// `do shell script` with an administrator prompt; the command and the
    /// text escaped as AppleScript strings.
    static func shellScript(_ command: String, prompt: String) -> String {
        "do shell script \"\(appleScriptEscaped(command))\" "
            + "with prompt \"\(appleScriptEscaped(prompt))\" with administrator privileges"
    }

    static func appleScriptEscaped(_ text: String) -> String {
        text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
    }
}

/// The setting for "Keep Awake" (settings.json, section "keepAwake").
///
/// `lidClosed`: with the lid closed too. Fresh installations: off - it needs
/// administrator rights and leaves a Mac in a bag awake. When the section is
/// missing in an existing file: on, because before that it always held.
public struct KeepAwakeSettings: Codable, Equatable, Sendable {
    public var lidClosed: Bool

    public init(lidClosed: Bool) {
        self.lidClosed = lidClosed
    }

    public static let firstLaunch = KeepAwakeSettings(lidClosed: false)
    public static let existingInstall = KeepAwakeSettings(lidClosed: true)

    /// The section is there, the key missing or unreadable: off (the safe side).
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        lidClosed = (try? c.decodeIfPresent(Bool.self, forKey: .lidClosed)) ?? false
    }
}

/// The setting for "Hide Apple's Dock while ApolloShell runs"
/// (settings.json, section "appleDockHiding"). The same pattern as
/// `KeepAwakeSettings`: fresh installations off (until somebody decides for
/// it), existing files without this section on (the nix-config did that
/// permanently from outside so far), the section without the key off (the
/// safe side).
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

/// How the lid part of "Keep Awake" stands right now.
public enum KeepAwakeLid: Equatable, Sendable {
    /// Not wanted (the setting is off) or Keep Awake is off.
    case off
    /// Holds with the lid closed too.
    case on
    /// macOS is asking for an administrator right now.
    case pending
    /// Refused or failed: awake only with the lid open.
    case declined
}

import Foundation

/// The three keys in `com.apple.dock` that make Apple's own Dock disappear
/// entirely (autohide, plus the delay before it shows at the screen edge and
/// the animation time set to zero - otherwise it flashes up briefly when the
/// mouse goes there).
///
/// Pure: reads and writes nothing itself (no `CFPreferences`, no `killall`) -
/// the app controller does that. Only the values and the decisions about what
/// belongs where stand here.
public enum AppleDockHiding {
    public static let domain = "com.apple.dock"
    public static let autohideKey = "autohide"
    public static let autohideDelayKey = "autohide-delay"
    public static let autohideTimeModifierKey = "autohide-time-modifier"

    /// From this delay (seconds) on, a current state that has been read looks
    /// hidden already - the own values of macOS lie far below it (the default
    /// 0.5 s). A guard against saving twice: when ApolloShell starts while an
    /// earlier version (or the old nix-config script) had set the hiding
    /// permanently, or after a crash in the middle of the hidden state, that
    /// does NOT count as the original.
    public static let alreadyHiddenDelayThreshold: Double = 100

    public static let hidden = AppleDockPreferenceValues(
        autohide: true, autohideDelay: 1000, autohideTimeModifier: 0
    )

    /// What is saved as the original out of the current state that was read.
    /// When it looks hidden already (see `alreadyHiddenDelayThreshold`), it
    /// does not count as the original - then the macOS default counts: all
    /// three keys missing.
    public static func originalToSave(current: AppleDockPreferenceValues) -> AppleDockPreferenceValues {
        if let delay = current.autohideDelay, delay >= alreadyHiddenDelayThreshold {
            return AppleDockPreferenceValues()
        }
        return current
    }

    /// What is to be done in `com.apple.dock` for `target` in the end: set the
    /// values, delete missing keys (not write them back to a macOS default
    /// that could change one day).
    public static func actions(toReach target: AppleDockPreferenceValues) -> [AppleDockPreferenceAction] {
        [
            target.autohide.map { AppleDockPreferenceAction.setBool(key: autohideKey, value: $0) }
                ?? .remove(key: autohideKey),
            target.autohideDelay.map { AppleDockPreferenceAction.setDouble(key: autohideDelayKey, value: $0) }
                ?? .remove(key: autohideDelayKey),
            target.autohideTimeModifier.map { AppleDockPreferenceAction.setDouble(key: autohideTimeModifierKey, value: $0) }
                ?? .remove(key: autohideTimeModifierKey),
        ]
    }
}

/// One change to exactly one key in `com.apple.dock`.
public enum AppleDockPreferenceAction: Equatable, Sendable {
    case setBool(key: String, value: Bool)
    case setDouble(key: String, value: Double)
    case remove(key: String)
}

/// The three keys, each a value or "missing" (`nil`) - when one is missing, it
/// did not stand in `com.apple.dock`.
public struct AppleDockPreferenceValues: Codable, Equatable, Sendable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?

    public init(autohide: Bool? = nil, autohideDelay: Double? = nil, autohideTimeModifier: Double? = nil) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
    }

    /// The content of apple-dock.json (the saved original). When the file is
    /// missing: `nil` - no original saved, so ApolloShell has not run with the
    /// hiding on yet or cleaned up properly.
    public static func load(from data: Data?) -> AppleDockPreferenceValues? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppleDockPreferenceValues.self, from: data)
    }

    /// Sorted keys and indented, like the other files of the shell - readable
    /// by hand.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

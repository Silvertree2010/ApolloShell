import Foundation

public enum AppleDockHiding {
    public static let domain = "com.apple.dock"
    public static let autohideKey = "autohide"
    public static let autohideDelayKey = "autohide-delay"
    public static let autohideTimeModifierKey = "autohide-time-modifier"

    public static let alreadyHiddenDelayThreshold: Double = 100

    public static let hidden = AppleDockPreferenceValues(
        autohide: true, autohideDelay: 1000, autohideTimeModifier: 0
    )

    public static func originalToSave(current: AppleDockPreferenceValues) -> AppleDockPreferenceValues {
        if let delay = current.autohideDelay, delay >= alreadyHiddenDelayThreshold {
            return AppleDockPreferenceValues()
        }
        return current
    }

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

public enum AppleDockPreferenceAction: Equatable, Sendable {
    case setBool(key: String, value: Bool)
    case setDouble(key: String, value: Double)
    case remove(key: String)
}

public struct AppleDockPreferenceValues: Codable, Equatable, Sendable {
    public var autohide: Bool?
    public var autohideDelay: Double?
    public var autohideTimeModifier: Double?

    public init(autohide: Bool? = nil, autohideDelay: Double? = nil, autohideTimeModifier: Double? = nil) {
        self.autohide = autohide
        self.autohideDelay = autohideDelay
        self.autohideTimeModifier = autohideTimeModifier
    }

    public static func load(from data: Data?) -> AppleDockPreferenceValues? {
        guard let data else { return nil }
        return try? JSONDecoder().decode(AppleDockPreferenceValues.self, from: data)
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(self)) ?? Data()
    }
}

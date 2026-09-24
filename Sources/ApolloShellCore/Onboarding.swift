import Foundation

public struct OnboardingSettings: Codable, Equatable, Sendable {
    public var completed: Bool

    public init(completed: Bool) {
        self.completed = completed
    }

    public static let firstLaunch = OnboardingSettings(completed: false)
    public static let existingInstall = OnboardingSettings(completed: true)

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        completed = (try? c.decodeIfPresent(Bool.self, forKey: .completed)) ?? true
    }
}

public enum OnboardingRule {
    public static func shouldShow(completed: Bool, launcherOnly: Bool) -> Bool {
        !launcherOnly && !completed
    }
}

public enum OnboardingStep: Int, CaseIterable, Identifiable, Sendable {
    case welcome, permissions, hotKeys, finish

    public var id: Self { self }

    public var title: String {
        switch self {
        case .welcome: String(localized: "Welcome to ApolloShell")
        case .permissions: String(localized: "Permissions")
        case .hotKeys: String(localized: "Keyboard Shortcuts")
        case .finish: String(localized: "All Set")
        }
    }

    public var next: OnboardingStep? { OnboardingStep(rawValue: rawValue + 1) }
    public var previous: OnboardingStep? { OnboardingStep(rawValue: rawValue - 1) }
    public var isLast: Bool { next == nil }

    public var primaryButton: String {
        switch self {
        case .welcome: String(localized: "Get Started")
        case .permissions, .hotKeys: String(localized: "Continue")
        case .finish: String(localized: "Done")
        }
    }
}

public enum LauncherOnlyFlag {
    public static let key = "launcherOnly"
    public static let legacyKey = "nurLauncher"

    public static func isOn(_ value: (String) -> Any?) -> Bool {
        if let current = value(key) { return bool(current) }
        return value(legacyKey).map(bool) ?? false
    }

    private static func bool(_ value: Any) -> Bool {
        switch value {
        case let flag as Bool: flag
        case let number as NSNumber: number.boolValue
        case let text as String: ["1", "yes", "true"].contains(text.lowercased())
        default: false
        }
    }
}

public enum OnboardingAutostart {
    public enum Status: Sendable {
        case notRegistered, enabled, requiresApproval, notFound
    }

    public struct State: Equatable, Sendable {
        public var isOn: Bool
        public var canToggle: Bool
        public var needsApproval: Bool
        public var note: String?

        public init(isOn: Bool, canToggle: Bool, needsApproval: Bool = false, note: String? = nil) {
            self.isOn = isOn
            self.canToggle = canToggle
            self.needsApproval = needsApproval
            self.note = note
        }
    }

    public static func launchdLabel(environment: [String: String]) -> String? {
        guard let name = environment["XPC_SERVICE_NAME"]?.trimmingCharacters(in: .whitespaces),
              !name.isEmpty, name != "0", !name.hasPrefix("application.")
        else { return nil }
        return name
    }

    public static func state(status: Status, launchdLabel: String?, isAppBundle: Bool) -> State {
        let on = status == .enabled || status == .requiresApproval
        if let launchdLabel {
            return State(isOn: on, canToggle: on, note: String(localized: "Already starts via the launchd agent “\(launchdLabel)”. This switch therefore stays off – both together would start ApolloShell twice."))
        }
        guard isAppBundle else {
            return State(isOn: on, canToggle: on, note: String(localized: "Only works in the finished app (ApolloShell.app), not in a development build."))
        }
        switch status {
        case .enabled:
            return State(isOn: true, canToggle: true)
        case .requiresApproval:
            return State(isOn: true, canToggle: true, needsApproval: true,
                         note: String(localized: "macOS is waiting for your approval under General > Login Items."))
        case .notRegistered, .notFound:
            return State(isOn: false, canToggle: true)
        }
    }
}

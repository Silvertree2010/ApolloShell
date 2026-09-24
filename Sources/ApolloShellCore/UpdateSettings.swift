import Foundation

public struct UpdateSettings: Codable, Equatable, Sendable {
    public var checkAutomatically: Bool
    public var installAutomatically: Bool
    public var lastCheck: Date?

    public init(checkAutomatically: Bool = true, installAutomatically: Bool = true, lastCheck: Date? = nil) {
        self.checkAutomatically = checkAutomatically
        self.installAutomatically = installAutomatically
        self.lastCheck = lastCheck
    }

    private enum CodingKeys: String, CodingKey {
        case checkAutomatically, installAutomatically, lastCheck
    }

    public init(from decoder: any Decoder) throws {
        self.init()
        let c = try decoder.container(keyedBy: CodingKeys.self)
        c.lenient(.checkAutomatically, into: &checkAutomatically)
        c.lenient(.installAutomatically, into: &installAutomatically)
        c.lenient(.lastCheck, into: &lastCheck)
    }
}

public struct ThemeSettings: Codable, Equatable, Sendable {
    public var name: String?

    public init(name: String? = nil) {
        self.name = name
    }

    private enum CodingKeys: String, CodingKey {
        case name
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let stored: String? = c.lenient(.name)
        let trimmed = stored?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        name = (trimmed.isEmpty || trimmed.contains("/") || trimmed.hasPrefix(".")) ? nil : trimmed
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(name, forKey: .name)
    }
}

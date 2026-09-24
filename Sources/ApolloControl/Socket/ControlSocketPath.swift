import Foundation

public enum ControlSocketPath {
    public static let environmentKey = "APOLLO_SOCKET"

    public static func resolve(environment: [String: String], home: URL) -> String {
        if let path = environment[environmentKey], !path.isEmpty {
            return path
        }
        return home
            .appendingPathComponent("Library")
            .appendingPathComponent("Application Support")
            .appendingPathComponent("ApolloShell")
            .appendingPathComponent("apollo.sock")
            .path
    }
}

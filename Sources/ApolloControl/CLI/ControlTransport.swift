import Foundation
import ApolloConfig

public protocol ControlTransport: Sendable {
    func call(_ cmd: String, _ args: Record) throws -> ControlOutcome
    func stream(_ cmd: String, _ args: Record, _ onOutcome: (ControlOutcome) -> Bool) throws
}

public struct SocketTransport: ControlTransport {
    public let path: String

    public init(path: String) {
        self.path = path
    }

    public func call(_ cmd: String, _ args: Record) throws -> ControlOutcome {
        var outcome: ControlOutcome?
        try stream(cmd, args) { received in
            outcome = received
            return false
        }
        guard let outcome else { throw ControlSocketError.closed }
        return outcome
    }

    public func stream(_ cmd: String, _ args: Record, _ onOutcome: (ControlOutcome) -> Bool) throws {
        let client = try ControlSocketClient.connect(path: path)
        defer { client.close() }
        try client.send(ControlRequest(id: 1, cmd: cmd, args: args))
        while let response = try client.readResponse() {
            guard response.id == 1 || response.id == nil else { continue }
            guard onOutcome(response.outcome) else { return }
        }
    }
}

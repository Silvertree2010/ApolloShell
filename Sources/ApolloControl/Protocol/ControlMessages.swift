import Foundation
import ApolloConfig

public struct ControlRequest: Sendable, Hashable {
    public var id: Int
    public var cmd: String
    public var args: Record

    public init(id: Int, cmd: String, args: Record = Record()) {
        self.id = id
        self.cmd = cmd
        self.args = args
    }

    public var line: String {
        var output = ""
        JSONText.writeObject([("id", .number(Double(id))), ("cmd", .string(cmd)), ("args", .record(args))], into: &output)
        return output
    }

    public static func parse(_ line: String) -> Result<ControlRequest, ControlRequestError> {
        guard case .record(let object)? = JSONText.decode(line) else {
            return .failure(ControlRequestError(id: nil, message: "request is not a JSON object"))
        }
        guard case .number(let number)? = object["id"], number == number.rounded(), abs(number) < 9_007_199_254_740_992 else {
            return .failure(ControlRequestError(id: nil, message: "request needs a whole number 'id'"))
        }
        let id = Int(number)
        guard case .string(let cmd)? = object["cmd"], !cmd.isEmpty else {
            return .failure(ControlRequestError(id: id, message: "request needs a string 'cmd'"))
        }
        switch object["args"] {
        case nil, .null?:
            return .success(ControlRequest(id: id, cmd: cmd))
        case .record(let args)?:
            return .success(ControlRequest(id: id, cmd: cmd, args: args))
        default:
            return .failure(ControlRequestError(id: id, message: "'args' must be an object"))
        }
    }
}

public struct ControlRequestError: Error, Sendable, Hashable {
    public var id: Int?
    public var message: String
}

public enum ControlOutcome: Sendable, Hashable {
    case success(Value)
    case failure(String)
}

public struct ControlResponse: Sendable, Hashable {
    public var id: Int?
    public var outcome: ControlOutcome

    public init(id: Int?, outcome: ControlOutcome) {
        self.id = id
        self.outcome = outcome
    }

    public var line: String {
        let idValue: Value = id.map { .number(Double($0)) } ?? .null
        var output = ""
        switch outcome {
        case .success(let result):
            JSONText.writeObject([("id", idValue), ("ok", .bool(true)), ("result", result)], into: &output)
        case .failure(let message):
            JSONText.writeObject([("id", idValue), ("ok", .bool(false)), ("error", .string(message))], into: &output)
        }
        return output
    }

    public static func parse(_ line: String) -> ControlResponse? {
        guard case .record(let object)? = JSONText.decode(line), case .bool(let ok)? = object["ok"] else { return nil }
        var id: Int?
        if case .number(let number)? = object["id"] { id = Int(exactly: number) }
        if ok {
            return ControlResponse(id: id, outcome: .success(object["result"] ?? .null))
        }
        if case .string(let message)? = object["error"] {
            return ControlResponse(id: id, outcome: .failure(message))
        }
        return ControlResponse(id: id, outcome: .failure("unknown error"))
    }
}

public enum ControlReply: Sendable {
    case success(Value)
    case failure(String)
    case stream(AsyncStream<Value>)
}

public protocol ControlService: Sendable {
    func reply(to request: ControlRequest) async -> ControlReply
}

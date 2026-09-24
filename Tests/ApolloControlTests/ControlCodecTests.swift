import Testing
import Foundation
import ApolloConfig
@testable import ApolloControl

@Suite("JSON-Zeilen des Sockets")
struct ControlCodecTests {
    @Test("Anfrage wird aus einer Zeile gelesen")
    func parsesRequest() throws {
        let request = try ControlRequest.parse(#"{"id": 7, "cmd": "get", "args": {"name": "index"}}"#).get()
        #expect(request.id == 7)
        #expect(request.cmd == "get")
        #expect(request.args["name"] == .string("index"))
    }

    @Test("Anfrage ohne args hat leere args")
    func parsesRequestWithoutArgs() throws {
        let request = try ControlRequest.parse(#"{"id": 1, "cmd": "version"}"#).get()
        #expect(request.args.count == 0)
    }

    @Test("kaputte Anfrage ergibt einen Fehler mit der id, soweit lesbar")
    func rejectsBrokenRequests() {
        #expect(ControlRequest.parse("nope").failureID == .some(nil))
        #expect(ControlRequest.parse(#"{"id": 3}"#).failureID == .some(3))
        #expect(ControlRequest.parse(#"{"id": 3, "cmd": 5}"#).failureID == .some(3))
        #expect(ControlRequest.parse(#"{"id": 3, "cmd": "x", "args": [1]}"#).failureID == .some(3))
    }

    @Test("Anfrage und Antwort sind je eine Zeile in der Form der Spec")
    func encodesLines() {
        let request = ControlRequest(id: 2, cmd: "set", args: Record([("name", .string("a")), ("value", .number(3))]))
        #expect(request.line == #"{"id":2,"cmd":"set","args":{"name":"a","value":3}}"#)
        #expect(ControlResponse(id: 2, outcome: .success(.bool(true))).line == #"{"id":2,"ok":true,"result":true}"#)
        #expect(ControlResponse(id: 2, outcome: .failure("no \"var\"\n")).line == #"{"id":2,"ok":false,"error":"no \"var\"\n"}"#)
        #expect(ControlResponse(id: nil, outcome: .failure("bad")).line == #"{"id":null,"ok":false,"error":"bad"}"#)
    }

    @Test("Antwort wird wieder gelesen")
    func parsesResponse() throws {
        let response = try #require(ControlResponse.parse(#"{"id":4,"ok":true,"result":{"a":[1,"x",null]}}"#))
        #expect(response.id == 4)
        #expect(response.outcome == .success(.record(Record([("a", .list([.number(1), .string("x"), .null]))]))))
        let failure = try #require(ControlResponse.parse(#"{"id":4,"ok":false,"error":"nope"}"#))
        #expect(failure.outcome == .failure("nope"))
    }

    @Test("NaN und unendlich werden null, ganze Zahlen ohne Nachkommastellen")
    func numbers() {
        #expect(JSONText.encode(.list([.number(.nan), .number(-.infinity), .number(2), .number(0.25), .number(-0.0)])) == "[null,null,2,0.25,0]")
    }

    @Test("Zeichenketten werden nach JSON maskiert")
    func strings() {
        #expect(JSONText.encode(.string("a\u{1}b\t\\/ü")) == #""a\u0001b\t\\/ü""#)
    }

    @Test("Datum und Bild haben eine JSON-Form")
    func dateAndImage() {
        #expect(JSONText.encode(.date(Date(timeIntervalSince1970: 0))) == #""1970-01-01T00:00:00Z""#)
        #expect(JSONText.encode(.image(ImageRef(source: "sf", id: "wifi"))) == #"{"source":"sf","id":"wifi"}"#)
    }

    @Test("JSON-Text wird zum Wert, Unsinn nicht")
    func decodes() {
        #expect(JSONText.decode("[true, 1e3, \"x\"]") == .list([.bool(true), .number(1000), .string("x")]))
        #expect(JSONText.decode("0.5") == .number(0.5))
        #expect(JSONText.decode("{") == nil)
    }
}

extension Result where Success == ControlRequest, Failure == ControlRequestError {
    var failureID: Int?? {
        if case .failure(let error) = self { return .some(error.id) }
        return nil
    }
}

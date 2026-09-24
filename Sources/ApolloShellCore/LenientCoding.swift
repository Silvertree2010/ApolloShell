import Foundation

public extension KeyedDecodingContainer {
    func lenient<T: Decodable>(_ key: Key) -> T? {
        (try? decodeIfPresent(T.self, forKey: key)) ?? nil
    }

    func lenient<T: Decodable>(_ key: Key, into target: inout T) {
        if let value: T = lenient(key) { target = value }
    }
}

struct LenientElement<T: Decodable>: Decodable {
    let value: T?
    init(from decoder: any Decoder) {
        value = try? T(from: decoder)
    }
}

public struct LenientList<Element: Decodable>: Decodable {
    public let values: [Element]

    public init(from decoder: any Decoder) throws {
        var c = try decoder.unkeyedContainer()
        var list: [Element] = []
        while !c.isAtEnd {
            guard let item = try? c.decode(LenientElement<Element>.self) else { break }
            if let value = item.value { list.append(value) }
        }
        values = list
    }
}

struct AnyEncodable: Encodable {
    let value: any Encodable
    func encode(to encoder: any Encoder) throws {
        try value.encode(to: encoder)
    }
}

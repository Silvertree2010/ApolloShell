import Foundation

public struct PinnedList: Equatable, Sendable {
    public static let limit = 10

    public private(set) var ids: [String]

    public init(_ ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public var isFull: Bool { ids.count >= Self.limit }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    @discardableResult
    public mutating func add(_ id: String) -> Bool {
        guard !id.isEmpty, !isFull, !contains(id) else { return false }
        ids.append(id)
        return true
    }

    public mutating func remove(_ id: String) {
        ids.removeAll { $0 == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        ids.move(fromOffsets: source, toOffset: destination)
    }

    public mutating func move(_ id: String, by step: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + step
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
    }

    private struct File: Codable {
        var pinned: [String]
    }

    public static func load(from data: Data?) -> PinnedList {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else {
            return PinnedList()
        }
        return PinnedList(file.pinned)
    }

    public static func isUnreadable(_ data: Data?) -> Bool {
        guard let data else { return false }
        return (try? JSONDecoder().decode(File.self, from: data)) == nil
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(File(pinned: ids))) ?? Data()
    }
}

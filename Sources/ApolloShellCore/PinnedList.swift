import Foundation

/// The pinned apps of the launcher (pinned.json, `{"pinned": [...]}`), the way
/// Nexus edits them: reorder, remove, add.
///
/// Every bundle ID at most once - the launcher does take the first place with
/// duplicates (AppRanker), but in the list for editing a second entry would be
/// a row that does nothing.
///
/// At most `limit` entries ("the fixed top 10"). A file that is longer by hand
/// is NOT shortened when read - Nexus deletes nothing it did not put there
/// itself; it only adds nothing more.
public struct PinnedList: Equatable, Sendable {
    public static let limit = 10

    public private(set) var ids: [String]

    public init(_ ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public var isFull: Bool { ids.count >= Self.limit }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Append at the end. `false` when it is in already, empty or the list is full.
    @discardableResult
    public mutating func add(_ id: String) -> Bool {
        guard !id.isEmpty, !isFull, !contains(id) else { return false }
        ids.append(id)
        return true
    }

    public mutating func remove(_ id: String) {
        ids.removeAll { $0 == id }
    }

    /// Like SwiftUI's `onMove`: `destination` counts in the list BEFORE the
    /// move ("insert before row n"), see `Array.move` in Reorder.swift -
    /// `move(fromOffsets:toOffset:)` itself belongs to SwiftUI, and
    /// ApolloShellCore stays without a user interface.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        ids.move(fromOffsets: source, toOffset: destination)
    }

    /// One place up (-1) or down (+1); nothing at the edge.
    public mutating func move(_ id: String, by step: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + step
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
    }

    private struct File: Codable {
        var pinned: [String]
    }

    /// The content of pinned.json. When the file is missing or broken: empty -
    /// exactly as the launcher reads it (PinnedApps.load).
    public static func load(from data: Data?) -> PinnedList {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else {
            return PinnedList()
        }
        return PinnedList(file.pinned)
    }

    /// There, but not readable. `load` hands back an empty list for that as for
    /// a missing file; whoever saves afterwards replaces the broken file. So
    /// Nexus keeps it beforehand.
    public static func isUnreadable(_ data: Data?) -> Bool {
        guard let data else { return false }
        return (try? JSONDecoder().decode(File.self, from: data)) == nil
    }

    /// The same format as the file so far, indented.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(File(pinned: ids))) ?? Data()
    }
}

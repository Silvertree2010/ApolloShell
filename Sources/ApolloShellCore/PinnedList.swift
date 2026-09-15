import Foundation

/// Die angehefteten Apps des Launchers (pinned.json, `{"pinned": [...]}`),
/// wie Nexus sie bearbeitet: umsortieren, entfernen, hinzufuegen.
///
/// Jede Bundle-ID hoechstens einmal - der Launcher nimmt bei Doppelten zwar
/// die erste Stelle (AppRanker), aber in der Liste zum Bearbeiten waere ein
/// zweiter Eintrag eine Zeile, die nichts tut.
///
/// Hoechstens `limit` Eintraege ("die festen Top 10"). Eine von Hand
/// laengere Datei wird beim Lesen NICHT gekuerzt - Nexus loescht nichts, was
/// es nicht selbst angelegt hat; es nimmt nur nichts mehr dazu.
public struct PinnedList: Equatable, Sendable {
    public static let limit = 10

    public private(set) var ids: [String]

    public init(_ ids: [String] = []) {
        var seen = Set<String>()
        self.ids = ids.filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    public var isFull: Bool { ids.count >= Self.limit }

    public func contains(_ id: String) -> Bool { ids.contains(id) }

    /// Hinten anhaengen. `false`, wenn schon drin, leer oder die Liste voll ist.
    @discardableResult
    public mutating func add(_ id: String) -> Bool {
        guard !id.isEmpty, !isFull, !contains(id) else { return false }
        ids.append(id)
        return true
    }

    public mutating func remove(_ id: String) {
        ids.removeAll { $0 == id }
    }

    /// Wie SwiftUIs `onMove`: `destination` zaehlt in der Liste VOR dem
    /// Verschieben ("vor Zeile n einfuegen"). Eigene Fassung, weil
    /// `move(fromOffsets:toOffset:)` zu SwiftUI gehoert und ApolloShellCore ohne
    /// Oberflaeche bleibt.
    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { ids.indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { ids[$0] }
        // Ziel um die davor herausgenommenen Zeilen verschieben.
        let before = valid.filter { $0 < destination }.count
        var rest = ids.enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let target = min(max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: target)
        ids = rest
    }

    /// Eine Stelle nach oben (-1) oder unten (+1); am Rand nichts.
    public mutating func move(_ id: String, by step: Int) {
        guard let index = ids.firstIndex(of: id) else { return }
        let target = index + step
        guard ids.indices.contains(target) else { return }
        ids.swapAt(index, target)
    }

    private struct File: Codable {
        var pinned: [String]
    }

    /// Inhalt von pinned.json. Fehlt die Datei oder ist sie kaputt: leer -
    /// genau wie der Launcher sie liest (PinnedApps.load).
    public static func load(from data: Data?) -> PinnedList {
        guard let data, let file = try? JSONDecoder().decode(File.self, from: data) else {
            return PinnedList()
        }
        return PinnedList(file.pinned)
    }

    /// Gleiches Format wie die bisherige Datei, eingerueckt.
    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
        return (try? encoder.encode(File(pinned: ids))) ?? Data()
    }
}

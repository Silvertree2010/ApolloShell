import Foundation

// Eine Liste umsortieren wie SwiftUIs `onMove`: `destination` zaehlt in der
// Liste VOR dem Verschieben ("vor Zeile n einfuegen"). Bisher sechsmal
// wortgleich (BarLayout, DashboardLayout, UtilitiesLayout, PinnedList,
// Weather, NexusLauncherPage) - jetzt eine Fassung fuer jede Liste.
public extension Array {
    mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        let valid = source.filter { indices.contains($0) }
        guard !valid.isEmpty else { return }
        let moving = valid.map { self[$0] }
        // Ziel um die davor herausgenommenen Zeilen verschieben.
        let before = valid.filter { $0 < destination }.count
        var rest = enumerated().filter { !valid.contains($0.offset) }.map(\.element)
        let target = Swift.min(Swift.max(destination - before, 0), rest.count)
        rest.insert(contentsOf: moving, at: target)
        self = rest
    }
}

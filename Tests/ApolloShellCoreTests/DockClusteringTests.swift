import ApolloShellCore
import Foundation
import Testing

@Suite("Dock-Gruppen")
struct DockClusteringTests {
    private func s(_ ids: [String]) -> [DockSlot] { ids.map { DockSlot(bundleID: $0, pinned: false, running: true) } }
    private let k: (String) -> DockCategory.Kind = { id in
        DockCategory.kind(key: String(id.prefix(while: { $0 != "." })))
    }

    @Test("bis 9 Apps keine Gruppen")
    func small() {
        let r = DockClustering.items(s((1...9).map { "dev.\($0)" }), weight: { _ in 0 }, kind: k)
        #expect(r.count == 9)
        #expect(r.allSatisfy { if case .app = $0 { true } else { false } })
    }

    @Test("viele Apps: nie mehr als 9, meistgenutzte einzeln")
    func many() {
        let ids = (1...40).map { "dev.\($0)" } + (1...40).map { "media.\($0)" } + (1...40).map { "chat.\($0)" }
            + (1...40).map { "web.\($0)" } + (1...40).map { "x\($0)" }
        let w: (String) -> Double = { ["media.7": 50, "x3": 40, "web.1": 30, "chat.2": 20][$0] ?? 0 }
        let r = DockClustering.items(s(ids), weight: w, kind: k)
        #expect(r.count <= 9)
        let apps = r.compactMap { if case .app(let a) = $0 { a.bundleID } else { nil } }
        #expect(Set(apps).isSuperset(of: ["media.7", "x3", "web.1", "chat.2"]))
        let members = r.flatMap { item -> [String] in if case .group(let g) = item { g.members.map(\.bundleID) } else { [] } }
        #expect(Set(members + apps).count == ids.count)
    }

    @Test("Gruppen nach Art, Reihenfolge nach erstem Mitglied")
    func byKind() {
        let ids = ["dev.a", "media.a", "dev.b", "media.b", "chat.a", "chat.b", "web.a", "web.b", "design.a", "design.b"]
        let r = DockClustering.items(s(ids), weight: { _ in 0 }, kind: k)
        #expect(r.map(\.id) == ["g:dev", "g:media", "g:chat", "g:web", "g:design"])
    }

    @Test("Einzelne Mitglieder bleiben App, unbekannte folgen ihrem Partner")
    func partner() {
        let ids = ["write.a", "write.b", "dev.a", "dev.b", "media.a", "media.b", "chat.a", "chat.b", "web.a", "zz"]
        let r = DockClustering.items(s(ids), weight: { _ in 0 }, kind: k, partner: { $0 == "zz" ? "write.a" : nil })
        guard case .group(let g)? = r.first else { Issue.record("keine Gruppe"); return }
        #expect(g.members.map(\.bundleID) == ["write.a", "write.b", "zz"])
        #expect(r.contains(.app(DockSlot(bundleID: "web.a", pinned: false, running: true))))
    }

    @Test("selten genutzte Apps bleiben in der Gruppe")
    func rare() {
        let ids = (1...12).map { "dev.\($0)" }
        let r = DockClustering.items(s(ids), weight: { $0 == "dev.3" ? 1 : 0 }, kind: k)
        #expect(r.count == 1)
    }

    @Test("feste Plätze bleiben einzeln")
    func fixed() {
        let ids = ["finder"] + (1...20).map { "dev.\($0)" }
        let r = DockClustering.items(s(ids), fixed: ["finder"], weight: { _ in 0 }, kind: k)
        #expect(r.first?.id == "finder")
        #expect(r.count == 2)
    }

    @Test("Nutzung: Partner erst ab drei gemeinsamen Wechseln")
    func usage() {
        var u = DockUsage()
        let t = Date(timeIntervalSince1970: 0)
        for i in 0..<3 {
            u.record("md.obsidian", at: t.addingTimeInterval(Double(i) * 100))
            u.record("com.apple.Notes", at: t.addingTimeInterval(Double(i) * 100 + 10))
        }
        #expect(u.partner("md.obsidian", among: ["com.apple.Notes", "x"]) == "com.apple.Notes")
        #expect(u.partner("x", among: ["com.apple.Notes"]) == nil)
        #expect(u.weight("md.obsidian", at: t.addingTimeInterval(300)) > 0)
    }

    @Test("Notizen und Obsidian landen in derselben Art")
    func notes() {
        #expect(DockCategory.kind(bundleID: "com.apple.Notes", category: nil).key == DockCategory.kind(bundleID: "md.obsidian", category: nil).key)
    }
}

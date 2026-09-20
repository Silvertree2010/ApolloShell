import ApolloShellCore
import Testing

@Suite("Apples Dock-Menue nachbauen")
struct DockMenuTreeTests {
    /// So sieht Apples Menue bei Vivaldi aus (gemessen 17.09. am Bildschirm):
    /// das vordere Fenster mit Haken, ein Trenner, die Befehle der App, ein
    /// Trenner, "Options" mit Untermenue, ein Trenner, der Schlussblock.
    private var vivaldi: [RawMenuItem] {
        [
            RawMenuItem(title: "ApolloShell, a desktop shell for macOS Tahoe - Vivaldi", mark: "✓"),
            RawMenuItem(title: ""),
            RawMenuItem(title: "New window"),
            RawMenuItem(title: "New Private Window"),
            RawMenuItem(title: ""),
            RawMenuItem(title: "Options", hasSubmenu: true, children: [
                RawMenuItem(title: "Keep in Dock"),
                RawMenuItem(title: "Open at Login"),
                RawMenuItem(title: "Show in Finder"),
            ]),
            RawMenuItem(title: ""),
            RawMenuItem(title: "Show All Windows"),
            RawMenuItem(title: "Hide"),
            RawMenuItem(title: "Quit"),
        ]
    }

    @Test("Reihenfolge und Trenner bleiben, wie Apple sie liefert")
    func keepsOrderAndSeparators() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes.count == vivaldi.count)
        #expect(nodes.map(\.separator) == [false, true, false, false, true, false, true, false, false, false])
    }

    @Test("der Haken am vordersten Fenster kommt mit")
    func marksBecomeCheckmarks() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes[0].checked)
        #expect(!nodes[2].checked)
    }

    @Test("ein Untermenue wird mitgelesen")
    func readsSubmenus() {
        let options = DockMenuTree.nodes(from: vivaldi)[5]
        #expect(options.children.map(\.title) == ["Keep in Dock", "Open at Login", "Show in Finder"])
        #expect(!options.separator, "ein Eintrag mit Untermenue ist kein Trenner")
    }

    @Test("der Weg zu einem Eintrag nennt Titel und Stelle")
    func pathsLeadBackToTheItem() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes[2].path == [DockMenuStep(title: "New window", index: 2)])
        #expect(nodes[5].children[2].path == [DockMenuStep(title: "Options", index: 5),
                                              DockMenuStep(title: "Show in Finder", index: 2)])
    }

    @Test("gleichnamige Eintraege bleiben auseinanderzuhalten")
    func sameTitlesKeepTheirPlace() {
        let windows = [RawMenuItem(title: "Bericht.pdf"), RawMenuItem(title: "Bericht.pdf")]
        let nodes = DockMenuTree.nodes(from: windows)
        #expect(nodes[0].path.map(\.index) == [0])
        #expect(nodes[1].path.map(\.index) == [1])
    }

    @Test("tiefer als eine Ebene Untermenue wird nicht gelesen")
    func stopsAtTheDepthLimit() {
        let deep = [
            RawMenuItem(title: "A", hasSubmenu: true, children: [
                RawMenuItem(title: "B", hasSubmenu: true, children: [RawMenuItem(title: "C")]),
            ]),
        ]
        let nodes = DockMenuTree.nodes(from: deep)
        #expect(nodes[0].children.map(\.title) == ["B"])
        #expect(nodes[0].children[0].children.isEmpty)
    }

    @Test("ausgegraute Eintraege bleiben ausgegraut")
    func keepsDisabledItems() {
        let nodes = DockMenuTree.nodes(from: [RawMenuItem(title: "Show All Windows", enabled: false)])
        #expect(!nodes[0].enabled)
    }

    @Test("ein Eintrag aus Leerzeichen ist ein Trenner, einer mit Untermenue nie")
    func separatorDetection() {
        #expect(DockMenuTree.nodes(from: [RawMenuItem(title: "   ")])[0].separator)
        #expect(!DockMenuTree.nodes(from: [RawMenuItem(title: "", hasSubmenu: true)])[0].separator)
    }

    @Test("Im Dock behalten wird erkannt", arguments: ["Keep in Dock", "Keep in Dock", " keep in dock "])
    func findsKeepInDock(title: String) {
        #expect(DockMenuTree.isKeepInDock(title))
    }

    @Test("und nichts anderes", arguments: ["Show in Finder", "Open at Login", "Dock", ""])
    func othersAreNotKeepInDock(title: String) {
        #expect(!DockMenuTree.isKeepInDock(title))
    }
}

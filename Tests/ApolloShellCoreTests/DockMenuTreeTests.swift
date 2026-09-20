import ApolloShellCore
import Testing

@Suite("Rebuilding Apple's Dock menu")
struct DockMenuTreeTests {
    /// This is what Apple's menu looks like with Vivaldi (measured 17.09. on
    /// the screen): the front window with a tick, a separator, the commands of
    /// the app, a separator, "Options" with a submenu, a separator, the end block.
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

    @Test("The order and the separators stay the way Apple delivers them")
    func keepsOrderAndSeparators() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes.count == vivaldi.count)
        #expect(nodes.map(\.separator) == [false, true, false, false, true, false, true, false, false, false])
    }

    @Test("The tick on the frontmost window comes along")
    func marksBecomeCheckmarks() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes[0].checked)
        #expect(!nodes[2].checked)
    }

    @Test("A submenu is read along")
    func readsSubmenus() {
        let options = DockMenuTree.nodes(from: vivaldi)[5]
        #expect(options.children.map(\.title) == ["Keep in Dock", "Open at Login", "Show in Finder"])
        #expect(!options.separator, "an entry with a submenu is no separator")
    }

    @Test("The way to an entry names the title and the place")
    func pathsLeadBackToTheItem() {
        let nodes = DockMenuTree.nodes(from: vivaldi)
        #expect(nodes[2].path == [DockMenuStep(title: "New window", index: 2)])
        #expect(nodes[5].children[2].path == [DockMenuStep(title: "Options", index: 5),
                                              DockMenuStep(title: "Show in Finder", index: 2)])
    }

    @Test("Entries of the same name can still be told apart")
    func sameTitlesKeepTheirPlace() {
        let windows = [RawMenuItem(title: "Bericht.pdf"), RawMenuItem(title: "Bericht.pdf")]
        let nodes = DockMenuTree.nodes(from: windows)
        #expect(nodes[0].path.map(\.index) == [0])
        #expect(nodes[1].path.map(\.index) == [1])
    }

    @Test("Deeper than one level of submenu is not read")
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

    @Test("Greyed-out entries stay greyed out")
    func keepsDisabledItems() {
        let nodes = DockMenuTree.nodes(from: [RawMenuItem(title: "Show All Windows", enabled: false)])
        #expect(!nodes[0].enabled)
    }

    @Test("An entry of spaces is a separator, one with a submenu never is")
    func separatorDetection() {
        #expect(DockMenuTree.nodes(from: [RawMenuItem(title: "   ")])[0].separator)
        #expect(!DockMenuTree.nodes(from: [RawMenuItem(title: "", hasSubmenu: true)])[0].separator)
    }

    @Test("Keep in Dock is recognised", arguments: ["Keep in Dock", "Im Dock behalten", " keep in dock "])
    func findsKeepInDock(title: String) {
        #expect(DockMenuTree.isKeepInDock(title))
    }

    @Test("and nothing else is", arguments: ["Show in Finder", "Open at Login", "Dock", ""])
    func othersAreNotKeepInDock(title: String) {
        #expect(!DockMenuTree.isKeepInDock(title))
    }
}

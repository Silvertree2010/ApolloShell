import CoreGraphics
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("App menus from accessibility: entries, shortcuts, alternates, room")
struct AppMenuTreeTests {
    private let finderFile: [AXMenuEntry] = [
        AXMenuEntry(title: "New Finder Window", commandCharacter: "N"),
        AXMenuEntry(title: "New Folder", enabled: false, commandCharacter: "N", commandModifiers: 1),
        AXMenuEntry(title: "New Folder with Selection", enabled: false, commandCharacter: "N", commandModifiers: 4),
        AXMenuEntry(title: "Open With", enabled: false, commandModifiers: 8,
                    children: [AXMenuEntry(title: "TextEdit")]),
        AXMenuEntry(title: "Always Open With", enabled: false, commandModifiers: 10,
                    children: [AXMenuEntry(title: "TextEdit")]),
        AXMenuEntry(title: "Close Window", enabled: false, commandCharacter: "W"),
        AXMenuEntry(title: "Close All", commandCharacter: "W", commandModifiers: 2),
        AXMenuEntry(title: "", enabled: false),
        AXMenuEntry(title: "Get Info", enabled: false, commandCharacter: "I"),
        AXMenuEntry(title: "Show Inspector", enabled: false, commandCharacter: "I", commandModifiers: 2),
        AXMenuEntry(title: "Get Summary Info", enabled: false, commandCharacter: "I", commandModifiers: 4),
        AXMenuEntry(title: "", enabled: false),
        AXMenuEntry(title: "Move to Trash", enabled: false, commandCharacter: "\u{8}", commandGlyph: 23),
        AXMenuEntry(title: "Delete Immediately…", enabled: false, commandCharacter: "\u{8}", commandModifiers: 2,
                    commandGlyph: 23),
        AXMenuEntry(title: "", enabled: false),
        AXMenuEntry(title: "", enabled: true),
        AXMenuEntry(title: "", enabled: false),
        AXMenuEntry(title: "Find", commandCharacter: "F"),
    ]

    @Test("The measured Finder menu: separators folded, submenus kept, paths by place")
    func finder() {
        let nodes = AppMenuTree.nodes(from: finderFile, path: [AXMenuStep(title: "File", index: 2)])
        #expect(nodes.map { $0.isSeparator ? "-" : $0.title } == [
            "New Finder Window", "New Folder", "New Folder with Selection", "Open With", "Always Open With",
            "Close Window", "Close All", "-", "Get Info", "Show Inspector", "Get Summary Info", "-",
            "Move to Trash", "Delete Immediately…", "-", "Find",
        ])
        let find = nodes.last!
        #expect(find.path == [AXMenuStep(title: "File", index: 2), AXMenuStep(title: "Find", index: 17)])
        #expect(find.shortcut?.display == "⌘F")
        let openWith = nodes[3]
        #expect(openWith.hasSubmenu && !openWith.enabled && openWith.shortcut == nil)
        #expect(openWith.children.map(\.path.last?.title) == ["TextEdit"])
        #expect(openWith.children[0].path.count == 3)
    }

    @Test("Only what Option adds is an alternate")
    func alternates() {
        let nodes = AppMenuTree.nodes(from: finderFile)
        let alternates = nodes.filter(\.isAlternate).map(\.title)
        #expect(alternates == ["Always Open With", "Close All", "Show Inspector", "Delete Immediately…"])
        #expect(!nodes[1].isAlternate)
        #expect(nodes[4].modifiers == [.option])
    }

    @Test("No separator at the top, the bottom or twice")
    func separators() {
        let nodes = AppMenuTree.nodes(from: [
            AXMenuEntry(title: ""), AXMenuEntry(title: "A"), AXMenuEntry(title: " "), AXMenuEntry(title: ""),
            AXMenuEntry(title: "B"), AXMenuEntry(title: ""),
        ])
        #expect(nodes.map { $0.isSeparator ? "-" : $0.title } == ["A", "-", "B"])
        #expect(!AppMenuTree.isSeparator(AXMenuEntry(title: "", children: [AXMenuEntry(title: "x")])))
    }

    @Test("Marks: tick, mixed, none")
    func marks() {
        let nodes = AppMenuTree.nodes(from: [
            AXMenuEntry(title: "A", mark: "✓"), AXMenuEntry(title: "B", mark: "-"), AXMenuEntry(title: "C"),
            AXMenuEntry(title: "D", mark: "•"),
        ])
        #expect(nodes.map(\.mark) == [.check, .mixed, .none, .check])
    }

    @Test("Shortcuts read like Apple's menus", arguments: [
        ("N", 0, 0, "⌘N", "n"),
        ("N", 1, 0, "⇧⌘N", "n"),
        ("O", 2, 0, "⌥⌘O", "o"),
        ("A", 5, 0, "⌃⇧⌘A", "a"),
        ("F", 7, 0, "⌃⌥⇧⌘F", "f"),
        ("\u{8}", 0, 23, "⌘⌫", "\u{8}"),
        ("", 8, 0x6F, "F1", "\u{F704}"),
        ("", 0, 0x7A, "⌘F12", "\u{F70F}"),
        ("", 4, 0x68, "⌃⌘↑", "\u{F700}"),
        ("\r", 0, 0, "⌘↩", "\r"),
        ("\u{F708}", 8, 0, "F5", "\u{F708}"),
        (" ", 12, 0, "⌃Space", " "),
        (",", 0, 0, "⌘,", ","),
    ] as [(String, Int, Int, String, String)])
    func shortcut(character: String, modifiers: Int, glyph: Int, display: String, equivalent: String) throws {
        let shortcut = try #require(AppMenuShortcut.from(character: character, modifiers: modifiers, glyph: glyph))
        #expect(shortcut.display == display)
        #expect(shortcut.keyEquivalent == equivalent)
    }

    @Test("No key, no shortcut; an unnamed control character neither")
    func noShortcut() {
        #expect(AppMenuShortcut.from(character: "", modifiers: 8, glyph: 0) == nil)
        #expect(AppMenuShortcut.from(character: "", modifiers: 2, glyph: 0) == nil)
        #expect(AppMenuShortcut.from(character: "\u{1}", modifiers: 0, glyph: 0) == nil)
    }

    @Test("A step finds its entry at its place, else by title, else not at all")
    func resolve() {
        let step = AXMenuStep(title: "Edit", index: 3)
        #expect(step.resolve(in: ["Apple", "Finder", "File", "Edit"]) == 3)
        #expect(step.resolve(in: ["Apple", "Finder", "Edit", "View"]) == 2)
        #expect(step.resolve(in: ["Apple", "Finder"]) == nil)
        #expect(AXMenuStep(title: "a.txt", index: 1).resolve(in: ["a.txt", "a.txt"]) == 1)
    }

    @Test("Titles that do not fit go into the overflow menu", arguments: [
        (500.0, 6, false),
        (200.0, 3, true),
        (120.0, 1, true),
        (80.0, 0, true),
    ] as [(Double, Int, Bool)])
    func collapse(available: Double, shown: Int, overflow: Bool) {
        let fit = AppMenuCollapse.fit(available: available, lead: 50, titles: [30, 30, 30, 30, 30, 30],
                                      overflow: 20, spacing: 10)
        #expect(fit == AppMenuCollapse.Fit(shown: shown, overflow: overflow))
    }

    @Test("Exactly enough room shows everything")
    func collapseExact() {
        #expect(AppMenuCollapse.fit(available: 170, lead: 50, titles: [30, 30, 30], overflow: 20, spacing: 10)
            == .init(shown: 3, overflow: false))
        #expect(AppMenuCollapse.fit(available: 169, lead: 50, titles: [30, 30, 30], overflow: 20, spacing: 10)
            == .init(shown: 2, overflow: true))
    }
}

@Suite("Mirrored status items: which, in which order, which window, which tint")
struct StatusItemMirrorTests {
    private func record(_ pid: Int32, _ bundle: String?, _ index: Int, x: CGFloat, width: CGFloat = 24) -> StatusItemRecord {
        StatusItemRecord(pid: pid, bundleID: bundle, index: index, frame: CGRect(x: x, y: 4, width: width, height: 22))
    }

    @Test("Apple's own and empty items fall away, the rest left to right")
    func order() {
        let records = [
            record(356, "com.apple.controlcenter", 0, x: 875),
            record(40, "com.docker.docker", 0, x: 700),
            record(41, "com.spotify.client", 0, x: 650),
            record(41, "com.spotify.client", 1, x: 0, width: 0),
            record(42, nil, 0, x: 700),
            record(429, "com.apple.Spotlight", 0, x: 792),
        ]
        #expect(StatusItemOrder.mirrored(records).map(\.id) == ["41-0", "40-0", "42-0"])
        #expect(StatusItemOrder.isSystem(bundleID: "com.apple.TextInputMenuAgent"))
        #expect(!StatusItemOrder.isSystem(bundleID: "io.github.silvertree2010.apolloshell"))
    }

    @Test("The window is found by its centre (measured: item 792/34, window 793/32)")
    func window() {
        let item = CGRect(x: 792, y: 3, width: 34, height: 24)
        let windows = [CGRect(x: 825, y: 0, width: 42, height: 30), CGRect(x: 793, y: 0, width: 32, height: 30),
                       CGRect(x: 867, y: 0, width: 157, height: 30)]
        #expect(StatusItemOrder.window(for: item, among: windows) == 1)
        #expect(StatusItemOrder.window(for: CGRect(x: 100, y: 3, width: 20, height: 22), among: windows) == nil)
    }

    @Test("Grey glyphs take our colour, coloured icons keep theirs")
    func tint() {
        let white: [UInt8] = [255, 255, 255, 255]
        let clear: [UInt8] = [0, 0, 0, 0]
        let red: [UInt8] = [220, 30, 30, 255]
        #expect(StatusItemTint.isMonochrome(rgba: Array([[UInt8]](repeating: white, count: 100).joined())
                                              + Array([[UInt8]](repeating: clear, count: 100).joined())))
        #expect(!StatusItemTint.isMonochrome(rgba: Array([[UInt8]](repeating: white, count: 50).joined())
                                               + Array([[UInt8]](repeating: red, count: 50).joined())))
        #expect(StatusItemTint.isMonochrome(rgba: Array([[UInt8]](repeating: white, count: 100).joined()) + red))
        #expect(StatusItemTint.isMonochrome(rgba: []))
    }
}

@Suite("Hiding Apple's menu bar")
struct AppleMenuBarHidingTests {

    @Test("The saved original reads back, a missing key included")
    func original() {
        for value in [AppleMenuBarOriginal(hidden: nil), .init(hidden: true), .init(hidden: false)] {
            #expect(AppleMenuBarOriginal.load(from: value.encoded()) == value)
        }
        #expect(AppleMenuBarOriginal.load(from: nil) == nil)
        #expect(AppleMenuBarOriginal.load(from: Data("nonsense".utf8)) == nil)
    }

}

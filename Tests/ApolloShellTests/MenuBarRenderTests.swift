import Testing
import Foundation
import AppKit
import ApolloRuntime
import ApolloConfig
@testable import ApolloShell

@MainActor
@Suite("Render: menu bar zones and app-menus", .serialized)
struct MenuBarRenderTests {
    func panel(_ children: String, _ css: String) throws -> Snapshot {
        try RenderProbe.render("panel \"t\" anchor=\"left\" {\n\(children)\n}", css: "#t { width: 300px; height: 20px; align-items: start; }\n" + css)
    }

    @Test("justify-self center sits in the true middle, end at the end, start at the start")
    func zones() throws {
        let css = """
            .r { width: 300px; height: 10px; gap: 8px; }
            .a { width: 60px; height: 10px; background: #ff0000; }
            .b { width: 20px; height: 10px; background: #0000ff; justify-self: center; }
            .c { width: 10px; height: 10px; background: #00ff00; justify-self: end; }
            """
        let shot = try panel("row class=\"r\" { stack class=\"a\"; stack class=\"b\"; stack class=\"c\" }", css)
        #expect(shot.bounds { $0.near(.red) } == CGRect(x: 0, y: 0, width: 60, height: 10))
        #expect(shot.bounds { $0.near(.blue) } == CGRect(x: 140, y: 0, width: 20, height: 10))
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 290, y: 0, width: 10, height: 10))
    }

    @Test("A row without justify-self children lays out as before")
    func plainRowUnchanged() throws {
        let css = ".r { width: 300px; height: 10px; gap: 8px; } .a { width: 60px; height: 10px; background: #ff0000; } .c { width: 10px; height: 10px; background: #00ff00; }"
        let shot = try panel("row class=\"r\" { stack class=\"a\"; stack class=\"c\" }", css)
        #expect(shot.bounds { $0.near(.green) } == CGRect(x: 68, y: 0, width: 10, height: 10))
    }

    @Test("app-menus keeps the first child, folds the middle ones and shows the last only on overflow")
    func appMenusCollapse() throws {
        let css = """
            .m { height: 10px; }
            .lead { width: 40px; height: 10px; background: #ff0000; }
            .title { width: 30px; height: 10px; background: #0000ff; }
            .more { width: 10px; height: 10px; background: #00ff00; }
            """
        let wide = try panel("app-menus class=\"m\" { stack class=\"lead\"; stack class=\"title\"; stack class=\"title\"; stack class=\"more\" }", css)
        #expect(wide.bounds { $0.near(.green) } == nil)
        #expect(wide.bounds { $0.near(.blue) } == CGRect(x: 40, y: 0, width: 60, height: 10))
        #expect(wide.bounds { $0.near(.red) } == CGRect(x: 0, y: 0, width: 40, height: 10))
        let tight = try panel("app-menus class=\"m\" style=\"width: 90px\" { stack class=\"lead\"; stack class=\"title\"; stack class=\"title\"; stack class=\"more\" }", css)
        #expect(tight.bounds { $0.near(.blue) } == CGRect(x: 40, y: 0, width: 30, height: 10))
        #expect(tight.bounds { $0.near(.green) } == CGRect(x: 70, y: 0, width: 10, height: 10))
    }

    @Test("AppMenusLayout.fit reports the folded middle children")
    func fit() {
        let result = AppMenusLayout.fit(widths: [40, 30, 30, 30, 10], available: 100, spacing: 0)
        #expect(result.shown == [0, 1, 4])
        #expect(result.hidden == [2, 3])
        #expect(AppMenusLayout.fit(widths: [40, 30, 10], available: 100, spacing: 0).hidden.isEmpty)
    }

    @Test("Menu source helpers read indices and item ids from values and records")
    func sourceHelpers() {
        #expect(MenuBarMenuSources.indices([.number(3), .record(Record([("index", .number(4))])), .string("x")]) == [3, 4])
        #expect(MenuBarMenuSources.itemID(.string("12-0")) == "12-0")
        #expect(MenuBarMenuSources.itemID(.record(Record([("id", .string("9-1"))]))) == "9-1")
        #expect(MenuBarMenuSources.itemID(.null) == nil)
    }
}

@MainActor
@Suite("Hiding Apple's menu bar: controller")
struct AppleMenuBarHidingControllerTests {
    func make() -> (AppleMenuBarHidingController, URL, Box) {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("menubar-\(UUID().uuidString)/apple-menubar.json")
        let controller = AppleMenuBarHidingController(fileURL: url)
        let box = Box()
        controller.read = { box.value }
        controller.write = { box.value = $0; box.writes += 1 }
        return (controller, url, box)
    }

    final class Box {
        var value: Bool?
        var writes = 0
    }

    @Test("Hide saves the original, restore writes it back and removes the file")
    func roundTrip() {
        let (controller, url, box) = make()
        controller.apply(true)
        #expect(box.value == true)
        #expect(controller.isHidden)
        controller.apply(true)
        #expect(box.writes == 1)
        controller.apply(false)
        #expect(box.value == nil)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }

    @Test("A file left by a crash restores at start; quitting restores too; the user's own hiding survives")
    func crashAndQuit() throws {
        let (controller, url, box) = make()
        box.value = false
        controller.apply(true)
        let second = AppleMenuBarHidingController(fileURL: url)
        second.read = { box.value }
        second.write = { box.value = $0 }
        second.recoverAfterCrash()
        #expect(box.value == false)
        #expect(!second.isHidden)
        box.value = true
        second.apply(true)
        second.terminate()
        #expect(box.value == true)
        #expect(!FileManager.default.fileExists(atPath: url.path))
    }
}

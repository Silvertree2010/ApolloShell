import Foundation
import Testing
import ApolloConfig
import ApolloRuntime
@testable import ApolloProviders

@MainActor
final class FakeMenuBarSource: MenuBarSource {
    var handler: (@MainActor (MenuBarState?) -> Void)?
    var pressed: [[String]] = []
    var state: MenuBarState? = MenuBarState(appName: "Finder", bundleID: "com.apple.finder", titles: ["Apple", "Finder", "File", "Edit"], trusted: true)

    func start(_ handler: @escaping @MainActor (MenuBarState?) -> Void) {
        self.handler = handler
        handler(state)
    }

    func stop() { handler = nil }

    func press(_ path: [String]) async -> Bool {
        pressed.append(path)
        return true
    }

    func change(_ state: MenuBarState?) {
        self.state = state
        handler?(state)
    }
}

@MainActor
final class FakeStatusItemsSource: StatusItemsSource {
    var handler: (@MainActor ([StatusItemState]) -> Void)?
    var clicked: [String] = []
    var items = [StatusItemState(id: "12-0", app: "com.docker.docker", name: "Docker", hasImage: true, imageVersion: 2, kind: "menu", monochrome: true)]

    func start(_ handler: @escaping @MainActor ([StatusItemState]) -> Void) {
        self.handler = handler
        handler(items)
    }

    func stop() { handler = nil }

    func click(_ id: String) async -> Bool {
        clicked.append(id)
        return items.contains { $0.id == id }
    }

    func imageData(_ id: String) -> Data? { id == "12-0" ? Data([1, 2]) : nil }
}

@MainActor
@Suite("Provider menubar and status-items")
struct MenuBarProviderTests {
    @Test("menubar delivers every registry field, the app's own name as menu 1")
    func menubarFields() {
        let harness = ProviderHarness()
        let source = FakeMenuBarSource()
        harness.register(MenuBarProvider(source: source, clock: harness.clock))
        let token = harness.demand("menubar")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("menubar")).isEmpty)
        #expect(harness.value("menubar", "app-name") == .string("Finder"))
        guard case .list(let menus) = harness.value("menubar", "menus") else { Issue.record("no menus"); return }
        #expect(menus.count == 4)
        #expect(menus[0] == .record(Record([("index", .number(0)), ("title", .string("Apple")), ("apple", .bool(true)), ("app", .bool(false))])))
        source.change(MenuBarState(appName: "Terminal", bundleID: "com.apple.Terminal", titles: [], trusted: false))
        harness.flush()
        guard case .list(let bare) = harness.value("menubar", "menus") else { Issue.record("no menus"); return }
        #expect(bare.count == 2)
        #expect(harness.value("menubar", "app-name") == .string("Terminal"))
        #expect(harness.value("menubar", "trusted") == .bool(false))
        harness.release(token)
        #expect(source.handler == nil)
    }

    @Test("menubar.press hands the title path to the source")
    func press() async throws {
        let harness = ProviderHarness()
        let source = FakeMenuBarSource()
        let provider = MenuBarProvider(source: source, clock: harness.clock)
        harness.register(provider)
        _ = try await provider.perform("menubar.press", arguments: [.string("File"), .string("New Folder")], properties: Record())
        #expect(source.pressed == [["File", "New Folder"]])
        await #expect(throws: ProviderActionError.self) {
            _ = try await provider.perform("menubar.press", arguments: [], properties: Record())
        }
    }

    @Test("status-items lists items with a versioned image and clicks by id or record")
    func statusItems() async throws {
        let harness = ProviderHarness()
        let source = FakeStatusItemsSource()
        let provider = StatusItemsProvider(source: source, clock: harness.clock)
        harness.register(provider)
        harness.demand("status-items", "list")
        #expect(harness.conformanceProblems(BuiltinProviderSchemas.schema("status-items")).isEmpty)
        guard case .list(let list) = harness.value("status-items", "list"), case .record(let item)? = list.first else { Issue.record("no list"); return }
        #expect(item["image"] == .image(ImageRef(source: "status-item", id: "12-0#2")))
        #expect(item["kind"] == .string("menu"))
        #expect(provider.imageData("12-0#2") == Data([1, 2]))
        _ = try await provider.perform("status-items.click", arguments: [.string("12-0")], properties: Record())
        _ = try await provider.perform("status-items.click", arguments: [.record(item)], properties: Record())
        #expect(source.clicked == ["12-0", "12-0"])
    }

    @Test("Notch areas are screen-relative with y from the top, null without")
    func notchArea() {
        let frame = CGRect(x: 100, y: 0, width: 1728, height: 1117)
        #expect(ScreensProvider.area(nil, in: frame) == .null)
        let left = CGRect(x: 100, y: 1085, width: 771, height: 32)
        #expect(ScreensProvider.area(left, in: frame) == .record(Record([("x", .number(0)), ("y", .number(0)), ("width", .number(771)), ("height", .number(32))])))
    }
}

import AppKit
import ApolloShellCore
import SwiftUI

struct DockStackItem: Identifiable, Equatable {
    enum Kind: Equatable {
        case app(SidebarDockModel.Entry)
        case file(URL)
    }

    let id: String
    let name: String
    let icon: NSImage
    let running: Bool
    let kind: Kind
}

struct DockStack: Equatable {
    let id: String
    let title: String
    let items: [DockStackItem]

    static let cell: CGFloat = 40

    var rows: Int { max(11, Int((Double(items.count) / 7).rounded(.up))) }
    var columns: Int { max(1, Int((Double(items.count) / Double(rows)).rounded(.up))) }
    var width: CGFloat { CGFloat(columns) * Self.cell + 16 }
}

struct DockFile: Identifiable, Equatable {
    let url: URL
    let name: String
    let icon: NSImage
    let folder: Bool
    var id: String { "f:" + url.path }

    static func make(_ url: URL) -> DockFile? {
        var dir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &dir) else { return nil }
        return DockFile(url: url, name: FileManager.default.displayName(atPath: url.path),
                        icon: NSWorkspace.shared.icon(forFile: url.path), folder: dir.boolValue)
    }

    func contents(limit: Int = 60) -> [DockStackItem] {
        let keys: [URLResourceKey] = [.contentModificationDateKey, .isHiddenKey]
        let list = (try? FileManager.default.contentsOfDirectory(at: url, includingPropertiesForKeys: keys, options: [.skipsHiddenFiles])) ?? []
        let sorted = list.sorted { a, b in
            let da = (try? a.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            let db = (try? b.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .distantPast
            return da > db
        }
        return sorted.prefix(limit).map { u in
            DockStackItem(id: "f:" + u.path, name: FileManager.default.displayName(atPath: u.path),
                          icon: NSWorkspace.shared.icon(forFile: u.path), running: false, kind: .file(u))
        }
    }
}

@MainActor
enum DockTrash {
    static var url: URL {
        (try? FileManager.default.url(for: .trashDirectory, in: .userDomainMask, appropriateFor: nil, create: false))
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash", isDirectory: true)
    }

    static func full() -> Bool {
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: nil, options: [.skipsSubdirectoryDescendants]) else { return false }
        while let u = e.nextObject() as? URL {
            if u.lastPathComponent != ".DS_Store" { return true }
        }
        return false
    }

    static func icon(full: Bool) -> NSImage {
        NSImage(named: full ? NSImage.trashFullName : NSImage.trashEmptyName) ?? NSWorkspace.shared.icon(forFile: url.path)
    }

    static func open() {
        NSWorkspace.shared.open(url)
    }

    static func recycle(_ urls: [URL], done: @escaping @MainActor () -> Void) {
        NSWorkspace.shared.recycle(urls) { _, _ in
            Task { @MainActor in done() }
        }
    }

    static func empty(done: @escaping @MainActor () -> Void) {
        let a = NSAlert()
        a.messageText = String(localized: "Empty the Trash?")
        a.informativeText = String(localized: "The items in the Trash are deleted immediately. This cannot be undone.")
        a.addButton(withTitle: String(localized: "Empty Trash"))
        a.addButton(withTitle: String(localized: "Cancel"))
        a.alertStyle = .warning
        NSApp.activate()
        guard a.runModal() == .alertFirstButtonReturn else { return }
        Task.detached {
            var err: NSDictionary?
            NSAppleScript(source: "tell application \"Finder\" to empty trash")?.executeAndReturnError(&err)
            await MainActor.run { done() }
        }
    }
}

struct DockStackView: View {
    let model: StatusPopoutModel

    var body: some View {
        let stack = model.stack
        let items = stack?.items ?? []
        let cols = stack?.columns ?? 1
        let rows = stack?.rows ?? 11
        HStack(alignment: .top, spacing: 0) {
            ForEach(0..<cols, id: \.self) { c in
                VStack(spacing: 4) {
                    ForEach(items.dropFirst(c * rows).prefix(rows)) { item in
                        DockStackCell(item: item, model: model)
                    }
                }
                .frame(width: DockStack.cell)
            }
        }
        .padding(8)
        .background { HoverTracker { model.onPanelHover($0) } }
    }
}

private struct DockStackCell: View {
    let item: DockStackItem
    let model: StatusPopoutModel
    @State private var hov = false
    @State private var down = false
    @State private var drop = false

    var body: some View {
        Image(nsImage: item.icon)
            .resizable()
            .interpolation(.high)
            .frame(width: 26, height: 26)
            .brightness(down || drop ? -0.25 : 0)
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(hov || drop ? 0.14 : 0), in: .rect(cornerRadius: 9))
            .overlay(alignment: .leading) {
                if item.running {
                    Circle().fill(Color.primary.opacity(0.65)).frame(width: 4, height: 4).offset(x: -5)
                }
            }
            .overlay {
                DockMouseCatcher(
                    bundleID: item.id, dragImage: item.icon,
                    onClick: { model.onStackClick(item, $0) },
                    onMenu: { model.onStackMenu(item, $0) },
                    onPress: { down = $0 },
                    onScroll: {},
                    onDropFiles: { model.onStackDrop(item, $0) },
                    onDropApp: { _ in },
                    onDropTarget: { drop = $0 }
                )
            }
            .background { HoverTracker { hov = $0 } }
            .animation(.easeOut(duration: 0.12), value: hov)
            .help(item.name)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(item.name)
            .accessibilityAddTraits(.isButton)
    }
}

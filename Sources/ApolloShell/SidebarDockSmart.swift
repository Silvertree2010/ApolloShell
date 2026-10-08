import AppKit
import ApolloShellCore
import SwiftUI

@MainActor
enum DockSmartMenu {
    static func file(_ f: URL, pinned: DockFile?, model: SidebarDockModel, at view: NSView) {
        let m = NSMenu()
        m.addItem(Item(String(localized: "Open")) { model.open(f) })
        m.addItem(Item(String(localized: "Show in Finder")) { NSWorkspace.shared.activateFileViewerSelecting([f]) })
        if let pinned {
            m.addItem(.separator())
            m.addItem(Item(String(localized: "Remove from Dock")) { model.unpin(pinned) })
        }
        m.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX, y: view.bounds.maxY), in: view)
    }

    static func trash(model: SidebarDockModel, at view: NSView) {
        let m = NSMenu()
        m.addItem(Item(String(localized: "Open")) { DockTrash.open() })
        let e = Item(String(localized: "Empty Trash…")) { DockTrash.empty { model.readTrash() } }
        e.isEnabled = model.trashFull
        m.autoenablesItems = false
        m.addItem(e)
        m.popUp(positioning: nil, at: NSPoint(x: view.bounds.maxX, y: view.bounds.maxY), in: view)
    }

    final class Item: NSMenuItem {
        private let run: () -> Void

        init(_ title: String, _ run: @escaping () -> Void) {
            self.run = run
            super.init(title: title, action: #selector(fire), keyEquivalent: "")
            target = self
        }

        required init(coder: NSCoder) { fatalError("nicht aus Nib") }

        @objc private func fire() { run() }
    }
}

extension SidebarDockModel {
    func wire(_ p: StatusPopoutModel) {
        p.onStackClick = { [weak self, weak p] item, mods in
            guard let self else { return }
            switch item.kind {
            case .app(let e): self.click(e, modifiers: mods)
            case .file(let u): self.open(u)
            }
            p?.onOpenedSettings()
        }
        p.onStackMenu = { [weak self] item, view in
            guard let self else { return }
            switch item.kind {
            case .app(let e): DockMenu.show(for: e, model: self, at: view)
            case .file(let u): DockSmartMenu.file(u, pinned: nil, model: self, at: view)
            }
        }
        p.onStackDrop = { [weak self] item, urls in
            guard let self else { return }
            switch item.kind {
            case .app(let e): self.openFiles(urls, with: e)
            case .file(let u):
                if (try? u.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true { self.move(urls, into: u) }
            }
        }
    }
}

struct DockStackButton<Face: View>: View {
    let id: String
    let help: String
    let image: NSImage
    let make: () -> DockStack
    var onMenu: (NSView) -> Void = { _ in }
    var onDropFiles: ([URL]) -> Void = { _ in }
    @ViewBuilder let face: () -> Face
    @Environment(StatusPopoutModel.self) private var popout: StatusPopoutModel?
    @State private var frame: CGRect = .zero
    @State private var hov = false
    @State private var down = false
    @State private var drop = false

    var body: some View {
        let open = popout?.isOpen == true && popout?.shown == .stack && popout?.stack?.id == id
        face()
            .brightness(down || drop ? -0.25 : 0)
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(hov || drop || open ? 0.14 : 0), in: .rect(cornerRadius: 9))
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { frame = $0 }
            .overlay {
                DockMouseCatcher(
                    bundleID: id, dragImage: image,
                    onClick: { _ in popout?.onStackToggle(make(), frame) },
                    onMenu: onMenu,
                    onPress: { down = $0 },
                    onScroll: {},
                    onDropFiles: onDropFiles,
                    onDropApp: { _ in },
                    onDropTarget: { drop = $0 }
                )
            }
            .background {
                HoverTracker { inside in
                    hov = inside
                    popout?.onStackHover(make(), frame, inside)
                }
            }
            .animation(.easeOut(duration: 0.12), value: hov)
            .animation(.easeOut(duration: 0.12), value: open)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
    }
}

struct DockGroupFace: View {
    let icons: [NSImage]
    let size: CGFloat

    var body: some View {
        let c = (size - 3) / 2
        VStack(spacing: 2) {
            HStack(spacing: 2) { cell(0, c); cell(1, c) }
            HStack(spacing: 2) { cell(2, c); cell(3, c) }
        }
        .padding(1)
        .frame(width: size, height: size)
        .background(Color.primary.opacity(0.10), in: .rect(cornerRadius: size * 0.26))
    }

    @ViewBuilder
    private func cell(_ i: Int, _ c: CGFloat) -> some View {
        if i < icons.count {
            Image(nsImage: icons[i]).resizable().interpolation(.high).frame(width: c, height: c)
        } else {
            Color.clear.frame(width: c, height: c)
        }
    }
}

struct DockFileItem: View {
    let file: DockFile
    let model: SidebarDockModel
    let size: CGFloat

    var body: some View {
        if file.folder {
            DockStackButton(id: file.id, help: file.name, image: file.icon, make: { model.stack(file) },
                            onMenu: { DockSmartMenu.file(file.url, pinned: file, model: model, at: $0) },
                            onDropFiles: { model.move($0, into: file.url) }) {
                Image(nsImage: file.icon).resizable().interpolation(.high).frame(width: size, height: size)
            }
        } else {
            DockPlainItem(id: file.id, help: file.name, image: file.icon, size: size,
                          onClick: { model.open(file.url) },
                          onMenu: { DockSmartMenu.file(file.url, pinned: file, model: model, at: $0) },
                          onDropFiles: { _ in })
        }
    }
}

struct DockTrashItem: View {
    let model: SidebarDockModel
    let size: CGFloat

    var body: some View {
        let img = DockTrash.icon(full: model.trashFull)
        DockPlainItem(id: "trash", help: String(localized: "Trash"), image: img, size: size,
                      onClick: { DockTrash.open() },
                      onMenu: { DockSmartMenu.trash(model: model, at: $0) },
                      onDropFiles: { model.trash($0) },
                      onDropApp: { model.dropOnTrash($0) })
    }
}

struct DockPlainItem: View {
    let id: String
    let help: String
    let image: NSImage
    let size: CGFloat
    let onClick: () -> Void
    let onMenu: (NSView) -> Void
    let onDropFiles: ([URL]) -> Void
    var onDropApp: (String) -> Void = { _ in }
    @State private var hov = false
    @State private var down = false
    @State private var drop = false

    var body: some View {
        Image(nsImage: image)
            .resizable()
            .interpolation(.high)
            .frame(width: size, height: size)
            .brightness(down || drop ? -0.25 : 0)
            .frame(width: 32, height: 32)
            .background(Color.primary.opacity(hov || drop ? 0.14 : 0), in: .rect(cornerRadius: 9))
            .overlay {
                DockMouseCatcher(
                    bundleID: id, dragImage: image,
                    onClick: { _ in onClick() }, onMenu: onMenu, onPress: { down = $0 },
                    onScroll: {}, onDropFiles: onDropFiles, onDropApp: onDropApp,
                    onDropTarget: { drop = $0 }
                )
            }
            .background { HoverTracker { hov = $0 } }
            .animation(.easeOut(duration: 0.12), value: hov)
            .help(help)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(help)
            .accessibilityAddTraits(.isButton)
    }
}

struct DockDropZone: NSViewRepresentable {
    let onDrop: ([URL]) -> Void

    func makeNSView(context: Context) -> V {
        let v = V()
        v.onDrop = onDrop
        return v
    }

    func updateNSView(_ v: V, context: Context) { v.onDrop = onDrop }

    final class V: NSView {
        var onDrop: ([URL]) -> Void = { _ in }

        override init(frame: NSRect) {
            super.init(frame: frame)
            registerForDraggedTypes([.fileURL])
        }

        required init?(coder: NSCoder) { fatalError("nicht aus Nib") }

        override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
            sender.draggingPasteboard.canReadObject(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) ? .link : []
        }

        override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
            let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL] ?? []
            guard !urls.isEmpty else { return false }
            onDrop(urls)
            return true
        }
    }
}

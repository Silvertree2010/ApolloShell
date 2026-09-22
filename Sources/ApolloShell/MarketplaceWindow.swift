import AppKit
import SwiftUI

/// The Marketplace in a window of its own, opened from Nexus > Themes. A
/// window rather than a sheet: you can keep browsing while Nexus shows the
/// theme you just installed, and the window keeps its size.
@MainActor
final class MarketplaceWindow: NSObject, NSWindowDelegate {
    static let shared = MarketplaceWindow()

    private static let frameName = "Marketplace"
    private var window: NSWindow?
    private var store: MarketplaceStore?

    func show(themes: ThemeStore) {
        let store = self.store ?? MarketplaceStore(themeStore: themes)
        self.store = store
        let window = self.window ?? makeWindow(store: store, themes: themes)
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
    }

    private func makeWindow(store: MarketplaceStore, themes: ThemeStore) -> NSWindow {
        let window = ShellWindow(
            contentRect: NSRect(x: 0, y: 0, width: 780, height: 620),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: true
        )
        window.title = String(localized: "Marketplace")
        window.isReleasedWhenClosed = false
        window.tabbingMode = .disallowed
        window.collectionBehavior = [.moveToActiveSpace]
        window.minSize = NSSize(width: 640, height: 480)
        window.delegate = self
        let root = MarketplaceView(store: store, themes: themes) { [weak window] in window?.close() }
            .shellTheme()
        window.contentViewController = NSHostingController(rootView: root)
        window.setContentSize(NSSize(width: 780, height: 620))
        if !window.setFrameUsingName(Self.frameName) { window.center() }
        window.setFrameAutosaveName(Self.frameName)
        self.window = window
        return window
    }
}

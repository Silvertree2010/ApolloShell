#if DEBUG
import AppKit
import ApolloShellCore
import SwiftUI

/// Invisible self-test of global edit mode:
/// `ApolloShell --selftest-edit <file>` builds the Dashboard, Control Center
/// and the windows of edit mode with an in-memory-only settings instance,
/// runs through Begin, Gallery, Add, Done, quick restart and Cancel, and
/// writes what passed and what failed to the file. All panels stay
/// transparent and click-through (`ShellPanel`), Esc and mouse monitoring
/// stay off - so it runs alongside the real ApolloShell without touching
/// the screen. Debug builds only.
@MainActor
enum EditModeSelfTest {
    static var invisible = false
    private static var harness: EditModeSelfTestHarness?

    static func runIfRequested() {
        let args = CommandLine.arguments
        guard let index = args.firstIndex(of: "--selftest-edit"), index + 1 < args.count else { return }
        invisible = true
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let harness = EditModeSelfTestHarness(output: URL(fileURLWithPath: args[index + 1]))
        self.harness = harness
        DispatchQueue.main.async { harness.run() }
        app.run()
    }
}

@MainActor
private final class EditModeSelfTestHarness {
    private let output: URL
    private var lines: [String] = []
    private var failures = 0
    private let store: ShellSettingsStore
    private let dashboardEditor: DashboardEditor
    private let editor: ShellEditor
    private let dashboard: Dashboard
    private let utilities: UtilitiesPanel
    private let windows: EditModeWindows

    init(output: URL) {
        self.output = output
        var settings = ShellSettings()
        settings.dashboardPages = DashboardPages(pages: DashboardPages.defaultPages(
            places: .empty, hasBattery: PerformanceSampler.hasInternalBattery))
        store = .preview(settings)
        dashboardEditor = DashboardEditor(store: store)
        editor = ShellEditor(store: store, dashboard: dashboardEditor)
        dashboard = Dashboard(settings: store, editor: dashboardEditor)
        utilities = UtilitiesPanel(settings: store, editor: editor)
        windows = EditModeWindows(editor: editor)
        editor.dashboardStartPageID = { [weak dashboard] in dashboard?.currentPageID }
        windows.utilitiesFrame = { [weak utilities] in utilities?.openFrame }
        windows.dashboardFrame = { [weak dashboard] in dashboard?.openFrame }
        utilities.onHeightChange = { [weak windows] _ in windows?.utilitiesHeightChanged() }
    }

    func run() {
        Task { @MainActor in
            await scenario()
            lines.append(failures == 0 ? "ALL OK" : "\(failures) FAILURES")
            try? lines.joined(separator: "\n").write(to: output, atomically: true, encoding: .utf8)
            exit(failures == 0 ? 0 : 1)
        }
    }

    private func check(_ ok: Bool, _ what: String) {
        lines.append((ok ? "ok     " : "FAILED ") + what)
        if !ok { failures += 1 }
    }

    private func note(_ text: String) { lines.append("       " + text) }

    private func wait(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    private func r(_ rect: NSRect?) -> String {
        guard let rect else { return "-" }
        return "(\(Int(rect.minX)),\(Int(rect.minY)) \(Int(rect.width))x\(Int(rect.height)))"
    }

    /// Measurement setup for gestures under `scaleEffect`: same structure as
    /// the Dashboard (`ScaledToFit` + `scaleEffect` around the top left, a
    /// named coordinate space inside), scale 2, a field at a known
    /// location. A drag over 200 window points must yield 100 in the
    /// coordinate space.
    private func probeScaledDrag() async {
        var translation: CGSize?
        var location: CGPoint?
        let view = ScaledToFit(scale: 2) {
            ZStack(alignment: .topLeading) {
                Color.blue.frame(width: 50, height: 50)
                    .padding(.leading, 20).padding(.top, 20)
                    .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .named("probe"))
                        .onEnded { value in
                            translation = value.translation
                            location = value.startLocation
                        })
            }
            .frame(width: 200, height: 100, alignment: .topLeading)
            .coordinateSpace(name: "probe")
            .scaleEffect(2, anchor: .topLeading)
        }
        let hosting = FirstMouseHostingView(rootView: view)
        let panel = ShellPanel(size: hosting.fittingSize, level: .normal, behavior: [.canJoinAllSpaces])
        panel.contentView = hosting
        panel.setFrameOrigin(NSPoint(x: 100, y: 100))
        panel.orderFrontRegardless()
        await wait(0.2)
        note("Measurement setup: window \(r(panel.frame)), host \(r(hosting.frame))")
        func send(_ type: NSEvent.EventType, _ p: CGPoint) {
            let loc = hosting.convert(NSPoint(x: p.x, y: p.y), to: nil)
            if let e = NSEvent.mouseEvent(with: type, location: loc, modifierFlags: [], timestamp: ProcessInfo.processInfo.systemUptime,
                                          windowNumber: panel.windowNumber, context: nil, eventNumber: 0, clickCount: 1, pressure: 1) {
                panel.sendEvent(e)
            }
        }
        send(.leftMouseDown, CGPoint(x: 90, y: 90))
        for step in 1...8 { send(.leftMouseDragged, CGPoint(x: 90 + 25 * CGFloat(step), y: 90)) }
        send(.leftMouseUp, CGPoint(x: 290, y: 90))
        await wait(0.2)
        note("Measurement setup: drag of 200 window points -> translation \(translation.map { "\($0.width)" } ?? "no gesture"), start \(location.map { "\($0)" } ?? "-")")
        check(translation.map { abs($0.width - 100) < 1 } ?? false,
              "Gestures under scaleEffect compute in the unscaled coordinate space (expected 100)")
        panel.orderOut(nil)
    }

    /// Handle, tap (popover on the widget), minus - at real scale.
    private func widgetHandles(_ id: WidgetInstance.ID) async {
        guard let page = dashboardEditor.debugPageRectInHost,
              let frame = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame else { return }
        let scale = dashboard.debugScale
        func host(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: page.minX + x * scale, y: page.minY + y * scale)
        }
        // Drag the bottom-right handle (center 17 points before the corner)
        // by 100 x 120: height jumps to 250, width 110 + 100 = 210.
        let handle = host(frame.maxX - 17, frame.maxY - 17)
        dashboard.debugDrag(from: handle, to: CGPoint(x: handle.x + 100 * scale, y: handle.y + 120 * scale))
        await wait(0.4)
        let resized = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame
        check(resized.map { $0.width == frame.width + 100 && $0.height == 250 && $0.x == frame.x } ?? false,
              "Handle changes the size (before \(Int(frame.width))x\(Int(frame.height)), after \(resized.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"))")
        guard let current = resized else { return }

        // Tap: popover with the options, positioned next to this widget.
        dashboardEditor.optionsWidgetID = nil
        dashboard.debugClick(at: host(current.x + current.width / 2, current.y + current.height / 2))
        await wait(0.6)
        check(dashboardEditor.optionsWidgetID == id, "Tapping opens the options")
        let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
        let widgetOnScreen = dashboard.debugScreenRect(ofHostRect: CGRect(x: page.minX + current.x * scale, y: page.minY + current.y * scale,
                                                                             width: current.width * scale, height: current.height * scale))
        note("Popover \(r(popover?.frame)), widget on screen \(r(widgetOnScreen))")
        if let popover, let widgetOnScreen {
            let besideRight = abs(popover.frame.minX - widgetOnScreen.maxX) < 40
            let verticallyNear = popover.frame.minY < widgetOnScreen.maxY && popover.frame.maxY > widgetOnScreen.minY
            check(besideRight && verticallyNear, "Popover sits to the right of the widget")
            check(popover.level.rawValue > windows.debugLevels.scrim,
                  "Popover is above the scrim (level \(popover.level.rawValue), scrim \(windows.debugLevels.scrim))")
        } else {
            check(false, "Popover appears")
        }
        dashboardEditor.optionsWidgetID = nil
        await wait(0.4)

        // Minus at the top left (center exactly on the corner).
        dashboard.debugClick(at: host(current.x, current.y))
        await wait(0.5)
        check(!(dashboardEditor.page?.widgets.contains { $0.id == id } ?? true), "Minus removes the widget")
    }

    /// Pages in the sidebar: an empty name falls back to "Page", deleting
    /// happens without confirmation, never the last page.
    private func pageBar(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.5)
        guard let id = dashboardEditor.addPage() else { check(false, "Create page"); return }
        dashboardEditor.renamingPageID = id
        dashboardEditor.renamePage(id, to: "   ")
        dashboardEditor.renamingPageID = nil
        check(dashboardEditor.session?.pages.page(id: id)?.name == String(localized: "Page"),
              "An empty name when renaming becomes \u{201c}Page\u{201d}")
        let count = dashboardEditor.session?.pages.pages.count ?? 0
        check(dashboardEditor.removePage(id) && dashboardEditor.session?.pages.pages.count == count - 1,
              "Deleting a page needs no confirmation")
        for page in dashboardEditor.session?.pages.pages.dropFirst() ?? [] { _ = dashboardEditor.removePage(page.id) }
        let last = dashboardEditor.session?.pages.pages.first?.id
        check(last.map { !dashboardEditor.removePage($0) } ?? false, "The last page cannot be deleted")
        dashboardEditor.restoreDefaults()
        check(Set(dashboardEditor.session?.pages.pages.compactMap(\.template) ?? []).count == PageTemplate.allCases.count,
              "Restoring defaults brings back all four")
        editor.cancel()
        await wait(0.6)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Esc from the inside out: selection, renaming, gallery, confirmation,
    /// only then Cancel.
    private func escapeOrder(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.5)
        let page = dashboardEditor.page
        dashboardEditor.selectedWidgetID = page?.widgets.first?.id
        dashboardEditor.optionsWidgetID = page?.widgets.first?.id
        editor.galleryVisible = true
        editor.debugEscape()
        check(dashboardEditor.selectedWidgetID == nil && dashboardEditor.optionsWidgetID == nil && editor.galleryVisible,
              "Esc 1: only selection and options close, gallery stays")
        dashboardEditor.renamingPageID = page?.id
        editor.debugEscape()
        check(dashboardEditor.renamingPageID == nil && editor.galleryVisible, "Esc 2: renaming closes, gallery stays")
        editor.debugEscape()
        check(!editor.galleryVisible && editor.isEditing, "Esc 3: gallery closes, mode stays")
        dashboardEditor.addPage()
        let plainToolbar = windows.debugToolbarFrame
        editor.debugEscape()
        check(editor.pendingCancelConfirmation && editor.isEditing, "Esc 4 with changes: confirmation instead of cancel")
        await wait(0.4)
        let confirmToolbar = windows.debugToolbarFrame
        note("Toolbar normal \(r(plainToolbar)), with confirmation \(r(confirmToolbar))")
        check(confirmToolbar != nil && confirmToolbar?.size != plainToolbar?.size && (confirmToolbar.map(screen.frame.contains) ?? false),
              "Confirmation: toolbar adjusts its size and stays on screen")
        editor.debugEscape()
        check(!editor.pendingCancelConfirmation && editor.isEditing, "Esc 5: confirmation closes, keep editing")
        await wait(0.4)
        check(windows.debugToolbarFrame?.width == plainToolbar?.width, "Toolbar shrinks back afterward")
        editor.debugEscape()
        await wait(0.4)
        // "Discard" is the right button of the confirmation.
        if let toolbar = windows.debugToolbarFrame, editor.pendingCancelConfirmation {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: toolbar.width - 18 - 35, y: toolbar.height / 2))
            await wait(0.3)
        }
        check(!editor.isEditing, "Clicking Discard ends the mode")
        if editor.isEditing { editor.confirmCancel() }
        await wait(0.8)
        editor.begin(screen: screen)
        await wait(0.3)
        editor.debugEscape()
        check(!editor.isEditing, "Esc without changes cancels immediately")
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Control Center: tapping Wi-Fi (selects, no popover), minus on Wi-Fi
    /// and on a card, then tapping the link button (options). Always fresh
    /// frames: if the panel grows (new row), reported window coordinates
    /// go stale.
    private func controlCentre(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.8)
        guard let wifi = editor.utilities?.layout.toggles.first(where: { $0.kind == .wifi }),
              let wifiRect = editor.debugUtilitiesRects[wifi.id] else {
            check(false, "Found the Wi-Fi tile in Control Center")
            editor.cancel()
            return
        }
        editor.selectedToggleID = nil
        utilities.debugClick(fromTop: CGPoint(x: wifiRect.midX, y: wifiRect.midY))
        await wait(0.6)
        let wifiPopover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
        check(editor.selectedToggleID == wifi.id && wifiPopover == nil, "Tapping Wi-Fi selects it, without an empty popover")
        editor.selectedToggleID = nil
        await wait(0.3)
        // Minus on a button: center 1 point right, 3 below the top-left corner.
        utilities.debugClick(fromTop: CGPoint(x: wifiRect.minX + 1, y: wifiRect.minY + 3))
        await wait(0.5)
        check(!(editor.utilities?.layout.toggles.contains { $0.id == wifi.id } ?? true), "Minus removes the Wi-Fi button")
        await wait(0.3)
        if let card = editor.debugUtilitiesRects["card:keepAwake"] {
            utilities.debugClick(fromTop: CGPoint(x: card.minX + 2, y: card.minY + 2))
            await wait(0.5)
            check(editor.utilities?.layout.isEnabled(.keepAwake) == false, "Minus hides the \u{201c}Keep Awake\u{201d} card")
        } else {
            check(false, "Found the \u{201c}Keep Awake\u{201d} card")
        }
        editor.cancel()
        await wait(0.8)

        editor.begin(screen: screen)
        await wait(0.6)
        guard let link = editor.addToggle(.openLink) else { check(false, "Insert link button"); return }
        editor.selectedToggleID = nil
        await wait(0.8)
        utilities.debugRelayout()
        await wait(0.2)
        if let linkRect = editor.debugUtilitiesRects[link] {
            utilities.debugClick(fromTop: CGPoint(x: linkRect.midX, y: linkRect.midY))
            await wait(0.6)
            let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
            note("Link: frame \(r(linkRect)), window height \(Int(utilities.debugWindowHeight)), selected \(String(describing: editor.selectedToggleID)), popover \(r(popover?.frame))")
            note("all tiles: " + (editor.utilities?.layout.toggles.map { "\($0.id)=\(r(editor.debugUtilitiesRects[$0.id]))" }.joined(separator: " ") ?? ""))
            check(editor.selectedToggleID == link && popover != nil, "Tapping the link button shows its options")
            if let popover {
                check(popover.level.rawValue > windows.debugLevels.scrim,
                      "Popover in Control Center is above the scrim (level \(popover.level.rawValue))")
            }
        } else {
            check(false, "Found the link tile")
        }
        editor.cancel()
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Normal operation without editing: bar buttons open the matching
    /// page, a second click closes it, performance is only measured on the
    /// performance page.
    private func normalUse() async {
        guard let pages = store.settings.dashboardPages else { check(false, "Pages present"); return }
        for (tab, template) in [(DashboardTab.media, PageTemplate.media), (.performance, .performance), (.weather, .weather), (.dashboard, .overview)] {
            dashboard.show(tab: tab)
            await wait(0.5)
            let expected = pages.pages.first { $0.template == template }?.id
            check(dashboard.debugIsOpen && dashboard.debugShownPage == expected, "Bar button \(tab.rawValue) opens its page")
            check(dashboard.debugShowsPerformance == (template == .performance), "Performance measurement only on the performance page (\(tab.rawValue))")
            dashboard.show(tab: tab)
            await wait(0.5)
            check(!dashboard.debugIsOpen, "Second click on \(tab.rawValue) closes it")
        }
        dashboard.toggle()
        await wait(0.5)
        check(dashboard.debugIsOpen, "Dashboard shortcut opens")
        dashboard.toggle()
        await wait(0.5)
        check(!dashboard.debugIsOpen, "Dashboard shortcut closes")
    }

    private func scenario() async {
        await normalUse()
        await probeScaledDrag()
        for screen in NSScreen.screens {
            note("Screen \(r(screen.frame)), visible \(r(screen.visibleFrame))")
        }
        for screen in NSScreen.screens {
            await pass(on: screen)
        }
        // Toolbar size slider: the Dashboard follows live, Cancel resets it,
        // Done saves it.
        if let screen = NSScreen.screens.first {
            editor.begin(screen: screen)
            await wait(0.8)
            let before = dashboard.openFrame
            dashboardEditor.scale = 0.8
            await wait(0.4)
            let smaller = dashboard.openFrame
            check((smaller?.width ?? 0) < (before?.width ?? 0), "Slider 80%: Dashboard shrinks immediately (\(r(before)) -> \(r(smaller)))")
            if let gallery = windows.debugGalleryFrame ?? nil, let smaller { check(!gallery.intersects(smaller), "Gallery follows along") }
            check(editor.hasChanges, "Slider counts as a change")
            editor.cancel()
            await wait(0.6)
            check(store.settings.dashboardScale == 1, "Cancel discards the size")
            dashboard.debugClose(); utilities.debugClose()
            await wait(0.5)
            editor.begin(screen: screen)
            await wait(0.6)
            dashboardEditor.scale = 1.2
            editor.done()
            await wait(0.4)
            check(store.settings.dashboardScale == 1.2, "Done saves the size")
            store.settings.dashboardScale = 1
            dashboard.debugClose(); utilities.debugClose()
            await wait(0.5)
        }
        // Stress: begin and end ten times quickly in a row, with varying delays.
        if let screen = NSScreen.screens.first {
            for round in 0..<10 {
                editor.begin(screen: screen)
                await wait([0.02, 0.1, 0.3, 0.05, 0.6][round % 5])
                if round % 2 == 0 { editor.cancel() } else { editor.done() }
                await wait([0.03, 0.2, 0.01, 0.4, 0.08][round % 5])
            }
            await wait(0.9)
            check(!editor.isEditing && windows.debugVisibleScrims == 0 && windows.debugToolbarFrame == nil
                  && windows.debugGalleryFrame == nil, "Stress: nothing left stuck after ten quick rounds")
            dashboard.debugClose()
            utilities.debugClose()
            await wait(0.6)
            // Dashboard already open, then editing: stays open, pinned;
            // back to normal once done.
            dashboard.toggle()
            await wait(0.5)
            editor.begin(screen: screen)
            await wait(0.6)
            check(dashboard.debugIsOpen && windows.debugToolbarFrame != nil, "Editing while the Dashboard is already open")
            dashboard.toggle()
            await wait(0.4)
            check(dashboard.debugIsOpen, "Pinned: Dashboard shortcut does not close during editing")
            editor.cancel()
            await wait(0.6)
            dashboard.debugClose()
            utilities.debugClose()
            await wait(0.5)
        }
        // Edge case: slider at 150% - the Dashboard nearly fills the height.
        if let screen = NSScreen.screens.first {
            store.settings.dashboardScale = 1.5
            editor.begin(screen: screen)
            await wait(0.8)
            editor.galleryVisible = true
            await wait(0.8)
            let dashboardFrame = dashboard.openFrame
            let gallery = windows.debugGalleryFrame
            let toolbar = windows.debugToolbarFrame
            note("150%: Dashboard \(r(dashboardFrame)), gallery \(r(gallery)), toolbar \(r(toolbar))")
            check(gallery.map(screen.frame.contains) ?? false, "150%: gallery stays entirely on screen")
            check(toolbar.map(screen.frame.contains) ?? false, "150%: toolbar stays entirely on screen")
            if let gallery, let toolbar { check(!gallery.intersects(toolbar), "150%: gallery clear of the toolbar") }
            editor.cancel()
            await wait(0.8)
            dashboard.debugClose()
            utilities.debugClose()
            store.settings.dashboardScale = 1
            await wait(0.5)
        }
        if let screen = NSScreen.screens.first {
            await escapeOrder(on: screen)
            await pageBar(on: screen)
            await controlCentre(on: screen)
        }
    }

    /// One full pass on one screen.
    private func pass(on screen: NSScreen) async {
        note("--- Pass on \(r(screen.frame))")
        let before = store.settings
        editor.begin(screen: screen)
        await wait(0.9)
        check(editor.isEditing, "Mode running after Begin")
        let dashboardFrame = dashboard.openFrame
        let utilitiesFrame = utilities.openFrame
        check(dashboardFrame.map(screen.frame.intersects) ?? false, "Dashboard open on this screen \(r(dashboardFrame))")
        check(utilitiesFrame.map(screen.frame.intersects) ?? false, "Control Center open on this screen \(r(utilitiesFrame))")
        check(windows.debugVisibleScrims == NSScreen.screens.count,
              "Scrim on all \(NSScreen.screens.count) screens (\(windows.debugVisibleScrims))")
        let toolbar = windows.debugToolbarFrame
        check(toolbar.map(screen.frame.contains) ?? false, "Toolbar entirely on screen \(r(toolbar))")
        if let toolbar, let utilitiesFrame {
            check(!toolbar.intersects(utilitiesFrame), "Toolbar clear of Control Center")
        }
        if let toolbar, let dashboardFrame {
            check(!toolbar.intersects(dashboardFrame), "Toolbar clear of the Dashboard")
        }
        // Does the Control Center's content fit the panel while editing?
        if let layout = editor.utilities?.layout {
            let content = NSHostingView(rootView: EditableUtilitiesView(editor: editor, layout: layout).shellTheme(nil))
            let needed = content.fittingSize.height
            check(needed <= utilities.height + 1,
                  "Control Center while editing fits the panel (content \(Int(needed)), panel \(Int(utilities.height)))")
        }
        let levels = windows.debugLevels
        let drawerLevels = [dashboard.debugLevel, utilities.debugLevel].compactMap { $0 }
        check(drawerLevels.allSatisfy { $0 > levels.scrim && $0 < levels.controls },
              "Levels: scrim \(levels.scrim) < edge windows \(drawerLevels) < toolbar/gallery \(levels.controls)")
        check(levels.scrim > NSWindow.Level.mainMenu.rawValue, "Scrim above menu bar and Dock")
        check(windows.debugPanelLevels.allSatisfy { $0 == levels.scrim || $0 == levels.controls },
              "Panels really sit on their level \(windows.debugPanelLevels)")

        // Click on the toolbar's "+" (18 margin + half the button width 17,
        // half the height) - does it register, does the gallery open.
        if let toolbar = windows.debugToolbarFrame {
            // Edge of the circle (12 points off center), not the plus sign.
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: 35 - 12, y: toolbar.height / 2 + 5))
            await wait(0.2)
            check(editor.galleryVisible, "A click on the edge of the +-circle registers")
        }
        editor.galleryVisible = true
        await wait(0.9)
        let gallery = windows.debugGalleryFrame
        check(gallery.map(screen.frame.contains) ?? false, "Gallery entirely on screen \(r(gallery))")
        if let gallery, let dashboardFrame { check(!gallery.intersects(dashboardFrame), "Gallery clear of the Dashboard") }
        if let gallery, let utilitiesFrame { check(!gallery.intersects(utilitiesFrame), "Gallery clear of Control Center") }
        if let gallery, let toolbar = windows.debugToolbarFrame { check(!gallery.intersects(toolbar), "Gallery clear of the toolbar") }

        // Full page (Overview): clicking the clock in the gallery -> notice,
        // gallery grows but stays clear of the Dashboard.
        if let gallery = windows.debugGalleryFrame, dashboardEditor.page?.template == .overview {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let before = dashboardEditor.page?.widgets.count ?? 0
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column * 2.5 + 20, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.4)
            check(editor.galleryNotice != nil && dashboardEditor.page?.widgets.count == before,
                  "Full page: gallery click shows \u{201c}No Room\u{201d} instead of inserting")
            if let grown = windows.debugGalleryFrame, let dashboardFrame {
                check(!grown.intersects(dashboardFrame), "Gallery with notice stays clear of the Dashboard \(r(grown))")
            }
        }
        // Tab via click: right half of the tab row (16 margin, 36 high).
        if let gallery = windows.debugGalleryFrame {
            // Far outside on the tab, not on the text: the whole capsule counts.
            windows.debugClickGallery(fromTopLeft: NSPoint(x: gallery.width - 16 - 20, y: 16 + 18))
            await wait(0.4)
            check(editor.galleryTab == .controlCentre, "Clicking outside on the \u{201c}Control Center\u{201d} tab (not on the text) switches")
            // "Show All (Advanced)" checkbox below that, at the left edge.
            let before = editor.showsAllInGallery
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 60, y: 16 + 36 + 12 + 10))
            await wait(0.3)
            check(editor.showsAllInGallery != before, "Clicking \u{201c}Show All\u{201d} toggles it")
            editor.showsAllInGallery = before
        }
        // Click into the scrim: selection cleared in both panels.
        dashboardEditor.selectedWidgetID = dashboardEditor.page?.widgets.first?.id
        editor.selectedToggleID = editor.utilities?.layout.toggles.first?.id
        windows.debugClickScrim()
        await wait(0.3)
        check(dashboardEditor.selectedWidgetID == nil && editor.selectedToggleID == nil, "Clicking into the scrim clears every selection")
        // Control Center tab: clicking "Display Off" (14th tile, second row,
        // sixth column) adds the button.
        editor.galleryTab = .controlCentre
        await wait(0.4)
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let tileHeight: CGFloat = 73
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 5 * (column + 10) + column / 2,
                                                           y: 16 + 36 + 12 + 20 + 12 + tileHeight + 10 + tileHeight / 2))
            await wait(0.4)
            check(editor.utilities?.layout.toggles.contains { $0.kind == .displaySleep } ?? false,
                  "Control Center gallery: click adds \u{201c}Display Off\u{201d}")
            // Wi-Fi (4th tile, first row) is already there and greyed out: click does nothing.
            let wifiCount = editor.utilities?.layout.toggles.filter { $0.kind == .wifi }.count ?? 0
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 3 * (column + 10) + column / 2,
                                                           y: 16 + 36 + 12 + 20 + 12 + tileHeight / 2))
            await wait(0.3)
            check(editor.utilities?.layout.toggles.filter { $0.kind == .wifi }.count == wifiCount,
                  "Greyed-out tile (Wi-Fi already present) inserts nothing")
        }
        editor.galleryTab = .dashboard
        await wait(0.3)

        // Change and Done.
        let pageCount = dashboardEditor.session?.pages.pages.count ?? 0
        let newPage = dashboardEditor.addPage()
        // Click on the first gallery tile (Weather): 16 margin + half a
        // column, below the tabs (36) and checkbox (~20) with 12-point gaps.
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column / 2, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.2)
            check(dashboardEditor.page?.widgets.contains { $0.kind == .weather } ?? false,
                  "Clicking a gallery tile inserts the widget")
        }
        let clock = dashboardEditor.addAtFirstFreeSpot(.clock)
        check(clock != nil, "Clock inserted on the new page")
        // Dragging at a scale other than 1: the clock 100 reference points to the right.
        await wait(0.3)
        if let clock, let before = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame,
           let page = dashboardEditor.debugPageRectInHost {
            let scale = dashboard.debugScale
            let start = CGPoint(x: page.minX + (before.x + before.width / 2) * scale,
                                y: page.minY + (before.y + before.height / 2) * scale)
            note("Page in host \(r(page)), start \(Int(start.x)),\(Int(start.y)), scale \(scale)")
            dashboardEditor.selectedWidgetID = nil
            dashboard.debugDrag(from: start, to: CGPoint(x: start.x + 100 * scale, y: start.y))
            await wait(0.4)
            note("selected after the drag: \(dashboardEditor.selectedWidgetID == clock ? "the clock" : String(describing: dashboardEditor.selectedWidgetID))")
            let after = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame
            check(after.map { abs($0.x - (before.x + 100)) <= 1 && $0.y == before.y } ?? false,
                  "Dragging at scale \(String(format: "%.3f", scale)): 100 points become 100 (before x \(Int(before.x)), after \(after.map { String(Int($0.x)) } ?? "-"))")
            await widgetHandles(clock)
        } else {
            check(false, "Dragging: page or clock not found")
        }
        let toggle = editor.addToggle(.openLink)
        check(toggle != nil, "\u{201c}Open Link\u{201d} button inserted into Control Center")
        // "Done" via click: right button of the toolbar.
        if let toolbar = windows.debugToolbarFrame {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: toolbar.width - 18 - 25, y: toolbar.height / 2))
            await wait(0.2)
        }
        if editor.isEditing {
            check(false, "Click on Done registers")
            editor.done()
        } else {
            check(true, "Click on Done registers")
        }
        await wait(0.1)
        check(!editor.isEditing, "Mode ends with Done")
        check(store.settings.dashboardPages?.pages.count == pageCount + 1, "Done saves the new page")
        check(store.settings.utilities.layout.toggles.contains { $0.kind == .openLink }, "Done saves the new button")
        check(dashboard.debugShownPage == newPage, "After Done the Dashboard stays on the edited page")
        await wait(0.9)
        check(windows.debugVisibleScrims == 0, "Scrim gone after Done")
        check(windows.debugToolbarFrame == nil, "Toolbar gone after Done")
        check(windows.debugGalleryFrame == nil, "Gallery gone after Done")

        // Quick restart: end and begin again in quick succession.
        editor.begin(screen: screen)
        await wait(0.05)
        editor.cancel()
        await wait(0.05)
        editor.begin(screen: screen)
        await wait(0.9)
        check(windows.debugVisibleScrims == NSScreen.screens.count, "Scrim present after a quick restart")
        check(windows.debugToolbarFrame != nil, "Toolbar present after a quick restart")
        check(dashboard.openFrame != nil && utilities.openFrame != nil, "Panels open after a quick restart")

        // Cancel discards.
        let saved = store.settings
        dashboardEditor.addPage()
        _ = editor.addToggle(.openApp)
        editor.cancel()
        await wait(0.9)
        check(store.settings == saved, "Cancel discards both working copies")
        check(windows.debugVisibleScrims == 0 && windows.debugToolbarFrame == nil, "Mode windows gone after Cancel")
        note("Dashboard after end \(r(dashboard.openFrame)), Control Center \(r(utilities.openFrame)) (closed, unless the pointer is still there)")
        store.settings = before
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.6)
    }
}

/// Self-test: reports its own frame in window coordinates (AppKit,
/// bottom left) - more precise than SwiftUI coordinate spaces when the
/// hosting window is clipped differently than the content.
struct DebugWindowRectReporter: NSViewRepresentable {
    let report: (NSRect) -> Void

    func makeNSView(context: Context) -> ReporterView {
        let view = ReporterView()
        view.report = report
        return view
    }

    func updateNSView(_ view: ReporterView, context: Context) {
        view.report = report
        view.needsLayout = true
    }

    final class ReporterView: NSView {
        var report: (NSRect) -> Void = { _ in }
        override func layout() {
            super.layout()
            // Distance from the top edge instead of the bottom: if the
            // window grows upward (Control Center gets a new row), the
            // content stays put at the top without `layout()` firing again.
            let rect = convert(bounds, to: nil)
            let height = window?.frame.height ?? 0
            report(NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height))
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

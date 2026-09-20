#if DEBUG
import AppKit
import ApolloShellCore
import SwiftUI

/// Invisible self-test of the global edit mode:
/// `ApolloShell --selftest-edit <file>` builds the dashboard, the control
/// centre and the mode's windows on settings that live only in memory, runs
/// begin, gallery, add, done, a quick restart and cancel through, and writes
/// what holds and what does not into the file. All panels stay transparent
/// and click-through (`ShellPanel`), Esc and the mouse watch stay off - so it
/// runs next to the real ApolloShell without ever touching the screen.
/// Debug builds only.
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
    private let sidebar: Sidebar

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
        sidebar = Sidebar(settings: store, editor: editor)
        editor.addBeginHandler { [weak sidebar] _ in sidebar?.setEditing(true) }
        editor.addEndHandler { [weak sidebar] in sidebar?.setEditing(false) }
        editor.dashboardStartPageID = { [weak dashboard] in dashboard?.currentPageID }
        windows.utilitiesFrame = { [weak utilities] in utilities?.openFrame }
        windows.dashboardFrame = { [weak dashboard] in dashboard?.openFrame }
        utilities.onHeightChange = { [weak windows] _ in windows?.utilitiesHeightChanged() }
    }

    func run() {
        Task { @MainActor in
            await scenario()
            lines.append(failures == 0 ? "ALL OK" : "\(failures) FAILED")
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

    /// Probe for gestures under `scaleEffect`: the same structure as the
    /// dashboard (`ScaledToFit` + `scaleEffect` around the top left, a named
    /// coordinate space inside), scale 2, a field at a known spot. A drag over
    /// 200 window points has to come out as 100 in that space.
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
        note("Probe: window \(r(panel.frame)), host \(r(hosting.frame))")
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
        note("Probe: drag of 200 window points → translation \(translation.map { "\($0.width)" } ?? "no gesture"), start \(location.map { "\($0)" } ?? "-")")
        check(translation.map { abs($0.width - 100) < 1 } ?? false,
              "Gestures under scaleEffect measure in the unscaled space (100 expected)")
        panel.orderOut(nil)
    }

    /// Handle, tap (popover at the widget), minus - at the real scale.
    private func widgetHandles(_ id: WidgetInstance.ID) async {
        guard let page = dashboardEditor.debugPageRectInHost,
              let frame = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame else { return }
        let scale = dashboard.debugScale
        func host(_ x: Double, _ y: Double) -> CGPoint {
            CGPoint(x: page.minX + x * scale, y: page.minY + y * scale)
        }
        // Drag the handle at the bottom right (centre 17 points from the corner) by 100 x 120:
        // the height jumps to 250, the width 110 + 100 = 210.
        let handle = host(frame.maxX - 17, frame.maxY - 17)
        dashboard.debugDrag(from: handle, to: CGPoint(x: handle.x + 100 * scale, y: handle.y + 120 * scale))
        await wait(0.4)
        let resized = dashboardEditor.page?.widgets.first(where: { $0.id == id })?.frame
        check(resized.map { $0.width == frame.width + 100 && $0.height == 250 && $0.x == frame.x } ?? false,
              "The handle resizes (before \(Int(frame.width))x\(Int(frame.height)), after \(resized.map { "\(Int($0.width))x\(Int($0.height))" } ?? "-"))")
        guard let current = resized else { return }

        // Tap: the popover with the options, and right next to this widget.
        dashboardEditor.optionsWidgetID = nil
        dashboard.debugClick(at: host(current.x + current.width / 2, current.y + current.height / 2))
        await wait(0.6)
        check(dashboardEditor.optionsWidgetID == id, "Tapping opens the options")
        let popover = NSApp.windows.first { $0.isVisible && String(describing: type(of: $0)).contains("Popover") }
        let widgetOnScreen = dashboard.debugScreenRect(ofHostRect: CGRect(x: page.minX + current.x * scale, y: page.minY + current.y * scale,
                                                                             width: current.width * scale, height: current.height * scale))
        note("Popover \(r(popover?.frame)), widget on the screen \(r(widgetOnScreen))")
        if let popover, let widgetOnScreen {
            let besideRight = abs(popover.frame.minX - widgetOnScreen.maxX) < 40
            let verticallyNear = popover.frame.minY < widgetOnScreen.maxY && popover.frame.maxY > widgetOnScreen.minY
            check(besideRight && verticallyNear, "The popover sits to the right of the widget")
            check(popover.level.rawValue > windows.debugLevels.scrim,
                  "The popover lies above the scrim (level \(popover.level.rawValue), scrim \(windows.debugLevels.scrim))")
        } else {
            check(false, "The popover appears")
        }
        dashboardEditor.optionsWidgetID = nil
        await wait(0.4)

        // Minus at the top left (centre exactly on the corner).
        dashboard.debugClick(at: host(current.x, current.y))
        await wait(0.5)
        check(!(dashboardEditor.page?.widgets.contains { $0.id == id } ?? true), "Minus removes the widget")
    }

    /// Pages in the bar: an empty name falls back to “Page”, deleting takes
    /// no confirmation, the last page never goes.
    private func pageBar(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.5)
        guard let id = dashboardEditor.addPage() else { check(false, "The page is created"); return }
        dashboardEditor.renamingPageID = id
        dashboardEditor.renamePage(id, to: "   ")
        dashboardEditor.renamingPageID = nil
        check(dashboardEditor.session?.pages.page(id: id)?.name == String(localized: "Page"),
              "An empty name when renaming becomes “Page”")
        let count = dashboardEditor.session?.pages.pages.count ?? 0
        check(dashboardEditor.removePage(id) && dashboardEditor.session?.pages.pages.count == count - 1,
              "Deleting a page takes no confirmation")
        for page in dashboardEditor.session?.pages.pages.dropFirst() ?? [] { _ = dashboardEditor.removePage(page.id) }
        let last = dashboardEditor.session?.pages.pages.first?.id
        check(last.map { !dashboardEditor.removePage($0) } ?? false, "The last page cannot be deleted")
        dashboardEditor.restoreDefaults()
        check(Set(dashboardEditor.session?.pages.pages.compactMap(\.template) ?? []).count == PageTemplate.allCases.count,
              "Restoring the default pages brings all four back")
        editor.cancel()
        await wait(0.6)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Esc from the inside out: selection, renaming, gallery, confirmation,
    /// and only then cancel.
    private func escapeOrder(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.5)
        let page = dashboardEditor.page
        dashboardEditor.selectedWidgetID = page?.widgets.first?.id
        dashboardEditor.optionsWidgetID = page?.widgets.first?.id
        editor.galleryVisible = true
        editor.debugEscape()
        check(dashboardEditor.selectedWidgetID == nil && dashboardEditor.optionsWidgetID == nil && editor.galleryVisible,
              "Esc 1: only the selection and the options close, the gallery stays")
        dashboardEditor.renamingPageID = page?.id
        editor.debugEscape()
        check(dashboardEditor.renamingPageID == nil && editor.galleryVisible, "Esc 2: renaming closes, the gallery stays")
        editor.debugEscape()
        check(!editor.galleryVisible && editor.isEditing, "Esc 3: the gallery closes, the mode stays")
        dashboardEditor.addPage()
        let plainToolbar = windows.debugToolbarFrame
        editor.debugEscape()
        check(editor.pendingCancelConfirmation && editor.isEditing, "Esc 4 with changes: the confirmation instead of the cancel")
        await wait(0.4)
        let confirmToolbar = windows.debugToolbarFrame
        note("Toolbar plain \(r(plainToolbar)), with the confirmation \(r(confirmToolbar))")
        check(confirmToolbar != nil && confirmToolbar?.size != plainToolbar?.size && (confirmToolbar.map(screen.frame.contains) ?? false),
              "Confirmation: the toolbar resizes and stays on the screen")
        editor.debugEscape()
        check(!editor.pendingCancelConfirmation && editor.isEditing, "Esc 5: the confirmation closes, editing goes on")
        await wait(0.4)
        check(windows.debugToolbarFrame?.width == plainToolbar?.width, "The toolbar shrinks back afterwards")
        editor.debugEscape()
        await wait(0.4)
        // “Discard” is the right button of the confirmation.
        if let toolbar = windows.debugToolbarFrame, editor.pendingCancelConfirmation {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: toolbar.width - 18 - 35, y: toolbar.height / 2))
            await wait(0.3)
        }
        check(!editor.isEditing, "A click on Discard ends the mode")
        if editor.isEditing { editor.confirmCancel() }
        await wait(0.8)
        editor.begin(screen: screen)
        await wait(0.3)
        editor.debugEscape()
        check(!editor.isEditing, "Esc without changes cancels right away")
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Control centre: tap Wi-Fi (selects, no popover), minus on Wi-Fi and on
    /// a card, then tap the link button (options). Frames always fresh: when
    /// the panel grows (a new row), window coordinates that were reported
    /// earlier go stale.
    private func controlCentre(on screen: NSScreen) async {
        editor.begin(screen: screen)
        await wait(0.8)
        guard let wifi = editor.utilities?.layout.toggles.first(where: { $0.kind == .wifi }),
              let wifiRect = editor.debugUtilitiesRects[wifi.id] else {
            check(false, "The Wi-Fi tile in the control centre is found")
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
        // Minus of a button: centre 1 point right, 3 below the top left corner.
        utilities.debugClick(fromTop: CGPoint(x: wifiRect.minX + 1, y: wifiRect.minY + 3))
        await wait(0.5)
        check(!(editor.utilities?.layout.toggles.contains { $0.id == wifi.id } ?? true), "Minus removes the Wi-Fi button")
        await wait(0.3)
        if let card = editor.debugUtilitiesRects["card:keepAwake"] {
            utilities.debugClick(fromTop: CGPoint(x: card.minX + 2, y: card.minY + 2))
            await wait(0.5)
            check(editor.utilities?.layout.isEnabled(.keepAwake) == false, "Minus hides the “Keep Awake” card")
        } else {
            check(false, "The “Keep Awake” card is found")
        }
        editor.cancel()
        await wait(0.8)

        editor.begin(screen: screen)
        await wait(0.6)
        guard let link = editor.addToggle(.openLink) else { check(false, "The link button is inserted"); return }
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
                      "The popover in the control centre lies above the scrim (level \(popover.level.rawValue))")
            }
        } else {
            check(false, "The link tile is found")
        }
        editor.cancel()
        await wait(0.8)
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.5)
    }

    /// Normal use without editing: the buttons of the bar open the matching
    /// page, a second click closes it, performance only measures on the
    /// performance page.
    private func normalUse() async {
        guard let pages = store.settings.dashboardPages else { check(false, "The pages are there"); return }
        for (tab, template) in [(DashboardTab.media, PageTemplate.media), (.performance, .performance), (.weather, .weather), (.dashboard, .overview)] {
            dashboard.show(tab: tab)
            await wait(0.5)
            let expected = pages.pages.first { $0.template == template }?.id
            check(dashboard.debugIsOpen && dashboard.debugShownPage == expected, "Bar button \(tab.rawValue) opens its page")
            check(dashboard.debugShowsPerformance == (template == .performance), "Performance only measures on the performance page (\(tab.rawValue))")
            dashboard.show(tab: tab)
            await wait(0.5)
            check(!dashboard.debugIsOpen, "A second click on \(tab.rawValue) closes it")
        }
        dashboard.toggle()
        await wait(0.5)
        check(dashboard.debugIsOpen, "The dashboard shortcut opens it")
        dashboard.toggle()
        await wait(0.5)
        check(!dashboard.debugIsOpen, "The dashboard shortcut closes it")
    }

    private func scenario() async {
        await normalUse()
        await probeScaledDrag()
        await sidebar()
        for screen in NSScreen.screens {
            note("Screen \(r(screen.frame)), visible \(r(screen.visibleFrame))")
        }
        for screen in NSScreen.screens {
            await pass(on: screen)
        }
        // Size slider of the toolbar: the dashboard follows live, cancel puts
        // it back, done saves it.
        if let screen = NSScreen.screens.first {
            editor.begin(screen: screen)
            await wait(0.8)
            let before = dashboard.openFrame
            dashboardEditor.scale = 0.8
            await wait(0.4)
            let smaller = dashboard.openFrame
            check((smaller?.width ?? 0) < (before?.width ?? 0), "Slider 80 %: the dashboard shrinks right away (\(r(before)) -> \(r(smaller)))")
            if let gallery = windows.debugGalleryFrame ?? nil, let smaller { check(!gallery.intersects(smaller), "The gallery moves along") }
            check(editor.hasChanges, "The slider counts as a change")
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
        // Stress: ten quick begins and ends in a row, with changing gaps.
        if let screen = NSScreen.screens.first {
            for round in 0..<10 {
                editor.begin(screen: screen)
                await wait([0.02, 0.1, 0.3, 0.05, 0.6][round % 5])
                if round % 2 == 0 { editor.cancel() } else { editor.done() }
                await wait([0.03, 0.2, 0.01, 0.4, 0.08][round % 5])
            }
            await wait(0.9)
            check(!editor.isEditing && windows.debugVisibleScrims == 0 && windows.debugToolbarFrame == nil
                  && windows.debugGalleryFrame == nil, "Stress: nothing is left hanging after ten quick rounds")
            dashboard.debugClose()
            utilities.debugClose()
            await wait(0.6)
            // The dashboard is open already, then editing: it stays open,
            // pinned; after the end it is back to normal.
            dashboard.toggle()
            await wait(0.5)
            editor.begin(screen: screen)
            await wait(0.6)
            check(dashboard.debugIsOpen && windows.debugToolbarFrame != nil, "Editing with the dashboard already open")
            dashboard.toggle()
            await wait(0.4)
            check(dashboard.debugIsOpen, "Pinned: the dashboard shortcut does not close it while editing")
            editor.cancel()
            await wait(0.6)
            dashboard.debugClose()
            utilities.debugClose()
            await wait(0.5)
        }
        // Edge case: the slider at 150 % - the dashboard fills nearly the height.
        if let screen = NSScreen.screens.first {
            store.settings.dashboardScale = 1.5
            editor.begin(screen: screen)
            await wait(0.8)
            editor.galleryVisible = true
            await wait(0.8)
            let dashboardFrame = dashboard.openFrame
            let gallery = windows.debugGalleryFrame
            let toolbar = windows.debugToolbarFrame
            note("150 %: dashboard \(r(dashboardFrame)), gallery \(r(gallery)), toolbar \(r(toolbar))")
            check(gallery.map(screen.frame.contains) ?? false, "150 %: the gallery stays fully on the screen")
            check(toolbar.map(screen.frame.contains) ?? false, "150 %: the toolbar stays fully on the screen")
            if let gallery, let toolbar { check(!gallery.intersects(toolbar), "150 %: the gallery keeps clear of the toolbar") }
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

    /// The sidebar in the mode (bar plan, task 3): selecting, adding out of
    /// the gallery, a kind that may exist only once, reordering, removing -
    /// and what Cancel and Done do with all of it. The blocks themselves
    /// are drawn in the bar window, which this test does not build; what is
    /// checked here is the working copy behind them.
    private func sidebar() async {
        guard let screen = NSScreen.screens.first else { return }
        let before = store.settings.bar.layout.entries.map(\.kind)
        editor.begin(screen: screen)
        await wait(0.6)
        guard let session = editor.bar else {
            check(false, "The mode opens a working copy of the bar")
            editor.cancel()
            return
        }
        check(session.layout.entries.map(\.kind) == before, "The working copy starts as the bar stands")
        // The bar is edited where it stands, so it has to be visible: above
        // the scrim, below toolbar and gallery (the screenshot of 20.09.
        // showed it swallowed by the scrim).
        let scrim = windows.debugLevels.scrim
        let barLevel = sidebar.debugLevels.first ?? 0
        check(barLevel > scrim, "The bar stands above the scrim while editing (bar \(barLevel), scrim \(scrim))")
        // A bar is handed the editor when it is built, and shows no edit
        // surface at all without one - on 20.09. the manager was given it
        // only after its bars stood, and the blocks stayed calm while the
        // rest of the shell was being edited.
        check(sidebar.debugBarsKnowEditor, "Every bar that stands knows the edit mode")
        check(barLevel < windows.debugLevels.controls, "Toolbar and gallery stay above the bar")

        let clock = session.layout.entries.first { $0.kind == .clock }?.id
        dashboardEditor.selectedWidgetID = dashboardEditor.page?.widgets.first?.id
        editor.selectedToggleID = editor.utilities?.layout.toggles.first?.id
        editor.selectedBarEntryID = clock
        check(editor.selectedBarEntryID == clock, "A click on a block selects it")
        // One selection in the whole shell: otherwise a widget, a tile and
        // a block stand selected at once, with three options popovers open.
        check(dashboardEditor.selectedWidgetID == nil && editor.selectedToggleID == nil,
              "Selecting a block lets the other two surfaces go")
        dashboardEditor.selectedWidgetID = dashboardEditor.page?.widgets.first?.id
        check(editor.selectedBarEntryID == nil, "Selecting a widget lets the block go")
        editor.selectedBarEntryID = clock

        let addedID = editor.addBarModule(.battery)
        check(addedID != nil, "The gallery adds a block")
        check(editor.selectedBarEntryID == addedID, "A new block is selected right away")
        check(editor.bar?.layout.entries.contains { $0.kind == .battery } == true, "The battery stands in the working copy")
        check(editor.addBarModule(.dock) == nil, "A second Dock is refused")

        if let addedID, let first = editor.bar?.layout.entries.first?.id {
            editor.moveBarModule(addedID, onto: first)
            check(editor.bar?.layout.entries.first?.id == addedID, "Dragging a block to the top moves it there")
        }
        check(editor.hasChanges, "The bar counts as a change of the mode")
        check(store.settings.bar.layout.entries.map(\.kind) == before, "Nothing is written while editing")

        editor.cancel()
        await wait(0.5)
        check(store.settings.bar.layout.entries.map(\.kind) == before, "Cancel leaves the bar as it was")
        let afterCancel = sidebar.debugLevels.first ?? 0
        check(afterCancel == Int(NSWindow.Level.floating.rawValue),
              "After the cancel the bar is back at its own level (\(afterCancel))")
        check(editor.bar == nil, "The working copy is gone after the cancel")

        // The same once more, this time kept.
        editor.begin(screen: screen)
        await wait(0.6)
        let removable = editor.bar?.layout.entries.first { $0.kind == .clock }?.id
        if let removable {
            editor.selectedBarEntryID = removable
            editor.removeBarModule(removable)
            check(editor.selectedBarEntryID == nil, "Minus on the selected block clears the selection")
        }
        editor.addBarModule(.cpu)
        editor.done()
        await wait(0.6)
        let after = store.settings.bar.layout.entries.map(\.kind)
        check(!after.contains(.clock), "Done keeps the removal")
        check(after.contains(.cpu), "Done keeps the new block")
        check(editor.bar == nil, "The working copy is gone after Done")
        note("bar after Done: \(after.map(\.rawValue).joined(separator: ", "))")
        dashboard.debugClose(); utilities.debugClose()
        await wait(0.4)
    }

    /// One whole pass on one screen.
    private func pass(on screen: NSScreen) async {
        note("--- pass on \(r(screen.frame))")
        let before = store.settings
        editor.begin(screen: screen)
        await wait(0.9)
        check(editor.isEditing, "The mode runs after the begin")
        let dashboardFrame = dashboard.openFrame
        let utilitiesFrame = utilities.openFrame
        check(dashboardFrame.map(screen.frame.intersects) ?? false, "The dashboard is open on this screen \(r(dashboardFrame))")
        check(utilitiesFrame.map(screen.frame.intersects) ?? false, "The control centre is open on this screen \(r(utilitiesFrame))")
        check(windows.debugVisibleScrims == NSScreen.screens.count,
              "Scrim on all \(NSScreen.screens.count) screens (\(windows.debugVisibleScrims))")
        let toolbar = windows.debugToolbarFrame
        check(toolbar.map(screen.frame.contains) ?? false, "The toolbar is fully on the screen \(r(toolbar))")
        if let toolbar, let utilitiesFrame {
            check(!toolbar.intersects(utilitiesFrame), "The toolbar keeps clear of the control centre")
        }
        if let toolbar, let dashboardFrame {
            check(!toolbar.intersects(dashboardFrame), "The toolbar keeps clear of the dashboard")
        }
        // Does the content of the control centre fit the panel while editing?
        if let layout = editor.utilities?.layout {
            let content = NSHostingView(rootView: EditableUtilitiesView(editor: editor, layout: layout).shellTheme(nil))
            let needed = content.fittingSize.height
            check(needed <= utilities.height + 1,
                  "The control centre fits the panel while editing (content \(Int(needed)), panel \(Int(utilities.height)))")
        }
        let levels = windows.debugLevels
        let drawerLevels = [dashboard.debugLevel, utilities.debugLevel].compactMap { $0 }
        check(drawerLevels.allSatisfy { $0 > levels.scrim && $0 < levels.controls },
              "Levels: scrim \(levels.scrim) < edge windows \(drawerLevels) < toolbar/gallery \(levels.controls)")
        check(levels.scrim > NSWindow.Level.mainMenu.rawValue, "The scrim lies above the menu bar and the Dock")
        check(windows.debugPanelLevels.allSatisfy { $0 == levels.scrim || $0 == levels.controls },
              "The panels really sit at their level \(windows.debugPanelLevels)")

        // Click on the “+” of the toolbar (18 margin + half the button width 17,
        // half the height) - if it lands, the gallery opens.
        if let toolbar = windows.debugToolbarFrame {
            // The rim of the circle (12 points beside the centre), not the plus sign.
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: 35 - 12, y: toolbar.height / 2 + 5))
            await wait(0.2)
            check(editor.galleryVisible, "A click on the rim of the + circle lands")
        }
        editor.galleryVisible = true
        await wait(0.9)
        let gallery = windows.debugGalleryFrame
        check(gallery.map(screen.frame.contains) ?? false, "The gallery is fully on the screen \(r(gallery))")
        if let gallery, let dashboardFrame { check(!gallery.intersects(dashboardFrame), "The gallery keeps clear of the dashboard") }
        if let gallery, let utilitiesFrame { check(!gallery.intersects(utilitiesFrame), "The gallery keeps clear of the control centre") }
        if let gallery, let toolbar = windows.debugToolbarFrame { check(!gallery.intersects(toolbar), "The gallery keeps clear of the toolbar") }

        // Full page (overview): a click on the clock in the gallery -> a note,
        // the gallery grows but keeps clear of the dashboard.
        if let gallery = windows.debugGalleryFrame, dashboardEditor.page?.template == .overview {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let before = dashboardEditor.page?.widgets.count ?? 0
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column * 2.5 + 20, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.4)
            check(editor.galleryNotice != nil && dashboardEditor.page?.widgets.count == before,
                  "Full page: a click in the gallery shows “No room” instead of inserting")
            if let grown = windows.debugGalleryFrame, let dashboardFrame {
                check(!grown.intersects(dashboardFrame), "The gallery with the note keeps clear of the dashboard \(r(grown))")
            }
        }
        // Tabs by click: the tab row (16 margin, 36 high) holds three equal
        // capsules since the sidebar joined - so the far right is the
        // sidebar, and the middle third the control centre.
        if let gallery = windows.debugGalleryFrame {
            let row = gallery.width - 32
            let dashboardTabHeight = gallery.height
            // Far out in the tab, not on the text: the whole capsule counts.
            windows.debugClickGallery(fromTopLeft: NSPoint(x: gallery.width - 16 - 20, y: 16 + 18))
            await wait(0.4)
            check(editor.galleryTab == .bar, "A click far out in the “Sidebar” tab (not on the text) switches")
            // Every tab brings its own number of tiles, so the panel has to
            // measure itself again - otherwise it keeps the height of the
            // tab it was opened on and cuts the last row off (20.09.).
            if let onBar = windows.debugGalleryFrame {
                note("Gallery dashboard \(Int(dashboardTabHeight)) high, sidebar \(Int(onBar.height))")
                check(onBar.height != dashboardTabHeight, "The gallery measures itself again on a tab switch")
                check(NSScreen.screens.first.map { $0.visibleFrame.contains(onBar) } ?? false,
                      "The sidebar tab stays fully on the screen \(r(onBar))")
            }
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + row * 2 / 3 - 8, y: 16 + 18))
            await wait(0.4)
            check(editor.galleryTab == .controlCentre, "A click at the edge of the middle tab switches to the control centre")
            // “Show all (advanced)” only hides something on the dashboard
            // tab, and stands only there - so back to it first.
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 20, y: 16 + 18))
            await wait(0.4)
            check(editor.galleryTab == .dashboard, "A click on the left tab goes back to the dashboard")
            // The checkbox below the tab row, at the left margin.
            let before = editor.showsAllInGallery
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 60, y: 16 + 36 + 12 + 10))
            await wait(0.4)
            check(editor.showsAllInGallery != before, "A click on “Show all” toggles it")
            if let wide = windows.debugGalleryFrame {
                check(NSScreen.screens.first.map { $0.visibleFrame.contains(wide) } ?? false,
                      "With “Show all” the gallery stays fully on the screen \(r(wide))")
            }
            editor.showsAllInGallery = before
            await wait(0.3)
        }
        // Click into the scrim: the selection goes in both panels.
        dashboardEditor.selectedWidgetID = dashboardEditor.page?.widgets.first?.id
        editor.selectedToggleID = editor.utilities?.layout.toggles.first?.id
        editor.selectedBarEntryID = editor.bar?.layout.entries.first?.id
        windows.debugClickScrim()
        await wait(0.3)
        check(dashboardEditor.selectedWidgetID == nil && editor.selectedToggleID == nil
              && editor.selectedBarEntryID == nil, "A click into the scrim clears every selection")
        // Control centre tab: a click on “Display Off” (14th tile, second
        // row, sixth column) adds the button.
        editor.galleryTab = .controlCentre
        await wait(0.4)
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            let tileHeight: CGFloat = 73
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 5 * (column + 10) + column / 2,
                                                           y: 16 + 36 + 12 + 20 + 12 + tileHeight + 10 + tileHeight / 2))
            await wait(0.4)
            check(editor.utilities?.layout.toggles.contains { $0.kind == .displaySleep } ?? false,
                  "Gallery control centre: the click adds “Display Off”")
            // Wi-Fi (4th tile, first row) is there already and grey: a click does nothing.
            let wifiCount = editor.utilities?.layout.toggles.filter { $0.kind == .wifi }.count ?? 0
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + 3 * (column + 10) + column / 2,
                                                           y: 16 + 36 + 12 + 20 + 12 + tileHeight / 2))
            await wait(0.3)
            check(editor.utilities?.layout.toggles.filter { $0.kind == .wifi }.count == wifiCount,
                  "A grey tile (Wi-Fi is there already) inserts nothing")
        }
        editor.galleryTab = .dashboard
        await wait(0.3)

        // Change and done.
        let pageCount = dashboardEditor.session?.pages.pages.count ?? 0
        let newPage = dashboardEditor.addPage()
        // Click on the first gallery tile (weather): 16 margin + half a
        // column, below the tabs (36) and the checkbox (≈20) with 12 point gaps.
        if let gallery = windows.debugGalleryFrame {
            let column = (gallery.width - 32 - 7 * 10) / 8
            windows.debugClickGallery(fromTopLeft: NSPoint(x: 16 + column / 2, y: 16 + 36 + 12 + 20 + 12 + 30))
            await wait(0.2)
            check(dashboardEditor.page?.widgets.contains { $0.kind == .weather } ?? false,
                  "A click on a gallery tile inserts the widget")
        }
        let clock = dashboardEditor.addAtFirstFreeSpot(.clock)
        check(clock != nil, "The clock is inserted on the new page")
        // Dragging at a scale ≠ 1: the clock 100 reference points to the right.
        await wait(0.3)
        if let clock, let before = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame,
           let page = dashboardEditor.debugPageRectInHost {
            let scale = dashboard.debugScale
            let start = CGPoint(x: page.minX + (before.x + before.width / 2) * scale,
                                y: page.minY + (before.y + before.height / 2) * scale)
            note("Page in the host \(r(page)), start \(Int(start.x)),\(Int(start.y)), scale \(scale)")
            dashboardEditor.selectedWidgetID = nil
            dashboard.debugDrag(from: start, to: CGPoint(x: start.x + 100 * scale, y: start.y))
            await wait(0.4)
            note("selected after the drag: \(dashboardEditor.selectedWidgetID == clock ? "the clock" : String(describing: dashboardEditor.selectedWidgetID))")
            let after = dashboardEditor.page?.widgets.first(where: { $0.id == clock })?.frame
            check(after.map { abs($0.x - (before.x + 100)) <= 1 && $0.y == before.y } ?? false,
                  "Dragging at scale \(String(format: "%.3f", scale)): 100 points come out as 100 (before x \(Int(before.x)), after \(after.map { String(Int($0.x)) } ?? "-"))")
            await widgetHandles(clock)
        } else {
            check(false, "Drag: the page or the clock is not found")
        }
        let toggle = editor.addToggle(.openLink)
        check(toggle != nil, "The “Open Link” button is inserted in the control centre")
        // “Done” by click: the right button of the toolbar.
        if let toolbar = windows.debugToolbarFrame {
            windows.debugClickToolbar(fromTopLeft: NSPoint(x: toolbar.width - 18 - 25, y: toolbar.height / 2))
            await wait(0.2)
        }
        if editor.isEditing {
            check(false, "The click on Done lands")
            editor.done()
        } else {
            check(true, "The click on Done lands")
        }
        await wait(0.1)
        check(!editor.isEditing, "The mode ends with Done")
        check(store.settings.dashboardPages?.pages.count == pageCount + 1, "Done saves the new page")
        check(store.settings.utilities.layout.toggles.contains { $0.kind == .openLink }, "Done saves the new button")
        check(dashboard.debugShownPage == newPage, "After Done the dashboard stays on the page that was edited")
        await wait(0.9)
        check(windows.debugVisibleScrims == 0, "The scrim is gone after Done")
        check(windows.debugToolbarFrame == nil, "The toolbar is gone after Done")
        check(windows.debugGalleryFrame == nil, "The gallery is gone after Done")

        // Quick restart: an end and a new begin right after each other.
        editor.begin(screen: screen)
        await wait(0.05)
        editor.cancel()
        await wait(0.05)
        editor.begin(screen: screen)
        await wait(0.9)
        check(windows.debugVisibleScrims == NSScreen.screens.count, "The scrim is there after a quick restart")
        check(windows.debugToolbarFrame != nil, "The toolbar is there after a quick restart")
        check(dashboard.openFrame != nil && utilities.openFrame != nil, "The panels are open after a quick restart")

        // Cancel discards.
        let saved = store.settings
        dashboardEditor.addPage()
        _ = editor.addToggle(.openApp)
        editor.cancel()
        await wait(0.9)
        check(store.settings == saved, "Cancel discards both working copies")
        check(windows.debugVisibleScrims == 0 && windows.debugToolbarFrame == nil, "The windows of the mode are gone after the cancel")
        note("Dashboard after the end \(r(dashboard.openFrame)), control centre \(r(utilities.openFrame)) (closed, unless the pointer sits there)")
        store.settings = before
        dashboard.debugClose()
        utilities.debugClose()
        await wait(0.6)
    }
}

/// Self-test: reports its own frame in window coordinates (AppKit, bottom
/// left) - more exact than SwiftUI coordinate spaces when the hosting window
/// is cut differently from its content.
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
            // The distance to the top edge instead of the bottom one: when the
            // window grows upwards (the control centre gets a row), the content
            // stays at the top without `layout()` coming again.
            let rect = convert(bounds, to: nil)
            let height = window?.frame.height ?? 0
            report(NSRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height))
        }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
#endif

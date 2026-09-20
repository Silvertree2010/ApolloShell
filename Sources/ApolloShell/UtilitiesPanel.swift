import AppKit
import ApolloShellCore
import Observation
import SwiftUI

/// Utilities panel at the bottom right (Caelestia: modules/utilities in the
/// bottom right corner). Opens with SUPER+U, through the symbol in the bar
/// and, as in Caelestia, when the mouse hits the edge at the bottom right -
/// only not right in the corner, which macOS takes as a hot corner for the
/// quick note out of the box (`EdgeHoverArea.cornerGap`).
///
/// Cards and quick toggles come out of Nexus > Quick Actions
/// (settings.utilities.layout). Every change takes hold right away: the panel
/// draws the new arrangement and takes the height `UtilitiesLayout.panelHeight`
/// works out for it.
@MainActor
final class UtilitiesPanel {
    private let settings: ShellSettingsStore
    private let model: UtilitiesModel
    private let state: UtilitiesLayoutState
    private let drawer: EdgeDrawer<UtilitiesPanelView>
    private var observation: Task<Void, Never>?
    private var editingObservation: Task<Void, Never>?
    private var lidObservation: Task<Void, Never>?
    /// Open or closed - the toasts then move up out of the way
    /// (Caelestia hangs them on `utilities.top`).
    var onVisibilityChange: (_ open: Bool) -> Void = { _ in }
    /// The new height after a change in Nexus - for the toasts that sit above
    /// the panel.
    var onHeightChange: (_ height: CGFloat) -> Void = { _ in }
    /// Settings button: open Nexus.
    var onOpenSettings: () -> Void = {}
    /// Show a toast (the color picker: "Color Copied"). LauncherApp sets it as
    /// soon as the toaster exists - that comes about after the panel, because
    /// its window needs the panel height.
    var onToast: (ToastText.Content) -> Void = { _ in }

    /// The visible height of the panel.
    var height: CGFloat { drawer.size.height }
    /// The frame of the open panel (edit mode: the toolbar and the gallery get
    /// out of its way when they would cover it otherwise).
    var openFrame: NSRect? { drawer.openFrame }
    #if DEBUG
    var debugLevel: Int? { drawer.debugLevel }
    func debugClose() { drawer.close() }
    /// `point` measured from the top edge of the window.
    func debugClick(fromTop point: CGPoint) {
        let height = drawer.debugWindowHeight
        drawer.debugClick(atWindowPoint: NSPoint(x: point.x, y: height - point.y))
    }
    var debugFrames: String { drawer.debugFrames }
    var debugWindowHeight: CGFloat { drawer.debugWindowHeight }
    func debugRelayout() { drawer.debugRelayout() }
    #endif

    /// `model`: for image samples a preview model that reads nothing and
    /// switches nothing; otherwise the real one. `editor`: the global edit
    /// mode (task 5) - the panel pins itself while an editing session runs and
    /// shows the working copy instead of the saved arrangement.
    /// Anordnung.
    init(settings: ShellSettingsStore, editor: ShellEditor, model injected: UtilitiesModel? = nil) {
        self.settings = settings
        model = injected ?? UtilitiesModel(lidAllowed: { settings.settings.keepAwake.lidClosed })
        let layout = settings.settings.utilities.layout
        state = UtilitiesLayoutState(layout: layout)
        let view = UtilitiesPanelView(model: model, state: state, editor: editor)
        // The height is worked out, not measured: every card has a fixed
        // height (UtilitiesMetrics) and the view sticks to it. No state (a
        // long device name, Keep Awake on) changes it.
        drawer = EdgeDrawer(edge: .bottomRight, size: Self.size(for: layout), cornerRadius: 25, rootView: view)
        drawer.opensOnHover = true
        drawer.onOpen = { [weak self] in
            self?.model.start()
            self?.onVisibilityChange(true)
        }
        drawer.onClose = { [weak self] in
            self?.model.stop()
            self?.onVisibilityChange(false)
        }
        // Close the panel on purpose, then open Nexus. Do not wait for it to
        // close itself on the focus change: that hangs on the order in which
        // macOS switches the windows.
        model.onOpenSettings = { [weak self] in
            self?.drawer.close()
            self?.onOpenSettings()
        }
        // Actions that need the screen or the keyboard (screenshot, desktop,
        // color picker, lock, apps, links): only once the panel is fully
        // gone.
        model.closePanel = { [weak self] then in
            self?.drawer.close(then: then)
        }
        model.onToast = { [weak self] content in
            self?.onToast(content)
        }
        // Delivers the current value first (the same, so nothing to do), then
        // every change out of Nexus. Lives as long as the app.
        observation = Task { [weak self, settings] in
            for await layout in Observations({ settings.settings.utilities.layout }) {
                self?.apply(layout)
            }
        }
        // "With the lid closed too" in Nexus: takes hold right away, in
        // the middle of "Keep Awake" too. The first value comes on the start.
        lidObservation = Task { [weak self, settings] in
            for await _ in Observations({ settings.settings.keepAwake.lidClosed }) {
                self?.model.lidSettingChanged()
            }
        }
        // While an editing session runs (task 5): every change to the working
        // copy (a card off/on, a button added/removed/moved) fits the window
        // size right away, exactly as above for the saved arrangement. `nil`
        // (the editing ends) is caught synchronously by `addEndHandler` below
        // - there `store.settings` already stands on the end result (see
        // `ShellEditor.done()`), here it would not yet on the first frame
        // after "Done".
        editingObservation = Task { [weak self, editor] in
            for await layout in Observations({ editor.utilities?.layout }) {
                guard let layout else { continue }
                self?.apply(layout)
            }
        }
        // The editing begins: pin the window, switch to the working copy
        // (already in `editor.utilities`, `begin` calls the listeners only
        // afterwards), open it if needed - like `Dashboard.editor.onBegin`.
        editor.addBeginHandler { [weak self, editor] screen in
            guard let self, let layout = editor.utilities?.layout else { return }
            let alreadyOpen = drawer.isOpen
            drawer.isPinned = true
            apply(layout)
            if !alreadyOpen { drawer.open(on: screen) }
        }
        // The editing ends ("Done" or "Cancel"): unpin, straight back to the
        // (now current) saved arrangement - do not wait for the async
        // observation above, which reacts only one turn later and would leave
        // the window standing at the wrong size for a moment.
        editor.addEndHandler { [weak self] in
            guard let self else { return }
            drawer.isPinned = false
            apply(settings.settings.utilities.layout)
        }
    }

    static func size(for layout: UtilitiesLayout) -> NSSize {
        NSSize(width: UtilitiesView.width, height: CGFloat(layout.panelHeight))
    }

    /// Content and frame in the same pass: SwiftUI draws the new arrangement
    /// in the next frame, and by then the window already has the right size -
    /// so nothing jumps halfway while it is open. Checks the window size apart
    /// from the content comparison: while an editing session runs, `drawer.size`
    /// can be bigger than `state.layout` although both stayed the same (see
    /// `editingObservation`/`addEndHandler`).
    private func apply(_ layout: UtilitiesLayout) {
        if layout != state.layout { state.layout = layout }
        let size = Self.size(for: layout)
        guard size != drawer.size else { return }
        drawer.resize(to: size)
        onHeightChange(size.height)
    }

    func toggle() {
        drawer.toggle()
    }

    /// When the app ends: let go of Keep Awake (with the lid closed too) cleanly.
    func shutdown() {
        model.shutdown()
    }

    /// From `FullscreenMonitor`: these screens are in full screen, and the
    /// mouse opens nothing at the bottom right there. At the edges of the
    /// other screens opening by mouse stays.
    func setFullscreen(_ screens: Set<CGDirectDisplayID>) {
        drawer.suspendedScreens = screens
    }
}

/// The arrangement the panel shows right now. A copy of its own instead of
/// `ShellSettingsStore` straight away: that way the content and the window
/// frame change in the same call (`UtilitiesPanel.apply`).
@MainActor
@Observable
final class UtilitiesLayoutState {
    var layout: UtilitiesLayout

    init(layout: UtilitiesLayout) {
        self.layout = layout
    }
}

/// The root in the edge window: the quiet view with the saved arrangement,
/// and while an editing session runs (task 5) the working copy in the editing
/// area (`EditableUtilitiesView`).
struct UtilitiesPanelView: View {
    /// The coordinate space of the editing area - only for the self-test.
    static let rootSpace = "utilitiesRoot"
    let model: UtilitiesModel
    let state: UtilitiesLayoutState
    @Bindable var editor: ShellEditor

    var body: some View {
        if let layout = editor.utilities?.layout {
            EditableUtilitiesView(editor: editor, layout: layout)
                .coordinateSpace(name: Self.rootSpace)
        } else {
            UtilitiesView(model: model, layout: state.layout)
        }
    }
}

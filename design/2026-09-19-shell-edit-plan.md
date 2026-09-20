# Global edit mode (dashboard + control centre) — Implementation Plan

> **For agentic workers:** Execute task by task. Steps use checkbox (`- [ ]`) syntax.

> **Done (20.09.2026).** Everything in this plan is in `release/0.2`; the
> boxes below were not ticked off as the work went in. What the shell
> does today is `CHANGELOG.md` and the spec
> (`design/2026-09-18-bento-dashboard.md`), not the state of these
> checkboxes.

**Goal:** Replace "edit the dashboard with Nexus beside it" by one edit mode for the whole shell, as the spec's revised section 4 describes: button in Nexus → Nexus hides, scrim over all screens, dashboard and control centre pinned open, floating toolbar (+ / Abbrechen / Fertig), floating gallery with a tab per surface, options in popovers, page management in the dashboard's page bar, control centre editable in its panel. Robust next to window managers.

**Spec:** `design/2026-09-18-bento-dashboard.md`, sections 4 (revised) and 5. Read it first.

**What exists (read before starting):**
- Core: `BentoEditSession` (dashboard working copy, previews, commit/add/remove/options), `BentoGeometry`, `DashboardPages` (page ops), `UtilitiesLayout` (cards enable/order, toggles add/remove/update/`moveToggle(_:onto:)`, `panelHeight`).
- App: `DashboardEditor` (wraps `BentoEditSession`, begin/done/cancel, drop state), `BentoEditOverlay` + `BentoPageView` (wobble, `−`, handle, drag, drop target), `EdgeDrawer` (`isPinned`, `open(on:)`, `unpin()`, `DrawerScrim`, levels ~line 638), `Dashboard`, `UtilitiesPanel` + `UtilitiesView` + `UtilitiesToggleItem`, Nexus editors to be retired: `NexusDashboardPage/Pages/Widgets`, `NexusWidgetOptions` (keep its option controls, they move into popovers), `UtilitiesEditor*` (keep `UtilitiesEditorOptions`/`UtilitiesEditorPickers` controls for popovers, retire the page/grid/gallery/presets), `GlobalHotKey` (register/unregister), `HotKeyCenter`.

## Global Constraints

- Repo `~/projects/private/apolloshell-0.2`, branch `release/0.2`. Never push, never `./build.sh`, never start the app normally, never touch `~/Applications` or `~/Library/Application Support/ApolloShell`. Visual checks only via render mode into `/private/tmp/claude-501/-Users-andrin/682a6faf-d551-4585-9c5b-045f6c3eb083/scratchpad/renders/`.
- Non-edit dashboard renders must keep today's comparison against `renders/baseline` (6 `gleich`, dashboard-* 555/565 px).
- Build `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build --product ApolloShell`; tests `./test.sh --filter <Suite>`; full `./test.sh` once at the end.
- Comments and UI strings in English; there is no strings file to keep up any more.
- Commit per task, one English imperative line, no Co-Authored-By, only `git add` your files.
- Reuse existing motion curves and `ShellStyle`; respect Reduce Motion (dashed outline instead of wobble).

---

### Task 1: Core — page ops in the session, first free spot, control-centre session (TDD)

- [ ] `BentoEditSession`: add `addPage(name:symbol:) -> DashboardPage.ID` (switches to it), `duplicatePage(_:name:)`, `removePage(_:) -> Bool` (never the last; switching away if it was shown), `renamePage(_:to:)`, `setSymbol(_:forPage:)`, `movePages(fromOffsets:toOffset:)` — all delegating to `DashboardPages`.
- [ ] `BentoGeometry.firstFreeFrame(kind:others:) -> WidgetFrame?`: the smallest size of the kind at the first valid position scanning rows top→bottom, left→right in steps of the spacing grid (candidates: x/y = 0 and every other widget's `maxX + spacing` / `maxY + spacing`), `nil` if none fits. `BentoEditSession.addAtFirstFreeSpot(_ kind:places:) -> WidgetInstance.ID?`.
- [ ] New `UtilitiesEditSession` (Core, `Equatable, Sendable`): `original`, `layout` (a `UtilitiesLayout`), `selectedToggleID: String?`, `hasChanges`, pass-throughs for `setCard(_:enabled:)`, `moveCards`, `add(_ kind:)` (selects the new toggle), `remove(toggle:)`, `update(toggle:to:)`, `moveToggle(_:onto:)`.
- [ ] Tests for each (new suites `BentoEditSessionPageTests`, `BentoFirstFreeTests`, `UtilitiesEditSessionTests`): e.g. first free spot on the Caelestia overview for a clock is `nil` (page full) and on an empty page is `(0,0,110,130)`; on a page with one clock at (0,0) it is `(122,0,110,130)`; removing the last page fails; adding a page switches to it; removing the shown page shows its neighbour; utilities `add` of a unique kind twice returns `nil` the second time and `hasChanges` flips.
- [ ] Commit "Add page management and first free spot to editing sessions".

### Task 2: `ShellEditor` — one edit mode object

**Files:** new `Sources/ApolloShell/ShellEditor.swift`; `DashboardEditor.swift` becomes the dashboard half of it (keep the type if simpler, owned by `ShellEditor`); `LauncherApp.swift` wiring.

- [ ] `@MainActor @Observable final class ShellEditor`: `isEditing`, `dashboard: DashboardEditor` (existing), `utilities: UtilitiesEditSession?`, `galleryVisible`, `galleryTab: WidgetSurface`, `showsAllInGallery`, `begin(screen: NSScreen)`, `done()`, `cancel(confirmIfChanged: Bool)`, `hasChanges`. `done()` writes `settings.dashboardPages` and `settings.utilities.layout` (only what changed) in one assignment of `store.settings`. `cancel` drops both.
- [ ] Callbacks for the owners: `onBegin(screen)`, `onEnd` (Dashboard, UtilitiesPanel, the new windows, Nexus).
- [ ] Nexus: one button “Edit Interface” visible on every Nexus page (sidebar footer or window toolbar — pick what fits NexusView's layout), calls `begin(screen: window.screen)`, then Nexus orders out; on `onEnd` Nexus comes back (makeKeyAndOrderFront) on the same page.
- [ ] Build, commit "Add one edit mode object for the whole shell".

### Task 3: Windows of the mode: scrim, toolbar, gallery

**Files:** new `Sources/ApolloShell/EditModeWindows.swift` (or `EditScrim.swift`, `EditToolbar.swift`, `EditGallery.swift`).

- [ ] One helper that builds a mode panel: `NSPanel(styleMask: [.borderless, .nonactivatingPanel])`, `isFloatingPanel = true`, `hidesOnDeactivate = false`, `collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]`, `isExcludedFromWindowsMenu = true`, `setAccessibilitySubrole(.unknown)` (non-standard, so AeroSpace/yabai/Amethyst treat it as a popup), `level` chosen relative to the drawers (EdgeDrawer uses `.popUpMenu` / `+1` with scrim): scrim just below the pinned drawers, toolbar and gallery above them. Write the reason for each flag in a comment.
- [ ] Scrim: one panel per `NSScreen`, black at ~0.35 + a light blur (`NSVisualEffectView` `.hudWindow`/`.fullScreenUI` material, or plain dim if blur costs too much), fades in/out with the drawers' curve; clicks on the scrim only clear the selection (never end the mode).
- [ ] Toolbar: bottom centre of the edit screen, capsule glass (`ThemedGlass`/`cardSurface` like the rest), buttons “+” (toggles gallery), “Cancel”, “Done” (default action styling). Stays above the control centre panel, never overlapping it (move up if needed).
- [ ] Gallery: centred on the edit screen, ~560×380 pt, glass, segmented tabs “Dashboard” / “Control Centre”, toggle “Show all (advanced)”. Dashboard tab: every `WidgetKind` with `home == .dashboard` as a tile (symbol, title, sizes count); drag = existing `NSItemProvider` payload `apolloshell.widget:<kind>`; click = `addAtFirstFreeSpot` on the shown page (if `nil`: short shake + “No room on this page”). Control centre tab: the three cards (only those currently disabled are addable) and every toggle kind (unique ones greyed when present); drag payload `apolloshell.toggle:<kind>` / `apolloshell.card:<kind>`; click = add at end / enable card. Esc closes the gallery first, the mode second.
- [ ] Render mode: `--render-edit` additionally renders toolbar and gallery (both tabs) into `<dir>/edit/`. Look at them yourself.
- [ ] Commit "Add scrim, toolbar and gallery for the edit mode".

### Task 4: Dashboard in the global mode

- [ ] `Dashboard`: on `onBegin(screen)` pin and open on that screen (already exists for the old flow), on `onEnd` unpin (existing `unpin()` behaviour).
- [ ] Options popover: clicking a widget selects it and shows a `.popover` anchored at the widget with the options now in `NexusWidgetOptions` (move the controls into a reusable `WidgetOptionsView`; clock time zone list and weather places included). Popover closes on deselect/page switch.
- [ ] Page bar while editing: a `+` at the end (new page “Page <n>”, switches to it), right click on a page: Rename (inline text field in the tab), Symbol (menu of the same ~24 symbols Nexus used), Duplicate, Delete (confirmation; disabled for the last page). Drag to reorder pages is optional — skip if it costs more than a few turns and say so.
- [ ] Remove the old start path (the Nexus page list “Edit”, the Nexus widget list/options while editing).
- [ ] Commit "Edit dashboard pages and widget options in the dashboard".

### Task 5: Control centre in the global mode

**Files:** `UtilitiesPanel.swift`, `UtilitiesView.swift`, `UtilitiesToggleItem.swift`, maybe new `UtilitiesEditOverlay.swift`.

- [ ] `UtilitiesPanel`: on `onBegin(screen)` pin + `open(on:)`, render from `editor.utilities.layout` while editing (height follows `panelHeight` of the working copy via `drawer.resize`), on `onEnd` unpin and go back to the saved layout.
- [ ] While editing: toggles and cards do nothing when clicked (no toggling Wi-Fi etc.), wobble like dashboard widgets, `−` badge each; toggles reorder by dragging within the grid (`moveToggle(_:onto:)`, live, as the Nexus grid did), cards reorder by dragging vertically (`moveCards`); clicking a toggle that has options opens a popover with the controls from `UtilitiesEditorOptions` (app picker, link, shortcut, symbol, hide-apps).
- [ ] Drop target for gallery payloads `apolloshell.toggle:` / `apolloshell.card:`.
- [ ] Render check: control centre in edit mode (one toggle selected) into `<dir>/edit/`.
- [ ] Commit "Edit the control centre in its panel".

### Task 6: Robustness

- [ ] Esc: while editing register a `GlobalHotKey` for Esc (unregister at end) → gallery open? close gallery : cancel(confirmIfChanged: true). The confirmation is a small alert on the toolbar panel (“Discard changes?” Discard / Keep editing).
- [ ] End as cancel (no confirmation) on `NSApplication.didChangeScreenParametersNotification`, `NSWorkspace.willSleepNotification`, `NSWorkspace.sessionDidResignActiveNotification`.
- [ ] While editing ignore the shell hot keys (launcher, dashboard, utilities, power menu, Nexus) and the edge-hover opening of other drawers; the session menu cannot open.
- [ ] Fullscreen app on the edit screen: `open(on:)` must not be blocked by `suspendedScreens`.
- [ ] A small debug helper (DEBUG only, not shipped behaviour) that logs each mode window's level, collection behaviour and accessibility role/subrole when the mode begins — the live test with AeroSpace/yabai reads it.
- [ ] Commit "Keep the edit mode safe next to window managers and system events".

### Task 7: Nexus cleanup, docs, full check

- [ ] Nexus › Dashboard: keep only the size slider and the weather places section. Nexus › Schnellaktionen: keep only settings (lid-closed rule etc.); remove the card list, toggle grid, gallery, options and the control-centre templates (`UtilitiesPreset` UI; keep the core type only if tests still need it, otherwise remove it with its tests). Remove dead Nexus files/types.
- [ ] CHANGELOG `[Unreleased] - 0.2.0`: rewrite the edit-mode bullet for the global mode; add “The control centre is edited in place too”; under Removed add the control-centre templates and the Nexus editors. README/README.de: one sentence each that arranging happens in the edit mode (Nexus › Edit Interface).
- [ ] Full `./test.sh`, `check-l10n`, build, non-edit render compare.
- [ ] Report (max 30 lines): commits, test count, l10n, compare result, what the edit renders show (toolbar, gallery tabs, popover, control centre), decisions the plan left open, and a live-test checklist for Andrin (including AeroSpace/yabai in a VM).

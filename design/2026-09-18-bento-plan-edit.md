# Bento dashboard, part 3: edit mode and Nexus — Implementation Plan

> **For agentic workers:** Execute task by task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** Pages are edited as the spec describes: Nexus starts edit mode, the dashboard stays open, widgets wobble, `−` deletes, a handle resizes, widgets are dragged in from a list in Nexus, the selected widget's options show in Nexus, Done/Cancel. Nexus manages pages (list, +, rename, symbol, duplicate, delete, restore, size slider). The old card editor and the three templates go away.

**Architecture:** One core value type `BentoEditSession` holds the working copy and answers every "where would this land, is it valid" question with `BentoGeometry` (tested). The app wraps it in an `@Observable` `DashboardEditor` shared by Nexus and the dashboard. While a session is active the dashboard draws the session's pages instead of the settings; Done writes them to `settings.dashboardPages`, Cancel drops them.

**Spec:** `design/2026-09-18-bento-dashboard.md` sections 4 and 5. Parts 1-2 are built; read `Sources/ApolloShellCore/{WidgetCatalog,WidgetInstance,BentoGeometry,DashboardPages,DashboardPagesDefaults}.swift` and `Sources/ApolloShell/{Dashboard,DashboardView,BentoPageView,WidgetView,WeatherModels,EdgeDrawer}.swift` first.

## Global Constraints

- Repo `~/projects/private/apolloshell-0.2`, branch `release/0.2`. Never push, never `./build.sh`, never start the app normally, never touch `~/Applications` or `~/Library/Application Support/ApolloShell`. Visual checks only through the render mode (`.build/debug/ApolloShell --render-dashboard <dir>`), renders under `/private/tmp/claude-501/-Users-andrin/682a6faf-d551-4585-9c5b-045f6c3eb083/scratchpad/renders/`.
- The render comparison must stay as it is now for the normal (non-edit) pages: `python3 scripts/compare-renders.py <baseline> <new>` → 6 files `gleich`, the two `dashboard-*` files at 555/565 px (known calendar rounding, see spec "Testing"). Check this after Tasks 3 and 5.
- Build `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build --product ApolloShell`; tests `./test.sh --filter <Suite>`, full run once at the end.
- Comments German with ASCII spelling; UI strings German with umlauts plus English lines in `Support/Localization/en/Nexus.strings` or `Dashboard.strings`; `python3 scripts/check-l10n.py` clean.
- Commit per task, one English imperative line, no Co-Authored-By. Only `git add` files you changed.
- Motion: reuse the shell's curves (`Animation.shellSpatial` etc. in `ShellMotion.swift`), respect `accessibilityReduceMotion`.

---

### Task 1: `BentoEditSession` (core, TDD)

**Files:** create `Sources/ApolloShellCore/BentoEditSession.swift`, `Tests/ApolloShellCoreTests/BentoEditSessionTests.swift`.

- [ ] **Write the failing tests:**

```swift
import Foundation
import Testing
@testable import ApolloShellCore

@Suite("Bearbeiten: Arbeitskopie, Vorschau beim Ziehen, Abbrechen")
struct BentoEditSessionTests {
    private func f(_ x: Double, _ y: Double, _ w: Double, _ h: Double) -> WidgetFrame {
        WidgetFrame(x: x, y: y, width: w, height: h)
    }

    private func session() throws -> (BentoEditSession, WidgetInstance.ID) {
        let clock = WidgetInstance(kind: .clock, frame: f(0, 0, 110, 130))
        let page = DashboardPage(name: "A", symbol: "star", widgets: [clock])
        let pages = try #require(DashboardPages(pages: [page]))
        return (BentoEditSession(pages: pages, pageID: page.id), clock.id)
    }

    @Test("Ziehen: Vorschau rastet ein und sagt, ob es passt; erst Loslassen aendert")
    func move() throws {
        var (s, id) = try session()
        let ok = s.previewMove(id, proposed: f(4, 146, 110, 130))
        #expect(ok.frame == f(0, 146, 110, 130))   // x rastet am Rand ein, y hat kein Ziel
        #expect(ok.valid)
        #expect(s.page.widgets[0].frame == f(0, 0, 110, 130))
        #expect(s.commit(id, frame: ok.frame))
        #expect(s.page.widgets[0].frame == ok.frame)
        let outside = s.previewMove(id, proposed: f(800, 0, 110, 130))
        #expect(!outside.valid)
        #expect(!s.commit(id, frame: outside.frame))
    }

    @Test("Groesse: Vorschau nach den Groessen der Art")
    func resize() throws {
        let (s, id) = try session()
        let r = s.previewResize(id, proposedWidth: 300, proposedHeight: 240)
        #expect(r.frame == f(0, 0, 300, 250))
        #expect(r.valid)
    }

    @Test("Ablegen aus Nexus: kleinste Groesse, ungueltig wenn zu nah")
    func drop() throws {
        var (s, _) = try session()
        let near = s.previewDrop(.clock, x: 60, y: 60)
        #expect(!near.valid)
        let free = s.previewDrop(.clock, x: 300, y: 300)
        #expect(free.valid)
        let added = try #require(s.add(.clock, frame: free.frame))
        #expect(s.page.widgets.count == 2)
        #expect(s.selectedWidgetID == added)
    }

    @Test("Entfernen, Optionen, Auswahl faellt mit dem Widget")
    func removeAndOptions() throws {
        var (s, id) = try session()
        s.selectedWidgetID = id
        s.setOptions(WidgetOptions(clock: DashboardClockOptions(timeZone: "Asia/Tokyo")), for: id)
        #expect(s.page.widgets[0].options.clock?.timeZone == "Asia/Tokyo")
        s.remove(id)
        #expect(s.page.widgets.isEmpty)
        #expect(s.selectedWidgetID == nil)
    }

    @Test("Aenderungen erkennen; Seite wechseln waehlt ab")
    func changes() throws {
        var (s, id) = try session()
        #expect(!s.hasChanges)
        s.selectedWidgetID = id
        s.remove(id)
        #expect(s.hasChanges)
        #expect(s.original.pages[0].widgets.count == 1)
        let other = DashboardPage(name: "B", symbol: "star")
        var pages = s.pages
        pages.update(other) // unbekannt: nichts
        #expect(pages == s.pages)
    }
}
```

- [ ] **Run:** `./test.sh --filter BentoEditSessionTests` → compile error.
- [ ] **Implement:**

```swift
import Foundation

/// Eine Bearbeitung des Dashboards (Nexus > Dashboard > Bearbeiten): die
/// Arbeitskopie aller Seiten, die gezeigte Seite, das gewaehlte Widget.
/// "Fertig" uebernimmt `pages`, "Abbrechen" verwirft sie (`original`).
/// Waehrend gezogen wird, aendert sich nichts - `preview...` sagt nur, wo
/// es landen wuerde und ob es dort passt; erst `commit`/`add` aendert.
public struct BentoEditSession: Equatable, Sendable {
    public let original: DashboardPages
    public private(set) var pages: DashboardPages
    /// Gezeigte Seite. Wechsel waehlt ab.
    public var pageID: DashboardPage.ID {
        didSet { if pageID != oldValue { selectedWidgetID = nil } }
    }
    public var selectedWidgetID: WidgetInstance.ID?

    public init(pages: DashboardPages, pageID: DashboardPage.ID) {
        original = pages
        self.pages = pages
        self.pageID = pages.page(id: pageID)?.id ?? pages.pages[0].id
    }

    public var page: DashboardPage { pages.page(id: pageID) ?? pages.pages[0] }
    public var hasChanges: Bool { pages != original }

    public struct Preview: Equatable, Sendable {
        public var frame: WidgetFrame
        public var valid: Bool
    }

    public func previewMove(_ id: WidgetInstance.ID, proposed: WidgetFrame) -> Preview {
        guard let widget = page.widgets.first(where: { $0.id == id }) else { return Preview(frame: proposed, valid: false) }
        let others = page.frames(excluding: id)
        let frame = BentoGeometry.snapMove(proposed, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: widget.kind, others: others))
    }

    public func previewResize(_ id: WidgetInstance.ID, proposedWidth: Double, proposedHeight: Double) -> Preview {
        guard let widget = page.widgets.first(where: { $0.id == id }) else {
            return Preview(frame: WidgetFrame(x: 0, y: 0, width: proposedWidth, height: proposedHeight), valid: false)
        }
        let others = page.frames(excluding: id)
        let frame = BentoGeometry.snapResize(widget.frame, kind: widget.kind, proposedWidth: proposedWidth,
                                             proposedHeight: proposedHeight, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: widget.kind, others: others))
    }

    public func previewDrop(_ kind: WidgetKind, x: Double, y: Double) -> Preview {
        let others = page.frames()
        let frame = BentoGeometry.dropFrame(kind: kind, x: x, y: y, others: others)
        return Preview(frame: frame, valid: BentoGeometry.isValid(frame, kind: kind, others: others))
    }

    @discardableResult
    public mutating func commit(_ id: WidgetInstance.ID, frame: WidgetFrame) -> Bool {
        var page = page
        guard page.setFrame(frame, for: id) else { return false }
        pages.update(page)
        return true
    }

    /// Neues Widget mit Vorgaben (Wetter: die Orte aus `places`). Liefert
    /// seine Kennung und waehlt es aus; `nil`, wenn der Rahmen nicht passt.
    @discardableResult
    public mutating func add(_ kind: WidgetKind, frame: WidgetFrame, places: WeatherFavorites = .empty) -> WidgetInstance.ID? {
        var page = page
        let widget = WidgetInstance(kind: kind, frame: frame, options: .defaults(for: kind, places: places))
        guard page.add(widget) else { return nil }
        pages.update(page)
        selectedWidgetID = widget.id
        return widget.id
    }

    public mutating func remove(_ id: WidgetInstance.ID) {
        var page = page
        page.removeWidget(id: id)
        pages.update(page)
        if selectedWidgetID == id { selectedWidgetID = nil }
    }

    public mutating func setOptions(_ options: WidgetOptions, for id: WidgetInstance.ID) {
        var page = page
        page.setOptions(options, for: id)
        pages.update(page)
    }
}
```

- [ ] **Run** the suite → pass. Commit "Add the bento edit session".

### Task 2: Editor object and a pinned dashboard

**Files:** new `Sources/ApolloShell/DashboardEditor.swift`; `EdgeDrawer.swift`; `Dashboard.swift`; `LauncherApp.swift` (wiring).

- [ ] `DashboardEditor` (`@MainActor @Observable final class`): `private(set) var session: BentoEditSession?`, `var isEditing: Bool { session != nil }`, `begin(pageID:screen:)`, `done()`, `cancel()`, pass-throughs for the session's mutating calls (the views call these, never mutate `session` directly). `done()` writes `store.settings.dashboardPages = session.pages` only if `hasChanges`. Callbacks `onBegin(screen)` / `onEnd` for the dashboard. One instance, created in the app delegate next to `Dashboard` and `Nexus`, handed to both.
- [ ] `EdgeDrawer`: add `func open(on screen: NSScreen)` (same as `open()` but on the given screen instead of the pointer's) and `var isPinned = false`: while pinned, the hover logic never closes it, `windowDidResignKey` does not close it, and `Esc` does not close it. Unpinning does not close by itself.
- [ ] `Dashboard`: on `onBegin(screen)` → `drawer.isPinned = true`, open on that screen (the one Nexus's window is on), show the session's page. On `onEnd` → unpin, keep it open as a normal open dashboard (the next hover-out/outside click closes it). While editing, weather/media/performance models run for the session's current page just as in normal mode.
- [ ] `DashboardView` reads pages from `editor.session?.pages ?? settings.dashboardPages` and the page from `editor.session?.pageID` while editing; switching pages in the page bar during editing sets `editor` page (and Nexus follows because it observes the same editor).
- [ ] Build. Commit "Pin the dashboard open while a page is being edited".

### Task 3: Edit mode in the dashboard

**Files:** `BentoPageView.swift` (or a new `BentoEditOverlay.swift`), `WidgetView.swift` untouched.

- [ ] While editing, every widget:
  - content `allowsHitTesting(false)` (no media buttons, no calendar arrows);
  - wobbles: rotation ±0.6°, period ~0.26 s, phase from the widget ID's hash so they do not move in sync; with Reduce Motion no wobble but a dashed 1.5 pt outline in `.secondary`;
  - `−` badge at the top-left corner (22 pt circle, `.regularMaterial` + minus symbol, offset half outside the corner): removes the widget with a short scale-down/fade;
  - click selects: 2 pt outline in `style.accent`, radius following the card radius (use 24 pt if the widget has none);
  - resize handle at the bottom-right: a short rounded arc (quarter circle, 4 pt stroke, ~22 pt radius) like Apple's widget editing; `DragGesture` on it → `editor.previewResize(...)` live, commit on end;
  - dragging the widget body → `editor.previewMove(...)` live: the widget follows the snapped preview frame; while `valid == false` the outline is red (`Color.red`) and on release it springs back; valid release commits.
  - Gesture translations are in the page's local coordinates; the page is scaled with `scaleEffect` from outside, so values arrive in reference points. Verify with one render or a print, do not assume.
- [ ] Drop target for Nexus: the page gets `.onDrop(of: [.plainText], delegate:)` with a `DropDelegate`; payload string `"apolloshell.widget:<WidgetKind.rawValue>"`. `dropUpdated` → `editor.previewDrop(kind, x, y)` and draw that frame as a ghost outline (accent when valid, red when not); `performDrop` → `editor.add(kind, frame:, places:)` when valid (places: `WeatherFavorites.load` of weather.json, the same default the migration used). Only active while editing.
- [ ] Render check: extend `RenderMode` with `--render-edit` output: the overview page in edit mode, one widget selected, one ghost drop outline invalid (red), Reduce Motion variant; write to `<dir>/edit/`. Look at the PNGs yourself (Read) and describe in the report what you see.
- [ ] Compare non-edit renders with the baseline (constraint above). Commit "Edit bento pages in the dashboard".

### Task 4: Nexus › Dashboard rebuilt

**Files:** `NexusDashboardPage.swift`, `NexusDashboardEditor.swift` (mostly deleted/replaced), `NexusDashboardPreview` (keep, show the selected page), `NexusWeatherModel` (places sink), maybe new `NexusDashboardPages.swift` and `NexusWidgetOptions.swift`.

Not editing (normal Nexus page):
- [ ] Section **Seiten**: list of pages (symbol + name), reorder by dragging (`onMove` → `movePages`), name editable in place (`TextField`), symbol via a `Menu` of ~24 SF Symbols (grid-ish), context menu **Duplizieren** (name „<Name> Kopie“) and **Löschen** (confirmation alert; disabled for the last page). Buttons **+** (empty page „Seite <n>“, n = count+1) and **Standardseiten wiederherstellen** (`restoreDefaults(from: DashboardPages.defaultPages(places: weather.json favourites, hasBattery: <shared helper from part 2>))`, disabled when nothing is missing).
- [ ] Section **Größe**: slider 70…150 % bound to `settings.dashboardScale`, value shown as „100 %“; footer „Zusätzlich zur Automatik nach Bildschirmgröße.“
- [ ] Prominent button **Bearbeiten** → `editor.begin(pageID: selected page in the list, screen: Nexus window's screen)`.
- [ ] Bottom preview: the selected page (as today's preview, sample data).

Editing (the same Nexus page switches its content while `editor.isEditing`):
- [ ] Left: the page list, selection only (reorder/add/delete disabled); selecting a page switches the dashboard (`editor` page).
- [ ] Middle: **Widgets**: every `WidgetKind` whose `home == .dashboard` (toggle **Alle Widgets zeigen (erweitert)** also shows other surfaces; today there are none, keep the toggle), row = symbol + title + one line of sizes (e.g. „3 Größen“); each row is `.onDrag { NSItemProvider(object: "apolloshell.widget:\(kind.rawValue)" as NSString) }`. Hint above: „In das Dashboard ziehen.“
- [ ] Right: **Optionen** of the selected widget (none selected: „Ein Widget im Dashboard anklicken.“). Move the per-kind option controls from today's `NexusDashboardCardOptions` over, bound to `editor.setOptions` instead of `settings.dashboard.cards`; drop the „Platz“ menu (placement is by dragging now). New for clock: **Zeitzone** — „System“ plus a searchable list of `TimeZone.knownTimeZoneIdentifiers` (city part shown, e.g. „Tokyo (Asia)“) in a popover. New for weather widgets (`kind.usesPlaces`): the places list and place search from today's weather sections, writing into the widget's `options.places` instead of weather.json — give `NexusWeatherModel` a sink (`read`/`write` closures, default weather.json) rather than copying it.
- [ ] Bottom bar: **Abbrechen** and **Fertig** (default action). Closing Nexus while editing = Fertig (`windowWillClose`).
- [ ] Delete the old editor pieces: `NexusDashboardTabsSection`, `NexusDashboardCardSections`, `NexusDashboardCardRow`, `NexusDashboardCardOptions` (after moving the controls), `NexusDashboardGallery`, the template/reset alert and `NexusDashboardText` parts that only served them. Keep core `DashboardPreset` (migration tests use it).
- [ ] Build, commit "Manage and edit dashboard pages in Nexus".

### Task 5: Docs and full check

- [ ] `CHANGELOG.md`: new `## [Unreleased] - 0.2.0` section at the top (above 0.1.2.1) with **Added**: bento dashboard (pages, widgets in today's sizes, several of the same widget, own pages, edit mode, size per screen + slider, weather places per widget, clock time zone) and **Removed**: the three dashboard templates. Style like the 0.1.2.1 entry (bold lead sentence per bullet, plain English, no marketing).
- [ ] `README.md` and `README.de.md`: update the "Dashboard" bullet in "What's inside" to one sentence about pages and widgets; nothing else.
- [ ] `./test.sh` (full), `python3 scripts/check-l10n.py`, app build, render compare (constraint above).
- [ ] Report (max 25 lines): commits, test count, l10n, compare results, what the edit renders show, every decision the plan left open, and a list of things only a live test can confirm (drag from Nexus into the panel, pinned drawer vs. Nexus focus, dashboard covering Nexus, gesture coordinates at scale ≠ 1).

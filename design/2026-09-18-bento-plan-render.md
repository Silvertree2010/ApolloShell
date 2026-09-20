# Bento dashboard, part 2: rendering — Implementation Plan

> **For agentic workers:** Execute task by task. Steps use checkbox (`- [ ]`) syntax.

**Goal:** The dashboard shows `DashboardPages` instead of tabs and cards: a page bar, every page laid out from widget frames, weather per widget, scaling per screen. The four preset pages render pixel-identical to the 0.1 dashboard.

**Architecture:** Part 1 (core) is done: `WidgetKind`, `WidgetInstance`, `DashboardPage(s)`, `PageTemplate.defaultPage`, `DashboardPages.migrated`, `BentoGeometry`, `ShellSettings.dashboardPages/dashboardScale` (all in `Sources/ApolloShellCore`, read them). This part changes only the app target. Today's card and page views are reused, not rewritten. Correctness of the look is measured, not judged: `ApolloShell --render-dashboard <dir>` renders offscreen with fixed sample data, `scripts/compare-renders.py <before> <after> <diffdir>` counts differing pixels.

**Spec:** `design/2026-09-18-bento-dashboard.md` (sections 3 and 5).

## Global Constraints

- Repo `~/projects/private/apolloshell-0.2`, branch `release/0.2`. Never push, never run `./build.sh`, never start the app normally, never touch `~/Applications` or `~/Library/Application Support/ApolloShell`. The render mode is the only way you run the app.
- Build: `SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk swift build --product ApolloShell`. Render: `.build/debug/ApolloShell --render-dashboard <dir>`.
- Baseline renders of the 0.1 dashboard: `/private/tmp/claude-501/-Users-andrin/682a6faf-d551-4585-9c5b-045f6c3eb083/scratchpad/renders/baseline` (8 PNGs: `dashboard|media|performance|weather` × `light|dark`). If missing, recreate them from commit `68dc3c2` in a temporary `git worktree` (build + render there), never by editing current code back.
- Tests: `./test.sh --filter <Suite>`; full `./test.sh` once at the end.
- Comments and UI strings in English; there is no strings file to keep up any more.
- Commit per task, one English imperative line, no Co-Authored-By.
- Nexus keeps compiling but is not reworked here (part 4). The old Nexus dashboard editor may temporarily edit `settings.dashboard` without effect on the dashboard; that is accepted on this branch.

---

### Task 1: Widget views from today's cards (no visible change)

**Files:** `Sources/ApolloShell/DashboardView.swift`, `PerformanceView.swift`, `WeatherView.swift`, `MediaView.swift`, new `Sources/ApolloShell/WidgetView.swift`.

- [ ] Make the private building blocks internal so a widget view can use them: in `DashboardView.swift` `UserCard`, `DateTimeCard`, `CalendarCard`, `ResourcesCard`; in `PerformanceView.swift` `HeroCard`, `StorageCard`, `NetworkCard`, `MemoryCard`, `BatteryTank`; in `WeatherView.swift` `WeatherHero`, `WeatherHourly`, `WeatherDaily`. Only drop `private`; no other change.
- [ ] Create `WidgetView.swift`: one view that draws one `WidgetInstance` at a given size. For the six overview kinds move the body of `DashboardCardView` (DashboardView.swift ~line 165) here unchanged, reading options from `instance.options` (`options.clock ?? .init()` etc.) instead of the `DashboardCard` payload; the size logic (`upright`, `tall`, `horizontal`, the three media shapes) stays exactly as it is. For the performance kinds use the same views and arguments `PerformanceView.body` passes today. For `weatherHero/Hourly/Daily` use the same views and arguments `WeatherTab.body` passes (including its empty states when there is no report or no place). For `mediaPlayer` use `MediaTab(model:)`.

```swift
/// A widget in its frame - the one place where every kind gets its view.
/// The size is set by the page (`BentoPageView`); the shape follows the
/// area like before 0.2 (portrait, tall, wide).
struct WidgetView: View {
    let widget: WidgetInstance
    let context: WidgetContext
    var body: some View { ... }
}

/// What widgets need for drawing. Weather comes per widget
/// (`weather(for:)`), because every weather widget has places of its own.
@MainActor
struct WidgetContext {
    let dashboard: DashboardModel
    let media: MediaModel
    let weather: (WidgetInstance) -> WeatherModel
}
```

- [ ] Let `DashboardGrid` build a `WidgetInstance` per placement (`WidgetKind(placement.card.kind)`, frame from the placement, options from the card) and draw `WidgetView` instead of `DashboardCardView`; delete `DashboardCardView`. The other three tabs stay as they are for now.
- [ ] Build, render into `…/renders/t1`, compare with the baseline: **must be identical** (`same` for all 8). Commit "Draw dashboard cards through one widget view".

### Task 2: Weather per widget

**Files:** `Sources/ApolloShell/WeatherModel.swift`, `WeatherView.swift`, new `Sources/ApolloShell/WeatherModels.swift`.

Today one `WeatherModel` reads the favourites from weather.json in `start()` and writes the choice back in `select(_:)`. Weather widgets carry their own `WidgetOptions.places` instead.

- [ ] Give `WeatherModel` a source for its places, default = today's behaviour:

```swift
/// Where a weather model gets its places from. `.file`: weather.json (bar,
/// Nexus, so far the dashboard too). `.widget`: the places of one weather
/// widget (0.2), read and written through the page in settings.json.
enum WeatherPlacesSource {
    case file
    case widget(read: @MainActor () -> WeatherFavorites, write: @MainActor (WeatherFavorites) -> Void)
}
```

  `init(settings:places:)` with `places: WeatherPlacesSource = .file`. In `start()` read `favorites` from the source; in `select(_:)` write through the source instead of `ShellFiles.write` when it is `.widget`. Nothing else in the fetching logic changes.
- [ ] Shared report cache so two widgets for the same place ask once: a `@MainActor` static dictionary keyed by `"\(provider.rawValue)|\(latitude)|\(longitude)"` holding `(report, fetchedAt)`. `finish(.success)` stores; `start()` adopts a cached report for the current place when it is newer than its own and then skips the fetch if `WeatherRefresh.needsFetch` says the cached one is fresh enough.
- [ ] `WeatherPlacePicker`: take `favorites: WeatherFavorites`, `selected: WeatherLocation?`, `select: (WeatherLocation) -> Void` instead of the model, and pass `model.favorites`, `model.location`, `model.select` from the call sites.
- [ ] `WeatherModels.swift`: one model per weather widget, created lazily and kept by widget ID; `start(for widgets:)` starts the models of the widgets on the open page and stops the others, `stop()` stops all. The `.widget` source reads `options.places` of that widget from `store.settings.dashboardPages` and writes it back via `DashboardPages.update` (page found by the widget's ID). A `preview(_ model:)` variant returns the same fixed model for every widget (render mode, Nexus preview).
- [ ] Unit-testable part: none new in core; build, render into `…/renders/t2`, compare with the baseline: identical. Commit "Give every weather widget its own places".

### Task 3: Pages instead of tabs

**Files:** `Dashboard.swift`, `DashboardModel.swift`, `DashboardView.swift`, new `Sources/ApolloShell/BentoPageView.swift`, `RenderMode.swift`, `NexusDashboardEditor.swift` (only to keep compiling), maybe `LauncherApp.swift`.

- [ ] Migration at startup, in `Dashboard.init` before anything reads pages: if `settings.settings.dashboardPages == nil`, set it to `DashboardPages.migrated(from: settings.settings.dashboard, places: WeatherFavorites.load(from: try? Data(contentsOf: ShellFiles.live.weather)), hasBattery: …)`. For `hasBattery` reuse the existing power-source code (`StatusModel.swift` ~line 64 or `PerformanceSampler.swift` ~line 78 call `IOPSCopyPowerSourcesInfo`); extract a small shared `static var hasInternalBattery: Bool` instead of copying it.
- [ ] `DashboardModel`: replace `tab: DashboardTab` with `pageID: DashboardPage.ID?` and add `var showsPerformance = false`; `syncPerformance()` runs the sampler when `isOpen && showsPerformance`. Keep `preview(...)` working.
- [ ] `BentoPageView.swift`:

```swift
/// One page: every widget at its frame (reference points). Set through
/// frames and offsets in whole points instead of through a `Layout` of its
/// own - see the comment above `DashboardGrid`: a layout of its own rounded
/// differently inside and shifted text by a pixel.
struct BentoPageView: View {
    let page: DashboardPage
    let context: WidgetContext

    var body: some View {
        if page.widgets.isEmpty {
            BentoEmptyPage()
        } else {
            ZStack(alignment: .topLeading) {
                ForEach(page.widgets) { widget in
                    WidgetView(widget: widget, context: context)
                        .frame(width: widget.frame.width, height: widget.frame.height)
                        .offset(x: widget.frame.x, y: widget.frame.y)
                }
            }
            .frame(width: CGFloat(DashboardGeometry.width), height: CGFloat(DashboardGeometry.height),
                   alignment: .topLeading)
        }
    }
}
```

  `BentoEmptyPage` = today's `DashboardEmptyGrid` with the text “Empty page” / “Edit in Nexus”.
- [ ] `DashboardView`: the page bar lists `pages.pages` (title = `page.name`, icon = `ThemedIcon(page.template.tab.iconID, fallback: page.symbol)` for presets, `Image(systemName: page.symbol)` for own pages), same look, indicator and animation as today's tab bar. While all pages fit at ≥ 96 pt each, distribute them exactly as today (`frame(maxWidth: .infinity)` across `gridWidth`); otherwise wrap the bar in a horizontal `ScrollView` with 96 pt per page and scroll the selected one into view. Below the bar draw `BentoPageView` for the selected page (resolved: `pageID` if it exists, else the first page). Delete `DashboardGrid`; `MediaTab`, `PerformanceView` and `WeatherTab` stay only if something else still uses them.
- [ ] `Dashboard`: `onOpen` resolves the page, sets `model.showsPerformance = page.widgets.contains { $0.kind.isPerformance }` (and again whenever `pageID` changes, e.g. via `onChange` in the view or a `didSet` hook), starts `WeatherModels` for the page's weather widgets only if `pages.usesWeather`, media only if `pages.usesMedia`. `show(tab:)` maps to `pages.page(for: PageTemplate(tab), showing: kinds)` with kinds: `.media` → `[.mediaPlayer, .media]`, `.performance` → the six performance kinds, `.weather` → `[.weatherHero, .weatherHourly, .weatherDaily, .weather]`, `.dashboard` → `[]`; a second click on an open page closes it, as today.
- [ ] `RenderMode.renderDashboard`: render the pages of `DashboardPages(pages: DashboardPages.defaultPages(places: <one place, "Berlin" 52.52/13.405>, hasBattery: fixtures.dashboard.performance.battery != nil))!` through the real `DashboardView` (store `.preview(settings)` with those pages, `WeatherModels.preview(fixtures.weather)`), selecting each page in turn; file name = `page.template!.tab.rawValue` so the names match the baseline.
- [ ] Build, render into `…/renders/t3`, compare with the baseline. Target: **identical**. If not: write diff images (third argument), look at them, and fix the cause — typical causes are stacks that centred or stretched content which absolute frames do not (e.g. the daily forecast in `WeatherTab` had no height of its own; performance cards took leftover space). Fix inside the widget view (alignment, frame), not by moving widget frames away from the spec numbers. If after two honest attempts a page still differs, stop and report the pixel counts and what the diff images show.
- [ ] Commit "Show dashboard pages instead of tabs".

### Task 4: Scale per screen

**Files:** `EdgeDrawer.swift`, `Dashboard.swift`, `DashboardView.swift`, `RenderMode.swift`.

- [ ] `EdgeDrawer`: add `var prepareForScreen: ((NSScreen) -> Void)?`, called in `open(byHover:)` right after the screen is known and before `applyGeometry(on:)`. Other drawers leave it `nil`.
- [ ] `DashboardModel.scale: CGFloat = 1`. `DashboardView` wraps its content in `.scaleEffect(model.scale, anchor: .topLeading)` and a frame of the unscaled size × scale (top-leading).
- [ ] `Dashboard`: remember the unscaled `fittingSize` (as today) as `baseSize`; `prepareForScreen` sets `model.scale = BentoGeometry.scale(screenWidth: screen.frame.width, availableHeight: screen.visibleFrame.height, contentHeight: baseSize.height, userScale: settings.settings.dashboardScale)` and `drawer.resize(to: baseSize × scale)`.
- [ ] Render mode: additionally render the preset pages at scale 1.5 into `<dir>/scaled/` (light only). Look at them yourself (Read the PNG): text must be sharp, not blurred. If text is soft, report it with the file names instead of redesigning; the fallback (scaling style values) is decided by the reviewer.
- [ ] Compare the scale-1 renders with the baseline again: still identical. Commit "Scale the dashboard to the screen".

### Task 5: Full check

- [ ] `./test.sh` (full, once), `python3 scripts/check-l10n.py`, app build. Report counts.
- [ ] Report (max 25 lines): commits, compare results per file for t1/t2/t3/final, what you fixed to reach pixel equality, anything left different, sharpness verdict at 1.5 with file names, and every place where you had to decide something the plan did not say.

# Bento dashboard (0.2.0)

Status: design agreed with Andrin on 2026-09-18, edit mode revised 2026-09-19. Core, rendering and a first edit mode built; global edit mode open.
Branch: `release/0.2` (local only, never pushed; merged into `main` when 0.2.0
is done).

## Goal

Every page of the dashboard becomes a freely arranged grid of widgets, the
way Apple's widgets work: each widget comes in a few fixed sizes and shows
more or less depending on the size. The four pages that exist today
(Dashboard, Media, Performance, Weather) ship as ready-made pages that look
exactly like today. People can edit them, delete them, and add their own
pages.

## Non-goals (this step)

- New widget sizes. Every widget keeps exactly the sizes it has today. New
  sizes and new widgets come later ("lots of new elements", idea 12).
- Editing the sidebar or the control centre. The widget catalog already knows
  which surface a widget belongs to, so that step can reuse it later.
- Sharing pages or layouts (theme gallery is a separate feature).
- User-made content widgets (shell command, note, image). Not wanted.

## Decisions

| Topic | Decision |
| --- | --- |
| Pages | Every dashboard page is a bento page. The four current pages are presets. `+` adds more. |
| Presets | Pixel-exact to today. Editable, renamable, deletable like any page. "Restore default pages" brings missing ones back. |
| Widgets | The current cards and page parts, 16 in total (table below). Several instances of the same widget are allowed, each with its own options. |
| Sizes | Only today's sizes. |
| Geometry | No cells. A fixed reference page of 839 × 392 pt; frames are stored in reference points; the whole page is scaled by one factor. |
| Page size | Same aspect ratio for every page. Factor comes from the screen width, times a slider in Nexus. |
| Placement | Free, no overlap, at least 12 pt apart. Magnetic snapping. Invalid spot: red outline, widget returns. |
| Editing | One global edit mode for dashboard and control centre, started from Nexus, over a scrim; gallery, popover options, page management in the page bar (section 4, revised 2026-09-19). |
| Surfaces | Each widget has a home surface (dashboard or control centre). Using a widget outside its home is an advanced option and not optimised. |
| Weather | Each weather widget has its own list of places and switches between them by click or arrows, like today's place picker. |
| Clock | New option: time zone (default: system). |
| Many pages | The page bar scrolls sideways. No upper limit. |
| New page | `+` makes an empty page. Right click on a page: "Duplicate". |
| Old "templates" | The three dashboard templates in Nexus (Caelestia, Compact, Calendar & Weather) go away. Restore and Duplicate replace them. |

## Widget catalog

Sizes are width × height in reference points. "flex a…b" means the width may
be anything from a to b; the height is fixed. The implementation derives the
exact numbers from today's code (`DashboardCardKind.width(in:)`,
`DashboardGeometry`, `PerformanceView`, `WeatherTab`, `MediaTab`) and pins
them in tests; the table is what that code produces today.

Overview widgets. A row is 130 high (top) or 250 high (bottom) when both rows
exist, and 392 high when it is the only row; the side column is 200 × 392 and
a column card alone fills the page. A row without a flexible card was
stretched in proportion before 0.2, so every overview card can already be
any width from the smallest width of its places up to the full 839. Per
height, the minimum is the smallest width among the places that have that
height.

| ID | Widget | Sizes |
| --- | --- | --- |
| `weather` | Weather card | flex 275…839 × 130, flex 200…839 × 250, flex 200…839 × 392 |
| `user` | User | flex 230…839 × 130, flex 200…839 × 250, flex 200…839 × 392 |
| `clock` | Clock | flex 110…839 × 130/250/392 |
| `calendar` | Calendar | flex 300…839 × 250, flex 300…839 × 392 |
| `resources` | Resource rings | flex 230…839 × 130, flex 90…839 × 250, flex 90…839 × 392 |
| `media` | Media card | flex 300…839 × 130 (strip), flex 200…839 × 250 (compact), flex 200…839 × 392 (card) |

Performance widgets. With a battery the left block is 698 wide, without it
839; hence the flexible widths.

| ID | Widget | Sizes |
| --- | --- | --- |
| `performance.cpu` | CPU | flex 343…413.5 × 191 |
| `performance.gpu` | GPU | flex 343…413.5 × 191 |
| `performance.storage` | Storage | flex 169.5…240 × 189 |
| `performance.network` | Network | 335 × 189 |
| `performance.memory` | Memory | flex 169.5…240 × 189 |
| `performance.battery` | Battery | 129 × 392 |

Weather page and media page.

| ID | Widget | Sizes |
| --- | --- | --- |
| `weather.hero` | Weather overview | 839 × 116 |
| `weather.hourly` | Hourly | 839 × 108 |
| `weather.daily` | Next days | 839 × 144 |
| `media.player` | Player | 839 × 392 |

All 16 have the home surface `dashboard`. Half-point widths (169.5, 413.5)
stay as they are: rounding them moved a card by one pixel in the render
comparison, and the presets must be identical. Frames the user makes by
dragging are whole points.

## 1. Data model (`ApolloShellCore`)

- `WidgetKind`: the catalog. Stable string ID (stored in `settings.json`,
  never renamed), localised title, SF Symbol, theme icon ID, home surface,
  sizes. A size is `fixed(width, height)` or `flexible(minWidth, maxWidth,
  height)`.
- `WidgetOptions`: tagged per kind. Reuses `DashboardWeatherOptions`,
  `DashboardUserOptions`, `DashboardClockOptions`,
  `DashboardCalendarOptions`, `DashboardResourcesOptions`,
  `DashboardMediaOptions`. New fields: clock `timeZone: String?` (nil =
  system); weather widgets `places: WeatherFavorites` (same shape as
  weather.json: list plus selected place).
- `WidgetInstance`: `id: UUID`, `kind`, `frame` (x, y, width, height in
  reference points; whole points except the half-point preset widths),
  `options`.
- `DashboardPage`: `id: UUID`, `name`, `symbol` (SF Symbol name),
  `template: PageTemplate?` (`overview`, `media`, `performance`, `weather`;
  nil for own pages), `widgets: [WidgetInstance]`.
- `DashboardPages`: ordered list, never empty.
- `ShellSettings` gains `dashboardPages: DashboardPages?` and
  `dashboardScale: Double` (default 1.0, range 0.7…1.5).

Persistence and migration:

- New keys in `settings.json`; decoded leniently like everything else.
  Unknown widget kinds and broken entries are dropped silently.
- When `dashboardPages` is missing, it is built once from the old
  `dashboard` value (`DashboardLayout`: tab order, visibility, cards and their
  options). Visible tabs become pages in the same order; hidden tabs are not
  carried over (Restore brings them back). The overview page is laid out with
  today's `DashboardGeometry.placements`, so frames match to the point.
- The old `dashboard` key is left as it is, so going back to 0.1.x still
  works.
- The weather widgets created by the migration get today's favourites from
  `weather.json` as their places. The bar's weather module keeps using the
  global favourites.
- The performance preset depends on the Mac: with a battery the battery
  widget is on the page and the others use the narrow widths; without one it
  is left out and the others use the wide widths.

## 2. Geometry and snapping (`ApolloShellCore`, pure functions)

- Scale factor per screen: `clamp(screenWidth / 1512, 0.85, 1.5) ×
  dashboardScale`, then lowered if the dashboard would not fit the screen's
  height. 1512 pt is the 14-inch MacBook, where the factor is 1.0 and nothing
  changes.
- Valid frame: inside the page, at least 12 pt away from every other widget.
- Dragging: per axis, snap to the nearest target closer than 8 pt: page edges,
  aligned edges of other widgets, and the position exactly 12 pt next to
  another widget.
- Resizing: the handle jumps to the nearest allowed size. Flexible widths move
  freely within their range and snap to neighbour edges and the 12 pt gap.
- Dropping a new widget from Nexus: smallest size of that widget, at the drop
  point, then snapped. If it does not fit there, the outline is red and the
  drop does nothing.

## 3. Rendering and data

- The bar at the top of the dashboard lists the pages (name + symbol) in
  today's style and scrolls sideways when they do not fit. Only the active
  page is built.
- The page is laid out at reference size and scaled with
  `scaleEffect(factor)`. If text looks soft at factors above 1, switch to
  scaling the style values (font sizes, spacing, radii) instead. Check in a
  render, not by assumption.
- Every widget view knows its size. Today's card and page views are reused;
  they are not rewritten.
- The media player draws its artwork background only inside its own frame.
- Weather: one cache per place, so two widgets for the same place cause one
  request. Each widget switches between its own places.
- Performance: one sampler for all widgets. It runs only while the dashboard
  is open and the active page contains a performance widget, as it does today
  for the Performance tab.
- Media and calendar: one source; every widget shows the same.
- `usesWeather` and `usesMedia` look at the widgets of the pages instead of
  tabs and cards.
- An empty page says "Edit in Nexus".

## 4. Edit mode (revised 2026-09-19 after the first live test)

The first version edited the dashboard with Nexus open next to it. In the
live test that felt wrong ("nicht cool"). It is replaced by one edit mode for
the whole shell:

- **Start:** one button “Edit Interface” in Nexus (visible on every
  Nexus page). Nexus hides; a scrim (dark, slightly blurred) covers every
  screen. Other apps are not hidden or touched.
- **Panels:** on the screen Nexus was on, the dashboard (top) and the control
  centre (bottom right) open and stay open until the mode ends. The power
  menu does not take part in 0.2.
- **Toolbar:** a small floating bar at the bottom centre with **+**,
  **Cancel** and **Done**.
- **Gallery:** **+** opens a floating gallery in the middle of the screen with
  one tab per surface (“Dashboard”, “Control Centre”). Only elements whose
  home is that surface are listed; “Show all (advanced)” also lists the
  others. Drag an element into its panel, or click it: it lands on the first
  free spot (dashboard) or at the end (control centre).
- **Dashboard while editing:** widgets wobble (±0.3°), `−` removes, the corner
  handle resizes, dragging moves; everything snaps (section 2). Clicking a
  widget opens its options in a popover next to it. Pages are managed in the
  page bar: `+` adds a page, right click on a page offers Rename, Icon,
  Duplicate, Delete. Switching pages works as usual.
- **Control centre while editing:** cards (Keep Awake, Audio,
  Quick Toggles) and toggles wobble and have `−`; cards reorder vertically,
  toggles reorder in their grid by dragging (it is a grid, not free
  placement). Clicking a toggle with options (app, link, shortcut, hide apps)
  opens them in a popover. Removed cards come back from the gallery.
- **End:** “Done” saves dashboard pages and the control-centre layout;
  “Cancel” drops both. Esc = Cancel; with unsaved changes it asks once
  (“Discard changes?”). Nexus comes back afterwards.

### Robustness (his word: “bombenfest”)

People who use a shell like this also run AeroSpace, yabai, Amethyst,
Rectangle, Stage Manager and more. The edit mode must not fight them:

- Every window of the mode (scrim, toolbar, gallery, pinned panels) is a
  borderless, non-activating `NSPanel` on its own level, on all Spaces
  (`canJoinAllSpaces`, `fullScreenAuxiliary`, `stationary`, `ignoresCycle`),
  not in the Windows menu, and exposes a non-standard accessibility subrole,
  so window managers neither tile, move nor hide it.
- Esc works even when another app took focus (a global hot key registered
  only while editing).
- The mode ends as “Cancel” on: screen configuration change, sleep, fast
  user switching. No half-open states.
- While editing, the shell's other hot keys (launcher, dashboard, control
  centre, power menu) are ignored. The sidebar was meant to sit under the
  scrim; since 20.09.2026 it stands above it, because it is arranged there
  too (`design/2026-09-20-bar-edit-plan.md`).
- Only “Done” writes settings; a crash leaves settings unchanged, and the
  scrim disappears with the process.
- Live test in a macOS VM with AeroSpace and yabai before release.

## 5. Nexus and edge cases

- Nexus keeps settings only. The Dashboard and Quick Actions pages are gone
  (2026-09-19): the dashboard size slider lives in the edit mode's toolbar
  (a working copy like the pages, saved with “Done”), the weather places
  for the bar and for new weather widgets moved to Nexus › Leiste, and
  lid-closed Keep Awake moved to Nexus › Allgemein (not into an edit-mode
  popover: it installs a system rule behind an admin prompt at once, which
  Cancel could not take back). The old editors and all templates are gone.
  "Schnellaktionen"/"Quick Actions" is called Kontrollzentrum/Control Centre
  everywhere.
- Buttons and shortcuts that open a specific page (media, performance and
  weather modules in the bar) open the page with that template; if it was
  deleted, the first page with a widget of that kind; otherwise the first
  page.
- Widgets take their surface and border from the theme via `cardSurface`, as
  today. Preset pages keep their theme icon IDs (`bar-dashboard`,
  `panel-media`, `panel-performance`, `panel-weather`); own pages use their
  SF Symbol.
- ~~All new text in German and English, checked with `scripts/check-l10n.py`.~~
  Overtaken on 19.09.2026: 0.2 has an English interface only, the script
  and the German README are gone.
- README, README.de and CHANGELOG get the 0.2.0 section.

## Testing

- Core: catalog sizes pinned against today's geometry; migration of every
  old preset and of hidden tabs; frames of the migrated overview equal
  `DashboardGeometry.placements` for the same cards; snapping, validity and
  resize rules; lenient decoding; page operations (add, duplicate, delete
  last, restore); page resolution for bar buttons; scale factor.
- UI: offscreen renders (`ImageRenderer`) of every preset page and every
  widget size with sample data, compared by eye against the current dashboard.
  A hidden launch mode renders them without starting the shell, so the
  running copy is not disturbed.
- Live tests only together with Andrin; his running app is never quit without
  his yes.
- Edit mode self-test (DEBUG builds): `ApolloShell --selftest-edit <file>`
  builds dashboard, control centre and the mode's windows with in-memory
  settings, keeps every panel transparent, click-through and never key, and
  drives begin/gallery/add/drag/resize/options/minus/Esc/Done/Cancel with
  synthetic events sent to its own windows. It runs next to the real shell
  without touching the screen. It cannot exercise real drag sessions
  (gallery → panel, reordering), the first click of an inactive app, the
  global Esc hot key or typing - those stay live-test items.
- Result of part 2 (2026-09-18): media, performance and weather pages render
  identical to the 0.1 dashboard in light and dark. The overview differs in
  two glyphs only ("Th" and "10" in the calendar's Thursday column move one
  device pixel, half a point): the column's centre is exactly 201.5 pt, a
  half-pixel boundary, and the old stack layout and the new frames round it
  to different sides (the effect the old `DashboardGrid` comment describes).
  Accepted as invisible.

## Build order

1. Catalog, data model, migration (core, TDD).
2. Geometry and snapping (core, TDD).
3. Rendering: pages, widgets at their sizes, scaling, render mode.
4. Edit mode in the dashboard.
5. Nexus: pages, widget list, options, slider; remove the old editor and
   templates.
6. Docs, l10n, review.

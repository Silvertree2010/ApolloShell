# Bento dashboard (0.2.0)

Status: design agreed with Andrin on 2026-09-18, not built yet.
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
| Editing | Started from Nexus. Dashboard stays open, widgets wobble, `−` deletes, handle bottom right resizes, widgets are dragged in from a list in Nexus. Options of the selected widget show in Nexus. |
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
exist, and 392 high when it is the only row. The side column is 200 × 392.

| ID | Widget | Sizes |
| --- | --- | --- |
| `weather` | Weather card | 275 × 130/392 (top row), 200 × 250/392 (bottom row), 200 × 392 (column) |
| `user` | User | flex 230…839 × 130/392, 200 × 250/392, 200 × 392 |
| `clock` | Clock | 110 × 130/250/392, 200 × 392 |
| `calendar` | Calendar | flex 300…839 × 250/392 |
| `resources` | Resource rings | 230 × 130/392, 90 × 250/392, 200 × 392 |
| `media` | Media card | flex 300…839 × 130/392 (strip), 200 × 250/392 (compact), 200 × 392 (card) |

Performance widgets. With a battery the left block is 698 wide, without it
839; hence the flexible widths.

| ID | Widget | Sizes |
| --- | --- | --- |
| `performance.cpu` | CPU | flex 343…414 × 191 |
| `performance.gpu` | GPU | flex 343…414 × 191 |
| `performance.storage` | Storage | flex 169…240 × 189 |
| `performance.network` | Network | 335 × 189 |
| `performance.memory` | Memory | flex 169…240 × 189 |
| `performance.battery` | Battery | 129 × 392 |

Weather page and media page.

| ID | Widget | Sizes |
| --- | --- | --- |
| `weather.hero` | Weather overview | 839 × 116 |
| `weather.hourly` | Hourly | 839 × 108 |
| `weather.daily` | Next days | 839 × 144 |
| `media.player` | Player | 839 × 392 |

All 16 have the home surface `dashboard`. Half-point results (169.5) are
rounded to whole points; the difference is invisible.

## 1. Data model (`ApolloShellCore`)

- `WidgetKind`: the catalog. Stable string ID (stored in `settings.json`,
  never renamed), localised title, SF Symbol, theme icon ID, home surface,
  sizes. A size is `fixed(width, height)` or `flexible(minWidth, maxWidth,
  height)`.
- `WidgetOptions`: tagged per kind. Reuses `DashboardWeatherOptions`,
  `DashboardUserOptions`, `DashboardClockOptions`,
  `DashboardCalendarOptions`, `DashboardResourcesOptions`,
  `DashboardMediaOptions`. New fields: clock `timeZone: String?` (nil =
  system); weather `places: [WeatherLocation]` and `selected: Int`.
- `WidgetInstance`: `id: UUID`, `kind`, `frame` (x, y, width, height in whole
  reference points), `options`.
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

## 4. Edit mode

- Nexus → Dashboard → "Edit". The dashboard opens on the screen Nexus is on,
  showing the page selected in Nexus, and stays open until editing ends.
  Hover does not close it.
- Widgets wobble slightly, each with its own phase. With Reduce Motion they do
  not wobble and get a dashed outline instead.
- `−` at the top left removes a widget immediately.
- Click selects a widget (accent outline); Nexus shows its options.
- The rounded handle at the bottom right resizes; dragging the widget moves
  it. Both snap as in section 2.
- Widgets do not react to clicks while editing (no media buttons etc.).
- Switching pages in the dashboard's page bar also switches Nexus.
- Nexus shows the page list on the left, the widget list next to it (only
  dashboard widgets unless "Show all widgets (advanced)" is on), and the
  selected widget's options on the right. Widgets are dragged from the list
  into the dashboard.
- "Done" saves. "Cancel" restores the state from when editing began. Closing
  Nexus counts as Done.
- All screens show the same pages; only the scale differs.

Risks to check early: drag and drop from the Nexus window into the
non-activating dashboard panel, and the dashboard covering the top of Nexus.

## 5. Page management in Nexus and edge cases

- The page list reorders by dragging. `+` adds an empty page ("Page 2", ...)
  with a symbol chosen from a list. Rename in place. Delete asks once; the last
  page cannot be deleted. Right click: Duplicate (new IDs, name "… copy").
- "Restore default pages" appends the missing presets in their Caelestia form
  and leaves existing pages alone.
- The size slider lives here. The scaled live preview of the selected page
  stays.
- Buttons and shortcuts that open a specific page (media, performance and
  weather modules in the bar) open the page with that template; if it was
  deleted, the first page with a widget of that kind; otherwise the first
  page.
- Widgets take their surface and border from the theme via `cardSurface`, as
  today. Preset pages keep their theme icon IDs (`bar-dashboard`,
  `panel-media`, `panel-performance`, `panel-weather`); own pages use their
  SF Symbol.
- All new text in German and English, checked with `scripts/check-l10n.py`.
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

## Build order

1. Catalog, data model, migration (core, TDD).
2. Geometry and snapping (core, TDD).
3. Rendering: pages, widgets at their sizes, scaling, render mode.
4. Edit mode in the dashboard.
5. Nexus: pages, widget list, options, slider; remove the old editor and
   templates.
6. Docs, l10n, review.

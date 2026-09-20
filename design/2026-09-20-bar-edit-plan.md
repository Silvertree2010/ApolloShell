# The sidebar in the global edit mode

The edit mode (0.2) opens the dashboard and the control centre together. The
sidebar is the last kit that is still arranged in a settings page: Nexus ›
Bar with its list, its presets and its option rows (`NexusBarEditor.swift`,
532 lines). After this change the shell is arranged where it lives, and Nexus
keeps settings only.

## What it has to do

- "Edit Interface" also opens the sidebar for editing, on every screen that
  shows one. The blocks wobble, `−` removes one, dragging reorders them,
  clicking one opens its options in a popover next to it.
- The gallery behind `+` gets a third tab, **Sidebar**, with the block kinds
  that are not in the bar yet (`BarLayout.canAdd`). Click inserts at the end
  of the group the pointer is in, dragging inserts where it is dropped.
- Done writes `settings.bar.layout`, Cancel drops it - the same contract the
  dashboard and the control centre already keep.
- Nexus › Bar loses the editor and keeps the settings: which screens the bar
  stands on, the background, and the weather places.

## What it must not do

- No change to how the bar draws outside the edit mode. `SidebarContent`
  stays the view it is today; the overlay sits on top of it, like
  `UtilitiesEditOverlay` does for the control centre.
- No new file format. `BarLayout` already reads and writes what the editor
  produces, and `BlockList` already enforces the rules (unique ids, kinds
  that may exist only once).
- The bar keeps taking clicks for its real actions while **not** editing. A
  click during editing selects a block instead of opening the dashboard.

## Decisions taken up front

- **The gallery tab is not a `WidgetSurface`.** That type says where a widget
  is at home, and no widget is at home in the bar. The gallery gets its own
  `GalleryTab { dashboard, controlCentre, bar }`, and `ShellEditor.galleryTab`
  changes to it. `WidgetSurface` stays as it is.
- **One session type per surface.** `BarEditSession` mirrors
  `UtilitiesEditSession`: `original`, `layout`, `selectedEntryID`, and the
  mutations pass through to `BarLayout`. The rules stay in the layout.
- **Sidebar blocks have no size.** Dragging moves them, there is no corner
  handle. Height is shared out by `BarFlex` as before.

## Tasks

### Task 1: The session in the core

**Files:** `Sources/ApolloShellCore/BarEditSession.swift`,
`Tests/ApolloShellCoreTests/BarEditSessionTests.swift`.

- [ ] `BarEditSession`: `init(layout:)`, `hasChanges`, `add(_:at:)` (selects
      the new block, `nil` when the kind may exist only once and is there),
      `remove(id:)` (clears the selection when it was that block),
      `update(id:to:)`, `move(fromOffsets:toOffset:)`, `move(id:by:)`.
- [ ] Tests first, against the behaviour the control centre session shows:
      a fresh session has no changes, adding selects, removing the selected
      block clears the selection, a refused add changes nothing, and the
      mutations match what `BarLayout` does on its own.
- [ ] Commit "Hold the sidebar's working copy while editing".

### Task 2: The editor holds it

**Files:** `Sources/ApolloShell/ShellEditor.swift`, `EditGallery.swift`.

- [ ] `ShellEditor.bar: BarEditSession?`, filled in `begin`, written in
      `done` when it has changes, dropped in `cancel`; `hasChanges` counts it.
- [ ] `galleryTab` becomes `GalleryTab`; the gallery shows three tabs and
      lists the addable bar kinds in the third.
- [ ] Esc order stays: gallery first, then the selection, then the mode.
- [ ] Commit "Carry the sidebar through the edit mode".

### Task 3: The overlay in the bar

**Files:** new `Sources/ApolloShell/BarEditOverlay.swift`,
`SidebarScreen.swift`, `SidebarContent.swift`.

- [ ] While editing, the bar window draws the blocks with the wobble, the `−`
      badge and the selection ring, and takes clicks for selecting instead of
      for their real action.
- [ ] Dragging a block up or down reorders it live (`move(id:by:)` on the
      block under the pointer), dropping a gallery payload
      `apolloshell.bar:<kind>` inserts at that place.
- [ ] Options popover next to the selected block, with the rows that
      `NexusBarEditor` shows today (clock, spacer, app button, weather).
- [ ] Render check: the bar in edit mode into `<dir>/edit/`.
- [ ] Commit "Edit the sidebar where it stands".

### Task 4: Nexus cleanup and docs

**Files:** `NexusBarEditor.swift`, `NexusPages.swift`, `README.md`,
`CHANGELOG.md`, `docs/`.

- [ ] Nexus › Bar keeps screens, background and weather places; the list, the
      presets and the option rows go. Delete what nothing calls any more.
- [ ] README bullet and CHANGELOG entry: the sidebar is arranged in the edit
      mode too.
- [ ] Full `./test.sh`, build, render compare against the samples from before.
- [ ] Commit "Arrange the sidebar in the edit mode, not in Nexus".

## Live test for Andrin

Once Task 3 is in: open the edit mode with two screens connected, reorder a
few blocks, add a clock from the gallery, cancel, and check that the bar is
exactly as before. Then the same with Done, and a restart to see it stuck.

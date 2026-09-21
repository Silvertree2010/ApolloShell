# Nexus moves into the menu bar

Nexus is a window with eleven pages for a shell that has, after 0.2, about
two dozen settings left. The edit mode took the arranging away from it, and
what is left is mostly switches and lists. It becomes a menu bar item: the
same name, the same job, one click instead of a window.

Two things stay a window, because a menu cannot hold them: recording a
keyboard shortcut needs a key window, and the first start needs a guide
through the permissions. One window with two faces replaces eleven pages.

## Decisions taken up front

- **The menu is called Nexus.** It is not a second door next to the window;
  the window is gone. The icon is the one thing that is always reachable -
  in full screen, on a screen without a bar, with no shortcut set.
- **Nothing is on a shortcut out of the box.** A fresh install binds no
  keys at all. The first start offers to put the launcher on one, as an
  offer that can be skipped; everything else is set by hand in the
  shortcuts window. An app that takes keystrokes away from the system
  before being asked is a nuisance, and this one stops doing it.
- **What is already set stays set.** An installation that comes from 0.1.x
  keeps its four shortcuts. Only new settings start empty
  (`HotKeySettings.firstLaunch` becomes empty, the old value lives on as
  the preset the onboarding offers).
- **No settings move into the menu that the edit mode already owns.** The
  weather places of the bar are edited in the block's popover since 0.2,
  and the page for them goes without replacement.
- **Two features leave Nexus rather than the app.** Pinned apps move into
  the launcher itself (right click a row: pin, unpin, drag to reorder).
  The shortcuts get the window.

## What the menu holds

Top, the four things one wants to open:

- Dashboard, Control Centre, Launcher, Edit Interface

Then what used to be the pages, as submenus with check marks:

- **Bar**: which screens, background (material / liquid glass)
- **Themes**: the installed themes, "Add theme…" (open panel), "Show folder
  in Finder"
- **Toasts**: the five events
- **Desktop clock**: on/off
- **Weather provider** and **file manager** (from Providers)
- **Keep Awake with the lid closed**, **Hide Apple's Dock**
- **Updates**: "Check now", automatic check, automatic install

At the bottom: "Shortcuts…", "Introduction…", "Open System Settings",
"About ApolloShell", "Quit ApolloShell".

What falls away without replacement: the System page (eleven links into
Apple's settings plus chip, OS, uptime, computer name), the Bar's weather
places, the Launcher page, the Themes documentation page (a link to the
repository), the release notes panel (a link to the releases page).

## Tasks

### Task 1: The menu bar item

**Files:** new `Sources/ApolloShell/NexusMenu.swift`, `LauncherApp.swift`.

- [ ] `NSStatusItem` with the theme's icon (`ThemedIcon`, fallback an SF
      symbol), built at start, removed again when the setting says so.
- [ ] The four openers and Quit, wired to the same calls the bar buttons
      use. No new logic behind them.
- [ ] Robustness, the way Vorssaint's changelog shows it hurts: the item
      keeps its place across restarts (AppKit does that by autosave name),
      it is found again when the menu bar hides itself, and the app never
      ends up with no way in - without the item and without shortcuts,
      opening the app again (Finder, Spotlight, `open -a`) brings up the
      shortcuts window with a note on how to show the item again. A menu
      cannot be hung on an item that is not there.
- [ ] Live on the MacBook: with a full menu bar macOS hides items behind
      the notch. Check that case by hand; it is exactly the one where the
      app would be unreachable.
- [ ] Setting `menuBar.shown` (default on), in the menu itself.
- [ ] Commit "Open the shell from the menu bar".

### Task 2: The settings in the menu

**Files:** `NexusMenu.swift`, `ShellSettingsStore.swift`.

- [ ] The submenus listed above, each reading and writing the same
      settings the Nexus pages wrote. Check marks follow the store.
- [ ] Themes: list from `ThemeStore`, "Add theme…" with `NSOpenPanel`,
      errors as a toast instead of an alert.
- [ ] Updates: the three items around `UpdateController`; notes open the
      releases page in the browser.
- [ ] Commit "Put the settings of Nexus into its menu".

### Task 3: The shortcuts window

**Files:** new `ShortcutsWindow.swift`, `NexusGeneralPages.swift` (the
recorder moves out of it), `HotKey.swift`.

- [ ] One window, the four recorders, the note about Esc and backspace,
      and the two presets - now called what they are: "Launcher on fn"
      and "Control and Option".
- [ ] `HotKeySettings.firstLaunch` becomes empty; the old set stays as
      `HotKeySettings.suggested` for the onboarding and the preset menu.
- [ ] No migration code needed: `ShellSettings` already hands out
      `.firstLaunch` only when there is no settings file at all, and
      `.existingInstall` otherwise (`c.lenient(.hotKeys) ?? .existingInstall`).
      A test pins that down: a file without `hotKeys` keeps the old four.
- [ ] Commit "Give the shortcuts a window of their own".

### Task 4: Pins move into the launcher

**Files:** `LauncherView.swift`, `LauncherModel.swift`, `PinnedList.swift`,
`NexusLauncherPage.swift` (goes).

- [ ] Right click on an app row: "Pin", "Unpin". The launcher already has
      that menu (`LauncherController.showMenu`: "Open", then Apple's Dock
      menu or the app's own commands); the two items go into it, they need
      no Accessibility. Pinned rows can be dragged within the pinned block.
- [ ] Tests for the list operations in Core, as far as they are not there
      already.
- [ ] Commit "Pin an app where it stands".

### Task 5: The onboarding offers a shortcut

**Files:** `Onboarding.swift`, `OnboardingModels.swift`.

- [ ] A step after the permissions: "Open the launcher with a key?" with
      the suggestion, a recorder and "Not now". Skipping leaves everything
      empty.
- [ ] The step says where the shell lives without one: the menu bar item.
- [ ] Commit "Offer a launcher key instead of taking one".

### Task 6: Nexus goes

**Files:** `Nexus.swift`, `NexusView.swift`, `NexusPages.swift`,
`NexusGeneralPages.swift`, `NexusThemesPage.swift`, `NexusUpdatesPage.swift`,
`NexusProvidersPage.swift`, `NexusLauncherPage.swift`,
`NexusScaledPreview.swift`, `NexusSearchSheet.swift`,
`NexusAppChoiceRow.swift`, `NexusOptionsBinding.swift`, `NexusGallery.swift`,
`NexusBarEditor.swift`, `NexusDashboardPage.swift`, README, CHANGELOG.

- [ ] Delete what nothing calls any more. `NexusGallery.swift` is already
      dead today (nothing uses `NexusGallerySheet` or `NexusGalleryTile`)
      and can go at any time.
- [ ] Keep what the edit mode and the render tests still use, moved out of
      the Nexus files and renamed without the prefix:
      - `NexusWidgetOptions.swift`: the edit mode's popovers.
      - From `NexusDashboardPage.swift`: `NexusWeatherModel`,
        `NexusWeatherFavoriteRow`, `NexusWeatherSearchRow` (the weather
        block's popover uses them through `NexusWidgetOptions`). The page
        itself (`NexusDashboardWeatherSection`) goes.
      - From `NexusBarEditor.swift`: `NexusBarPreview` and
        `NexusBarPreviewModels`, which `RenderMode.swift` renders for the
        image comparison. The page (`NexusBarPage` and its sections) goes.
- [ ] Before deleting a file: `grep` every type in it across `Sources`
      and `Tests`; the build alone does not catch a render case that
      quietly drops out.
- [ ] The hotkey for Nexus becomes the one that opens the menu.
- [ ] README and CHANGELOG: the settings are in the menu bar, nothing is
      on a key out of the box.
- [ ] Full `./test.sh`, the self-test, render comparison.
- [ ] Commit "Take Nexus out of the window".

## Live test for Andrin

Fresh settings (move `settings.json` aside): no shortcut works, the icon is
in the menu bar, the onboarding offers the launcher key. Then with his own
settings: his four shortcuts still work, the menu shows what the pages
showed.

## Found on the way

`NexusGeneralPages.swift:68` still has a German "Vorlage laden …" in the
interface, in a build that says it is English only. It disappears with the
page, or earlier.

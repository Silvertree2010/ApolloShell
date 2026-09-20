# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.3] - 2026-09-21

The interface is in English, all of it.

Until now the shell was bilingual: the text in the code was German, and an
English translation sat beside it in `Support/Localization`. That worked for
the strings the check knew about, and quietly did not for the rest - a
handful of labels in the control centre and in Nexus were German whatever
language you had picked ("Mikrofon", "Dunkelmodus", "Bildschirmfoto"). One
language, written where it is used, cannot drift like that.

German is gone with it, and that is a loss for the people who used it. It
comes back when there is a way to keep translations honest; for now every
string is in English, in the code, where a change to it is a change to the
thing itself.

### Changed

- **The interface is written in English**, directly in the source. The
  translation layer (`Support/Localization`, `scripts/check-l10n.py`) is
  gone.
- **Nexus has no language picker any more.** The setting it wrote is not
  read; macOS' own language setting has no effect on the shell either.

### Fixed

- **Labels that were German in every language**: the quick toggles
  ("Microphone", "Dark Mode", "Screenshot", "Color Picker", "Desktop"), the
  cards of the control centre, the block names of the bar and the lines that
  describe them in Nexus.

## [0.1.2.2] - 2026-09-20

A patch on 0.1.2.1: a light theme on a dark Mac, and three ways to lose
work or run an action twice.

### Fixed

- **A light theme lights up the whole shell**, and a dark one darkens it.
  Around a hundred places take their text colour from macOS, so a light
  theme on a dark Mac wrote white on its own light surfaces. The token
  `--apollo-theme-appearance: light` or `dark` now sets the appearance of
  the app itself; `auto` follows the system as before.
- **A click on the screenshot, lock or colour picker button runs once.**
  The control centre stays clickable while it fades out, so a double
  click ran the action at once, with the glass still on screen, and a
  second time after the fade.
- **An unreadable `pinned.json` is kept.** Nexus read a broken file as an
  empty list and the next pin wrote that empty list over it, so a typo
  made while editing by hand cost every pinned app. The file is copied to
  `pinned.json.unreadable` first, as `settings.json` and `usage.json`
  already were.
- **"Restart now" stays while an update waits.** Checking again picked the
  downloaded update up a second time, and Nexus > Updates showed it as
  found instead of ready, without the button.

## [0.1.2.1] - 2026-09-18

A patch on 0.1.2: what a theme reaches, and what the icon list promised.

### Fixed

- **The launcher, the session menu and the introduction follow the theme.**
  All three were glass with the colours of macOS, so a theme stopped at
  their edge.
- **Every icon name in the documentation works.** The catalog listed the
  status glyphs, the toasts and the panel icons, but only the bar and the
  session menu read them.
- **A theme that only wrote `--apollo-bar-gradient: none` made the sidebar
  invisible.** A gradient of `none` no longer counts as painting a surface.
- **Glyphs on accent areas went dark** when a theme did not name its own
  on-accent colour; they are white again, as before themes existed.
- **An icon from a theme is drawn at the size of the symbol it replaces**
  instead of filling the whole button.

### Added

- `--apollo-icon-style: monochrome` tints the images a theme brings along
  like the symbols they replace. `auto` stays the default and leaves them
  exactly as they were drawn.

## [0.1.2] - 2026-09-17

### Added

- **App commands in the launcher**: a right click on a row opens the same
  menu as the dock - the app's own commands (new window, settings), and
  Show in Finder.
- **The app's own dock menu**: a right click on a dock icon mirrors the
  menu Apple's Dock shows for that app, so every app brings whatever it
  offers - recent documents, its own commands, the Options submenu. Keep in
  Dock is the one entry bound to this shell's dock instead of Apple's. When
  Apple's Dock has no icon for the app, the shell falls back to the menu it
  builds itself, in Apple's order: windows first with a tick on the front
  one, then the app's commands, then Options, then Show All Windows, Hide
  and Quit.
- **Commands are found by their keyboard shortcut** (⌘N, ⌘,) rather than by
  the wording of the menu item, so they also show up in other languages.

- **Themes apply to the shell.** Pick one in Nexus > Themes and the bar,
  the panels, the launcher, the toasts and the accent colour follow the
  file. Editing the file applies at once, without a restart, and the page
  lists what could not be read. Themes can be added from Finder, and the
  folder opens from the same page.
- **Icons from a theme**: a folder `icons/` next to `theme.css`, where the
  file name is the icon it replaces - the session emblem included. Anything
  not in there keeps its built-in symbol; see docs/THEMES.md.
- **Sizes, spacing and borders follow the theme** as well: corner radii,
  the bar's width, padding and item spacing, the dock's icon size and
  spacing, the launcher's row height, font family and size, and an optional
  border around cards.
- **Gradients in themes**: the backdrop, surfaces, the accent, the bar,
  panels, cards, the launcher highlight and toasts each have a gradient
  token next to their colour, `none` by default.

- **Automatic updates** for the `.dmg` build: a daily check in the
  background, the download right after, and the install when the app next
  quits. Nexus > Updates shows the state, has both switches (on by default)
  and offers **Restart now** while an update waits. A Homebrew install is
  never replaced by the app itself; it shows `brew upgrade apolloshell`
  instead. Updates are signed with an EdDSA key and with a fixed release
  certificate, so the Accessibility grant survives an update.

## [0.1.1] - 2026-09-16

First public release. It also contains everything listed under 0.1.0.

### Added

- **A bar on every screen** (Nexus → Bar → Screens: all, main screen only,
  or one screen). Dashboard, utilities, launcher, session menu and toasts
  open on the screen the pointer is on.
- **Bar background** setting (Nexus → Bar): system material (default),
  Liquid Glass, tinted Liquid Glass, or Liquid Glass on a solid surface.
- **Status popouts** (Wi-Fi, Bluetooth, battery) grow out of the bar as one
  surface.
- **Themes** as CSS files in
  `~/Library/Application Support/ApolloShell/themes`: a single `.css` or a
  folder with `theme.css` and images next to it. Tokens for colours, sizes,
  fonts and metadata, a dark-mode block, and guarantees that keep old themes
  working - see [docs/THEMES.md](docs/THEMES.md). Symlinked themes work.
  Reading and checking them is in place; applying them to the interface
  comes next.
- **Keep awake with the lid closed** without repeated password prompts: the
  first administrator prompt adds `/etc/sudoers.d/apolloshell`, which allows
  only `pmset -a disablesleep 1` and `0`. Nexus → Quick Actions shows the
  rule and can remove it.

### Changed

- **Dock clicks** follow Apple's Dock: launch, bring forward, restore the
  last minimized window, or open a new one. A window on the current desktop
  wins over windows on other desktops, so a click no longer jumps to
  another desktop. Clicking the app that is already in front only brings
  up a window that another app covers.
- **Fullscreen** is detected per screen from its active space, without the
  Accessibility permission. A fullscreen video stays free of the bar while
  you work on another screen.

### Fixed

- The bar could disappear from all desktops but one after leaving
  fullscreen.
- A theme with a huge number crashed the app.
- The contrast fix for theme text replaced colours with pure black on
  mid-light backgrounds.
- Clicking an app without visible windows could fail to open one when the
  app kept closed windows in memory.
- Toasts could end up off-screen after a display was unplugged.
- Quitting during the lid-closed administrator prompt could leave lid sleep
  disabled for good.
- The Apple Dock is no longer hidden when its original settings could not be
  saved, and it is restored first when ApolloShell quits.
- Unreadable `settings.json` and `usage.json` files are kept as
  `*.unreadable` instead of being overwritten.
- The session menu runs only one command per opening.
- A relaunch after a language change could end with no ApolloShell running.

## 0.1.0 - 2026-09-15

Not published on its own; it ships as part of 0.1.1.

### Added

- **Sidebar** built from blocks:
  - blocks: dashboard button, Spaces, dock, clock, utilities button, status
    icons, power, spacers, gaps, dividers, app buttons, battery, CPU, weather
    and media
  - presets: Caelestia, Minimal, Dock only, Everything
- **Dock** in the sidebar:
  - pinned and running apps, with badges
  - click, click-and-hold and right-click menus, including windows on all
    Spaces and the app's "New …" commands
  - drag to reorder, drop files on an app, scroll to cycle windows
  - pinned apps kept in sync with Apple's Dock
  - status popouts for Wi-Fi, Bluetooth and battery
- **Window guard**: keeps windows out of the sidebar's strip and hides the
  sidebar for full-screen apps. Needs Accessibility.
- **Launcher**: fuzzy search, ranking by usage, pinned apps on top.
- **Dashboard** with Dashboard, Media, Performance and Weather tabs:
  - cards and tabs can be rearranged
  - presets: Caelestia, Compact, Calendar & Weather
- **Utilities** panel:
  - keep awake (optionally with the lid closed)
  - sound card with output and input device
  - twelve quick toggles and actions
  - custom buttons for apps, links and Shortcuts
  - presets
- **OSD** for volume, **toasts** for power and audio events, **desktop clock**,
  **session menu** with an animated emblem that reacts to the chosen action.
- **Nexus** settings window with a page for every panel, live previews and
  presets.
- **Welcome guide** on first launch: what ApolloShell is, Accessibility with a
  live status, the launcher shortcut, start at login. Skippable, and available
  again under Nexus → About.
- **Configurable global shortcuts** (Nexus → Keyboard Shortcuts) with a
  shortcut recorder, live re-registration and conflict feedback. New defaults:
  ⌥Space, ⌃⌥D, ⌃⌥U, ⌃⌥,; existing settings keep F20 and Hyper + D / U / ,.
- **Start at login** switch (`SMAppService`) in the welcome guide and in Nexus
  → General.
- **Hide Apple's Dock while ApolloShell runs** (Nexus → General, off by
  default): saves the original `com.apple.dock` autohide values and restores
  them when ApolloShell quits or the setting turns off.
- **Keep awake with the lid closed** is now a setting. Without passwordless
  `sudo` macOS asks for an administrator password instead.
- **Weather providers**: Open-Meteo, MET Norway, wttr.in.
- **Weather favorites**: search and add places in Nexus, reorder and choose
  among them; the weather tab shows them as chips. No place by default -
  Nexus opens from the weather tab or card until you add one.
  A selectable **file manager** for the dock.
- **English and German** interface. It follows the macOS language order, and
  Nexus › General can override it for ApolloShell alone. Dates and weekdays
  follow the chosen language. `scripts/check-l10n.py` finds untranslated text.
- **Single instance**: opening ApolloShell again brings up Nexus instead of
  starting a second copy.
- **Release tooling**:
  - app icon (`scripts/make-icon.swift`)
  - universal disk image (`scripts/make-dmg.sh`)
  - Homebrew formula template (`packaging/homebrew/apolloshell.rb`)
  - stable local code signing (`scripts/setup-signing.sh`)

### Known limitations

- The Intel (x86_64) build has not been tested on Intel hardware.
- Relies on private macOS interfaces that may change with macOS updates.

[0.1.2.1]: https://github.com/Silvertree2010/ApolloShell/releases/tag/v0.1.2.1
[0.1.2]: https://github.com/Silvertree2010/ApolloShell/releases/tag/v0.1.2
[0.1.1]: https://github.com/Silvertree2010/ApolloShell/releases/tag/v0.1.1

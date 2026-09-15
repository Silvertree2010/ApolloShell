# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/).

## [0.1.0] - Unreleased

First public release.

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

[0.1.0]: https://github.com/OWNER/ApolloShell/releases/tag/v0.1.0

<p align="center">
  <img src="docs/images/icon.png" width="128" alt="ApolloShell app icon">
</p>

<h1 align="center">ApolloShell</h1>

<p align="center">
  A desktop shell for macOS 26 Tahoe: a sidebar with its own dock, a launcher,
  a dashboard and a control centre, all built from blocks you arrange yourself.
</p>

<p align="center">
  <a href="https://github.com/Silvertree2010/ApolloShell/actions/workflows/ci.yml"><img src="https://img.shields.io/github/actions/workflow/status/Silvertree2010/ApolloShell/ci.yml?branch=main&amp;label=CI" alt="CI"></a>
  <a href="https://github.com/Silvertree2010/ApolloShell/releases/latest"><img src="https://img.shields.io/github/v/release/Silvertree2010/ApolloShell" alt="Latest release"></a>
  <a href="https://github.com/Silvertree2010/ApolloShell/releases"><img src="https://img.shields.io/github/downloads/Silvertree2010/ApolloShell/total" alt="Downloads"></a>
  <a href="https://github.com/Silvertree2010/homebrew-apolloshell"><img src="https://img.shields.io/badge/Homebrew-tap-FBB040?logo=homebrew&amp;logoColor=black" alt="Homebrew tap"></a>
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-000000?logo=apple" alt="macOS 26 Tahoe">
  <img src="https://img.shields.io/badge/Swift-6.2%2B-F05138?logo=swift&amp;logoColor=white" alt="Swift 6.2+">
  <a href="LICENSE"><img src="https://img.shields.io/github/license/Silvertree2010/ApolloShell" alt="License: MPL 2.0"></a>
  <a href="https://www.producthunt.com/products/apolloshell"><img src="https://img.shields.io/badge/Product%20Hunt-ApolloShell-DA552F?logo=producthunt&amp;logoColor=white" alt="ApolloShell on Product Hunt"></a>
</p>

<p align="center"><a href="https://silvertree2010.github.io/ApolloShell/">Website</a></p>

![ApolloShell on a desktop: sidebar with dock on the left, dashboard open at the top](docs/images/hero.png)

ApolloShell brings the look of Linux shells like [Caelestia][caelestia] to the
Mac. It doesn't replace Finder or the window manager. It adds panels to the
edges of your screen and stays out of the way otherwise.

> [!NOTE]
> This is an early release. It relies on private macOS interfaces, so a macOS
> update can break parts of it. The design follows Caelestia, but ApolloShell
> is an independent project and contains no Caelestia code.

If you like it, a star on GitHub helps other Mac users find it.

## What's inside

- **Sidebar** on the left edge with Spaces, a clock, status icons and a power
  button. Add, remove and reorder its blocks in the edit mode.
- **Dock** in the sidebar with your pinned and running apps. Clicks, menus,
  drag and drop and badges work like in Apple's Dock.
- **Launcher.** Press your key, type, hit Return. Apps you use often come
  first; right-click one to pin it to the top.
- **Dashboard** from the top edge: pages of widgets for weather, calendar,
  system stats and what's playing. Add pages of your own, or put the same
  widget on a page twice. Every weather widget keeps its own places, every
  clock its own time zone.
- **Control centre** in the bottom-right corner: keep awake, sound, Wi-Fi, dark
  mode, Night Shift, a colour picker and your own buttons.
- **One edit mode for all three.** "Edit Interface" in the menu bar dims the screen
  and opens the dashboard, the control centre and the sidebar together: drag a
  widget, a button or a bar block where you want it, resize a widget by its
  corner, pick new ones from the gallery behind `+`. A slider sets how large
  the dashboard is on this screen. Done keeps the changes, Cancel drops them.
- **Themes** as one CSS file: colours, gradients, fonts, sizes and even the
  icons for the whole shell, applied the moment you save the file.
- **Nexus**, a panel from the menu bar: switches the dashboard, the control
  centre and the launcher on or off and holds every setting as cards with
  switches, with the keyboard shortcuts in a small window of their own.
- Volume display, notifications for power and audio, a desktop clock and a
  session menu.
- **Keeps itself up to date** (the `.dmg` build), or says when a new version
  is out (Homebrew).

| Dashboard | Control centre | Launcher |
| --- | --- | --- |
| <img src="docs/images/dashboard.png" alt="Dashboard with weather, calendar, resources and now playing"> | <img src="docs/images/utilities.png" alt="Control centre with keep awake, sound and quick toggles"> | <img src="docs/images/launcher.png" alt="Launcher with a search field and a list of apps"> |

## Install

You need **macOS 26 Tahoe** or later, on Apple silicon or Intel.

**Download.** Get the `.dmg` from the [latest release][releases] and drag
ApolloShell into Applications. The app isn't notarised (that needs a paid Apple
developer account), so macOS blocks the first launch. Open **System Settings →
Privacy & Security** and click **Open Anyway**, or run:

```sh
xattr -dr com.apple.quarantine /Applications/ApolloShell.app
```

**Homebrew.** Builds it from source on your Mac:

```sh
brew trust --tap Silvertree2010/apolloshell   # Homebrew 7 and newer
brew tap Silvertree2010/apolloshell
brew install apolloshell
```

**From source.** Only the Command Line Tools are needed, no Xcode:

```sh
git clone https://github.com/Silvertree2010/ApolloShell.git
cd ApolloShell
scripts/setup-signing.sh   # once, keeps permissions across rebuilds
./build.sh
```

More about building and testing is in [CONTRIBUTING.md](CONTRIBUTING.md).

## Themes

A theme is a CSS file in
`~/Library/Application Support/ApolloShell/themes`: colours, sizes, fonts and
gradients as `--apollo-*` tokens, a dark-mode block, and nothing else - no
scripting, no selectors of your own. A theme folder can bring an `icons/`
folder along and swap the shell's symbols for its own images. Pick one on the **Themes** tab of the Nexus panel in the menu bar. Saving
the file applies it at once, and anything that could not be read falls back
to the built-in value; the theme's row counts the notes. The format and every token
are in [docs/THEMES.md](docs/THEMES.md).

The same shell, three themes. Colours, fonts, corners, sidebar width and dock
size all come out of the theme file.

| Afterglow | Marble | Tide |
| --- | --- | --- |
| <img src="docs/images/theme-afterglow.jpg" alt="Dark navy theme with coral accents, dashboard and launcher open"> | <img src="docs/images/theme-marble.jpg" alt="Light grey theme with a serif font, dashboard and control centre open"> | <img src="docs/images/theme-tide.jpg" alt="Indigo theme with round corners, weather page open"> |

## Updates

The `.dmg` build keeps itself up to date: it checks once a day in the
background, downloads a new version when it finds one, and installs it the
next time the app quits. The menu bar item also offers **Restart to Update**
as soon as an update is waiting, because a shell rarely quits on its own.
Both switches are on by default and can be turned off on the **Updates** tab
of the Nexus panel.

A Homebrew install belongs to Homebrew, so ApolloShell never replaces itself
there. It says when a new version is out; you install it with:

```sh
brew upgrade apolloshell
```

## Shortcuts

Nothing is on a key out of the box: ApolloShell takes no keystrokes until you
give it some. The introduction offers the launcher one, and **Shortcuts…** in
the menu bar item sets the rest. It has two presets:

| Opens | Control and Option | Launcher on fn |
| --- | --- | --- |
| Launcher | ⌥Space | F20 |
| Dashboard | ⌃⌥D | ⌃⌥⇧⌘D |
| Control centre | ⌃⌥U | ⌃⌥⇧⌘U |
| Nexus menu | ⌃⌥, | ⌃⌥⇧⌘, |

"Launcher on fn" fits Karabiner-Elements turning a tapped fn into F20 and a
held key into ⌃⌥⇧⌘. Installs from before 0.2 keep the shortcuts they had.

## Good to know

**Permissions.** A short welcome guide walks you through them on first launch.

- *Accessibility* keeps windows out of the sidebar and powers the dock's window
  list. Without it, ApolloShell still runs, but windows can slide under the
  sidebar.
- *Automation → System Events* is only used to log out, restart and shut down.
- *Keep awake with the lid closed* needs admin rights once. ApolloShell then
  adds a rule to `/etc/sudoers.d/apolloshell` that allows only
  `pmset -a disablesleep 1` and `0`. You can remove it from the menu bar item.

**Privacy.** No telemetry, no accounts. The only network traffic is weather:
the place you picked goes to Open-Meteo, MET Norway or wttr.in. Settings live
in `~/Library/Application Support/ApolloShell/`. Delete that folder to reset
everything.

**Apple's Dock.** "Hide Apple's Dock" in the menu bar item hides it while
ApolloShell runs. It comes back when ApolloShell quits.

**Tiling window managers.** None of ApolloShell's windows is a standard
window: they carry a subrole of their own, sit on their own window level and
cannot be moved by another app. AeroSpace, yabai and Amethyst each skip
windows like that by their own rules, so they do not get tiled, and Rectangle
only ever touches the focused window, which these never are. The other way
round, the strip ApolloShell keeps clear for its sidebar only moves standard
windows, so it leaves another bar alone.

Give your window manager a gap of the bar's width, though. ApolloShell tries
to push a window out of the strip, but it gives up after a few attempts
rather than fight your tiler over the same window - so without a gap, tiled
windows end up 44 pt underneath the bar. In yabai that is
`yabai -m config left_padding 44`, in AeroSpace `outer.left = 44`.

**Private interfaces.** Spaces, fullscreen detection, Night Shift, dark mode,
window lists and "now playing" use undocumented macOS APIs (SkyLight,
CoreBrightness, HIServices, MediaRemote through [mediaremote-adapter][mra]).
ApolloShell checks for them at launch and turns a feature off if one is
missing. That's also why it can't be in the Mac App Store.

**After an update Accessibility stops working?** Remove ApolloShell from the
list in System Settings, add it again and restart it.

## Credits

- [Caelestia shell][caelestia] for the design. No code is copied, and this
  project isn't affiliated with it.
- [mediaremote-adapter][mra] by ungive (BSD-3-Clause) for "now playing".
- Weather from [Open-Meteo][open-meteo] and [MET Norway][met] (both
  CC BY 4.0) and [wttr.in][wttr].

Full notices are in [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md).

## AI disclosure

<img src="https://img.shields.io/badge/Core-written%20by%20humans-2EA44F" alt="Core written by humans">
<img src="https://img.shields.io/badge/Refactored%20with-Claude%20Fable%205.1-D97757?logo=claude&amp;logoColor=white" alt="Refactored with Claude Fable 5.1">

The core was written by me and two friends in our free time. I do most of
the work; my friends help out. Since then the code has been refactored
several times with Claude (Fable 5.1), and we ran large multi-agent bug hunts
with it.

This stays the same for new releases:

| Part | Done by |
| --- | --- |
| New features | Us |
| Refactoring and bug hunts | Claude |
| Patch releases (fixes only) | Claude |
| Commits and code comments | Claude |

## License

[Mozilla Public License 2.0](LICENSE) © 2026 Silvertree2010. You can use
ApolloShell in your own work, open or closed; changes to its own files stay
under the MPL and have to be shared when you distribute them. Versions up to
0.1.3.1 were released under MIT and stay under MIT. Contributions are
welcome, see [CONTRIBUTING.md](CONTRIBUTING.md).

[releases]: https://github.com/Silvertree2010/ApolloShell/releases/latest
[caelestia]: https://github.com/caelestia-dots/shell
[mra]: https://github.com/ungive/mediaremote-adapter
[open-meteo]: https://open-meteo.com/
[met]: https://api.met.no/
[wttr]: https://wttr.in/

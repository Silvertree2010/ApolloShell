# ApolloShell 0.2.0: moving over from 0.1

0.2 rebuilds ApolloShell as a framework. Everything you see is now a config:
KDL files that say what exists and what happens, and a CSS file that says how
it looks. The built-in config, `apolloshell-default`, looks and behaves like
0.1.4.2. Nothing has to be done by hand for the update.

## Updating

The `.dmg` build gets 0.2.0 as a normal update. The certificate and bundle ID
are unchanged, so the Accessibility permission stays. Homebrew users run
`brew upgrade apolloshell` as usual.

## Where your settings live now

| What | 0.1.4.2 | 0.2.0 |
| --- | --- | --- |
| Settings | `~/Library/Application Support/ApolloShell/settings.json` | `~/.config/apolloshell/state/apolloshell-default.kdl` |
| Chosen theme and config | `settings.json` | `~/.config/apolloshell/settings.kdl` |
| Weather places | `~/Library/Application Support/ApolloShell/weather.json` | `~/.config/apolloshell/state/apolloshell-default.kdl` |
| Themes | `~/Library/Application Support/ApolloShell/themes/` | `~/.config/apolloshell/themes/` (the old folder is still read) |
| Launcher favourites and ranking | `pinned.json`, `usage.json` | unchanged, still read from Application Support |
| Your own configs | - | `~/.config/apolloshell/configs/<name>/` |

If `XDG_CONFIG_HOME` is set, `~/.config` above is that folder instead.

All files are plain text. `apollo config path` prints the folder of the
active config, `apollo config fork apolloshell-default <name>` copies the
built-in config so you can change it, and `apollo config select <name>`
switches to it.

## What is carried over once

On the first start of 0.2, if `settings.json` exists and
`~/.config/apolloshell/state/` does not, ApolloShell copies your settings
over one time:

- Every setting from `settings.json` becomes a saved value of the default
  config, including the sidebar layout. Block names change from camelCase to
  kebab-case (`dashboardButton` becomes `dashboard-button`).
- Weather favourites and the selected place from `weather.json`.
- The chosen theme goes to `settings.kdl`.
- If launcher-only mode was on, `settings.kdl` selects the built-in
  `launcher-only` config, and a custom launcher shortcut is kept for it.

A block the new version does not know, or a value of the wrong type, is
skipped and listed in "Show Problems"; the default applies there. After the
first start, changes to the old files are not read again.

## Going back

The old files are left untouched. Installing 0.1.4.2 again picks up the
settings you had before the update; changes made in 0.2 do not go back with
it.

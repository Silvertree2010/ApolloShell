# Security policy

## Supported versions

Only the latest release gets security fixes. ApolloShell is maintained by one
person in their spare time, so fixes land in the next release rather than as
backports.

## Reporting a vulnerability

Please do **not** open a public issue. Report it privately instead:

1. Open the repository's **Security** tab.
2. Click **Report a vulnerability**.
3. Describe the problem, the affected version, and how to reproduce it.

You will get an answer as soon as possible, usually within a week. Once a fix
is released, the advisory is published and you are credited unless you prefer
not to be. There is no bug bounty.

## What is in scope

Parts that deserve a closer look:

- **Keep awake with the lid closed.** ApolloShell can add
  `/etc/sudoers.d/apolloshell`, a rule that lets the current user run
  `/usr/bin/pmset -a disablesleep 1` and `0` without a password. Anything that
  widens this rule, or lets another user or process abuse it, is in scope.
- **Theme files.** Themes are read from
  `~/Library/Application Support/ApolloShell/themes` and may come from other
  people. A theme must never crash the app, read files outside its own folder,
  or load anything from the network. See [docs/THEMES.md](docs/THEMES.md).
- **Commands the app runs**, such as `pmset`, `osascript`, `shortcuts` and the
  bundled Now Playing helper.
- **Files the app writes** in `~/Library/Application Support/ApolloShell` and
  the Apple Dock preferences it changes.

Out of scope: problems that need an attacker who already controls your user
account, and the private macOS interfaces themselves (report those to Apple).

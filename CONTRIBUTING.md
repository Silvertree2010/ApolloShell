# Contributing

Thanks for your interest! Bug reports, ideas and pull requests are welcome.
Please open an issue before large changes, so we can agree on the direction
first.

## Building and testing

You need macOS 26 and the Command Line Tools with the macOS 26 SDK
(`xcode-select --install`). Xcode is not needed; there is no Xcode project.

```sh
# Build (the SDK pin matters: newer Command Line Tools default to an SDK
# that does not match their Swift compiler)
SDKROOT=/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk \
  swift build -c release --product ApolloShell

# Tests (Swift Testing; test.sh adds the search paths the CLT need)
./test.sh

# Build, sign and install to ~/Applications, restart a running copy
./build.sh

# Universal disk image into dist/
scripts/make-dmg.sh
```

- If the build complains about a *precompiled file* and the *module cache
  path*, remove the build folder with `rm -rf .build` and build again.
- For a stable signature, run `scripts/setup-signing.sh` once. It keeps the
  Accessibility grant across rebuilds (see the README).

## Project layout

| Path | What is in it |
| --- | --- |
| `Sources/ApolloShellCore` | UI-free logic: layouts, settings, weather parsing, ranking, geometry. Everything here should have tests. |
| `Sources/ApolloShell` | The app: AppKit windows and SwiftUI views, system integration |
| `Tests/ApolloShellCoreTests` | Swift Testing tests for the core |
| `extras/mediaremote-adapter` | Bundled third-party code (BSD-3-Clause), kept unmodified |
| `scripts/` | Build helpers: signing, adapter, app bundle, icon, DMG |
| `Support/` | `Info.plist` and the app icon |
| `packaging/homebrew` | Homebrew formula template |

## Code style

- Swift 6 language mode with strict concurrency. UI code runs on the main
  actor.
- Put logic into `ApolloShellCore` and test it there. Keep views thin.
- **Code comments are in German** for now; English comments are welcome in new
  code. Comments explain *why*, not *what*.
- **UI text is written in German in the code** and translated through
  `Support/Localization` (see [Translations](#translations)). Every new UI
  string needs an English entry.
- Load private macOS interfaces with `dlopen`/`dlsym`, check that they exist,
  and fall back or switch the feature off when they are missing. Never crash
  because Apple changed something.
- Check UI changes visually. Render views off-screen (an `NSHostingView` in a
  borderless window that is never shown, then `cacheDisplay`), or run the
  app. Green tests alone don't prove a view looks right.
- No personal data in code, tests or screenshots. Use neutral examples such as
  "Berlin" or "Alex".

## Translations

German is the source language. The German text in the code is the key, and
each translation is a set of `Support/Localization/<language>/*.strings` files
(`"Deutsch" = "English";`). For a new language:

1. Copy `Support/Localization/en` to your language code, for example `es`.
2. Translate the right-hand side. Keep placeholders such as `%@` and `%lld`.
3. Add the code to `CFBundleLocalizations` in `Support/Info.plist` and to the
   language picker (`AppLanguage.swift`).
4. Have `scripts/assemble-app.sh` copy the new folder too (`build.sh` uses it).

New UI text needs an English entry. `python3 scripts/check-l10n.py` lists what
is missing.

## Pull requests

- Keep each pull request to one topic, with a short description of what
  changed and why.
- `./test.sh` must pass.
- For visible changes, add a before/after screenshot.
- Update `CHANGELOG.md` under *Unreleased*.

By contributing, you agree that your contributions are licensed under the MIT
License of this project.

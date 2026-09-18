# Automatic updates (0.1.2)

Status: shipped in 0.1.2 on 2026-09-17. Kept as the record of why it is
built this way; the code is the truth now.
Date: 2026-09-17.

## Goal

ApolloShell keeps itself up to date with as little work for the user as
possible: it checks daily, downloads in the background, and installs the new
version when the app next quits. People who installed through Homebrew are
told that a new version exists and are given the command that upgrades it.

## Non-goals

- Notarisation or an Apple Developer ID. The first launch of a downloaded
  build still needs the usual confirmation in System Settings.
- Delta updates, beta channels, rollbacks, in-app release note rendering
  beyond a link.
- Updating the app while it runs. An update always ends in a restart of the
  shell.

## Constraints that shaped the design

1. **The Accessibility grant is bound to the code signature.** macOS matches
   the grant against the app's designated requirement. Ad-hoc signatures
   contain only the binary hash, which changes with every build, so every
   update would silently drop the window guard. A fixed signing certificate
   keeps the requirement stable across versions - the same reason
   `scripts/setup-signing.sh` exists for local builds.
2. **Two install paths.** The DMG carries a finished app; the Homebrew
   formula builds from source into the Cellar. An app that replaces itself
   inside the Cellar breaks Homebrew's bookkeeping, and the next
   `brew upgrade` overwrites the update.
3. **ApolloShell is an agent app** (`LSUIElement`) started by launchd and
   practically never quits, so "install on quit" alone would delay updates
   until the next logout.
4. **No paid certificate.** Sparkle accepts an update when the EdDSA
   signature is valid; the Apple code signature then only has to be valid,
   not to match the old one (`SUUpdateValidator.m`, Sparkle 2.10.0). Ad-hoc
   and self-signed builds both work. Key rotation, however, relies on a
   matching Apple signature, so a lost EdDSA key can never be replaced for
   installations already out there.

## Decisions

| # | Decision | Alternative rejected |
|---|----------|----------------------|
| D1 | Sign releases with a dedicated self-signed certificate, `ApolloShell Release Signing`, 20 years, private key held as a GitHub secret. | Staying ad-hoc: the Accessibility grant would have to be given again after every update. |
| D2 | Check daily, download in the background, install on quit, all on by default, plus an explicit "restart now" action. | Asking before every download: slower for the user, and the app rarely quits on its own. |
| D3 | One build for both install paths. The formula drops a marker file into the bundle; the app disables Sparkle when it finds it. | A second build without Sparkle: two build variants to keep working, for a framework that costs a few megabytes. |
| D4 | The appcast is a release asset, fetched through `https://github.com/Silvertree2010/ApolloShell/releases/latest/download/appcast.xml`. | GitHub Pages: CI would have to push to protected `main` for every release. |
| D5 | The DMG is the only release artifact; Sparkle installs from it. | A separate ZIP for Sparkle: two artifacts to sign and keep in step. |
| D6 | Release signing and publishing run in CI, triggered by a `v*` tag only. | Releasing from the local Mac: no keys leave the machine, but every release is a manual run. |

## Architecture

### ApolloShellCore (no UI, tested)

- `AppVersion` - parses `CFBundleShortVersionString` style versions and
  compares them. Used for the Homebrew hint and for tests.
- `InstallKind` - `.disk` or `.homebrew`. Decided by the presence of
  `Contents/Resources/installed-by-homebrew` inside the bundle, written by
  the formula during `install`. No path guessing.
- `HomebrewUpdateCheck` - asks
  `https://api.github.com/repos/Silvertree2010/ApolloShell/releases/latest`
  for the newest tag, compares it against the running version, and returns
  either "current" or the new version plus the upgrade command. Parsing is
  tested against a stored sample response; the network call sits behind a
  small protocol so tests never touch the network.
- `UpdatePreferences` - the two switches (check automatically, install
  automatically) and the timestamp of the last check, stored in
  `ShellSettings`, mirrored into Sparkle's own defaults keys.

### ApolloShell (UI layer)

- `UpdateController` - a thin wrapper around `SPUStandardUpdaterController`.
  Created only when `InstallKind == .disk`. It exposes: check now, the state
  (idle, checking, downloading, ready to install), and "install and
  restart". It implements `SPUStandardUserDriverDelegate` with
  `supportsGentleScheduledUpdateReminders` so nothing steals focus in an
  agent app.
- `NexusUpdatesPage` - current version, last check, the two switches, a
  check-now button, a link to the release notes. Under Homebrew the switches
  are replaced by the upgrade command with a copy button.
- Bar hint - when an update is downloaded and waiting, the session menu and
  Nexus show "Update ready - restart now". Ignoring it is fine: the update
  goes in at the next logout.

### Bundle and packaging

- `Package.swift` gains Sparkle 2.10.0 as a binary dependency of the
  `ApolloShell` target. `ApolloShellCore` stays dependency-free.
- `scripts/assemble-app.sh` copies `Sparkle.framework` into
  `Contents/Frameworks`, signs it before the app, and sets the runpath.
- `Support/Info.plist` gains `SUFeedURL`, `SUPublicEDKey`,
  `SUEnableAutomaticChecks = true`, `SUAutomaticallyUpdate = true`,
  `SUScheduledCheckInterval = 86400`.
- `packaging/homebrew/apolloshell.rb` writes the marker file after
  `assemble-app.sh` and keeps building from source as before. Homebrew
  allows network access during `install` by default
  (`DEFAULT_NETWORK_ACCESS_ALLOWED = true`), so SwiftPM can fetch Sparkle.

### Release workflow

`.github/workflows/release.yml`, triggered by `push: tags: v*` only, never by
pull requests, so no fork can reach the secrets:

1. Import the release certificate from the secret into a temporary keychain.
2. Build the universal DMG with `scripts/make-dmg.sh`, with `SIGN_IDENTITY`
   set to the release certificate, so the app inside is signed with it.
3. Sign the DMG with Sparkle's `sign_update` and the EdDSA key.
4. Generate `appcast.xml` with the version, the release notes link and the
   signature.
5. Create the GitHub release with the DMG and `appcast.xml` attached.
6. Update the tap: new URL and `sha256` in `apolloshell.rb`, pushed with a
   token that is scoped to the tap repository.

Secrets: `RELEASE_CERT_P12` (base64), `RELEASE_CERT_PASSWORD`,
`SPARKLE_EDDSA_KEY`, `TAP_TOKEN`.

A new script, `scripts/make-release-cert.sh`, creates the certificate and
exports the `.p12`, following `setup-signing.sh`. The EdDSA key pair is
created once with Sparkle's `generate_keys`. Both private keys are backed up
outside GitHub before the first release.

## Testing

- Unit tests in `ApolloShellCoreTests` for `AppVersion`, `InstallKind` and
  `HomebrewUpdateCheck` (sample response, no network).
- The existing l10n check covers the new interface strings.
- One end-to-end run in the VM before the release is published: install
  0.1.2, publish a 0.1.3 test build, watch the daily check, the background
  download, the restart, the Accessibility grant surviving it, and that the
  updated app starts without a Gatekeeper prompt - Sparkle takes the
  quarantine flag off what it installs.
- Homebrew path: `brew install --build-from-source`, then verify the marker
  file exists, Sparkle stays off, and the hint shows the upgrade command.

## Rollout

- 0.1.2 is the first version that can update itself; it has to be installed
  by hand or through Homebrew like every version before it.
- The Accessibility grant has to be given once more on the step to 0.1.2,
  because the signature changes from ad-hoc to the release certificate. The
  onboarding and the release notes say so.
- README, README.de and CHANGELOG document that checks and installs are on
  by default and where to switch them off.

## Risks

- **Lost EdDSA key** - existing installations can never be updated
  automatically again. Mitigated by an offline backup.
- **GitHub account compromise** - both signing keys live there, so an
  attacker could publish an update that users install silently. Mitigated by
  2FA, a tag-only workflow, and a tap token scoped to one repository.
- **Certificate expiry** - the grant resets once when the certificate is
  replaced. Mitigated by a 20 year validity.
- **Sparkle upgrade breaking the build** - the dependency is pinned to an
  exact version; CI builds both architectures.

# Window managers and bars: what is measured, what needs a VM

Spec section 4 ("bombenfest") asks for a live test with AeroSpace and yabai
before 0.2.0 goes out. That test needs a macOS VM, which this machine has no
room for yet (see below). Everything that can be decided without one is
decided here, by measurement, in the invisible self-test
(`--selftest-edit`, section "window manager safety", 20 checks).

## What the three tilers actually look at

Read from their source, not from their documentation:

| Tool | Manages a window when | Source |
| --- | --- | --- |
| yabai | role `AXWindow` **and** subrole `AXStandardWindow`, on the normal window layer. `AXUnknown` is skipped outright. | `src/window.c`, `window_is_standard`, `window_is_real`, `window_is_unknown` |
| Amethyst | the window is movable **and** its subrole is `AXStandardWindow` | `Amethyst/Model/Window.swift`, `shouldBeManaged()` |
| AeroSpace | sorts every window into popup / dialog / window via `getAxUiElementWindowType(windowId, windowLevel, …)`; a window on a level of its own lands in the popup container and is never tiled | `Sources/AppBundle/tree/MacWindow.swift` |
| Rectangle | acts only on the focused window, on a keystroke | its own design; none of our panels can become key |

## What ApolloShell's windows report (measured 20.09.2026)

| Window | Role | Subrole | Level | Movable |
| --- | --- | --- | --- | --- |
| Scrim | AXWindow | AXUnknown | 100 | no |
| Toolbar, gallery | AXWindow | AXUnknown | 103 | no |
| Dashboard, control centre (pinned) | AXWindow | AXUnknown | 101 | no |
| Dashboard, control centre (calm) | AXWindow | AXSystemDialog | 101 | no |
| Bar | AXWindow | AXSystemDialog | 3 (101 while editing) | no |

None of them is a standard window, none is movable, none stands on the
normal level. So all three tilers skip every one of them by their own
rules. The self-test asserts exactly that, on every window, both while
editing and outside it, so a new window or a changed flag trips it.

Unpinned drawers used to hand back `nil` as their subrole, which left
AppKit's default to be guessed at. They now say `AXSystemDialog`, the value
AppKit gives a panel like this anyway (the bar, which sets nothing, reports
it).

## The other direction: ApolloShell moving other people's windows

`WindowGuard` keeps a 44 pt strip clear for the bar by moving windows out of
it. It only ever touches windows whose subrole is `AXStandardWindow` and
whose position is settable (`WindowGuard.swift:455`, `:474`), so a bar of
another kind (SketchyBar, Übersicht) and the panels of other shells are out
of its reach by the same rule that keeps ours out of yabai's.

What that rule does **not** settle: a tiling manager and `WindowGuard` both
move standard windows. yabai places a window into the strip, `WindowGuard`
pushes it out, yabai places it back. Whether that ends in a ping-pong is a
question of timing, not of flags - it cannot be answered by reading code,
and it is the first thing the VM test has to try.

## What still needs the VM

1. yabai (with SIP off) and AeroSpace, each with the bar visible: does the
   strip fight the tiler? Is a window ever left standing in the strip, or
   moved back and forth?
2. Edit mode under both: does the scrim stay over every screen, do toolbar
   and gallery stay put, does Esc still arrive when another app has focus?
3. Amethyst and Rectangle: shortcuts while the mode runs.
4. A third-party bar (SketchyBar, Übersicht) at the same time: who draws
   above whom, does the sidebar overlap it?
5. Stage Manager on, and a full-screen app on a second space.

### How to set it up

Room is there since the evening of 20.09.2026 (207 GB free). What is left is
the part a person has to do, because none of it can be driven without a
screen: macOS' Setup Assistant, and granting Accessibility to a window
manager. Both are GUI, and the guest's window would be on the host's screen.

The shortest path:

1. `brew install cirruslabs/cli/tart`
2. `tart clone ghcr.io/cirruslabs/macos-sequoia-base:latest compat` - a
   prebuilt guest with SSH already on, so the Setup Assistant is done. (An
   `tart create --from-ipsw` guest is Apple's own image, but then step 1 of
   the assistant has to be clicked through by hand.)
3. `tart run compat` once, then `ssh admin@$(tart ip compat)` for everything
   after that.
4. In the guest: `brew install --cask nikitabobko/tap/aerospace amethyst
   rectangle`, `brew install koekeishiya/formulae/yabai FelixKratz/formulae/sketchybar`.
   yabai tiles without disabling SIP; only its scripting addition needs
   that, and the tests below do not.
5. Accessibility for AeroSpace, Amethyst and Rectangle: System Settings in
   the guest, by hand. There is no way around it with SIP on.
6. Copy ApolloShell in (`scp -r "build/ApolloShell.app" admin@…:~/Applications/`)
   and start it.

Then work through the five points above. The first one is the one worth the
whole setup: turn the bar on, let yabai tile a window into the strip, and
watch whether it ends up moved back and forth.

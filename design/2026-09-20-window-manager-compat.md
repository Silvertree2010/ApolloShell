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

## The VM test, run on 20.09.2026

Guest: macOS 26.6.2 in a tart VM (`ghcr.io/cirruslabs/macos-tahoe-base`),
1024 x 768 pt, ApolloShell 0.2.0 (build 286) out of `build/ApolloShell.app`,
next to yabai, AeroSpace, Amethyst, Rectangle and SketchyBar.

1. **The strip and a tiling manager do not fight.** yabai in `bsp` tiles its
   windows to `x = 0`, under the bar. `WindowGuard` pushes a window out of
   the strip within about half a second when nothing else moves it (measured:
   `0,100` becomes `44,100`), but against yabai it gives up: the ledger in
   `WindowClamp` allows three attempts in five seconds and then keeps quiet
   (`ClampLedger(maxAttempts: 3, period: 5)`). Ten seconds of sampling show
   no oscillation, and both processes stay at 0.0 % CPU.

   What is left over is the other half of it: with a tiling manager the
   windows stand **under** the bar, and 44 pt of them are covered. That is
   not a fight, it is a setting the person has to make - yabai
   `left_padding 44`, AeroSpace `outer.left = 44`. It belongs in the readme,
   not in the code.
2. **The edit mode holds up under a window manager.** Scrim over the whole
   screen, dashboard, control centre, toolbar and the bar all in place, the
   bar with its `-` badges. Esc closes the gallery first, the second Esc
   ends the mode and brings Nexus back. Nothing of the mode was tiled,
   moved or hidden.
3. **Rectangle's shortcut does not reach it.** With the mode running,
   ctrl-alt-left moved nothing of the shell: its panels never become the
   focused window, which is the only thing Rectangle acts on.
4. **SketchyBar alongside** changes nothing about the mode; it draws where
   it draws, below the scrim.
5. **On a 1024 pt screen the gallery cannot keep clear of the control
   centre.** It steps as far left as it can and then stands over the panel:
   760 pt of gallery do not fit beside 430 pt of panel on 1024 pt of
   screen. Staying on the screen wins, which is what
   `EditModeGeometry.galleryCenter` decides. A gallery that shrinks on a
   narrow screen would be the real answer - an open question, not a bug.

Not tried: Amethyst (installed, not driven), Stage Manager, a second space
in full screen.

### How the VM was set up

The prebuilt image turned out to have SIP switched off, which settled the
part that looked like it needed a pair of hands: the Accessibility grants
went into the guest's TCC database directly, and the guest's own screen was
driven over SSH with `osascript` and read back with `screencapture` - the
host's screen was never touched.

The path:

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

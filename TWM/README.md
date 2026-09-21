# ApolloWM

A tiling window manager framework for macOS, modeled on Hyprland. It will
become part of ApolloShell.

ApolloWM is headless: it arranges, moves and animates windows. Anything
visible (bars, menus, overlays) belongs to the host app.

## Layout

- `ApolloWMCore` — pure logic: dwindle layout tree, springs, stats. Tested.
- `ApolloWM` — macOS glue: Accessibility windows, mouse tracking, animation loop.
- `apollowm-probe` — measurement tool for the drag-and-glide spike.

## Build and test

    swift build
    ./test.sh    # plain `swift test` misses Swift Testing without Xcode

## Probe

Needs Accessibility access for the terminal it runs in.

    .build/debug/apollowm-probe bench   # animate, measure, verify, restore
    .build/debug/apollowm-probe run     # live: drag windows, Ctrl+C restores

`APOLLOWM_TRACE=1` prints every drag decision to stderr.
`--resize proxy|smooth|snap` picks how sizes animate (default `proxy`).

## Host settings

`TilingEngine.options` can change at runtime, e.g. from a settings UI:

- `resize` — `.proxy` (a snapshot glides and stretches, the app resizes once
  off screen; smooth and cheap, needs Screen Recording), `.smooth` (size
  glides, apps redraw every frame, more GPU) or `.snap` (only position
  glides, size jumps once).
- `reserved` — screen edges the host keeps free (ApolloShell sidebar: left 44).
- `gaps`, `response` — spacing and glide duration.

`FocusFollowsMouse` (the window under the mouse is raised and focused):

- `isEnabled` — on or off.
- `delay` — how long the mouse must rest over a window first
  (default 0.025 s; probe: `--focus-delay MS`).
- `disableFlags` — modifier keys that suspend it while held (default none).

## Keys (Super = fn held, which Karabiner sends as cmd+ctrl+opt+shift)

| Keys | Action |
|---|---|
| Super + arrows | focus the neighbor window in that direction |
| Super + H / J / K / L | swap with the neighbor left / down / up / right |
| Super + Tab | focus the next window |
| Super + T | turn the split (side by side / stacked) |
| Super + - / = | narrower / wider by 5 % |
| Super + E | all splits back to half and half |
| Super + Return | new terminal window (kitty, Ghostty or Terminal) |
| Super + Space | float / tile |
| Super + F | fill the area (not macOS fullscreen) |
| Super + Q | close the window |
| Super + 1-9 | Apple desktop 1-9 |
| Super + left drag | move a window from anywhere |
| Super + right drag | resize from the nearest corner |

All bindings live in `KeyBindings.bindings` and can be changed by the host.

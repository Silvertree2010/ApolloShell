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

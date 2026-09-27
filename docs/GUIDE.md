# Writing your first config

This guide builds a config from nothing in five small steps. Every step is a
complete config in [examples/configs](../examples/configs); the test suite
loads each one and fails on any warning, so what you read here works.

A config is a folder with a `shell.kdl` and usually a `style.css`. Put it in
`~/.config/apolloshell/configs/<name>/`, then switch to it:

```sh
apollo config select <name>
apollo check ~/.config/apolloshell/configs/<name>
```

Saving a file reloads the shell. Mistakes show up with file, line and a
suggestion, and the rest keeps working.

## 1. A surface with live data

[01-hello](../examples/configs/01-hello/shell.kdl) puts a clock on the desktop.

```kdl
style "style.css"

panel "hello" anchor="top-right" layer="desktop" click-through=#true {
    column class="card" {
        text "{clock.now | date 'HH:mm'}" class="time"
        text "{clock.now | date 'EEEE, d MMMM'}"
        when "{battery.present}" {
            text "Battery {battery.percent | percent}"
        }
    }
}
```

- A **surface** (`panel`, `popup`, `window`, …) is a window of the shell.
  `panel` is always visible.
- `column` and `row` stack their children; `text` shows a string.
- Anything in `{…}` is an **expression**. `clock.now` and `battery.percent` are
  fields of **providers**; the shell starts a provider only while something
  reads it and updates the text when the value changes.
- `|` passes a value through a **filter**: `date` formats a date, `percent`
  turns 0.42 into “42 %”. `date` also takes a time zone:
  `{clock.now | date 'HH:mm' 'Asia/Tokyo'}`.
- `when` creates its children only while the condition is true.
- `class` connects the node to `style.css`, which is plain CSS with the
  theme's tokens such as `var(--apollo-card-fill)`.

## 2. State and actions

[02-state](../examples/configs/02-state/shell.kdl) adds a button that shows
more or less.

```kdl
var expanded #false persist=#true

panel "status" anchor="bottom-left" {
    column class="card" {
        button class="header" {
            on-click { toggle-var "expanded" }
            text "{var.expanded ? 'Less' : 'More'}"
        }
        when "{var.expanded}" {
            text "CPU {perf.cpu | percent}"
            text "Memory {perf.memory | percent}"
        }
    }
}
```

- `var` declares state; `persist=#true` keeps it across restarts. Read it as
  `var.expanded`. A misspelled name is reported when the config loads.
- `on-click { … }` is a **handler**; inside it go **actions** such as
  `toggle-var`, `set "expanded" #true`, `open "surface"` or `notify title="Hi"`.
- `?:`, `??`, `&&`, `||`, `+` and friends work as in most languages.

## 3. Lists

[03-lists](../examples/configs/03-lists/shell.kdl) shows one button per running
app.

```kdl
panel "running" anchor="left" {
    column class="apps" {
        each app in="{apps.running}" key="{app.bundle-id}" {
            button class="app" checked="{app.active}" tooltip="{app.name}" {
                on-click { apps.launch "{app}" }
                app-icon "{app}"
            }
        }
    }
}
```

- `each` repeats its body for every entry; `app` is the entry.
- `key` tells the shell which entry is which, so a reordered list moves
  existing elements instead of rebuilding them.
- `checked` sets the `:checked` pseudo-class, which `style.css` can style.

## 4. Your own components

[04-components](../examples/configs/04-components/shell.kdl) defines a
component once and uses it three times.

```kdl
define "stat" {
    param "label"
    param "value"
    row class="stat" {
        text "{label}" class="stat-label"
        text "{value}" class="stat-value"
    }
}

panel "stats" anchor="bottom-right" {
    column class="card" {
        use "stat" label="CPU" value="{perf.cpu | percent}"
        use "stat" label="Memory" value="{perf.memory | percent}"
        use "stat" label="Down" value="{perf.net-down | bytes-per-second}"
    }
}
```

`define` declares parameters with `param`; `use` fills them. A define whose
body is a list of actions can be used inside a handler, too.

## 5. Popups, shortcuts and your own data

[05-popups](../examples/configs/05-popups/shell.kdl) opens a popup with a
keyboard shortcut and shows the output of a command.

```kdl
var hotkey "ctrl+alt+space" persist=#true

poll "uptime" command="uptime" interval="60s"

bind "{var.hotkey}" { emit "show-info" }

on "user.show-info" { toggle "info" }

popup "info" anchor="center" motion="grow" {
    column class="card" {
        text "Uptime" class="title"
        text "{poll.uptime ?? '…'}"
        button class="close" {
            on-click { close "info" }
            text "Close"
        }
    }
}
```

- A `popup` opens and closes on actions (`open`, `close`, `toggle`) and closes
  by itself on a click outside or Escape.
- `bind` runs actions on a keyboard shortcut.
- `emit "show-info"` sends the event `user.show-info` to your own `on`
  handlers. Put an action sequence there once and trigger it from buttons,
  shortcuts or the terminal with `apollo emit show-info`.
- `poll` runs a command every `interval` and exposes its output as
  `poll.<name>`; `format="json"` parses it. `listen` reads a long-running
  command line by line instead.

## Where to go next

- [CONFIG.md](CONFIG.md) lists every node, action, provider, filter and event.
- [THEMES.md](THEMES.md) explains the tokens and `-apollo-*` properties.
- `apollo config fork apolloshell-default mine` copies the built-in config,
  the largest example there is.

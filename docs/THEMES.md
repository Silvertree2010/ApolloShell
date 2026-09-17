# Themes

A theme is a CSS file. It sets a list of custom properties - *tokens* - that
the shell reads. There is no scripting, no layout, no selectors of your own:
a theme can change how ApolloShell looks, and nothing else.

The format is built to survive. A theme written today keeps working when the
shell grows twenty new features, because the rules below are promises, not
current behaviour.

## Where themes live

```
~/Library/Application Support/ApolloShell/themes/
├── Minimal.css            ← a theme in a single file
└── Everything/            ← a theme with files of its own
    ├── theme.css          ← must be called exactly this
    ├── background.png
    └── author.png
```

A theme is either

- a single `Name.css`, or
- a folder `Name/` containing `theme.css`.

The file or folder name is the theme's **identifier**. It is what the shell
remembers when you pick a theme, so renaming the file means picking the theme
again.

Only a folder theme can use images. A single file has no folder of its own,
and letting it reach into the themes folder would let it read its neighbours.

## Anatomy

```css
/* Comments are allowed anywhere. */
:root {
  --apollo-accent-color: #ff6b35;
  --apollo-corner-radius: 6px;
}

@media (prefers-color-scheme: dark) {
  :root {
    --apollo-accent-color: #ff8354;
  }
}
```

`:root` holds the theme. The `@media (prefers-color-scheme: dark)` block holds
only the values that differ in dark mode; everything else is inherited from
`:root`, exactly like in a browser. Tokens you do not mention keep their
built-in value - and the built-in value already differs between light and
dark, so a theme that only sets an accent colour still looks right in both.

### What is read, and what is skipped

Read:

- `:root { … }` blocks, as many as you like; the last value for a token wins
- `@media (prefers-color-scheme: dark) { :root { … } }`
- `/* comments */`
- `!important` (ignored, but tolerated)

Silently skipped:

- any other selector (`h1`, `:root:hover`, `*`)
- any other at-rule, including `@import`, `@supports` and other `@media`
  queries - a theme never loads a second file
- ordinary properties in `:root`, such as `color: red`
- custom properties outside our namespace, such as `--my-blue`

Not supported, on purpose: `var()`, calc, nesting, and anything that needs a
lookup chain. A value that contains `var(` counts as unreadable.

Everything that gets skipped, and every value that cannot be read, is
reported as a *note* with a line number. Notes never stop a theme from
loading.

## Value types

| Type | Accepted | Examples |
| --- | --- | --- |
| color | `#rgb`, `#rgba`, `#rrggbb`, `#rrggbbaa`, `rgb()`, `rgba()`, `hsl()`, `hsla()`, basic colour names, `transparent` | `#ff6b35`, `rgb(255 107 53 / 80%)`, `hsl(20, 100%, 60%)`, `red` |
| gradient | `none`, or `linear-gradient(<angle>, <colour> <position>, …)` | `linear-gradient(180deg, #101014, #2a2a33)` |
| length | a number with `px`, `pt` or no unit; `px` and `pt` are the same here, the shell works in points | `12px`, `12`, `0.5px` |
| ratio | a number from 0 to 1, or a percentage | `0.5`, `50%` |
| number | a plain number, no unit | `400` |
| text | a quoted string, or the text as written | `"Alex"`, `Inter` |
| file | `url("name.png")` or a quoted name, relative to the theme folder; `none` for nothing | `url("background.png")` |
| option | one of the listed words | `fill` |
| flag | `true`/`false`, `yes`/`no`, `on`/`off`, `1`/`0` | `true` |

Colours are stored with 8 bits per channel, the same precision they are
written with. Token names are matched case-insensitively, even though CSS
custom properties are normally case-sensitive.

### Gradients

Every gradient token sits next to a colour token and is `none` by default,
so a theme that only sets colours looks exactly as it did before. Set the
gradient and it paints that surface instead of the flat colour; the colour
still decides how text on it is checked for contrast.

```css
--apollo-bar-gradient: linear-gradient(180deg, #101014 0%, #2a2a33 100%);
```

- Only `linear-gradient` exists. `radial-gradient` and friends are not read;
  a theme that uses one gets a note and the flat colour.
- The angle follows CSS: `0deg` points up, `90deg` to the right. Words work
  too - `to bottom`, `to top right`. Leave it out and it runs top to bottom.
- Between two and eight colour stops. Positions are percentages and may be
  left out, and the colours are then spread evenly. A position that would
  step backwards is pulled up to the one before it.
- A gradient never makes a surface disappear: colours are clamped like every
  other colour, and `none` is always a valid value.

## Tokens

Every token and its type. **A token your theme does not mention changes
nothing** - that part of the shell stays exactly as it looks without a theme,
including the materials and the sizes you set in Nexus. The *Default* column
is what that built-in look amounts to, so you can start from it. *Dark* is the built-in value in dark mode, where it differs.
Numbers are clamped to the range in the type column.

<!-- The tables below are generated from the token catalogue in
     Sources/ApolloShellCore/ThemeTokens.swift and checked by a test. -->

### Metadata

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-theme-format` | number (1–1000000) | `1` |  | Format the theme was written for; higher numbers still load |
| `--apollo-theme-name` | text | `""` |  | Name shown in the theme list; empty means the file or folder name |
| `--apollo-theme-author` | text | `""` |  | Who made the theme |
| `--apollo-theme-description` | text | `""` |  | One line about the theme |
| `--apollo-theme-version` | text | `""` |  | Version of the theme itself, free text |
| `--apollo-theme-homepage` | text | `""` |  | Where the theme comes from; never opened or fetched by the core |
| `--apollo-theme-author-image` | file | `none` |  | Picture of the author, a file inside the theme folder |
| `--apollo-theme-appearance` | option (auto, light, dark) | `auto` |  | Which appearance the theme is made for; auto follows the system |

### Surfaces

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-background-color` | color | `#e8e8ed` | `#101014` | Desktop backdrop behind the shell |
| `--apollo-background-image` | file | `none` |  | Image behind the shell, a file inside the theme folder |
| `--apollo-background-image-opacity` | ratio (0–1) | `1` |  | How strongly the background image shows |
| `--apollo-background-fit` | option (fill, fit, stretch, tile, center) | `fill` |  | How the background image is placed |
| `--apollo-surface-color` | color | `#ffffff` | `#1c1c1e` | Base surface of windows and popovers |
| `--apollo-surface-opacity` | ratio (0–1) | `1` |  | How opaque surfaces are |
| `--apollo-background-gradient` | gradient | `none` |  | Gradient behind the shell instead of the flat backdrop colour |
| `--apollo-surface-gradient` | gradient | `none` |  | Gradient across surfaces instead of the flat surface colour |
| `--apollo-elevated-surface-color` | color | `#f5f5f7` | `#2a2a2d` | Surface of things that sit on top, such as menus |
| `--apollo-separator-color` | color | `#d8d8dc` | `#3a3a3d` | Hairlines between rows and sections |
| `--apollo-border-color` | color | `#d0d0d4` | `#3f3f43` | Outline around surfaces |
| `--apollo-border-width` | length (0px–8px) | `1px` |  | Thickness of that outline |
| `--apollo-shadow-opacity` | ratio (0–1) | `0.18` | `0.45` | How dark shadows under surfaces are |

### Text

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-text-color` | color | `#1c1c1e` | `#f5f5f7` | Main text |
| `--apollo-secondary-text-color` | color | `#6b6b70` | `#aeaeb2` | Subtitles and captions |
| `--apollo-muted-text-color` | color | `#8e8e93` |  | Text that should step back, such as hints |
| `--apollo-link-color` | color | `#0060df` | `#6cb6ff` | Links |
| `--apollo-on-accent-color` | color | `#ffffff` |  | Text and glyphs on accent coloured areas |

### Accent and state

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-accent-color` | color | `#007aff` | `#0a84ff` | Colour of selected and active things |
| `--apollo-secondary-accent-color` | color | `#5e5ce6` | `#7d7aff` | Second accent for charts and badges |
| `--apollo-accent-gradient` | gradient | `none` |  | Gradient for accent coloured areas instead of the flat accent colour |
| `--apollo-selection-color` | color | `#d6e4ff` | `#234a77` | Background of a selected row |
| `--apollo-hover-color` | color | `#00000014` | `#ffffff1a` | Tint under the pointer |
| `--apollo-success-color` | color | `#34c759` | `#30d158` | Everything is fine |
| `--apollo-warning-color` | color | `#c77700` | `#ffd60a` | Something needs attention |
| `--apollo-danger-color` | color | `#d70015` | `#ff453a` | Something went wrong |

### Sidebar

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-bar-color` | color | `#f5f5f7` | `#1c1c1e` | Backing of the sidebar |
| `--apollo-bar-gradient` | gradient | `none` |  | Gradient along the sidebar instead of the flat bar colour |
| `--apollo-bar-opacity` | ratio (0–1) | `1` |  | How opaque that backing is |
| `--apollo-bar-text-color` | color | `#1c1c1e` | `#f5f5f7` | Text in the sidebar, such as the clock |
| `--apollo-bar-icon-color` | color | `#3c3c43` | `#e5e5ea` | Status glyphs in the sidebar |
| `--apollo-bar-width` | length (36px–160px) | `44px` |  | Width of the sidebar |
| `--apollo-bar-radius` | length (0px–48px) | `16px` |  | Corner radius of the sidebar |
| `--apollo-bar-padding` | length (0px–48px) | `10px` |  | Space between sidebar edge and its blocks |
| `--apollo-bar-item-spacing` | length (0px–48px) | `8px` |  | Space between two blocks |
| `--apollo-bar-blur` | length (0px–64px) | `24px` |  | Blur behind the sidebar |

### Dock

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-dock-icon-size` | length (16px–128px) | `26px` |  | Size of the app icons |
| `--apollo-dock-spacing` | length (0px–48px) | `4px` |  | Space between two app icons |
| `--apollo-dock-indicator-color` | color | `#8e8e93` | `#aeaeb2` | Dot under a running app |

### Panels

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-panel-color` | color | `#ffffff` | `#1e1e20` | Backing of dashboard, utilities and popovers |
| `--apollo-panel-opacity` | ratio (0–1) | `1` |  | How opaque panels are |
| `--apollo-panel-radius` | length (0px–48px) | `20px` |  | Corner radius of panels |
| `--apollo-panel-padding` | length (0px–64px) | `16px` |  | Space inside a panel |
| `--apollo-panel-blur` | length (0px–64px) | `24px` |  | Blur behind panels |
| `--apollo-card-color` | color | `#f2f2f7` | `#2a2a2d` | Backing of a card in a panel |
| `--apollo-panel-gradient` | gradient | `none` |  | Gradient across a panel instead of the flat panel colour |
| `--apollo-card-gradient` | gradient | `none` |  | Gradient across a card instead of the flat card colour |
| `--apollo-card-radius` | length (0px–48px) | `14px` |  | Corner radius of a card |

### Launcher

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-launcher-highlight-color` | color | `#e5efff` | `#2a3c55` | Backing of the selected launcher row |
| `--apollo-launcher-highlight-gradient` | gradient | `none` |  | Gradient behind the selected launcher row instead of the flat colour |
| `--apollo-launcher-row-height` | length (24px–96px) | `44px` |  | Height of one launcher row |

### Typography

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-font-family` | text | `""` |  | Font for the whole shell; empty means the system font |
| `--apollo-monospace-font-family` | text | `""` |  | Font for numbers and code; empty means the system font |
| `--apollo-font-size` | length (8px–32px) | `13px` |  | Base text size |
| `--apollo-font-weight` | number (100–900) | `400` |  | Base text weight |

### Shape and motion

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-corner-radius` | length (0px–48px) | `12px` |  | Corner radius of everything without its own |
| `--apollo-control-radius` | length (0px–48px) | `8px` |  | Corner radius of buttons and fields |
| `--apollo-spacing` | length (0px–64px) | `12px` |  | Base spacing between elements |
| `--apollo-animation-speed` | number (0–3) | `1` |  | Factor on every animation; 0 means no animation |
| `--apollo-animations` | flag | `true` |  | Whether the shell animates at all |
| `--apollo-glass` | flag | `true` |  | Whether Liquid Glass is used where it fits |
| `--apollo-shadows` | flag | `true` |  | Whether surfaces cast a shadow |
| `--apollo-icon-style` | option (auto, monochrome, colorful) | `auto` |  | How status glyphs are drawn |

### Toasts

| Token | Type | Default | Dark | What it does |
| --- | --- | --- | --- | --- |
| `--apollo-toast-color` | color | `#1c1c1e` | `#f5f5f7` | Backing of a toast |
| `--apollo-toast-gradient` | gradient | `none` |  | Gradient across a toast instead of the flat toast colour |
| `--apollo-toast-text-color` | color | `#ffffff` | `#1c1c1e` | Text in a toast |
| `--apollo-toast-radius` | length (0px–48px) | `14px` |  | Corner radius of a toast |

## Icons

A theme folder may carry an `icons/` folder. The file name is the icon it
replaces, without the extension:

```
Nightfall/
├── theme.css
└── icons/
    ├── session-shutdown.png
    └── bar-power.png
```

What is not in there stays the built-in SF Symbol, so a theme can replace one
icon or all of them. File names are matched case-insensitively, a name this
version does not know is ignored and listed in Nexus, and the same rules as
for every other image apply: inside the theme folder, a supported type, and
within the size limit.

| File in `icons/` | Replaces | What it is |
| --- | --- | --- |
| `bar-dashboard` | `square.grid.2x2.fill` | Opens the dashboard |
| `bar-utilities` | `slider.horizontal.3` | Opens the control centre |
| `bar-clock` | `calendar` | Above the clock in the bar |
| `bar-power` | `power` | Opens the session menu |
| `bar-launcher` | `magnifyingglass` | Opens the launcher |
| `status-wifi` | `wifi` | Wi-Fi, when it is connected |
| `status-wifi-off` | `wifi.slash` | Wi-Fi, when it is off |
| `status-bluetooth` | `bluetooth` | Bluetooth, when it is on |
| `status-bluetooth-off` | `bluetooth.slash` | Bluetooth, when it is off |
| `status-battery` | `battery.100percent` | Battery |
| `status-battery-charging` | `battery.100percent.bolt` | Battery while charging |
| `status-volume` | `speaker.wave.2.fill` | Volume |
| `status-volume-muted` | `speaker.slash.fill` | Volume, when it is muted |
| `session-emblem` | the drawn emblem | The emblem in the middle of the session menu |
| `session-logout` | `rectangle.portrait.and.arrow.right` | Log out |
| `session-sleep` | `moon.fill` | Sleep |
| `session-restart` | `arrow.clockwise` | Restart |
| `session-shutdown` | `power` | Shut down |
| `toast-info` | `info.circle.fill` | A toast that just says something |
| `toast-success` | `checkmark.circle.fill` | A toast about something that worked |
| `toast-warning` | `exclamationmark.triangle.fill` | A toast that warns |
| `toast-error` | `exclamationmark.circle.fill` | A toast about a failure |
| `panel-media` | `music.note` | Media, and the placeholder without artwork |
| `panel-performance` | `speedometer` | The performance tab |
| `panel-weather` | `cloud.sun.fill` | The weather tab |
| `panel-cpu` | `cpu` | Processor load |
| `panel-memory` | `memorychip` | Memory in use |
| `panel-disk` | `internaldrive` | Disk in use |

## The compatibility promise

These are the rules ApolloShell holds itself to. Tests enforce each of them.

1. **A published token name never disappears.** If a token is renamed, the old
   name stays valid forever as an alias.
2. **New tokens only get added.** Their default is always the way the shell
   looks today, so an old theme that never heard of them looks unchanged.
3. **An unknown token is ignored, not an error.** It only produces a note.
   This is what makes a theme from a newer version usable on an older shell.
4. **A missing token falls back to its default**, per appearance.
5. **An unreadable value falls back to the default** (or to the last readable
   value of the same token) and produces a note with the line number.
6. **A broken file is still a theme.** Empty, truncated, binary, wrong
   encoding, far too large: the theme loads with defaults and a note. Nothing
   ever throws, nothing ever crashes.
7. **`--apollo-theme-format` is informational.** A theme that names a higher
   format than the shell knows is still read: known tokens apply, unknown ones
   are ignored, and a note says so. It is never rejected. The number only goes
   up if the meaning of an existing token changes - adding tokens does not
   change it.

## Safety

A theme is a file from the internet. It is treated like one.

- **Images only from the theme's own folder.** Relative paths, no `..`, no
  absolute paths, no `~`, no `http(s)`, no `file:`, no `data:`. Percent
  escapes are decoded *before* the check, so `%2e%2e` does not slip through.
- **Symlinks are resolved and checked again.** A link inside the theme folder
  that points anywhere else is refused.
- **Only image extensions** are accepted: png, jpg, jpeg, gif, heic, heif,
  webp, tiff, tif, bmp.
- **A single-file theme gets no files at all.**
- **Limits**: 512 KiB per style sheet, 8 MiB per image, 4096 declarations,
  200 characters per text token, 200 notes.
- **A theme cannot make the shell unusable.** Every number is clamped to the
  range in the table above, and every text colour is checked against the
  surface it sits on. A colour that would be unreadable is lightened or
  darkened until it reaches the required contrast (4.5:1 for body text, 3:1
  for secondary text and glyphs), per appearance, with a note. Colours that
  are already readable are left exactly as they are.

## Examples

Two themes to start from are in [`examples/themes`](../examples/themes):

- [`minimal.css`](../examples/themes/minimal.css) - a handful of colours in a
  single file.
- [`full/theme.css`](../examples/themes/full/theme.css) - every token with its
  default value, plus metadata and images. Copy it and change what you like.

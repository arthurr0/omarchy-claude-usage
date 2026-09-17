# Claude Usage for Omarchy

A bar widget for the [Omarchy](https://omarchy.org/) shell that shows how much
of your Claude subscription limits you have used: the rolling five-hour
session window, the weekly window and any model-scoped weekly windows. The bar
shows the busiest window (or all of them); the popup lists every window with a
meter and the reset countdown, and has a graphical settings page.

The numbers come from the same OAuth usage endpoint Claude Code uses, read
with the token Claude Code stores in `~/.claude/.credentials.json`. Nothing
leaves your machine except that request to Anthropic.

```
manifest.json     plugin manifest
Panel.qml         bar widget + popup
SettingsView.qml  graphical settings shown inside the popup
Model.js          parsing and formatting helpers
bin/              claude-usage (data source) and the Claude Code statusline hook
install.sh        copies the plugin into ~/.config/omarchy/plugins and enables it
```

The `bin/claude-usage` script is shared with
[claude-plasma-widget](https://github.com/arthurr0/claude-plasma-widget),
which carries the Plasma, GNOME, Waybar, Polybar, macOS and Windows variants.

## Install

From git, which leaves a checkout in `~/.config/omarchy/plugins/io.github.arthurr0.claude-usage/`
that `omarchy plugin update` keeps current:

```bash
omarchy plugin add https://github.com/arthurr0/omarchy-claude-usage.git --enable
```

Or from a local clone:

```bash
./install.sh              # copy, validate, enable in the right section of the bar
./install.sh --statusline # also wire the Claude Code statusline hook (see below)
```

Requirements: Omarchy 4 with `omarchy-shell`, `python3` and `jq` (both ship
with Omarchy), and a Claude Code login so the OAuth token exists.

Move the widget with `omarchy bar move io.github.arthurr0.claude-usage --section center`.

## Remove

```bash
omarchy plugin disable io.github.arthurr0.claude-usage   # take it out of the bar, keep the files
omarchy plugin remove io.github.arthurr0.claude-usage    # delete the plugin directory as well
```

If you used `./install.sh --statusline`, also delete `~/.local/bin/claude-usage`
and `~/.local/bin/claude-usage-statusline` and drop the `statusLine` key from
`~/.claude/settings.json` (the installer left a `settings.json.bak.<timestamp>`
copy next to it). Cached API answers live in `~/.cache/claude-usage/`.

## Using it

| Action | Effect |
|---|---|
| left click | open or close the popup |
| middle click | force a refresh (ignores the 60 s API cache) |
| right click | run the "Right-click command" from the settings, if set |
| gear icon in the popup, or `s` | open the settings |
| `r` in the popup | force a refresh |
| `Esc` | close the settings, then the popup; `Tab` / `Shift+Tab` switch to the next bar panel |

IPC for keybindings and scripts:

```bash
omarchy-shell claude-usage toggle     # open/close the popup
omarchy-shell claude-usage settings   # open the popup on the settings page
omarchy-shell claude-usage refresh    # force a refresh
omarchy-shell claude-usage text       # print the bar text, e.g. "5h 22%"
```

## Settings

Click the gear in the popup (or press `s` while it is open). The page has
chips for what the bar shows and in which style, switches for the window kinds
shown in the bar, sliders for the warning and critical thresholds, a refresh
interval picker, and text fields for the icon, colours, right-click command
and script path. Every change is written straight to
`~/.config/omarchy/shell.json` through the shell's own `setBarWidget` call
(what `omarchy bar set` does), and the bar updates at once. "Reset to
defaults" restores every value.

The same keys can be set from a terminal with
`omarchy bar set io.github.arthurr0.claude-usage <key> <value>` (add `--json` for numbers
and booleans) or edited on the widget's entry in `shell.json`:

| Key | Default | Meaning |
|---|---|---|
| `barMode` | `highest` | `highest` shows the most used window, `all` every window, `icon` only the icon |
| `barStyle` | `text` | `text` for `5h 12%` labels, `bars` for thin stacked meters |
| `showSession`, `showWeekly`, `showScoped` | `true` | which window kinds may appear in the bar (the popup always lists all of them) |
| `refreshIntervalSec` | `120` | how often the script runs; the script itself reuses API answers younger than 60 s |
| `warnPercent`, `criticalPercent` | `70`, `90` | thresholds for the warning and critical colours |
| `warningColor` | `#f67400` | hex colour for the warning state; empty keeps the theme foreground |
| `criticalColor` | empty | hex colour for the critical state; empty uses the theme's urgent colour |
| `icon` | `󰚩` | Nerd Font glyph in the bar; empty hides it |
| `command` | empty | path to a different `claude-usage` script |
| `onRightClick` | empty | shell command for right click, e.g. `omarchy-launch-or-focus-tui claude` |

## Claude Code statusline hook

`bin/claude-usage-statusline` is a Claude Code status line command. It prints
the working directory, model and usage, and stores the rate limits Claude Code
hands it in `~/.cache/claude-usage/statusline.json`. The widget watches that
file, so with the hook installed the bar refreshes the moment Claude Code
redraws its status line, without an extra API call. `./install.sh --statusline`
installs the scripts to `~/.local/bin` and sets `statusLine` in
`~/.claude/settings.json` unless one is already configured.

## How it fetches

The widget runs `python3 bin/claude-usage --format json` on the interval and
watches `~/.cache/claude-usage/{api,statusline}.json`. A write by the
statusline hook or by another integration triggers a cheap cache-only re-read,
so several bars and the Claude Code status line stay in sync.

The shell reloads plugin code when a file under `~/.config/omarchy/plugins/`
changes. If an edit does not show up, run `omarchy restart shell`.

## License

MIT, see [LICENSE](LICENSE).

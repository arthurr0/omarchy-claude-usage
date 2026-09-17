#!/usr/bin/env bash
# Installs the Claude Usage plugin into the Omarchy shell.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PLUGIN_ID="$(jq -r '.id' "$ROOT/manifest.json")"
DEST="${HOME}/.config/omarchy/plugins/${PLUGIN_ID}"
BIN_DIR="${HOME}/.local/bin"
SETTINGS="${HOME}/.claude/settings.json"
WITH_STATUSLINE=0

usage() {
    cat <<USAGE
Usage: $0 [--statusline]

Copies the plugin to $DEST, validates it and enables it in the bar.

  --statusline  also install ~/.local/bin/claude-usage-statusline and wire it
                into ~/.claude/settings.json (a backup is made) so the widget
                refreshes whenever Claude Code redraws its status line
USAGE
}

for arg in "$@"; do
    case "$arg" in
        --statusline) WITH_STATUSLINE=1 ;;
        -h|--help) usage; exit 0 ;;
        *) echo "Unknown argument: $arg" >&2; usage >&2; exit 1 ;;
    esac
done

install_plugin() {
    if [ -d "$DEST/.git" ]; then
        echo "$DEST is a git checkout (omarchy plugin add); update it with: omarchy plugin update $PLUGIN_ID"
        return 0
    fi
    rm -rf "$DEST"
    mkdir -p "$DEST/bin"
    install -m644 "$ROOT/manifest.json" "$ROOT/Panel.qml" "$ROOT/SettingsView.qml" "$ROOT/Model.js" "$DEST/"
    install -m755 "$ROOT/bin/claude-usage" "$ROOT/bin/claude-usage-statusline" "$DEST/bin/"
    echo "Plugin installed to $DEST"
}

enable_plugin() {
    if command -v omarchy-plugin-validate >/dev/null 2>&1; then
        omarchy-plugin-validate "$DEST"
    fi
    if ! command -v omarchy-shell >/dev/null 2>&1 || [ "$(omarchy-shell shell ping 2>/dev/null)" != "ok" ]; then
        echo "Omarchy shell is not running; after login run: omarchy plugin enable $PLUGIN_ID"
        return 0
    fi
    omarchy-shell shell rescanPlugins >/dev/null 2>&1 || true
    local shell_json="${HOME}/.config/omarchy/shell.json"
    if [ -f "$shell_json" ] && jq -e --arg id "$PLUGIN_ID" '[.bar.layout // {} | .[]? | .[]? | .id] | index($id) != null' "$shell_json" >/dev/null 2>&1; then
        echo "$PLUGIN_ID is already in the bar; the shell reloads the plugin code on its own (omarchy restart shell if it does not)"
    else
        omarchy plugin enable "$PLUGIN_ID"
        echo "Move it with: omarchy bar move $PLUGIN_ID --section center"
    fi
}

install_statusline() {
    mkdir -p "$BIN_DIR"
    install -m755 "$ROOT/bin/claude-usage" "$BIN_DIR/claude-usage"
    install -m755 "$ROOT/bin/claude-usage-statusline" "$BIN_DIR/claude-usage-statusline"
    echo "Scripts: $BIN_DIR/claude-usage, $BIN_DIR/claude-usage-statusline"
    if [ ! -f "$SETTINGS" ]; then
        echo "No $SETTINGS found, skipping the statusline step" >&2
        return 0
    fi
    cp "$SETTINGS" "$SETTINGS.bak.$(date +%Y%m%d%H%M%S)"
    python3 - "$SETTINGS" <<'PY'
import json
import sys

path = sys.argv[1]
with open(path) as handle:
    settings = json.load(handle)

existing = settings.get("statusLine")
if isinstance(existing, dict) and existing.get("command"):
    print("statusLine already configured, leaving it alone: %s" % existing.get("command"))
else:
    settings["statusLine"] = {"type": "command", "command": "~/.local/bin/claude-usage-statusline", "padding": 0}
    with open(path, "w") as handle:
        json.dump(settings, handle, indent=2, ensure_ascii=False)
        handle.write("\n")
    print("statusLine written to %s" % path)
PY
}

install_plugin
enable_plugin
if [ "$WITH_STATUSLINE" -eq 1 ]; then
    install_statusline
fi

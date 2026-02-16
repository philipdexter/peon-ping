#!/bin/bash
# peon-ping uninstaller
# Removes peon hooks/notify entries for Claude and/or Codex
set -euo pipefail

CLAUDE_INSTALL_DIR="$HOME/.claude/hooks/peon-ping"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
NOTIFY_BACKUP="$HOME/.claude/hooks/notify.sh.backup"
NOTIFY_SH="$HOME/.claude/hooks/notify.sh"
CODEX_INSTALL_DIR="$HOME/.codex/hooks/peon-ping"
CODEX_CONFIG="$HOME/.codex/config.toml"
TARGET="auto"

usage() {
  cat <<'USAGE'
Usage: uninstall.sh [--target claude|codex|both|auto]

Targets:
  auto   Remove from whichever installs exist [default]
  claude Remove only Claude integration
  codex  Remove only Codex integration
  both   Remove both integrations
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --target)
      [ $# -lt 2 ] && { echo "Error: --target requires a value" >&2; exit 1; }
      TARGET="$2"
      shift 2
      ;;
    --target=*)
      TARGET="${1#*=}"
      shift
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Error: unknown argument: $1" >&2
      usage
      exit 1
      ;;
  esac
done

TARGET=$(printf '%s' "$TARGET" | tr '[:upper:]' '[:lower:]')
case "$TARGET" in
  auto|claude|codex|both) ;;
  *)
    echo "Error: invalid target '$TARGET' (expected claude|codex|both|auto)" >&2
    exit 1
    ;;
esac

UNINSTALL_CLAUDE=false
UNINSTALL_CODEX=false

case "$TARGET" in
  auto)
    [ -d "$CLAUDE_INSTALL_DIR" ] && UNINSTALL_CLAUDE=true
    [ -d "$CODEX_INSTALL_DIR" ] && UNINSTALL_CODEX=true
    ;;
  claude)
    UNINSTALL_CLAUDE=true
    ;;
  codex)
    UNINSTALL_CODEX=true
    ;;
  both)
    UNINSTALL_CLAUDE=true
    UNINSTALL_CODEX=true
    ;;
esac

if [ "$UNINSTALL_CLAUDE" != true ] && [ "$UNINSTALL_CODEX" != true ]; then
  echo "Nothing to uninstall."
  exit 0
fi

echo "=== peon-ping uninstaller ==="
echo ""

# --- Remove Claude hook entries from settings.json ---
if [ "$UNINSTALL_CLAUDE" = true ] && [ -f "$CLAUDE_SETTINGS" ]; then
  echo "Removing peon hooks from Claude settings.json..."
  python3 - <<'PY'
import json
import os

settings_path = os.path.expanduser('~/.claude/settings.json')
with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.get('hooks', {})
events_cleaned = []

for event, entries in list(hooks.items()):
    original_count = len(entries)
    entries = [
        h
        for h in entries
        if not any(
            'peon.sh' in hk.get('command', '')
            for hk in h.get('hooks', [])
        )
    ]
    if len(entries) < original_count:
        events_cleaned.append(event)
    if entries:
        hooks[event] = entries
    else:
        del hooks[event]

settings['hooks'] = hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

if events_cleaned:
    print('Removed Claude hooks for: ' + ', '.join(events_cleaned))
else:
    print('No peon hooks found in Claude settings.json')
PY
fi

# --- Remove Codex notify command from config.toml ---
if [ "$UNINSTALL_CODEX" = true ] && [ -f "$CODEX_CONFIG" ]; then
  echo "Removing peon notify command from Codex config.toml..."
  python3 - <<'PY'
import json
import os
import re
import tomllib

config_path = os.path.expanduser('~/.codex/config.toml')
notify_cmd = 'bash ~/.codex/hooks/peon-ping/peon.sh --codex-notify'
text = open(config_path, 'r', encoding='utf-8').read()

pattern = re.compile(r'(?ms)^\s*notify\s*=\s*\[(.*?)\]\s*\n?')
match = pattern.search(text)

if not match:
    print('No notify array found in Codex config.toml')
    raise SystemExit(0)

snippet = 'notify = [' + match.group(1) + ']'
notify_values = []
try:
    parsed = tomllib.loads(snippet)
    values = parsed.get('notify', [])
    if isinstance(values, list):
        notify_values = [str(v) for v in values]
except Exception:
    notify_values = []

before = list(notify_values)
notify_values = [v for v in notify_values if v != notify_cmd]

if before == notify_values:
    print('No peon notify command found in Codex config.toml')
    raise SystemExit(0)

if notify_values:
    notify_block = 'notify = [\n' + ''.join(f'  {json.dumps(v)},\n' for v in notify_values) + ']\n'
    text = text[:match.start()] + notify_block + text[match.end():]
else:
    # Remove notify key entirely when no commands remain.
    text = text[:match.start()] + text[match.end():]

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Removed Codex peon notify command')
PY
fi

# --- Restore notify.sh backup (Claude only) ---
if [ "$UNINSTALL_CLAUDE" = true ] && [ -f "$NOTIFY_BACKUP" ] && [ -f "$CLAUDE_SETTINGS" ]; then
  echo ""
  read -p "Restore original notify.sh from backup? [Y/n] " -n 1 -r
  echo
  if [[ ! $REPLY =~ ^[Nn]$ ]]; then
    python3 - <<'PY'
import json
import os

settings_path = os.path.expanduser('~/.claude/settings.json')
notify_sh = os.path.expanduser('~/.claude/hooks/notify.sh')
with open(settings_path) as f:
    settings = json.load(f)

hooks = settings.setdefault('hooks', {})
notify_hook = {
    'matcher': '',
    'hooks': [{
        'type': 'command',
        'command': notify_sh,
        'timeout': 10,
    }],
}

for event in ['SessionStart', 'UserPromptSubmit', 'Stop', 'Notification']:
    event_hooks = hooks.get(event, [])
    has_notify = any(
        'notify.sh' in hk.get('command', '')
        for h in event_hooks
        for hk in h.get('hooks', [])
    )
    if not has_notify:
        event_hooks.append(notify_hook)
    hooks[event] = event_hooks

settings['hooks'] = hooks
with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Restored notify.sh hooks for: SessionStart, UserPromptSubmit, Stop, Notification')
PY
    cp "$NOTIFY_BACKUP" "$NOTIFY_SH"
    rm "$NOTIFY_BACKUP"
    echo "notify.sh restored"
  fi
fi

# --- Remove install directories ---
if [ "$UNINSTALL_CLAUDE" = true ] && [ -d "$CLAUDE_INSTALL_DIR" ]; then
  echo ""
  echo "Removing $CLAUDE_INSTALL_DIR..."
  rm -rf "$CLAUDE_INSTALL_DIR"
  echo "Removed"
fi

if [ "$UNINSTALL_CODEX" = true ] && [ -d "$CODEX_INSTALL_DIR" ]; then
  echo ""
  echo "Removing $CODEX_INSTALL_DIR..."
  rm -rf "$CODEX_INSTALL_DIR"
  echo "Removed"
fi

echo ""
echo "=== Uninstall complete ==="
echo "Me go now."

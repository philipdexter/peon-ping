#!/bin/bash
# peon-ping installer
# Works both via `curl | bash` (downloads from GitHub) and local clone
set -euo pipefail

REPO_BASE="https://raw.githubusercontent.com/tonyyont/peon-ping/main"
CLAUDE_INSTALL_DIR="$HOME/.claude/hooks/peon-ping"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"
CODEX_INSTALL_DIR="$HOME/.codex/hooks/peon-ping"
CODEX_CONFIG="$HOME/.codex/config.toml"
TARGET="auto"

# All available sound packs (add new packs here)
PACKS="peon peon_fr peon_pl peasant peasant_fr ra2_soviet_engineer sc_battlecruiser sc_kerrigan ut2004_male ut2004_female ut99"

usage() {
  cat <<'USAGE'
Usage: install.sh [--target claude|codex|both|auto]

Targets:
  auto   Install to whichever app is present (~/.claude and/or ~/.codex) [default]
  claude Install only for Claude Code
  codex  Install only for Codex
  both   Install for both Claude Code and Codex
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

# --- Platform detection ---
detect_platform() {
  case "$(uname -s)" in
    Darwin) echo "mac" ;;
    Linux)
      if grep -qi microsoft /proc/version 2>/dev/null; then
        echo "wsl"
      else
        echo "linux"
      fi ;;
    *) echo "unknown" ;;
  esac
}
PLATFORM=$(detect_platform)

HAS_CLAUDE=false
HAS_CODEX=false
[ -d "$HOME/.claude" ] && HAS_CLAUDE=true
[ -d "$HOME/.codex" ] && HAS_CODEX=true

INSTALL_CLAUDE=false
INSTALL_CODEX=false

case "$TARGET" in
  auto)
    [ "$HAS_CLAUDE" = true ] && INSTALL_CLAUDE=true
    [ "$HAS_CODEX" = true ] && INSTALL_CODEX=true
    ;;
  claude)
    INSTALL_CLAUDE=true
    ;;
  codex)
    INSTALL_CODEX=true
    ;;
  both)
    INSTALL_CLAUDE=true
    INSTALL_CODEX=true
    ;;
esac

if [ "$INSTALL_CLAUDE" = true ] && [ "$HAS_CLAUDE" != true ]; then
  echo "Error: ~/.claude/ not found. Is Claude Code installed?"
  exit 1
fi
if [ "$INSTALL_CODEX" = true ] && [ "$HAS_CODEX" != true ]; then
  echo "Error: ~/.codex/ not found. Is Codex installed?"
  exit 1
fi
if [ "$INSTALL_CLAUDE" != true ] && [ "$INSTALL_CODEX" != true ]; then
  echo "Error: no target app directories found. Install Claude Code (~/.claude) and/or Codex (~/.codex), or pass --target explicitly."
  exit 1
fi

# --- Detect update vs fresh install (per target) ---
CLAUDE_UPDATING=false
CODEX_UPDATING=false
if [ "$INSTALL_CLAUDE" = true ] && [ -f "$CLAUDE_INSTALL_DIR/peon.sh" ]; then
  CLAUDE_UPDATING=true
fi
if [ "$INSTALL_CODEX" = true ] && [ -f "$CODEX_INSTALL_DIR/peon.sh" ]; then
  CODEX_UPDATING=true
fi

if [ "$CLAUDE_UPDATING" = true ] || [ "$CODEX_UPDATING" = true ]; then
  echo "=== peon-ping updater ==="
  echo ""
  echo "Existing install found. Updating..."
else
  echo "=== peon-ping installer ==="
  echo ""
fi

# --- Prerequisites ---
if [ "$PLATFORM" != "mac" ] && [ "$PLATFORM" != "wsl" ]; then
  echo "Error: peon-ping requires macOS or WSL (Windows Subsystem for Linux)"
  exit 1
fi

if ! command -v python3 &>/dev/null; then
  echo "Error: python3 is required"
  exit 1
fi

if [ "$PLATFORM" = "mac" ]; then
  if ! command -v afplay &>/dev/null; then
    echo "Error: afplay is required (should be built into macOS)"
    exit 1
  fi
elif [ "$PLATFORM" = "wsl" ]; then
  if ! command -v powershell.exe &>/dev/null; then
    echo "Error: powershell.exe is required (should be available in WSL)"
    exit 1
  fi
  if ! command -v wslpath &>/dev/null; then
    echo "Error: wslpath is required (should be built into WSL)"
    exit 1
  fi
fi

# --- Detect if running from local clone or curl|bash ---
SCRIPT_DIR=""
if [ -n "${BASH_SOURCE[0]:-}" ] && [ "${BASH_SOURCE[0]}" != "bash" ]; then
  CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd)"
  if [ -f "$CANDIDATE/peon.sh" ]; then
    SCRIPT_DIR="$CANDIDATE"
  fi
fi

install_files_for_target() {
  local install_dir="$1"
  local updating="$2"

  for pack in $PACKS; do
    mkdir -p "$install_dir/packs/$pack/sounds"
  done

  if [ -n "$SCRIPT_DIR" ]; then
    # Local clone — copy files directly (including sounds)
    cp -R "$SCRIPT_DIR/packs/." "$install_dir/packs/"
    cp "$SCRIPT_DIR/peon.sh" "$install_dir/"
    cp "$SCRIPT_DIR/completions.bash" "$install_dir/"
    cp "$SCRIPT_DIR/VERSION" "$install_dir/"
    cp "$SCRIPT_DIR/uninstall.sh" "$install_dir/"
    if [ "$updating" = false ]; then
      cp "$SCRIPT_DIR/config.json" "$install_dir/"
    fi
  else
    # curl|bash — download from GitHub (sounds are version-controlled in repo)
    echo "Downloading from GitHub..."
    curl -fsSL "$REPO_BASE/peon.sh" -o "$install_dir/peon.sh"
    curl -fsSL "$REPO_BASE/completions.bash" -o "$install_dir/completions.bash"
    curl -fsSL "$REPO_BASE/VERSION" -o "$install_dir/VERSION"
    curl -fsSL "$REPO_BASE/uninstall.sh" -o "$install_dir/uninstall.sh"
    for pack in $PACKS; do
      curl -fsSL "$REPO_BASE/packs/$pack/manifest.json" -o "$install_dir/packs/$pack/manifest.json"
    done
    # Download sound files for each pack
    for pack in $PACKS; do
      manifest="$install_dir/packs/$pack/manifest.json"
      python3 -c "
import json
m = json.load(open('$manifest'))
seen = set()
for cat in m.get('categories', {}).values():
    for s in cat.get('sounds', []):
        f = s['file']
        if f not in seen:
            seen.add(f)
            print(f)
" | while read -r sfile; do
        curl -fsSL "$REPO_BASE/packs/$pack/sounds/$sfile" -o "$install_dir/packs/$pack/sounds/$sfile" </dev/null
      done
    done
    if [ "$updating" = false ]; then
      curl -fsSL "$REPO_BASE/config.json" -o "$install_dir/config.json"
    fi
  fi

  chmod +x "$install_dir/peon.sh"

  if [ "$updating" = false ]; then
    echo '{}' > "$install_dir/.state.json"
  fi
}

if [ "$INSTALL_CLAUDE" = true ]; then
  install_files_for_target "$CLAUDE_INSTALL_DIR" "$CLAUDE_UPDATING"
fi
if [ "$INSTALL_CODEX" = true ]; then
  install_files_for_target "$CODEX_INSTALL_DIR" "$CODEX_UPDATING"
fi

# --- Install skill (slash command, Claude only) ---
if [ "$INSTALL_CLAUDE" = true ]; then
  SKILL_DIR="$HOME/.claude/skills/peon-ping-toggle"
  mkdir -p "$SKILL_DIR"
  if [ -n "$SCRIPT_DIR" ] && [ -d "$SCRIPT_DIR/skills/peon-ping-toggle" ]; then
    cp "$SCRIPT_DIR/skills/peon-ping-toggle/SKILL.md" "$SKILL_DIR/"
  elif [ -z "$SCRIPT_DIR" ]; then
    curl -fsSL "$REPO_BASE/skills/peon-ping-toggle/SKILL.md" -o "$SKILL_DIR/SKILL.md"
  else
    echo "Warning: skills/peon-ping-toggle not found in local clone, skipping skill install"
  fi
fi

# --- Add shell alias ---
if [ "$INSTALL_CLAUDE" = true ]; then
  ALIAS_HOOK_PATH='~/.claude/hooks/peon-ping'
else
  ALIAS_HOOK_PATH='~/.codex/hooks/peon-ping'
fi
ALIAS_LINE="alias peon=\"bash $ALIAS_HOOK_PATH/peon.sh\""
for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rcfile" ] && ! grep -qF 'alias peon=' "$rcfile"; then
    echo "" >> "$rcfile"
    echo "# peon-ping quick controls" >> "$rcfile"
    echo "$ALIAS_LINE" >> "$rcfile"
    echo "Added peon alias to $(basename "$rcfile")"
  fi
done

# --- Add tab completion ---
COMPLETION_LINE='[ -f ~/.claude/hooks/peon-ping/completions.bash ] && source ~/.claude/hooks/peon-ping/completions.bash || [ -f ~/.codex/hooks/peon-ping/completions.bash ] && source ~/.codex/hooks/peon-ping/completions.bash'
for rcfile in "$HOME/.zshrc" "$HOME/.bashrc"; do
  if [ -f "$rcfile" ] && ! grep -qF 'peon-ping/completions.bash' "$rcfile"; then
    echo "$COMPLETION_LINE" >> "$rcfile"
    echo "Added tab completion to $(basename "$rcfile")"
  fi
done

verify_sounds_for_target() {
  local install_dir="$1"
  local label="$2"
  echo ""
  echo "Verifying sounds for $label ($install_dir):"
  for pack in $PACKS; do
    sound_dir="$install_dir/packs/$pack/sounds"
    sound_count=$({ ls "$sound_dir"/*.wav "$sound_dir"/*.mp3 "$sound_dir"/*.ogg 2>/dev/null || true; } | wc -l | tr -d ' ')
    if [ "$sound_count" -eq 0 ]; then
      echo "[$pack] Warning: No sound files found!"
    else
      echo "[$pack] $sound_count sound files installed."
    fi
  done
}

if [ "$INSTALL_CLAUDE" = true ]; then
  verify_sounds_for_target "$CLAUDE_INSTALL_DIR" "Claude"
fi
if [ "$INSTALL_CODEX" = true ]; then
  verify_sounds_for_target "$CODEX_INSTALL_DIR" "Codex"
fi

# --- Backup existing notify.sh (Claude fresh install only) ---
if [ "$INSTALL_CLAUDE" = true ] && [ "$CLAUDE_UPDATING" = false ]; then
  NOTIFY_SH="$HOME/.claude/hooks/notify.sh"
  if [ -f "$NOTIFY_SH" ]; then
    cp "$NOTIFY_SH" "$NOTIFY_SH.backup"
    echo ""
    echo "Backed up notify.sh → notify.sh.backup"
  fi
fi

# --- Update Claude settings.json ---
if [ "$INSTALL_CLAUDE" = true ]; then
  echo ""
  echo "Updating Claude Code hooks in settings.json..."

  python3 - <<'PY'
import json
import os

settings_path = os.path.expanduser('~/.claude/settings.json')
hook_cmd = os.path.expanduser('~/.claude/hooks/peon-ping/peon.sh')

if os.path.exists(settings_path):
    with open(settings_path) as f:
        settings = json.load(f)
else:
    settings = {}

hooks = settings.setdefault('hooks', {})

peon_hook = {
    'type': 'command',
    'command': hook_cmd,
    'timeout': 10,
}

peon_entry = {
    'matcher': '',
    'hooks': [peon_hook],
}

events = ['SessionStart', 'UserPromptSubmit', 'Stop', 'Notification', 'PermissionRequest']

for event in events:
    event_hooks = hooks.get(event, [])
    event_hooks = [
        h
        for h in event_hooks
        if not any(
            'notify.sh' in hk.get('command', '') or 'peon.sh' in hk.get('command', '')
            for hk in h.get('hooks', [])
        )
    ]
    event_hooks.append(peon_entry)
    hooks[event] = event_hooks

settings['hooks'] = hooks

with open(settings_path, 'w') as f:
    json.dump(settings, f, indent=2)
    f.write('\n')

print('Claude hooks registered for: ' + ', '.join(events))
PY
fi

# --- Update Codex config.toml notify ---
if [ "$INSTALL_CODEX" = true ]; then
  echo ""
  echo "Updating Codex notify command in config.toml..."

  python3 - <<'PY'
import json
import os
import re

config_path = os.path.expanduser('~/.codex/config.toml')
notify_values = ['bash', '~/.codex/hooks/peon-ping/peon.sh', '--codex-notify']

if os.path.exists(config_path):
    text = open(config_path, 'r', encoding='utf-8').read()
else:
    text = ''

pattern = re.compile(r'(?ms)^\s*notify\s*=\s*\[(.*?)\]\s*\n?')
match = pattern.search(text)

notify_block = 'notify = [\n' + ''.join(f'  {json.dumps(v)},\n' for v in notify_values) + ']\n'

if match:
    text = text[:match.start()] + notify_block + text[match.end():]
else:
    if text.strip():
        text = notify_block + '\n' + text
    else:
        text = notify_block

with open(config_path, 'w', encoding='utf-8') as f:
    f.write(text)

print('Codex notify command registered.')
PY
fi

# --- Test sound ---
echo ""
echo "Testing sound..."
if [ "$INSTALL_CLAUDE" = true ]; then
  TEST_INSTALL_DIR="$CLAUDE_INSTALL_DIR"
else
  TEST_INSTALL_DIR="$CODEX_INSTALL_DIR"
fi

ACTIVE_PACK=$(python3 -c "
import json, os
try:
    c = json.load(open('$TEST_INSTALL_DIR/config.json'))
    print(c.get('active_pack', 'peon'))
except:
    print('peon')
" 2>/dev/null)
PACK_DIR="$TEST_INSTALL_DIR/packs/$ACTIVE_PACK"
TEST_SOUND=$({ ls "$PACK_DIR/sounds/"*.wav "$PACK_DIR/sounds/"*.mp3 "$PACK_DIR/sounds/"*.ogg 2>/dev/null || true; } | head -1)
if [ -n "$TEST_SOUND" ]; then
  if [ "$PLATFORM" = "mac" ]; then
    if ! afplay -v 0.3 "$TEST_SOUND" >/dev/null 2>&1; then
      echo "Warning: test sound could not be played (afplay failed), but installation completed."
    fi
  elif [ "$PLATFORM" = "wsl" ]; then
    wpath=$(wslpath -w "$TEST_SOUND")
    wpath="${wpath//\\//}"
    if ! powershell.exe -NoProfile -NonInteractive -Command "
      Add-Type -AssemblyName PresentationCore
      \$p = New-Object System.Windows.Media.MediaPlayer
      \$p.Open([Uri]::new('file:///$wpath'))
      \$p.Volume = 0.3
      Start-Sleep -Milliseconds 200
      \$p.Play()
      Start-Sleep -Seconds 3
      \$p.Close()
    " 2>/dev/null; then
      echo "Warning: test sound could not be played (powershell MediaPlayer failed), but installation completed."
    fi
  fi
  echo "Sound test complete."
else
  echo "Warning: No sound files found. Sounds may not play."
fi

echo ""
if [ "$CLAUDE_UPDATING" = true ] || [ "$CODEX_UPDATING" = true ]; then
  echo "=== Update complete! ==="
else
  echo "=== Installation complete! ==="
fi

echo ""
echo "Installed targets:"
[ "$INSTALL_CLAUDE" = true ] && echo "  - Claude Code (~/.claude/hooks/peon-ping)"
[ "$INSTALL_CODEX" = true ] && echo "  - Codex (~/.codex/hooks/peon-ping)"

echo ""
if [ "$INSTALL_CLAUDE" = true ]; then
  echo "Claude config: $CLAUDE_INSTALL_DIR/config.json"
fi
if [ "$INSTALL_CODEX" = true ]; then
  echo "Codex config: $CODEX_INSTALL_DIR/config.json"
fi

echo ""
echo "Uninstall:"
[ "$INSTALL_CLAUDE" = true ] && echo "  bash ~/.claude/hooks/peon-ping/uninstall.sh --target claude"
[ "$INSTALL_CODEX" = true ] && echo "  bash ~/.codex/hooks/peon-ping/uninstall.sh --target codex"

echo ""
echo "Quick controls:"
if [ "$INSTALL_CLAUDE" = true ]; then
  echo "  /peon-ping-toggle  — toggle sounds in Claude Code"
fi
echo "  peon --toggle      — toggle sounds from any terminal"
echo "  peon --status      — check if sounds are paused"
echo ""
echo "Ready to work!"

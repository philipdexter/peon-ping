#!/usr/bin/env bats

# Tests for install.sh (local clone mode only — no network)

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  # Create both app dirs so --target/auto behavior can be tested.
  mkdir -p "$TEST_HOME/.claude"
  mkdir -p "$TEST_HOME/.codex"

  # Create a fake local clone with all required files
  CLONE_DIR="$(mktemp -d)"
  cp "$(dirname "$BATS_TEST_FILENAME")/../install.sh" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../peon.sh" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../config.json" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../VERSION" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../completions.bash" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../uninstall.sh" "$CLONE_DIR/" 2>/dev/null || touch "$CLONE_DIR/uninstall.sh"
  cp -r "$(dirname "$BATS_TEST_FILENAME")/../packs" "$CLONE_DIR/"

  CLAUDE_INSTALL_DIR="$TEST_HOME/.claude/hooks/peon-ping"
  CODEX_INSTALL_DIR="$TEST_HOME/.codex/hooks/peon-ping"
}

teardown() {
  rm -rf "$TEST_HOME" "$CLONE_DIR"
}

@test "default install (auto) creates expected files for both targets" {
  bash "$CLONE_DIR/install.sh"

  [ -f "$CLAUDE_INSTALL_DIR/peon.sh" ]
  [ -f "$CLAUDE_INSTALL_DIR/config.json" ]
  [ -f "$CLAUDE_INSTALL_DIR/.state.json" ]

  [ -f "$CODEX_INSTALL_DIR/peon.sh" ]
  [ -f "$CODEX_INSTALL_DIR/config.json" ]
  [ -f "$CODEX_INSTALL_DIR/.state.json" ]
}

@test "--target claude installs only Claude files" {
  bash "$CLONE_DIR/install.sh" --target claude

  [ -f "$CLAUDE_INSTALL_DIR/peon.sh" ]
  [ ! -d "$CODEX_INSTALL_DIR" ]
}

@test "--target codex installs only Codex files" {
  bash "$CLONE_DIR/install.sh" --target codex

  [ -f "$CODEX_INSTALL_DIR/peon.sh" ]
  [ ! -d "$CLAUDE_INSTALL_DIR" ]
}

@test "fresh Claude install registers hooks in settings.json" {
  bash "$CLONE_DIR/install.sh" --target claude
  [ -f "$TEST_HOME/.claude/settings.json" ]

  /usr/bin/python3 -c "
import json
s = json.load(open('$TEST_HOME/.claude/settings.json'))
hooks = s.get('hooks', {})
for event in ['SessionStart', 'UserPromptSubmit', 'Stop', 'Notification', 'PermissionRequest']:
    assert event in hooks, f'{event} not in hooks'
    found = any('peon.sh' in h.get('command','') for entry in hooks[event] for h in entry.get('hooks',[]))
    assert found, f'peon.sh not registered for {event}'
print('OK')
"
}

@test "fresh Codex install registers notify command in config.toml" {
  bash "$CLONE_DIR/install.sh" --target codex
  [ -f "$TEST_HOME/.codex/config.toml" ]

  run rg -n "\"bash\"|\"~/.codex/hooks/peon-ping/peon.sh\"|\"--codex-notify\"" "$TEST_HOME/.codex/config.toml"
  [ "$status" -eq 0 ]
}

@test "default install copies sound files for both targets" {
  bash "$CLONE_DIR/install.sh"

  c_peon_count=$(ls "$CLAUDE_INSTALL_DIR/packs/peon/sounds/"*.wav 2>/dev/null | wc -l | tr -d ' ')
  x_peon_count=$(ls "$CODEX_INSTALL_DIR/packs/peon/sounds/"*.wav 2>/dev/null | wc -l | tr -d ' ')

  [ "$c_peon_count" -gt 0 ]
  [ "$x_peon_count" -gt 0 ]
}

@test "rerun does not duplicate Claude hook entries" {
  bash "$CLONE_DIR/install.sh" --target claude
  bash "$CLONE_DIR/install.sh" --target claude

  /usr/bin/python3 -c "
import json
s = json.load(open('$TEST_HOME/.claude/settings.json'))
hooks = s.get('hooks', {})
for event in ['SessionStart', 'UserPromptSubmit', 'Stop', 'Notification', 'PermissionRequest']:
    entries = hooks.get(event, [])
    count = 0
    for entry in entries:
        for h in entry.get('hooks', []):
            if 'peon.sh' in h.get('command', ''):
                count += 1
    assert count == 1, f'{event}: expected 1 peon hook, got {count}'
print('OK')
"
}

@test "rerun does not duplicate Codex notify command" {
  bash "$CLONE_DIR/install.sh" --target codex
  bash "$CLONE_DIR/install.sh" --target codex

  script_matches=$(rg -o "\"~/.codex/hooks/peon-ping/peon.sh\"" "$TEST_HOME/.codex/config.toml" | wc -l | tr -d ' ')
  flag_matches=$(rg -o "\"--codex-notify\"" "$TEST_HOME/.codex/config.toml" | wc -l | tr -d ' ')
  [ "$script_matches" -eq 1 ]
  [ "$flag_matches" -eq 1 ]
}

@test "update preserves existing config for Claude and Codex installs" {
  bash "$CLONE_DIR/install.sh"

  echo '{"volume": 0.9, "active_pack": "peon"}' > "$CLAUDE_INSTALL_DIR/config.json"
  echo '{"volume": 0.8, "active_pack": "peon"}' > "$CODEX_INSTALL_DIR/config.json"

  bash "$CLONE_DIR/install.sh"

  c_volume=$(/usr/bin/python3 -c "import json; print(json.load(open('$CLAUDE_INSTALL_DIR/config.json')).get('volume'))")
  x_volume=$(/usr/bin/python3 -c "import json; print(json.load(open('$CODEX_INSTALL_DIR/config.json')).get('volume'))")

  [ "$c_volume" = "0.9" ]
  [ "$x_volume" = "0.8" ]
}

@test "peon.sh is executable after install for both targets" {
  bash "$CLONE_DIR/install.sh"
  [ -x "$CLAUDE_INSTALL_DIR/peon.sh" ]
  [ -x "$CODEX_INSTALL_DIR/peon.sh" ]
}

@test "fresh install adds completions source to shell rc" {
  touch "$TEST_HOME/.zshrc"
  bash "$CLONE_DIR/install.sh"
  grep -qF 'peon-ping/completions.bash' "$TEST_HOME/.zshrc"
}

#!/usr/bin/env bats

setup() {
  TEST_HOME="$(mktemp -d)"
  export HOME="$TEST_HOME"

  mkdir -p "$TEST_HOME/.claude"
  mkdir -p "$TEST_HOME/.codex"

  CLONE_DIR="$(mktemp -d)"
  cp "$(dirname "$BATS_TEST_FILENAME")/../install.sh" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../uninstall.sh" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../peon.sh" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../config.json" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../VERSION" "$CLONE_DIR/"
  cp "$(dirname "$BATS_TEST_FILENAME")/../completions.bash" "$CLONE_DIR/"
  cp -r "$(dirname "$BATS_TEST_FILENAME")/../packs" "$CLONE_DIR/"

  CLAUDE_INSTALL_DIR="$TEST_HOME/.claude/hooks/peon-ping"
  CODEX_INSTALL_DIR="$TEST_HOME/.codex/hooks/peon-ping"
}

teardown() {
  rm -rf "$TEST_HOME" "$CLONE_DIR"
}

@test "uninstall --target claude removes Claude hooks and files only" {
  bash "$CLONE_DIR/install.sh"
  [ -d "$CLAUDE_INSTALL_DIR" ]
  [ -d "$CODEX_INSTALL_DIR" ]

  bash "$CLONE_DIR/uninstall.sh" --target claude

  [ ! -d "$CLAUDE_INSTALL_DIR" ]
  [ -d "$CODEX_INSTALL_DIR" ]

  /usr/bin/python3 -c "
import json
s = json.load(open('$TEST_HOME/.claude/settings.json'))
hooks = s.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            assert 'peon.sh' not in h.get('command', '')
print('OK')
"
}

@test "uninstall --target codex removes Codex notify and files only" {
  bash "$CLONE_DIR/install.sh"

  bash "$CLONE_DIR/uninstall.sh" --target codex

  [ -d "$CLAUDE_INSTALL_DIR" ]
  [ ! -d "$CODEX_INSTALL_DIR" ]

  run rg -n "~/.codex/hooks/peon-ping/peon.sh|--codex-notify" "$TEST_HOME/.codex/config.toml"
  [ "$status" -ne 0 ]
}

@test "uninstall --target both removes both integrations" {
  bash "$CLONE_DIR/install.sh"

  bash "$CLONE_DIR/uninstall.sh" --target both

  [ ! -d "$CLAUDE_INSTALL_DIR" ]
  [ ! -d "$CODEX_INSTALL_DIR" ]

  /usr/bin/python3 -c "
import json
s = json.load(open('$TEST_HOME/.claude/settings.json'))
hooks = s.get('hooks', {})
for event, entries in hooks.items():
    for entry in entries:
        for h in entry.get('hooks', []):
            assert 'peon.sh' not in h.get('command', '')
print('OK')
"

  run rg -n "~/.codex/hooks/peon-ping/peon.sh|--codex-notify" "$TEST_HOME/.codex/config.toml"
  [ "$status" -ne 0 ]
}

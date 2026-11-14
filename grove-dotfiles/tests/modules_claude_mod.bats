# shellcheck disable=SC2016,SC1090,SC1091,SC2154
# 93-claude-mod: the grove mod for Claude Code, against a fake `claude`.
load helpers

CM_MODULE=93-claude-mod

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do . "$f"; done
  MODULE_DIR="$GROVE_ROOT/modules/$CM_MODULE"
  . "$MODULE_DIR/module.sh"
}

# The fake claude keeps its marketplaces and plugins as JSON in the test's
# folder and logs every call. It answers only what the module asks.
setup() {
  grove_test_setup
  CM_DIR="$BATS_TEST_TMPDIR/claude"
  mkdir -p "$CM_DIR"
  echo '[]' > "$CM_DIR/markets.json"
  echo '[]' > "$CM_DIR/plugins.json"
  stub claude '
d="'"$CM_DIR"'"
echo "$*" >> "$d/args"
case "$*" in
  "plugin marketplace list --json") cat "$d/markets.json" ;;
  "plugin list --json") cat "$d/plugins.json" ;;
  "plugin marketplace add "*)
    jq --arg p "$4" ". + [{name: \"grove\", source: \"directory\", path: \$p, installLocation: \$p}]" \
      "$d/markets.json" > "$d/m.new" && mv "$d/m.new" "$d/markets.json" ;;
  "plugin install grove@grove --scope user")
    p="$(jq -r ".[] | select(.name == \"grove\") | .path" "$d/markets.json")"
    [ -n "$p" ] || { echo "no marketplace grove" >&2; exit 1; }
    jq --arg f "$p/grove" ". + [{id: \"grove@grove\", scope: \"user\", enabled: true, readFromFolder: \$f}]" \
      "$d/plugins.json" > "$d/p.new" && mv "$d/p.new" "$d/plugins.json" ;;
  "plugin enable grove@grove")
    jq "map(if .id == \"grove@grove\" then .enabled = true else . end)" \
      "$d/plugins.json" > "$d/p.new" && mv "$d/p.new" "$d/plugins.json" ;;
  *) echo "fake claude: unexpected: $*" >&2; exit 2 ;;
esac'
  export GROVE_CLAUDE_BIN="$BATS_TEST_TMPDIR/stubs/claude"
  WANT="$(cd "$GROVE_CONFIG/grove-claude" && pwd -P)"
}

# cm_ready: the marketplace and the plugin as apply leaves them.
cm_ready() {
  jq -n --arg p "$WANT" '[{name: "grove", source: "directory", path: $p, installLocation: $p}]' > "$CM_DIR/markets.json"
  jq -n --arg f "$WANT/grove" '[{id: "grove@grove", scope: "user", enabled: true, readFromFolder: $f}]' > "$CM_DIR/plugins.json"
}

@test "claude-mod: the mod and its marketplace are tracked" {
  local p
  for p in config/grove-claude/.claude-plugin/marketplace.json \
           config/grove-claude/grove/.claude-plugin/plugin.json \
           config/grove-claude/grove/hooks/hooks.json \
           config/grove-claude/grove/hooks/register.tsx \
           config/grove-claude/grove/hooks/logic.ts \
           config/grove-claude/grove/hooks/motd.ts \
           config/grove-claude/grove/types/index.d.ts \
           config/grove-claude/grove/README.md; do
    [ -n "$(git -C "$GROVE_ROOT" ls-files "$p")" ] || { echo "not tracked: $p"; false; }
  done
}

@test "claude-mod: the types the engine lays beside the mod are ignored" {
  git -C "$GROVE_ROOT" check-ignore -q config/grove-claude/grove/.claude-plugin/types/claude-code/index.d.ts
}

@test "claude-mod: the marketplace lists the grove plugin from ./grove" {
  jq -e '.name == "grove" and (.plugins | length == 1)
    and .plugins[0].name == "grove" and .plugins[0].source == "./grove"' \
    "$GROVE_CONFIG/grove-claude/.claude-plugin/marketplace.json"
  jq -e '.name == "grove"' "$GROVE_CONFIG/grove-claude/grove/.claude-plugin/plugin.json"
}

@test "claude-mod: check is ok when the marketplace and the enabled plugin both match" {
  load_module
  cm_ready
  run check
  [ "$status" -eq 0 ]
}

@test "claude-mod: check needs work with nothing set up" {
  load_module
  run check
  [ "$status" -eq 3 ]
}

@test "claude-mod: check needs work when the plugin is missing or disabled" {
  load_module
  cm_ready
  echo '[]' > "$CM_DIR/plugins.json"
  run check
  [ "$status" -eq 3 ]
  cm_ready
  jq 'map(.enabled = false)' "$CM_DIR/plugins.json" > "$CM_DIR/p.new" && mv "$CM_DIR/p.new" "$CM_DIR/plugins.json"
  run check
  [ "$status" -eq 3 ]
}

@test "claude-mod: check needs work when the plugin runs from another folder" {
  load_module
  cm_ready
  jq 'map(.readFromFolder = "/elsewhere/grove")' "$CM_DIR/plugins.json" > "$CM_DIR/p.new" && mv "$CM_DIR/p.new" "$CM_DIR/plugins.json"
  run check
  [ "$status" -eq 3 ]
}

@test "claude-mod: check and apply need you when claude isn't installed" {
  load_module
  export GROVE_CLAUDE_BIN="$BATS_TEST_TMPDIR/nowhere/claude"
  export PATH="/usr/bin:/bin"
  run check
  [ "$status" -eq 4 ]
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"Claude Code"* ]]
}

@test "claude-mod: apply adds the marketplace, installs the plugin, and then check is ok" {
  load_module
  run apply
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx "plugin marketplace add $WANT" "$CM_DIR/args"
  grep -qx "plugin install grove@grove --scope user" "$CM_DIR/args"
  run check
  [ "$status" -eq 0 ]
}

@test "claude-mod: apply only enables a disabled plugin" {
  load_module
  cm_ready
  jq 'map(.enabled = false)' "$CM_DIR/plugins.json" > "$CM_DIR/p.new" && mv "$CM_DIR/p.new" "$CM_DIR/plugins.json"
  run apply
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  grep -qx "plugin enable grove@grove" "$CM_DIR/args"
  ! grep -q "plugin install" "$CM_DIR/args"
  ! grep -q "marketplace add" "$CM_DIR/args"
}

@test "claude-mod: apply refuses a grove marketplace that points at another folder" {
  load_module
  jq -n '[{name: "grove", source: "directory", path: "/elsewhere"}]' > "$CM_DIR/markets.json"
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"/elsewhere"* ]]
  ! grep -q "marketplace add" "$CM_DIR/args"
}

@test "claude-mod: apply never writes Claude Code's settings itself" {
  load_module
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.claude" ]
}

@test "claude-mod: the mod's own tests and validation pass" {
  local real
  real="$(PATH="$HOME/.local/bin:/Users/$(id -un)/.local/bin:$PATH" command -v claude || true)"
  [ -n "$real" ] && [ "$real" != "$BATS_TEST_TMPDIR/stubs/claude" ] || skip "Claude Code isn't installed"
  # Run against the checkout itself: the mod reads its palette three folders up.
  HOME="/Users/$(id -un)" run "$real" plugin validate "$GROVE_ROOT/config/grove-claude/grove"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
  HOME="/Users/$(id -un)" run "$real" plugin test "$GROVE_ROOT/config/grove-claude/grove"
  [ "$status" -eq 0 ] || { echo "$output"; false; }
}

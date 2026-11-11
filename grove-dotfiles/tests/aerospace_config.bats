#!/usr/bin/env bats
# config/aerospace/aerospace.base.toml (settings and rules) and
# config/grove-keys/keys.toml (bindings) against the AeroSpace spec (§4–§5),
# read back with Python's tomllib (Homebrew's python3; macOS's 3.9 has no tomllib).
# shellcheck disable=SC2016

load helpers

setup() {
  grove_test_setup
  AS_TOML="$GROVE_ROOT/config/aerospace/aerospace.base.toml"
  KEYS_TOML="$GROVE_ROOT/config/grove-keys/keys.toml"
  AS_PY="${GROVE_TEST_PYTHON:-/opt/homebrew/bin/python3}"
  [ -x "$AS_PY" ] || skip "no python3 with tomllib"
}

# as_q EXPR: print EXPR, evaluated with c = the parsed config.
as_q() {
  "$AS_PY" -I -c '
import sys, tomllib, json
c = tomllib.load(open(sys.argv[1], "rb"))
r = eval(sys.argv[2])
print(r if isinstance(r, str) else json.dumps(r))' "$AS_TOML" "$1"
}

# keys_q EXPR: the same, with k = the parsed keys.toml (bindings live there).
keys_q() {
  "$AS_PY" -I -c '
import sys, tomllib, json
k = tomllib.load(open(sys.argv[1], "rb"))
r = eval(sys.argv[2])
print(r if isinstance(r, str) else json.dumps(r))' "$KEYS_TOML" "$1"
}

main_key() { keys_q "k['aerospace']['main'].get('$1')"; }
service_key() { keys_q "k['aerospace']['service'].get('$1')"; }

@test "aerospace: parses as TOML" {
  [ -f "$AS_TOML" ]
  as_q '"ok"'
  [ "$(keys_q '"ok"')" = ok ]
}

@test "aerospace: the base has no key bindings, grove-keys renders them" {
  [ "$(as_q "'mode' in c")" = false ]
}

@test "aerospace: starts at login and starts borders" {
  [ "$(as_q "c['start-at-login']")" = true ]
  [ "$(as_q "c['after-startup-command']")" = '["exec-and-forget /bin/sh ~/.config/borders/bordersrc"]' ]
}

@test "aerospace: gaps are 8; windows start 3 pt below the Grove bar's 48 pt strip" {
  [ "$(as_q "[c['gaps']['inner'][k] for k in ('horizontal', 'vertical')] + [c['gaps']['outer'][k] for k in ('left', 'right', 'bottom')]")" = "[8, 8, 8, 8, 8]" ]
  # The 3 pt keep a top-row window's border (width 5, ~2.5 pt outside the
  # window) clear of the opaque strip. 51 where the menu bar reserves nothing;
  # on the built-in screen macOS keeps 37.5 pt for the notch even when the
  # menu bar hides, so 14 more is ~51.
  [ "$(as_q "c['gaps']['outer']['top']")" = '[{"monitor": {"built-in": 14}}, 51]' ]
  # The border width the 3 pt are sized for.
  grep -q ' width=5.0 ' "$GROVE_ROOT/config/borders/bordersrc.tmpl"
}

@test "aerospace: Option shortcuts" {
  local n d dir
  for n in 1 2 3 4 5 6 7 8 9; do
    [ "$(main_key "alt-$n")" = "workspace $n" ] || { echo "alt-$n"; false; }
    [ "$(main_key "alt-shift-$n")" = "move-node-to-workspace $n" ] || { echo "alt-shift-$n"; false; }
  done
  for d in h:left j:down k:up l:right; do
    dir="${d#*:}"
    [ "$(main_key "alt-${d%%:*}")" = "focus $dir" ] || { echo "alt-${d%%:*}"; false; }
    [ "$(main_key "alt-shift-${d%%:*}")" = "move $dir" ] || { echo "alt-shift-${d%%:*}"; false; }
  done
  [ "$(main_key alt-minus)" = "resize smart -50" ]
  [ "$(main_key alt-equal)" = "resize smart +50" ]
  [ "$(main_key alt-slash)" = "layout tiles horizontal vertical" ]
  [ "$(main_key alt-comma)" = "layout accordion horizontal vertical" ]
  [ "$(main_key alt-tab)" = "workspace-back-and-forth" ]
  [ "$(main_key alt-shift-tab)" = "move-workspace-to-monitor --wrap-around next" ]
  [ "$(main_key alt-shift-semicolon)" = "mode service" ]
}

@test "aerospace: service mode resets, floats, closes others, joins, and returns to main" {
  [ "$(service_key esc)" = '["reload-config", "mode main"]' ]
  [ "$(service_key r)" = '["flatten-workspace-tree", "mode main"]' ]
  [ "$(service_key f)" = '["layout floating tiling", "mode main"]' ]
  [ "$(service_key backspace)" = '["close-all-windows-but-current", "mode main"]' ]
  local d
  for d in h:left j:down k:up l:right; do
    [ "$(service_key "alt-shift-${d%%:*}")" = "[\"join-with ${d#*:}\", \"mode main\"]" ] || { echo "${d%%:*}"; false; }
  done
}

@test "aerospace: only workspaces 1-9, none kept when empty" {
  [ "$(as_q "'persistent-workspaces' in c")" = false ]
  [ "$(keys_q "all(t in '123456789' and len(t) == 1 for m in k['aerospace'].values() for v in m.values() if isinstance(v, str) and v.split()[0] in ('workspace', 'move-node-to-workspace') for t in [v.split()[-1]])")" = true ]
}

@test "aerospace: no app is pinned to a workspace; windows open where you are" {
  [ "$(as_q "[r['run'] for r in c['on-window-detected'] if 'workspace' in r['run']]")" = "[]" ]
}

@test "aerospace: System Settings, Grove Themes, Grove Keys and Finder float, also at startup" {
  local id
  for id in com.apple.systempreferences com.projectgrove.themes com.projectgrove.keys com.apple.finder; do
    [ "$(as_q "[(r['run'], 'during-aerospace-startup' in r['if']) for r in c['on-window-detected'] if r['if'].get('app-id') == '$id']")" = '[["layout floating", false]]' ] || { echo "$id"; false; }
  done
}

@test "aerospace: the Grove window (Ghostty, title starting with Grove · ) floats; other Ghostty windows tile" {
  [ "$(as_q "[(r['if'], r['run']) for r in c['on-window-detected'] if r['if'].get('app-id') == 'com.mitchellh.ghostty']")" \
    = '[[{"app-id": "com.mitchellh.ghostty", "window-title-regex-substring": "^Grove \u00b7 "}, "layout floating"]]' ]
  # The pattern against the titles grove present gives and ordinary ones.
  [ "$(as_q "[bool(__import__('re').search(r['if']['window-title-regex-substring'], t)) for r in c['on-window-detected'] if 'window-title-regex-substring' in r['if'] for t in ('Grove · Check', 'Grove · grove', 'zsh', 'About Grove · x', 'Grove')]")" \
    = '[true, true, false, false, false]' ]
  # bin/grove builds that title.
  grep -q -- '--title=Grove · \$title' "$GROVE_ROOT/lib/present.sh"
}

@test "aerospace: a workspace change triggers the Grove bar" {
  [ "$(as_q "c['exec-on-workspace-change']")" = '["/bin/bash", "-c", "/opt/homebrew/bin/sketchybar --trigger aerospace_workspace_change FOCUSED=$AEROSPACE_FOCUSED_WORKSPACE"]' ]
}

@test "aerospace: a focus change (a window moved or opened elsewhere) also refreshes the bar" {
  [ "$(as_q "c['on-focus-changed']")" = '["exec-and-forget /opt/homebrew/bin/sketchybar --trigger aerospace_workspace_change"]' ]
}

load helpers
bats_require_minimum_version 1.5.0
setup() {
  gt_test_setup
  DOTFILES="$(cd "$GT_ROOT/../grove-dotfiles" && pwd -P)"
  export GROVE_ROOT="$BATS_TEST_TMPDIR/dotfiles"
  export GROVE_STATE="$HOME/.local/state/grove"
  export GROVE_RUN_ID=test-run
  mkdir -p "$GROVE_ROOT"
  cp -R "$DOTFILES/theme" "$GROVE_ROOT/theme"
  cp -R "$DOTFILES/lib" "$GROVE_ROOT/lib"
  gt_copy_config "$GROVE_ROOT/config"
  CLI="$GT_ROOT/bin/grove-themes"
  LOG="$GROVE_STATE/theme-log.jsonl"
}

gt_copy_config() {
  local dest="$1" f
  mkdir -p "$dest"
  while IFS= read -r f; do
    mkdir -p "$dest/$(dirname "$f")"
    cp "$DOTFILES/config/$f" "$dest/$f"
  done < <(git -C "$DOTFILES/config" ls-files . | grep '\.tmpl$')
}

@test "set appends one log line" {
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 1 ]
  [ "$(jq -r .scheme "$LOG")" = dark-soft ]
  [ "$(jq -r .exit "$LOG")" -eq 0 ]
  [[ "$(jq -r .time "$LOG")" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}[+-][0-9]{2}:[0-9]{2}$ ]] || false
  [ "$(jq -r '.steps[0].name' "$LOG")" = configs ]
}

@test "a failed render writes no log line" {
  rm -rf "$GROVE_ROOT/config"
  run "$CLI" set dark-soft
  [ "$status" -eq 1 ]
  [ ! -e "$LOG" ]
}

@test "a set with a needs-you step logs exit 1 and its steps" {
  stub osascript 'echo "not authorized" >&2; exit 1'
  run "$CLI" set dark-soft --json
  [ "$status" -eq 1 ]
  [ "$(jq -r .exit "$LOG")" -eq 1 ]
  [ "$(jq -c .steps "$LOG")" = "$(printf '%s' "$output" | jq -c .steps)" ]
  [ "$(jq -r '[.steps[] | select(.result == "needs-you")] | length' "$LOG")" -ge 1 ]
}

@test "the log keeps the last 50" {
  local i
  for i in $(seq 1 55); do
    bash -c ". '$GT_ROOT/lib/log.sh'; gt_log_append dark-soft 0 '{\"name\": \"n$i\", \"result\": \"live\", \"message\": \"\"}'"
  done
  [ "$(wc -l < "$LOG" | tr -d ' ')" -eq 50 ]
  [ "$(jq -r '.steps[0].name' "$LOG" | head -1)" = n6 ]
  [ "$(jq -r '.steps[0].name' "$LOG" | tail -1)" = n55 ]
}

@test "log --json lists newest first, 5 by default, -n 2 gives 2" {
  local i
  for i in 1 2 3 4 5 6 7; do
    bash -c ". '$GT_ROOT/lib/log.sh'; gt_log_append dark-soft 0 '{\"name\": \"n$i\", \"result\": \"live\", \"message\": \"\"}'"
  done
  run "$CLI" log --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '.entries | length')" -eq 5 ]
  [ "$(printf '%s' "$output" | jq -r '.entries[0].steps[0].name')" = n7 ]
  run "$CLI" log --json -n 2
  [ "$(printf '%s' "$output" | jq '.entries | length')" -eq 2 ]
  [ "$(printf '%s' "$output" | jq -r '.entries[1].steps[0].name')" = n6 ]
  run "$CLI" log -n 1
  [[ "$output" =~ ^[0-9T:+-]+\ dark-soft\ exit=0$ ]] || false
}

@test "log with no file is empty" {
  run "$CLI" log --json
  [ "$status" -eq 0 ]
  [ "$output" = '{"entries": []}' ]
  run "$CLI" log
  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "log skips a damaged line" {
  mkdir -p "$GROVE_STATE"
  printf '%s\n' '{"time": "x"' 'garbage' > "$LOG"
  bash -c ". '$GT_ROOT/lib/log.sh'; gt_log_append light-soft 0 ''"
  printf '%s\n' '{"time": "y", "scheme": "dark-hard", "exit": 0, "steps": [' >> "$LOG"
  run "$CLI" log --json
  [ "$status" -eq 0 ]
  [ "$(printf '%s' "$output" | jq '.entries | length')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.entries[0].scheme')" = light-soft ]
}

@test "control characters, quotes and backslashes in a step message stay valid JSON" {
  export GROVE_STATE="$HOME/st	a\"te\\x"
  LOG="$GROVE_STATE/theme-log.jsonl"
  run "$CLI" set dark-medium
  [ "$status" -eq 0 ]
  echo "# my edit" >> "$GROVE_ROOT/config/ghostty/config"
  run "$CLI" set dark-hard --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . > /dev/null
  [[ "$(printf '%s' "$output" | jq -r '.steps[0].message')" == "backed up edited ghostty/config to $GROVE_STATE/backup/"* ]] || false
  run "$CLI" log --json -n 1
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . > /dev/null
  [[ "$(printf '%s' "$output" | jq -r '.entries[0].steps[0].message')" == *"st	a\"te\\x"* ]] || false
}

@test "a log cut off without a newline doesn't swallow the next entry" {
  mkdir -p "$GROVE_STATE"
  printf '%s' '{"time": "2026-11-10T13:10:04+00:00", "scheme": "dark-hard", "exit": 0, "steps": [{"name": "conf' > "$LOG"
  run "$CLI" set dark-soft
  [ "$status" -eq 0 ]
  run "$CLI" log --json
  [ "$status" -eq 0 ]
  printf '%s' "$output" | jq -e . > /dev/null
  [ "$(printf '%s' "$output" | jq '.entries | length')" -eq 1 ]
  [ "$(printf '%s' "$output" | jq -r '.entries[0].scheme')" = dark-soft ]
}

@test "log rejects a line with a second entry glued on" {
  mkdir -p "$GROVE_STATE"
  printf '%s\n' '{"time": "a", "scheme": "dark-hard", "exit": 0, "steps": [{"name": "c{"time": "b", "scheme": "dark-soft", "exit": 0, "steps": []}' > "$LOG"
  run "$CLI" log --json
  [ "$output" = '{"entries": []}' ]
}

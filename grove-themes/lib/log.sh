# shellcheck shell=bash
# grove-themes switch log: $GROVE_STATE/theme-log.jsonl, one JSON object per
# line, the last 50 kept. Source it; it sets no shell options. Bash 3.2 safe.

GT_LOG_KEEP=50

_gt_log_file() { printf '%s\n' "$GROVE_STATE/theme-log.jsonl"; }

# gt_log_append SCHEME EXIT STEPS_JSON: add one line (STEPS_JSON is the
# contents of the "steps" array, as `set --json` prints it) and trim the file.
gt_log_append() {
  local scheme="$1" code="$2" steps="$3" file ts
  file="$(_gt_log_file)"
  ts="$(date +%Y-%m-%dT%H:%M:%S%z | sed 's/\([0-9][0-9]\)$/:\1/')"
  mkdir -p "$GROVE_STATE" || return 1
  printf '{"time": "%s", "scheme": "%s", "exit": %s, "steps": [%s]}\n' \
    "$ts" "$scheme" "$code" "$steps" >> "$file" || return 1
  if ! { tail -n "$GT_LOG_KEEP" "$file" > "$file.tmp" && mv "$file.tmp" "$file"; }; then
    rm -f "$file.tmp"
    return 1
  fi
}

# gt_log_read N: the newest N intact lines, newest first. A line is intact when
# it starts with {"time": " and ends with ]}; any other line is skipped.
gt_log_read() {
  local n="${1:-5}" file
  file="$(_gt_log_file)"
  [ -f "$file" ] || return 0
  grep '^{"time": "' "$file" | grep ']}$' | tail -n "$n" | sed '1!G;h;$!d'
  return 0
}

#!/bin/bash
# Grove bar · the clock popup's rows: this month from cal, one line per row (cal.1…cal.8), today underlined. plugins/popup.sh runs it before showing the popup.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Today's number is underlined: a combining low line after each digit, which
# takes no room, so the grid keeps its columns. (The rows have a fixed width
# in sketchybarrc, so the lines go in as cal prints them, leading spaces too.)
today="$(date +%-d 2>/dev/null)"
low=$'\xcc\xb2'
args=()
i=0
while IFS= read -r line; do
  [ -n "${line// /}" ] || continue
  i=$((i + 1)); [ "$i" -le 8 ] || break
  # From the third line on, seven cells of two characters, a space between.
  if [ "$i" -ge 3 ] && [ -n "$today" ]; then
    for c in 0 3 6 9 12 15 18; do
      cell="${line:c:2}"
      [ "${cell# }" = "$today" ] || continue
      marked="${cell# }"
      [ "${#marked}" -eq 1 ] && marked=" $marked$low" || marked="${marked:0:1}$low${marked:1:1}$low"
      line="${line:0:c}$marked${line:c+2}"
      today=""
      break
    done
  fi
  args+=(--set "cal.$i" drawing=on label="$line")
done <<< "$(cal 2>/dev/null)"
for ((j = i + 1; j <= 8; j++)); do args+=(--set "cal.$j" drawing=off); done
"$SB" "${args[@]}"

#!/bin/bash
# Grove bar · the clock popup's rows: this month from cal, one line per row (cal.1…cal.8). plugins/popup.sh runs it before showing the popup.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Hover: clickable items get a soft bg1 background under the pointer.
NAME="${NAME:-}"
case "${SENDER:-}" in
  mouse.entered) "$SB" --set "$NAME" background.drawing=on background.color="$BG1"; exit 0 ;;
  mouse.exited) "$SB" --set "$NAME" background.drawing=off; exit 0 ;;
esac

# SketchyBar measures a label without its leading spaces but draws them, so a
# row would lose that many characters at its end: lead with no-break spaces.
nbsp=$'\xc2\xa0'
args=()
i=0
while IFS= read -r line; do
  [ -n "${line// /}" ] || continue
  i=$((i + 1)); [ "$i" -le 8 ] || break
  lead="${line%%[! ]*}"
  line="${lead// /$nbsp}${line#"$lead"}"
  args+=(--set "cal.$i" drawing=on label="$line")
done <<< "$(cal 2>/dev/null)"
for ((j = i + 1; j <= 8; j++)); do args+=(--set "cal.$j" drawing=off); done
"$SB" "${args[@]}"

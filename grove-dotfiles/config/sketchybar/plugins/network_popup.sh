#!/bin/bash
# Grove bar · the network popup's rows: each interface's totals since boot (net.total.1…4) and the top five apps (net.app.1…5); nettop gets 2 s. plugins/popup.sh runs it before showing the popup.
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

args=()
i=0
while read -r name tin tout; do
  [ -n "$name" ] || continue
  i=$((i + 1)); [ "$i" -le 4 ] || break
  args+=(--set "net.total.$i" drawing=on label="$name  ↓ $(sb_bytes "$tin")  ↑ $(sb_bytes "$tout")")
done <<< "$(netstat -ibn 2>/dev/null | sb_totals)"
for ((j = i + 1; j <= 4; j++)); do args+=(--set "net.total.$j" drawing=off); done
# -n: no name lookups. With them nettop takes 5 s here, over its limit; without, 10 ms.
apps="$(sb_timeout 2 nettop -P -L 1 -x -n -J bytes_in,bytes_out 2>/dev/null | sb_top_apps 5)"
i=0
if [ -z "$apps" ]; then
  i=1
  args+=(--set net.app.1 drawing=on label="top apps unavailable")
else
  while IFS=$'\t' read -r name ain aout; do
    i=$((i + 1))
    args+=(--set "net.app.$i" drawing=on label="$name  ↓ $(sb_bytes "$ain")  ↑ $(sb_bytes "$aout")")
  done <<< "$apps"
fi
for ((j = i + 1; j <= 5; j++)); do args+=(--set "net.app.$j" drawing=off); done
"$SB" "${args[@]}"

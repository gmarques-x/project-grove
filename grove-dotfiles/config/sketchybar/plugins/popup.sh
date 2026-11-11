#!/bin/bash
# Grove bar · popup ITEM: a click on an item with a popup (clock, net.down). Opens it, rows filled first, and closes the other one; a second click closes it.
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

item="${1:-}"
# The plugin that fills each popup's rows.
case "$item" in
  clock) fill=clock_popup ;;
  net.down) fill=network_popup ;;
  *) exit 0 ;;
esac

open="$(sb_popup_open)"
# A click on the open popup's item closes it: nothing to fill.
if [ "$open" = "$item" ]; then
  sb_popup_close
  exit 0
fi
# Fill, then show: the popup never opens empty or with the last visit's rows.
# The fill is told no event, or it would take the click for a hover.
SENDER="" /bin/bash "$CONFIG_DIR/plugins/$fill.sh"
args=()
[ -z "$open" ] || args+=(--set "$open" popup.drawing=off)
args+=(--set "$item" popup.drawing=on)
echo "$item" > "$SB_POPUP"
"$SB" "${args[@]}"

#!/bin/bash
# Grove bar · the tray: the other apps' menu-bar items, which the bar covers, as Grove Keys lists them (tray_change): the symbol, and how many beside it; the symbol alone at 0 or without Grove Keys. A click opens its panel (Grove Keys).
# shellcheck shell=bash
# SketchyBar starts plugins with a minimal environment: PATH is set here, and
# tests point SB_PATH / SKETCHYBAR_BIN at fakes.
export PATH="${SB_PATH:-/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin}"
# shellcheck source-path=SCRIPTDIR/.. source=lib.sh
. "$CONFIG_DIR/lib.sh"
# shellcheck source=/dev/null
. "$CONFIG_DIR/colors.sh"
SB="${SKETCHYBAR_BIN:-sketchybar}"

# Hover: the pill under the pointer fills softly.
sb_hover && exit 0

# The bar never looks at the menu bar: Grove Keys lists its items, writes
# the count to a file when it changes, then sends tray_change; this only
# reads that file. The count is in a fixed-width label, hidden without one.
count="$(sb_tray)"
if [ -n "$count" ]; then
  "$SB" --set tray icon.background.image="$(sb_icon tray)" label="$count" label.drawing=on
else
  "$SB" --set tray icon.background.image="$(sb_icon tray)" label= label.drawing=off
fi

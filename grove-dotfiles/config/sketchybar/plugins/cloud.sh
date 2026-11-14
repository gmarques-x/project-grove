#!/bin/bash
# Grove bar · the cloud: whether iCloud Drive and the CloudStorage providers have finished syncing, as Grove Keys follows them (cloud_change): grey checking, green synced, yellow syncing with the count beside it, red a problem; grey without Grove Keys. A click opens its panel (Grove Keys).
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

# The bar never looks at the files: Grove Keys watches the folders, writes
# one line to a file when the state changes, then sends cloud_change; this
# only reads that file. The count is in a fixed-width label, hidden without one.
read -r icon count <<< "$(sb_cloud)"
if [ -n "$count" ]; then
  "$SB" --set cloud icon.background.image="$(sb_icon "$icon")" label="$count" label.drawing=on
else
  "$SB" --set cloud icon.background.image="$(sb_icon "$icon")" label= label.drawing=off
fi

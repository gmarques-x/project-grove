#!/bin/bash
# Grove bar · cpu and mem: used percentages in the bar, fg, yellow above 70%, red above 90%. A click on either opens the CPU & memory panel (Grove Keys).
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

stat="$(sb_timeout 3 iostat -n 0 -c 2 -w 1 2>/dev/null || true)"
cpu="$(sb_cpu <<< "$stat")"
mem="$( { vm_stat 2>/dev/null || true; } | sb_mem "$(sysctl -n hw.memsize 2>/dev/null)")"
# load_color PERCENT: fg, yellow above 70, red above 90.
load_color() {
  case "$(sb_load "$1")" in critical) echo "$RED" ;; high) echo "$YELLOW" ;; *) echo "$FG" ;; esac
}
"$SB" --set cpu label="$(sb_pct "$cpu")" label.color="$(load_color "$cpu")" \
  --set mem label="$(sb_pct "$mem")" label.color="$(load_color "$mem")"

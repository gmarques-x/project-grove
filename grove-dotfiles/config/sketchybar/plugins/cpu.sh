#!/bin/bash
# Grove bar · cpu and mem: used percentages in the bar, and the same two readings pushed to their popup's charts (sys.cpu, sys.mem) with the user and system split (sys.split). While that popup is open, its other rows are filled again too.
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

# While the popup is open, each core's load is measured over the same second
# as iostat's sample (SB_CORES tells the fill not to measure it again).
open="$(sb_popup_open)"
[ "$open" != cpu ] || exec 3< <(sb_core_loads 1)
stat="$(sb_timeout 3 iostat -n 0 -c 2 -w 1 2>/dev/null || true)"
cpu="$(sb_cpu <<< "$stat")"
read -r user system <<< "$(sb_cpu_split <<< "$stat")"
mem="$( { vm_stat 2>/dev/null || true; } | sb_mem "$(sysctl -n hw.memsize 2>/dev/null)")"
# load_color PERCENT: fg, yellow above 70, red above 90.
load_color() {
  case "$(sb_load "$1")" in critical) echo "$RED" ;; high) echo "$YELLOW" ;; *) echo "$FG" ;; esac
}
split="$SB_NONE"
[ -z "$user" ] || split="user $user% · system $system%"
"$SB" --set cpu label="$(sb_pct "$cpu")" label.color="$(load_color "$cpu")" \
  --set mem label="$(sb_pct "$mem")" label.color="$(load_color "$mem")" \
  --set sys.cpu label="$(sb_pct "$cpu")" --set sys.mem label="$(sb_pct "$mem")" --set sys.split label="$split" \
  --push sys.cpu "$(sb_graph_pct "$cpu")" --push sys.mem "$(sb_graph_pct "$mem")"
if [ "$open" = cpu ]; then
  read -r cores <&3 || true
  exec 3<&-
  SENDER="" SB_CORES="${cores:--}" /bin/bash "$CONFIG_DIR/plugins/system_popup.sh"
fi

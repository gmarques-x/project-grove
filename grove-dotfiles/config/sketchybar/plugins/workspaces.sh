#!/bin/bash
# Grove bar · workspaces ws.1…ws.9: the ones in use drawn, the focused one a green pill,
# each followed by its apps' icons (ws.N.1…6) and a separator (sep.ws.N).
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

used="$( { sb_timeout 2 aerospace list-workspaces --monitor all --empty no 2>/dev/null || true; } | sb_workspaces)"
focused="${FOCUSED:-$( { sb_timeout 2 aerospace list-workspaces --focused 2>/dev/null || true; } | sb_workspaces)}"
# The focused workspace shows even while it's empty (AeroSpace keeps it).
[ -n "$focused" ] && used="$used $focused"
apps="$( { sb_timeout 2 aerospace list-windows --all --format '%{workspace}|%{app-bundle-id}|%{window-id}' 2>/dev/null || true; } | sb_ws_apps)"
args=()
shown=" "
while read -r n k bundle wid; do
  [ -n "$wid" ] || continue
  [[ " $used " == *" $n "* ]] || continue
  args+=(--set "ws.$n.$k" drawing=on icon.background.image="app.$bundle" click_script="aerospace focus --window-id $wid")
  shown+="$n.$k "
done <<< "$apps"
for n in 1 2 3 4 5 6 7 8 9; do
  if [[ " $used " == *" $n "* ]]; then
    if [ "$n" = "$focused" ]; then
      args+=(--set "ws.$n" drawing=on background.drawing=on label.color="$BG0")
    else
      args+=(--set "ws.$n" drawing=on background.drawing=off label.color="$GREY2")
    fi
    args+=(--set "sep.ws.$n" drawing=on)
  else
    args+=(--set "ws.$n" drawing=off --set "sep.ws.$n" drawing=off)
  fi
  for k in 1 2 3 4 5 6; do
    [[ "$shown" == *" $n.$k "* ]] || args+=(--set "ws.$n.$k" drawing=off)
  done
done
"$SB" "${args[@]}"

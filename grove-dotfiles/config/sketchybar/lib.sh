#!/bin/bash
# Grove bar · the parsers and formatters every plugin sources. Each reads its
# command's output on stdin (or takes arguments) and prints the text for the
# bar; output it can't read gives "—". Tests: tests/sketchybar_lib.bats.

SB_NONE="—"

# Numbers and dates read the same whatever the Mac's region: macOS awk follows
# LC_NUMERIC (a decimal-comma locale prints "1,2M"), date follows
# LC_TIME (Portuguese day names). LC_ALL would win over both, so it steps down
# to LANG first, which keeps the text encoding.
if [ -n "${LC_ALL:-}" ]; then
  export LANG="$LC_ALL" LC_CTYPE="$LC_ALL"
  unset LC_ALL
fi
export LC_NUMERIC=C LC_TIME=C

# The open panel. The bar's dropdowns are panels drawn by Grove Keys, which
# names the pill of the open one in this file (missing: none open), so the
# hover leaves that pill filled and a workspace change costs one file test.
SB_PANEL="${GROVE_STATE:-$HOME/.local/state/grove}/bar-panel"

# sb_cpu < `iostat -n 0 -c 2 -w 1`: used percentage (100 − idle) from the last
# sample, which covers a whole second (top's single sample includes its own
# start-up and reads high).
sb_cpu() {
  awk '
    / id / || /^ *us +sy +id/ { for (i = 1; i <= NF; i++) if ($i == "id") col = i; next }
    col && $col ~ /^[0-9]+$/ { idle = $col }
    END { if (idle != "") print 100 - idle; else print "—" }'
}

# sb_timeout SECONDS COMMAND…: run COMMAND, stopped after SECONDS (macOS has
# no timeout(1)); SketchyBar doesn't reap a plugin stuck on a hung command.
sb_timeout() {
  perl -e 'alarm shift; exec @ARGV' "$@"
}

# sb_mem MEMSIZE < `vm_stat`: used percentage, (active + wired + compressed)
# pages × page size over MEMSIZE bytes (`sysctl -n hw.memsize`).
sb_mem() {
  local size="$1"
  case "$size" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  awk -v size="$size" '
    /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
    /^Pages active:/ { a = $3 }
    /^Pages wired down:/ { w = $4 }
    /^Pages occupied by compressor:/ { c = $5 }
    END {
      gsub(/\./, "", a); gsub(/\./, "", w); gsub(/\./, "", c)
      if (ps == "" || a == "") { print "—"; exit }
      printf "%.0f\n", (a + w + c) * ps / size * 100
    }'
}

# sb_battery < `pmset -g batt`: "87 charging" or "87 discharging" (any other
# state, e.g. "charged" or "AC attached", counts as charging), nothing
# without a battery.
sb_battery() {
  awk -F '\t' '/InternalBattery/ {
    split($2, f, ";"); level = f[1]; state = f[2]; gsub(/[ %]/, "", level); gsub(/ /, "", state)
    print level, (state == "discharging" ? "discharging" : "charging")
  }'
}

# sb_conn IFACE < `ipconfig getsummary IFACE`: how the Mac is online through
# the default route's interface: vpn (a tunnel), wifi, eth, or off.
sb_conn() {
  case "$1" in
    '') echo off; return ;;
    utun* | ipsec* | ppp* | tun* | tap*) echo vpn; return ;;
  esac
  awk '/^ *InterfaceType : / { t = $3 } END { print (t == "WiFi" ? "wifi" : "eth") }'
}

# sb_icon NAME: the file of a symbol icon in the scheme's set, dark or light
# (icons/NAME-SET.png). A colors.sh rendered before the icons has no
# ICON_SET: the pine's file says which.
sb_icon() {
  local set="${ICON_SET:-}"
  [ -n "$set" ] || case "${PINE_ICON:-}" in *light*) set=light ;; *) set=dark ;; esac
  echo "$CONFIG_DIR/icons/$1-$set.png"
}

# sb_wifi_level RSSI: the Wi-Fi fan's arcs for a signal in dBm: 3 (-60 or
# better), 2 (down to -72), 1 (weaker); 3 when the signal can't be read.
sb_wifi_level() {
  case "$1" in -[0-9]*) ;; *) echo 3; return ;; esac
  case "${1#-}" in *[!0-9]*) echo 3; return ;; esac
  if [ "$1" -ge -60 ]; then echo 3; elif [ "$1" -ge -72 ]; then echo 2; else echo 1; fi
}

# sb_vol_level PERCENT: the speaker icon's fill in tenths, 0 to 10; anything
# above silence shows at least 1.
sb_vol_level() {
  case "$1" in '' | *[!0-9]*) echo 0; return ;; esac
  if [ "$1" -eq 0 ]; then echo 0; elif [ "$1" -lt 10 ]; then echo 1; elif [ "$1" -ge 100 ]; then echo 10; else echo $((($1 + 5) / 10)); fi
}

# sb_load PERCENT: normal, high (above 70) or critical (above 90).
sb_load() {
  case "$1" in '' | *[!0-9]*) echo normal; return ;; esac
  if [ "$1" -gt 90 ]; then echo critical; elif [ "$1" -gt 70 ]; then echo high; else echo normal; fi
}

# sb_transparent: the colour of no fill. A colors.sh rendered before the pills
# has no TRANSPARENT: bg0 without its alpha is as clear.
sb_transparent() {
  echo "${TRANSPARENT:-0x00${BG0#0x??}}"
}

# sb_pill ITEM: the pill (bracket) an item of the bar sits in; nothing for an
# item outside the pills (the front app's name).
sb_pill() {
  local n
  case "$1" in
    grove | battery | wifi | volume | clock) echo "pill.$1" ;;
    cpu | mem) echo pill.sys ;;
    ws.[1-9] | ws.[1-9].*) n="${1#ws.}"; echo "pill.ws.${n%%.*}" ;;
  esac
}

# sb_panel_open: the pill whose panel is open ("pill.clock"), nothing when
# none is.
sb_panel_open() {
  local pill=""
  [ -f "$SB_PANEL" ] && read -r pill < "$SB_PANEL"
  case "$pill" in *[!a-z0-9._]*) pill="" ;; esac
  echo "$pill"
}

# sb_panel_close: tell Grove Keys to put the open panel away (nothing is run
# when none is open). -g: the link doesn't bring Grove Keys forward.
sb_panel_close() {
  [ -e "$SB_PANEL" ] || return 0
  open -g grovekeys://panel/close
}

# sb_hover: the pointer over a clickable item ($SENDER mouse.entered or
# mouse.exited, $NAME the item). Its pill fills with the hover colour, the
# orange outline untouched, and clears when the pointer leaves, unless its
# panel is open: that pill stays filled until Grove Keys closes the panel.
# An item outside the pills gets a fill of its own. Returns 1 for any other
# event, so a plugin starts with `sb_hover && exit 0`. Uses the plugin's $SB.
sb_hover() {
  local pill
  case "${SENDER:-}" in mouse.entered | mouse.exited) ;; *) return 1 ;; esac
  pill="$(sb_pill "${NAME:-}")"
  if [ -n "$pill" ]; then
    if [ "$SENDER" = mouse.entered ]; then
      "${SB:-sketchybar}" --set "$pill" background.color="${HOVER_FILL:-$BG1}"
    elif [ "$pill" != "$(sb_panel_open)" ]; then
      "${SB:-sketchybar}" --set "$pill" background.color="$(sb_transparent)"
    fi
  elif [ "$SENDER" = mouse.entered ]; then
    "${SB:-sketchybar}" --set "$NAME" background.drawing=on background.color="${HOVER_FILL:-$BG1}"
  else
    "${SB:-sketchybar}" --set "$NAME" background.drawing=off
  fi
  return 0
}

# sb_workspaces < `aerospace list-workspaces …`: the names, space-separated.
sb_workspaces() {
  awk 'NF { printf "%s%s", sep, $1; sep = " " } END { if (sep != "") print "" }'
}

# sb_ws_apps < `aerospace list-windows --all --format '%{workspace}|%{app-bundle-id}|%{window-id}'`:
# one line per app and workspace, "WORKSPACE SLOT BUNDLE-ID WINDOW-ID": each app
# once per workspace (its first window), in AeroSpace's order, six at most.
sb_ws_apps() {
  awk -F '|' '{ for (i = 1; i <= NF; i++) gsub(/^ +| +$/, "", $i) }
    $1 ~ /^[1-9]$/ && $2 ~ /^[A-Za-z0-9._-]+$/ && $3 ~ /^[0-9]+$/ && !seen[$1 FS $2]++ {
      k = ++count[$1]; if (k <= 6) print $1, k, $2, $3 }'
}

# sb_pct VALUE: "52%" for a whole number, "—" otherwise.
sb_pct() {
  case "$1" in '' | *[!0-9]*) echo "$SB_NONE" ;; *) echo "$1%" ;; esac
}

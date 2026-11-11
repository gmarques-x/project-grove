#!/bin/bash
# Grove bar · the parsers and formatters every plugin sources. Each reads its
# command's output on stdin (or takes arguments) and prints the text for the
# bar; output it can't read gives "—". Tests: tests/sketchybar_lib.bats.

SB_NONE="—"

# Numbers and dates read the same whatever the Mac's region: macOS awk follows
# LC_NUMERIC (a decimal-comma locale prints "1,2M"), date and cal follow
# LC_TIME (Portuguese day names). LC_ALL would win over both, so it steps down
# to LANG first, which keeps the text encoding.
if [ -n "${LC_ALL:-}" ]; then
  export LANG="$LC_ALL" LC_CTYPE="$LC_ALL"
  unset LC_ALL
fi
export LC_NUMERIC=C LC_TIME=C

# The open popup: its item's name is kept in this file (missing: none open),
# so closing it on an app or workspace switch costs one file test, no query.
# sketchybarrc removes it, as a reload closes every popup.
SB_POPUP="${TMPDIR:-/tmp}/grove-sketchybar-popup"

# sb_rate BYTES_PER_SECOND: compact, at most 5 characters so the bar's slot
# never moves: "512B", "84K", "1.2M" (one decimal under 10), "12M", "1.0G".
sb_rate() {
  local n="$1"
  case "$n" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  awk -v n="$n" 'BEGIN {
    if (n < 1024) printf "%dB\n", n
    else if (n < 1048576) printf "%dK\n", (n + 512) / 1024
    else if (n < 10485760) printf "%.1fM\n", n / 1048576
    else if (n < 1073741824) printf "%dM\n", n / 1048576 + 0.5
    else printf "%.1fG\n", n / 1073741824
  }'
}

# sb_bytes BYTES: "512 B", "2 KB", "8.9 MB" (one decimal under 100 MB),
# "179 MB", "2.3 GB" (one decimal).
sb_bytes() {
  local n="$1"
  case "$n" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  awk -v n="$n" 'BEGIN {
    if (n < 1024) printf "%d B\n", n
    else if (n < 1048576) printf "%d KB\n", (n + 512) / 1024
    else if (n < 1073741824) { m = n / 1048576; if (m < 100) printf "%.1f MB\n", m; else printf "%d MB\n", m + 0.5 }
    else printf "%.1f GB\n", n / 1073741824
  }'
}

# sb_rate_delta OLD NEW SECONDS: the rate between two byte counters; a counter
# that went down (an interface change, a reset) or a missing value is "—".
sb_rate_delta() {
  local old="$1" new="$2" secs="$3"
  case "$old$new$secs" in *[!0-9]*) echo "$SB_NONE"; return ;; esac
  if [ -z "$old" ] || [ -z "$new" ] || [ -z "$secs" ] || [ "$secs" -eq 0 ] || [ "$new" -lt "$old" ]; then
    echo "$SB_NONE"
    return
  fi
  sb_rate "$(((new - old) / secs))"
}

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

# sb_load PERCENT: normal, high (above 70) or critical (above 90).
sb_load() {
  case "$1" in '' | *[!0-9]*) echo normal; return ;; esac
  if [ "$1" -gt 90 ]; then echo critical; elif [ "$1" -gt 70 ]; then echo high; else echo normal; fi
}

# sb_ssid < `ipconfig getsummary en0`: the network name, "on" when macOS
# redacts it (no Location permission), "off" when not connected.
sb_ssid() {
  awk '
    /^ *LinkStatusActive : / { active = $3 }
    /^ *SSID : / { sub(/^ *SSID : /, ""); ssid = $0 }
    END {
      if (active != "TRUE" || ssid == "") print "off"
      else if (ssid == "<redacted>") print "on"
      else print ssid
    }'
}

# sb_iface_bytes IFACE < `netstat -ibn`: "IN OUT" bytes from IFACE's Link row.
sb_iface_bytes() {
  awk -v want="$1" '$1 == want && $3 ~ /^<Link#/ {
    if (NF >= 11) print $7, $10; else print $6, $9
    exit
  }'
}

# sb_totals < `netstat -ibn`: "iface in out" for each interface with traffic,
# loopback left out.
sb_totals() {
  awk '$3 ~ /^<Link#/ && $1 !~ /^lo/ {
    if (NF >= 11) { i = $7; o = $10 } else { i = $6; o = $9 }
    if (i + o > 0) print $1, i, o
  }'
}

# sb_top_apps N < `nettop -P -L 1 -x -n -J bytes_in,bytes_out` (CSV, each row
# "name.pid,in,out,"): the N largest by in + out, one "app<TAB>in<TAB>out"
# each, the ".pid" suffix dropped. Tabs, because a name can have spaces
# ("Google Chrome H"); the two counters are taken from the row's end.
sb_top_apps() {
  awk -v OFS='\t' '{
    sub(/,$/, "")
    if (!match($0, /,[0-9]+,[0-9]+$/)) next
    name = substr($0, 1, RSTART - 1); sub(/\.[0-9]+$/, "", name)
    if (name == "") next
    split(substr($0, RSTART + 1), b, ",")
    print b[1] + b[2], name, b[1], b[2]
  }' | sort -t "$(printf '\t')" -rn -k1,1 | head -n "$1" | cut -f 2-
}

# sb_popup_open: the item whose popup is open, nothing when none is.
sb_popup_open() {
  local item=""
  [ -f "$SB_POPUP" ] && read -r item < "$SB_POPUP"
  case "$item" in *[!a-z0-9._]*) item="" ;; esac
  echo "$item"
}

# sb_popup_close: close the open popup, if any (one sketchybar call; nothing
# is run when none is open). Uses the plugin's $SB.
sb_popup_close() {
  [ -e "$SB_POPUP" ] || return 0
  local item
  item="$(sb_popup_open)"
  rm -f "$SB_POPUP"
  [ -z "$item" ] || "${SB:-sketchybar}" --set "$item" popup.drawing=off
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

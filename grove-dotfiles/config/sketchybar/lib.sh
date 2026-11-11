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

# sb_graph_value BYTES_PER_SECOND: the chart's height for a rate, 0 to 1, on a
# log scale so a trickle and a download both show: 1 KB/s is 0.4, 1 MB/s 0.8,
# 32 MB/s and above 1.
sb_graph_value() {
  case "$1" in '' | *[!0-9]*) echo 0; return ;; esac
  awk -v n="$1" 'BEGIN { v = log(n + 1) / log(10) / 7.5; if (v > 1) v = 1; printf "%.3f\n", v }'
}

# sb_dns < `scutil --dns`: the name servers in use, each once, three at most,
# joined by ", ".
sb_dns() {
  awk '/nameserver\[[0-9]+\] : / && !seen[$3]++ && n < 3 { printf "%s%s", (n++ ? ", " : ""), $3 } END { if (n) print "" }'
}

# sb_graph_pct PERCENT: the chart's height for a percentage, 0 to 1 ("0.07",
# "0.52", "1"); 0 for anything else.
sb_graph_pct() {
  case "$1" in '' | *[!0-9]*) echo 0; return ;; esac
  if [ "$1" -ge 100 ]; then echo 1; else printf '0.%02d\n' "$1"; fi
}

# sb_cpu_split < `iostat -n 0 -c 2 -w 1`: "USER SYSTEM" percentages from the
# last sample, nothing when it can't be read.
sb_cpu_split() {
  awk '
    / id / || /^ *us +sy +id/ { for (i = 1; i <= NF; i++) { if ($i == "us") u = i; if ($i == "sy") s = i }; next }
    u && s && $u ~ /^[0-9]+$/ && $s ~ /^[0-9]+$/ { us = $u; sy = $s }
    END { if (us != "") print us, sy }'
}

# sb_sysctl KEY < `sysctl KEY…` (the "key: value" lines): KEY's value.
sb_sysctl() {
  awk -v k="$1: " 'index($0, k) == 1 { print substr($0, length(k) + 1); exit }'
}

# sb_loadavg < `sysctl vm.loadavg`: the 1, 5 and 15 minute load averages,
# "1.85 1.93 1.97".
sb_loadavg() {
  sb_sysctl vm.loadavg | awk '{ gsub(/[{}]/, ""); gsub(/,/, "."); if ($1 ~ /^[0-9.]+$/ && NF == 3) print $1, $2, $3 }'
}

# sb_cores < `sysctl hw.physicalcpu hw.perflevel0.physicalcpu hw.perflevel0.name …`:
# the cores by type, "4 Performance · 6 Efficiency"; "8 cores" on a Mac with
# one type.
sb_cores() {
  awk -F ': ' '
    /^hw\.perflevel[0-9]\.physicalcpu: / { n[substr($1, 13, 1)] = $2 }
    /^hw\.perflevel[0-9]\.name: / { name[substr($1, 13, 1)] = $2 }
    /^hw\.physicalcpu: / { all = $2 }
    END {
      for (i = 0; i <= 9; i++) if (n[i] ~ /^[0-9]+$/ && name[i] != "") out = out (out == "" ? "" : " · ") n[i] " " name[i]
      if (out == "" && all ~ /^[0-9]+$/) out = all " cores"
      if (out != "") print out
    }'
}

# sb_boot < `sysctl kern.boottime`: when the Mac started, in seconds since 1970.
sb_boot() {
  sb_sysctl kern.boottime | sed -n 's/^{ sec = \([0-9][0-9]*\),.*/\1/p'
}

# sb_duration SECONDS: "45s", "12m", "3h 59m", "2d 3h"; "—" otherwise.
sb_duration() {
  case "$1" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  if [ "$1" -lt 60 ]; then echo "$1s"
  elif [ "$1" -lt 3600 ]; then echo "$(($1 / 60))m"
  elif [ "$1" -lt 86400 ]; then echo "$(($1 / 3600))h $(($1 % 3600 / 60))m"
  else echo "$(($1 / 86400))d $(($1 % 86400 / 3600))h"; fi
}

# sb_swap < `sysctl vm.swapusage`: the swap in use, in bytes.
sb_swap() {
  sb_sysctl vm.swapusage | awk '{
    for (i = 1; i < NF - 1; i++) if ($i == "used" && $(i + 1) == "=") {
      v = $(i + 2); unit = substr(v, length(v)); sub(/[A-Za-z]$/, "", v); sub(/,/, ".", v)
      if (v !~ /^[0-9.]+$/) exit
      printf "%.0f\n", v * (unit == "G" ? 1073741824 : unit == "K" ? 1024 : 1048576)
      exit
    }
  }'
}

# sb_pressure < `sysctl kern.memorystatus_vm_pressure_level`: the memory
# pressure as Activity Monitor colours it: normal, warning or critical.
sb_pressure() {
  case "$(sb_sysctl kern.memorystatus_vm_pressure_level)" in
    1) echo normal ;;
    2) echo warning ;;
    4) echo critical ;;
  esac
}

# sb_mem_parts < `vm_stat`: "USED APP WIRED COMPRESSED" in bytes. USED is what
# sb_mem counts (active + wired + compressed); the other three are Activity
# Monitor's: app memory (anonymous − purgeable pages), wired, compressed.
sb_mem_parts() {
  awk '
    /page size of/ { for (i = 1; i <= NF; i++) if ($i == "of") ps = $(i + 1) }
    /^Pages active:/ { a = $3 }
    /^Pages wired down:/ { w = $4 }
    /^Pages purgeable:/ { p = $3 }
    /^Anonymous pages:/ { an = $3 }
    /^Pages occupied by compressor:/ { c = $5 }
    END {
      gsub(/\./, "", a); gsub(/\./, "", w); gsub(/\./, "", p); gsub(/\./, "", an); gsub(/\./, "", c)
      if (ps == "" || a == "" || an == "") exit
      app = an - p; if (app < 0) app = 0
      printf "%.0f %.0f %.0f %.0f\n", (a + w + c) * ps, app * ps, w * ps, c * ps
    }'
}

# sb_gb BYTES: gigabytes with one decimal and no unit, "12.9"; "—" otherwise.
sb_gb() {
  case "$1" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  awk -v n="$1" 'BEGIN { printf "%.1f\n", n / 1073741824 }'
}

# sb_top_cpu N < `ps -Aceo pcpu,rss,comm`: the N processes using the CPU most,
# one "name<TAB>percent" each ("WindowServer<TAB>7.4"); idle ones left out.
sb_top_cpu() {
  awk -v OFS='\t' 'NR > 1 {
    p = $1; sub(/,/, ".", p)
    name = $0; sub(/^ *[^ ]+ +[^ ]+ +/, "", name)
    if (p ~ /^[0-9.]+$/ && p + 0 > 0 && name != "") print p, name
  }' | sort -t "$(printf '\t')" -k1,1rn -k2,2 | head -n "$1" | awk -F '\t' -v OFS='\t' '{ print $2, $1 }'
}

# sb_top_mem N < `ps -Aceo pcpu,rss,comm`: the N processes holding the most
# memory, one "name<TAB>bytes" each.
sb_top_mem() {
  awk -v OFS='\t' 'NR > 1 {
    name = $0; sub(/^ *[^ ]+ +[^ ]+ +/, "", name)
    if ($2 ~ /^[0-9]+$/ && $2 > 0 && name != "") print $2, name
  }' | sort -t "$(printf '\t')" -k1,1rn -k2,2 | head -n "$1" | awk -F '\t' -v OFS='\t' '{ printf "%s\t%.0f\n", $2, $1 * 1024 }'
}

# sb_name NAME: a process name short enough for a popup row, 24 characters at
# most, cut with "…".
sb_name() {
  if [ "${#1}" -gt 24 ]; then echo "${1:0:23}…"; else echo "$1"; fi
}

# sb_core_loads SECONDS: each core's load over SECONDS, as percentages in the
# cores' order ("12 40 3 …"). Reads the kernel's per-core tick counters twice
# through JavaScript for Automation: no root and no helper.
sb_core_loads() {
  case "$1" in '' | *[!0-9.]*) return ;; esac
  sb_timeout 4 osascript -l JavaScript -e '
    ObjC.bindFunction("mach_host_self", ["unsigned int", []]);
    ObjC.bindFunction("host_processor_info", ["int", ["unsigned int", "int", "unsigned int *", "int **", "unsigned int *"]]);
    function ticks() {
      var n = Ref(), info = Ref(), count = Ref(), t = [];
      if ($.host_processor_info($.mach_host_self(), 2, n, info, count) != 0) return t;
      for (var i = 0; i < count[0]; i++) t.push(info[0][i]);
      return t;
    }
    function run(argv) {
      var a = ticks(); delay(Number(argv[0])); var b = ticks(), out = [];
      // Four counters a core: user, system, idle, nice.
      for (var c = 0; c * 4 + 3 < b.length && b.length == a.length; c++) {
        var busy = 0, all = 0;
        for (var k = 0; k < 4; k++) { var d = (b[c * 4 + k] - a[c * 4 + k]) | 0; all += d; if (k != 2) busy += d; }
        out.push(all > 0 ? Math.round(100 * busy / all) : 0);
      }
      return out.join(" ");
    }' "$1" 2>/dev/null
}

# sb_core_types < `ioreg -p IODeviceTree -r -k cluster-type -d 1`: each core's
# type in the cores' order, "EEEEEEPPPP" (E efficiency, P performance);
# nothing on a Mac that doesn't say.
sb_core_types() {
  awk '
    function keep() { if (id != "" && type != "") { t[id] = type; if (id + 0 > max) max = id + 0; any = 1 }; id = ""; type = "" }
    /^ *\+-o / { keep() }
    /"cluster-type" = <"[A-Z]">/ { type = $0; sub(/.*<"/, "", type); sub(/">.*/, "", type) }
    /"logical-cpu-id" = [0-9]+/ { id = $NF }
    END {
      keep()
      if (!any) exit
      for (i = 0; i <= max; i++) out = out (t[i] == "" ? "?" : t[i])
      print out
    }'
}

# sb_core_rows TYPES < the loads from sb_core_loads: one row per core type,
# "P<TAB>34 12 8 2" then "E<TAB>40 31 …"; without usable TYPES one row,
# "-<TAB>…", for all the cores.
sb_core_rows() {
  awk -v types="$1" -v OFS='\t' '
    NR == 1 {
      for (i = 1; i <= NF; i++) if ($i !~ /^[0-9]+$/) exit
      if (NF == 0) exit
      if (length(types) != NF || types ~ /[^EP]/) {
        for (i = 1; i <= NF; i++) all = all (i > 1 ? " " : "") $i
        print "-", all; exit
      }
      for (i = 1; i <= NF; i++) { k = substr(types, i, 1); row[k] = row[k] (row[k] == "" ? "" : " ") $i }
      if (row["P"] != "") print "P", row["P"]
      if (row["E"] != "") print "E", row["E"]
    }'
}

# sb_batt_status < `pmset -g batt`: "LEVEL|STATE|TIME|SOURCE": the charge in
# percent; charging, on battery, charged or "plugged in, not charging"; the
# time macOS estimates ("1:42", empty without an estimate); ac or battery.
# Nothing without a battery.
sb_batt_status() {
  awk -F '\t' '
    /^Now drawing from/ { source = ($0 ~ /AC Power/ ? "ac" : "battery") }
    /InternalBattery/ {
      n = split($2, f, ";"); level = f[1]; state = f[2]; gsub(/[ %]/, "", level); gsub(/^ +| +$/, "", state)
      if (state == "discharging") state = "on battery"
      else if (state == "charging" || state == "finishing charge") state = "charging"
      else if (state == "AC attached") state = "plugged in, not charging"
      time = ""
      if (match($2, /[0-9]+:[0-9][0-9] remaining/)) { time = substr($2, RSTART, RLENGTH - 10); if (time == "0:00") time = "" }
      print level "|" state "|" time "|" source
      exit
    }'
}

# sb_ioreg KEY < `ioreg -rn AppleSmartBattery`: KEY's value, a number, Yes/No
# or a string without its quotes. A key of the battery itself wins over the
# same name inside one of its dictionaries.
sb_ioreg() {
  awk -v key="$1" '
    function value(rest) {
      if (rest ~ /^"/) { sub(/^"/, "", rest); sub(/".*/, "", rest); return rest }
      if (match(rest, /^[0-9]+|^Yes|^No/)) return substr(rest, 1, RLENGTH)
      return ""
    }
    {
      if (match($0, "^[ |]*\"" key "\" = ")) { top = value(substr($0, RSTART + RLENGTH)); found = 1; exit }
      if (inner == "" && match($0, "\"" key "\" ?= ?")) inner = value(substr($0, RSTART + RLENGTH))
    }
    END { if (found) print top; else if (inner != "") print inner }'
}

# sb_batt_power < `ioreg -rn AppleSmartBattery`: the watts going into the
# battery ("4.9") or out of it ("-12.3"): Amperage (mA) × Voltage (mV). A
# discharge comes as a 64-bit two's complement number.
sb_batt_power() {
  local reg amps volts
  reg="$(cat)"
  amps="$(sb_ioreg Amperage <<< "$reg")"
  volts="$(sb_ioreg Voltage <<< "$reg")"
  case "$amps$volts" in '' | *[!0-9]*) return ;; esac
  [ -n "$amps" ] && [ -n "$volts" ] || return 0
  awk -v a="$amps" -v v="$volts" 'BEGIN {
    # 2^64 is 18446744073709551616: past what awk counts exactly, so the
    # last ten digits are taken on their own.
    if (length(a) == 20 && substr(a, 1, 10) == "1844674407") a = substr(a, 11) - 3709551616
    printf "%.1f\n", a * v / 1000000
  }'
}

# sb_watts MILLIWATTS: "9.0"; "—" otherwise.
sb_watts() {
  case "$1" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  awk -v n="$1" 'BEGIN { printf "%.1f\n", n / 1000 }'
}

# sb_batt_health < `system_profiler SPPowerDataType`: the battery's health as
# System Settings gives it, "100% · Normal"; nothing when it isn't there.
sb_batt_health() {
  awk -F ': ' '
    /^ *Maximum Capacity: / { cap = $2 }
    /^ *Condition: / { cond = $2 }
    END { if (cap != "") print cap (cond != "" ? " · " cond : ""); else if (cond != "") print cond }'
}

# sb_lowpower < `pmset -g`: Low Power Mode, on or off; nothing on a Mac
# without it.
sb_lowpower() {
  awk '$1 == "lowpowermode" { print ($2 == 1 ? "on" : "off"); exit }'
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

# sb_hover: the pointer over a clickable item ($SENDER mouse.entered or
# mouse.exited, $NAME the item). Its pill fills with the hover colour, the
# orange outline untouched, and clears when the pointer leaves; an item
# outside the pills gets a fill of its own. Returns 1 for any other event, so
# a plugin starts with `sb_hover && exit 0`. Uses the plugin's $SB.
sb_hover() {
  local pill
  case "${SENDER:-}" in mouse.entered | mouse.exited) ;; *) return 1 ;; esac
  pill="$(sb_pill "${NAME:-}")"
  if [ -n "$pill" ]; then
    if [ "$SENDER" = mouse.entered ]; then
      "${SB:-sketchybar}" --set "$pill" background.color="${HOVER_FILL:-$BG1}"
    else
      "${SB:-sketchybar}" --set "$pill" background.color="$(sb_transparent)"
    fi
  elif [ "$SENDER" = mouse.entered ]; then
    "${SB:-sketchybar}" --set "$NAME" background.drawing=on background.color="${HOVER_FILL:-$BG1}"
  else
    "${SB:-sketchybar}" --set "$NAME" background.drawing=off
  fi
  return 0
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

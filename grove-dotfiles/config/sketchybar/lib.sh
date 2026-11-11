#!/bin/bash
# Grove bar · the parsers and formatters every plugin sources. Each reads its
# command's output on stdin (or takes arguments) and prints the text for the
# bar; output it can't read gives "—". Tests: tests/sketchybar_lib.bats.

SB_NONE="—"

# sb_rate BYTES_PER_SECOND: "512 B/s", "84 KB/s" (no decimals under 1 MB),
# "1.2 MB/s" (one decimal).
sb_rate() {
  local n="$1"
  case "$n" in '' | *[!0-9]*) echo "$SB_NONE"; return ;; esac
  if [ "$n" -lt 1024 ]; then
    echo "$n B/s"
  elif [ "$n" -lt 1048576 ]; then
    echo "$(((n + 512) / 1024)) KB/s"
  else
    awk -v n="$n" 'BEGIN { printf "%.1f MB/s\n", n / 1048576 }'
  fi
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

# sb_cpu < `top -l 1 -n 0`: used percentage (100 − idle), whole number.
sb_cpu() {
  awk '/CPU usage:/ {
    for (i = 1; i <= NF; i++) if ($i == "idle") { v = $(i - 1); gsub(/%/, "", v); gsub(/,/, ".", v); found = 1 }
  }
  END { if (found && v ~ /^[0-9.]+$/) printf "%.0f\n", 100 - v; else print "—" }'
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

# sb_battery < `pmset -g batt`: "87% charging", "87%", or nothing (no battery).
sb_battery() {
  awk -F '\t' '/InternalBattery/ {
    split($2, f, ";"); level = f[1]; state = f[2]; gsub(/ /, "", state)
    if (state == "charging") print level " charging"; else print level
  }'
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

# sb_top_apps N < `nettop -P -L 1 -x -J bytes_in,bytes_out`: the N largest
# "app in out" by in + out (the ".pid" suffix dropped).
sb_top_apps() {
  awk -F ',' -v n="$1" 'NR > 1 && $1 != "" {
    name = $1; sub(/\.[0-9]+$/, "", name)
    print ($2 + $3), name, $2, $3
  }' | sort -rn -k1,1 | head -n "$1" | awk '{ print $2, $3, $4 }'
}

# sb_workspaces < `aerospace list-workspaces …`: the names, space-separated.
sb_workspaces() {
  awk 'NF { printf "%s%s", sep, $1; sep = " " } END { if (sep != "") print "" }'
}

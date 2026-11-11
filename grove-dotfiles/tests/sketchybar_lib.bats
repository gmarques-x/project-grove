#!/usr/bin/env bats
# config/sketchybar/lib.sh: the parsers and formatters every bar plugin uses,
# against output recorded from macOS (anonymised) in fixtures/sketchybar/.

load helpers

setup() {
  grove_test_setup
  FX="$GROVE_ROOT/tests/fixtures/sketchybar"
  # shellcheck source=/dev/null
  . "$GROVE_ROOT/config/sketchybar/lib.sh"
}

@test "sb_rate: compact, at most 5 characters: B, K, M (one decimal under 10), G" {
  [ "$(sb_rate 0)" = "0B" ]
  [ "$(sb_rate 512)" = "512B" ]
  [ "$(sb_rate 1023)" = "1023B" ]
  [ "$(sb_rate 1024)" = "1K" ]
  [ "$(sb_rate 86016)" = "84K" ]
  [ "$(sb_rate 1048575)" = "1024K" ]
  [ "$(sb_rate 1048576)" = "1.0M" ]
  [ "$(sb_rate 1258291)" = "1.2M" ]
  [ "$(sb_rate 12582912)" = "12M" ]
  [ "$(sb_rate 1073741824)" = "1.0G" ]
}

@test "sb_rate: anything but a whole number is —" {
  [ "$(sb_rate "")" = "—" ]
  [ "$(sb_rate abc)" = "—" ]
  [ "$(sb_rate -5)" = "—" ]
}

@test "sb_bytes: B, KB, MB (one decimal under 100), GB (one decimal)" {
  [ "$(sb_bytes 0)" = "0 B" ]
  [ "$(sb_bytes 2048)" = "2 KB" ]
  [ "$(sb_bytes 1907949)" = "1.8 MB" ]
  [ "$(sb_bytes 9322838)" = "8.9 MB" ]
  [ "$(sb_bytes 187654321)" = "179 MB" ]
  [ "$(sb_bytes 2456789012)" = "2.3 GB" ]
  [ "$(sb_bytes x)" = "—" ]
}

@test "sb_rate_delta: bytes over seconds; a counter that went down or is missing is —" {
  [ "$(sb_rate_delta 1000 3048 2)" = "1K" ]
  [ "$(sb_rate_delta 0 2516582 2)" = "1.2M" ]
  [ "$(sb_rate_delta 5000 4000 2)" = "—" ]
  [ "$(sb_rate_delta "" 4000 2)" = "—" ]
  [ "$(sb_rate_delta 1000 2000 0)" = "—" ]
}

@test "sb_cpu: used percentage (100 − idle) from the last iostat sample" {
  [ "$(sb_cpu < "$FX/iostat.txt")" = 9 ]
  [ "$(echo nonsense | sb_cpu)" = "—" ]
  [ "$(printf '      cpu    load average\n us sy id   1m   5m   15m\n' | sb_cpu)" = "—" ]
}

@test "sb_mem: active + wired + compressed pages over the memory size" {
  [ "$(sb_mem 25769803776 < "$FX/vm_stat.txt")" = 52 ]
  [ "$(sb_mem "" < "$FX/vm_stat.txt")" = "—" ]
  [ "$(echo nonsense | sb_mem 25769803776)" = "—" ]
}

@test "sb_battery: level and whether it's charging, nothing without a battery" {
  [ "$(sb_battery < "$FX/pmset-charging.txt")" = "87 charging" ]
  [ "$(sb_battery < "$FX/pmset-battery.txt")" = "100 discharging" ]
  [ "$(sb_battery < "$FX/pmset-none.txt")" = "" ]
}

@test "sb_conn: vpn for a tunnel, wifi or eth from the interface type, off without a route" {
  [ "$(sb_conn utun3 < /dev/null)" = "vpn" ]
  [ "$(sb_conn ipsec0 < /dev/null)" = "vpn" ]
  [ "$(sb_conn en0 < "$FX/ipconfig-wifi.txt")" = "wifi" ]
  [ "$(sb_conn en5 < "$FX/ipconfig-eth.txt")" = "eth" ]
  [ "$(sb_conn "" < /dev/null)" = "off" ]
}

@test "sb_load: high above 70, critical above 90" {
  [ "$(sb_load 12)" = "normal" ]
  [ "$(sb_load 70)" = "normal" ]
  [ "$(sb_load 71)" = "high" ]
  [ "$(sb_load 90)" = "high" ]
  [ "$(sb_load 91)" = "critical" ]
  [ "$(sb_load —)" = "normal" ]
}

@test "sb_ssid: the network name, on when macOS redacts it, off when not connected" {
  [ "$(sb_ssid < "$FX/ipconfig-wifi.txt")" = "Grove Home" ]
  [ "$(sb_ssid < "$FX/ipconfig-redacted.txt")" = "on" ]
  [ "$(sb_ssid < "$FX/ipconfig-off.txt")" = "off" ]
  [ "$(: | sb_ssid)" = "off" ]
}

@test "sb_iface_bytes: an interface's in and out bytes from its Link row" {
  [ "$(sb_iface_bytes en0 < "$FX/netstat.txt")" = "2456789012 187654321" ]
  [ "$(sb_iface_bytes nope < "$FX/netstat.txt")" = "" ]
}

@test "sb_totals: one line per interface with traffic, loopback left out" {
  run sb_totals < "$FX/netstat.txt"
  [ "${lines[0]}" = "en0 2456789012 187654321" ]
  [ "${lines[1]}" = "utun3 4123456 912345" ]
  [ "${#lines[@]}" -eq 2 ]
}

@test "sb_top_apps: the N largest by in + out, process ids dropped" {
  run sb_top_apps 3 < "$FX/nettop.csv"
  [ "${lines[0]}" = "mDNSResponder 9322838 1907949" ]
  [ "${lines[1]}" = "exchangesyncd 637014 64154" ]
  [ "${lines[2]}" = "apsd 137341 492814" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "sb_workspaces: the numbers in use, space-separated" {
  [ "$(sb_workspaces < "$FX/workspaces.txt")" = "1 3 5" ]
  [ "$(sb_workspaces < "$FX/workspaces-none.txt")" = "" ]
}

@test "sb_ws_apps: each app once per workspace, numbered slots, six at most" {
  local out
  out="$(printf '1|com.google.Chrome|50\n1 | com.mitchellh.ghostty | 27\n1|com.google.Chrome|51\n2|com.google.Chrome|52\nx|bad|1\n1||9\n' | sb_ws_apps)"
  [ "$out" = "1 1 com.google.Chrome 50
1 2 com.mitchellh.ghostty 27
2 1 com.google.Chrome 52" ]
  out="$(for i in 1 2 3 4 5 6 7 8; do echo "3|app.n$i|$i"; done | sb_ws_apps | wc -l | tr -d ' ')"
  [ "$out" = 6 ]
}

@test "sb_pct: a whole number gets %, anything else is —" {
  [ "$(sb_pct 52)" = "52%" ]
  [ "$(sb_pct —)" = "—" ]
  [ "$(sb_pct "")" = "—" ]
}

@test "sb_timeout: a command that hangs is stopped after the limit" {
  local start=$SECONDS
  run sb_timeout 1 /bin/sleep 5
  [ "$status" -ne 0 ]
  [ $((SECONDS - start)) -lt 4 ]
  [ "$(sb_timeout 2 /bin/echo ok)" = ok ]
}

@test "lib.sh passes shellcheck" {
  command -v shellcheck >/dev/null || skip "no shellcheck"
  shellcheck "$GROVE_ROOT/config/sketchybar/lib.sh"
}

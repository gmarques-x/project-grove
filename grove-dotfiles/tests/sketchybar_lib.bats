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

@test "sb_icon: the symbol's file in the scheme's set; without ICON_SET the pine's file says which" {
  CONFIG_DIR=/cfg
  [ "$(ICON_SET=dark sb_icon wifi-2)" = "/cfg/icons/wifi-2-dark.png" ]
  [ "$(ICON_SET=light sb_icon vol-mute)" = "/cfg/icons/vol-mute-light.png" ]
  [ "$(ICON_SET='' PINE_ICON=/cfg/icons/pine-light.png sb_icon cpu)" = "/cfg/icons/cpu-light.png" ]
  [ "$(ICON_SET='' PINE_ICON=/cfg/icons/pine-dark.png sb_icon cpu)" = "/cfg/icons/cpu-dark.png" ]
  [ "$(unset ICON_SET PINE_ICON; sb_icon cpu)" = "/cfg/icons/cpu-dark.png" ]
}

@test "sb_wifi_level: three arcs from -60 dBm, two down to -72, one below; three when it can't be read" {
  [ "$(sb_wifi_level -40)" = 3 ]
  [ "$(sb_wifi_level -60)" = 3 ]
  [ "$(sb_wifi_level -61)" = 2 ]
  [ "$(sb_wifi_level -72)" = 2 ]
  [ "$(sb_wifi_level -73)" = 1 ]
  [ "$(sb_wifi_level -95)" = 1 ]
  [ "$(sb_wifi_level "")" = 3 ]
  [ "$(sb_wifi_level 0)" = 3 ]
  [ "$(sb_wifi_level -6x)" = 3 ]
  [ "$(sb_wifi_level nonsense)" = 3 ]
}

@test "sb_vol_level: tenths, rounded; anything above silence is at least 1" {
  [ "$(sb_vol_level 0)" = 0 ]
  [ "$(sb_vol_level 1)" = 1 ]
  [ "$(sb_vol_level 9)" = 1 ]
  [ "$(sb_vol_level 14)" = 1 ]
  [ "$(sb_vol_level 15)" = 2 ]
  [ "$(sb_vol_level 56)" = 6 ]
  [ "$(sb_vol_level 94)" = 9 ]
  [ "$(sb_vol_level 95)" = 10 ]
  [ "$(sb_vol_level 100)" = 10 ]
  [ "$(sb_vol_level "")" = 0 ]
  [ "$(sb_vol_level loud)" = 0 ]
}

@test "sb_graph_value: a rate on a log scale from 0 to 1" {
  [ "$(sb_graph_value 0)" = "0.000" ]
  [ "$(sb_graph_value 1024)" = "0.401" ]
  [ "$(sb_graph_value 2048)" = "0.442" ]
  [ "$(sb_graph_value 1048576)" = "0.803" ]
  [ "$(sb_graph_value 33554432)" = "1.000" ]
  [ "$(sb_graph_value 999999999999)" = "1.000" ]
  [ "$(sb_graph_value "")" = 0 ]
  [ "$(sb_graph_value —)" = 0 ]
}

@test "sb_graph_pct: a percentage as the chart's 0 to 1" {
  [ "$(sb_graph_pct 0)" = "0.00" ]
  [ "$(sb_graph_pct 7)" = "0.07" ]
  [ "$(sb_graph_pct 52)" = "0.52" ]
  [ "$(sb_graph_pct 100)" = 1 ]
  [ "$(sb_graph_pct 140)" = 1 ]
  [ "$(sb_graph_pct —)" = 0 ]
  [ "$(sb_graph_pct "")" = 0 ]
}

@test "sb_dns: the name servers in use, each once, three at most" {
  [ "$(sb_dns < "$FX/scutil-dns.txt")" = "192.168.1.1" ]
  [ "$(printf '  nameserver[0] : 1.1.1.1\n  nameserver[1] : 9.9.9.9\n  nameserver[0] : 1.1.1.1\n  nameserver[0] : 8.8.8.8\n  nameserver[1] : 8.8.4.4\n' | sb_dns)" = "1.1.1.1, 9.9.9.9, 8.8.8.8" ]
  [ "$(echo 'DNS configuration' | sb_dns)" = "" ]
}

@test "sb_cpu_split: user and system from the last iostat sample" {
  [ "$(sb_cpu_split < "$FX/iostat.txt")" = "6 4" ]
  [ "$(echo nonsense | sb_cpu_split)" = "" ]
  [ "$(printf '      cpu    load average\n us sy id   1m   5m   15m\n' | sb_cpu_split)" = "" ]
}

@test "sb_sysctl: one key's value from sysctl's lines" {
  [ "$(sb_sysctl hw.memsize < "$FX/sysctl.txt")" = 25769803776 ]
  [ "$(sb_sysctl hw.perflevel1.name < "$FX/sysctl.txt")" = Efficiency ]
  # A key that only starts another's name isn't it.
  [ "$(sb_sysctl hw.perflevel < "$FX/sysctl.txt")" = "" ]
  [ "$(sb_sysctl kern.nope < "$FX/sysctl.txt")" = "" ]
}

@test "sb_loadavg: the 1, 5 and 15 minute load averages" {
  [ "$(sb_loadavg < "$FX/sysctl.txt")" = "1.85 1.93 1.97" ]
  # A decimal-comma locale's sysctl.
  [ "$(echo 'vm.loadavg: { 2,25 1,95 1,98 }' | sb_loadavg)" = "2.25 1.95 1.98" ]
  [ "$(echo 'vm.loadavg: nonsense' | sb_loadavg)" = "" ]
  [ "$(: | sb_loadavg)" = "" ]
}

@test "sb_cores: how many cores of each type; one count on a Mac with one type" {
  [ "$(sb_cores < "$FX/sysctl.txt")" = "4 Performance · 6 Efficiency" ]
  [ "$(echo 'hw.physicalcpu: 8' | sb_cores)" = "8 cores" ]
  [ "$(: | sb_cores)" = "" ]
}

@test "sb_boot and sb_duration: the uptime from the boot time" {
  [ "$(sb_boot < "$FX/sysctl.txt")" = 1794421254 ]
  [ "$(echo 'kern.boottime: nonsense' | sb_boot)" = "" ]
  [ "$(sb_duration 45)" = "45s" ]
  [ "$(sb_duration 60)" = "1m" ]
  [ "$(sb_duration 3599)" = "59m" ]
  [ "$(sb_duration 14520)" = "4h 2m" ]
  [ "$(sb_duration 86399)" = "23h 59m" ]
  [ "$(sb_duration 200000)" = "2d 7h" ]
  [ "$(sb_duration "")" = "—" ]
  [ "$(sb_duration -5)" = "—" ]
}

@test "sb_swap: the swap in use, in bytes" {
  [ "$(sb_swap < "$FX/sysctl.txt")" = 0 ]
  [ "$(echo 'vm.swapusage: total = 2048.00M  used = 1269.75M  free = 778.25M  (encrypted)' | sb_swap)" = 1331429376 ]
  [ "$(echo 'vm.swapusage: total = 2048,00M  used = 1269,75M  free = 778,25M  (encrypted)' | sb_swap)" = 1331429376 ]
  [ "$(echo 'vm.swapusage: nonsense' | sb_swap)" = "" ]
}

@test "sb_pressure: the memory pressure level as a word" {
  [ "$(sb_pressure < "$FX/sysctl.txt")" = normal ]
  [ "$(echo 'kern.memorystatus_vm_pressure_level: 2' | sb_pressure)" = warning ]
  [ "$(echo 'kern.memorystatus_vm_pressure_level: 4' | sb_pressure)" = critical ]
  [ "$(: | sb_pressure)" = "" ]
}

@test "sb_mem_parts: used as the bar counts it, then app memory, wired and compressed, in bytes" {
  # 16384-byte pages: active 667404, wired 122886, compressor 23440, anonymous 707698, purgeable 33913.
  [ "$(sb_mem_parts < "$FX/vm_stat.txt")" = "13332152320 11039293440 2013364224 384040960" ]
  [ "$(echo nonsense | sb_mem_parts)" = "" ]
  [ "$(sb_gb 13332152320)" = "12.4" ]
  [ "$(sb_gb 25769803776)" = "24.0" ]
  [ "$(sb_gb x)" = "—" ]
}

@test "sb_top_cpu and sb_top_mem: the N processes using the most, names with spaces whole" {
  run sb_top_cpu 3 < "$FX/ps.txt"
  [ "${lines[0]}" = "launchd"$'\t'"18.7" ]
  [ "${lines[1]}" = "WindowServer"$'\t'"7.4" ]
  [ "${lines[2]}" = "ghostty"$'\t'"2.6" ]
  [ "${#lines[@]}" -eq 3 ]
  run sb_top_mem 6 < "$FX/ps.txt"
  [ "${lines[0]}" = "SourceKitService"$'\t'"868220928" ]
  [ "${lines[2]}" = "Google Chrome"$'\t'"323649536" ]
  [ "${lines[4]}" = "Siri AI"$'\t'"226557952" ]
  [ "${#lines[@]}" -eq 6 ]
  # Idle processes aren't busy ones; a decimal comma is a point.
  [ "$(printf ' %%CPU    RSS COMM\n  0,0   1024 idle one\n  3,5   2048 busy one\n' | sb_top_cpu 5)" = "busy one"$'\t'"3.5" ]
  [ "$(printf ' %%CPU    RSS COMM\n' | sb_top_mem 5)" = "" ]
  [ "$(sb_name ghostty)" = ghostty ]
  [ "$(sb_name com.apple.DriverKit-AppleBCMWLAN)" = "com.apple.DriverKit-App…" ]
}

@test "sb_core_types and sb_core_rows: the cores' loads on a row per type, performance first" {
  local types
  types="$(sb_core_types < "$FX/ioreg-cpus.txt")"
  [ "$types" = EEEEEEPPPP ]
  [ "$(: | sb_core_types)" = "" ]
  run sb_core_rows "$types" <<< "12 40 3 8 1 2 50 60 70 80"
  [ "${lines[0]}" = "P"$'\t'"50 60 70 80" ]
  [ "${lines[1]}" = "E"$'\t'"12 40 3 8 1 2" ]
  [ "${#lines[@]}" -eq 2 ]
  # Types that don't fit the loads (or none): every core on one row.
  [ "$(sb_core_rows "" <<< "1 2 3")" = "-"$'\t'"1 2 3" ]
  [ "$(sb_core_rows EEPP <<< "1 2 3")" = "-"$'\t'"1 2 3" ]
  [ "$(sb_core_rows EEPP <<< "1 2 x 4")" = "" ]
  [ "$(sb_core_rows EEPP <<< "")" = "" ]
}

@test "sb_core_loads: one percentage per core, from the kernel's counters" {
  [ "$(sb_core_loads "")" = "" ]
  [ "$(sb_core_loads abc)" = "" ]
  [ "$(uname -s)" = Darwin ] || skip "macOS only"
  local out n
  out="$(sb_core_loads 0.1)"
  [ -n "$out" ] || skip "no JavaScript for Automation here"
  [[ "$out" =~ ^[0-9]+(\ [0-9]+)*$ ]] || { echo "$out"; false; }
  n="$(wc -w <<< "$out" | tr -d ' ')"
  [ "$n" -eq "$(sysctl -n hw.logicalcpu)" ] || { echo "$out"; false; }
  for n in $out; do [ "$n" -le 100 ]; done
}

@test "sb_batt_status: level, state, time and source; nothing without a battery" {
  [ "$(sb_batt_status < "$FX/pmset-finishing.txt")" = "99|charging|0:13|ac" ]
  [ "$(sb_batt_status < "$FX/pmset-charging.txt")" = "87|charging|0:42|ac" ]
  [ "$(sb_batt_status < "$FX/pmset-battery.txt")" = "100|on battery|8:56|battery" ]
  [ "$(sb_batt_status < "$FX/pmset-none.txt")" = "" ]
  [ "$(printf "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t100%%; charged; 0:00 remaining present: true\n" | sb_batt_status)" = "100|charged||ac" ]
  [ "$(printf "Now drawing from 'AC Power'\n -InternalBattery-0 (id=1)\t80%%; AC attached; not charging present: true\n" | sb_batt_status)" = "80|plugged in, not charging||ac" ]
  [ "$(printf "Now drawing from 'Battery Power'\n -InternalBattery-0 (id=1)\t64%%; discharging; (no estimate) present: true\n" | sb_batt_status)" = "64|on battery||battery" ]
}

@test "sb_ioreg: a battery key's value; the battery's own key wins over one inside a dictionary" {
  [ "$(sb_ioreg CycleCount < "$FX/ioreg-battery.txt")" = 96 ]
  [ "$(sb_ioreg ExternalConnected < "$FX/ioreg-battery.txt")" = Yes ]
  # Only inside BatteryData, AdapterDetails, PowerTelemetryData on this Mac.
  [ "$(sb_ioreg AppleRawMaxCapacity < "$FX/ioreg-battery.txt")" = 5493 ]
  [ "$(sb_ioreg DesignCapacity < "$FX/ioreg-battery.txt")" = 5760 ]
  [ "$(sb_ioreg Watts < "$FX/ioreg-battery.txt")" = 94 ]
  [ "$(sb_ioreg Name < "$FX/ioreg-battery.txt")" = "140W USB-C Power Adapter" ]
  [ "$(sb_ioreg SystemLoad < "$FX/ioreg-battery.txt")" = 7730 ]
  # The battery's CurrentCapacity is a percentage; BatteryData has it too, and raw ones beside it.
  [ "$(sb_ioreg CurrentCapacity < "$FX/ioreg-battery.txt")" = 99 ]
  [ "$(printf '  |   "Other" = {"Voltage"=1,"X"=2}\n  |   "Voltage" = 13343\n' | sb_ioreg Voltage)" = 13343 ]
  # This Mac publishes no Temperature.
  [ "$(sb_ioreg Temperature < "$FX/ioreg-battery.txt")" = "" ]
  [ "$(: | sb_ioreg CycleCount)" = "" ]
}

@test "sb_batt_power: watts into the battery, negative on a discharge" {
  # 312 mA × 13343 mV.
  [ "$(sb_batt_power < "$FX/ioreg-battery.txt")" = "4.2" ]
  # -1000 mA as ioreg prints it.
  [ "$(sed 's/"Amperage" = [0-9]*/"Amperage" = 18446744073709550616/' "$FX/ioreg-battery.txt" | sb_batt_power)" = "-13.3" ]
  [ "$(sed 's/"Amperage" = [0-9]*/"Amperage" = 0/' "$FX/ioreg-battery.txt" | sb_batt_power)" = "0.0" ]
  [ "$(echo nonsense | sb_batt_power)" = "" ]
  [ "$(sb_watts 7730)" = "7.7" ]
  [ "$(sb_watts "")" = "—" ]
}

@test "sb_batt_health: System Settings' maximum capacity and condition" {
  [ "$(sb_batt_health < "$FX/system_profiler-power.txt")" = "100% · Normal" ]
  [ "$(printf '          Maximum Capacity: 87%%\n' | sb_batt_health)" = "87%" ]
  [ "$(echo 'Power:' | sb_batt_health)" = "" ]
}

@test "sb_lowpower: Low Power Mode on or off, nothing where pmset doesn't list it" {
  [ "$(sb_lowpower < "$FX/pmset-g.txt")" = off ]
  [ "$(sed 's/lowpowermode         0/lowpowermode         1/' "$FX/pmset-g.txt" | sb_lowpower)" = on ]
  [ "$(echo ' sleep 1' | sb_lowpower)" = "" ]
}

@test "fixtures: nothing recorded from this Mac names its serial numbers" {
  ! grep -nE '"Serial(String)?" ?= ?"[^X"]' "$FX/ioreg-battery.txt"
  ! grep -nE 'Serial Number: [^X]' "$FX/system_profiler-power.txt"
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

@test "sb_top_apps: the N largest by in + out, tab-separated, process ids dropped" {
  run sb_top_apps 3 < "$FX/nettop.csv"
  [ "${lines[0]}" = "mDNSResponder"$'\t'"9322838"$'\t'"1907949" ]
  [ "${lines[2]}" = "exchangesyncd"$'\t'"637014"$'\t'"64154" ]
  [ "${#lines[@]}" -eq 3 ]
}

@test "sb_top_apps: a name with spaces (or a comma) stays whole" {
  run sb_top_apps 3 < "$FX/nettop.csv"
  [ "${lines[1]}" = "Google Chrome H"$'\t'"2126350"$'\t'"76220" ]
  [ "$(printf ',bytes_in,bytes_out,\nAcme, Inc Helper.12,5,7,\n' | sb_top_apps 5)" = "Acme, Inc Helper"$'\t'"5"$'\t'"7" ]
  [ "$(printf ',bytes_in,bytes_out,\n' | sb_top_apps 5)" = "" ]
}

@test "locale: a decimal-comma, Portuguese locale changes neither numbers nor dates" {
  locale -a | grep -qx 'pt_PT.UTF-8' || skip "no pt_PT.UTF-8 locale"
  # The locale does change both without lib.sh, so the test means something.
  [ "$(LC_ALL=pt_PT.UTF-8 awk 'BEGIN { printf "%.1f", 1.2 }')" = "1,2" ]
  local lib="$GROVE_ROOT/config/sketchybar/lib.sh" how
  for how in LC_ALL LANG; do
    run env -i "$how=pt_PT.UTF-8" /bin/bash -c '. "$1"; sb_rate 1258291; sb_bytes 9322838; sb_bytes 2456789012; printf "100 pages of page size of 16384\nPages active: 300000.\nPages wired down: 200000.\nPages occupied by compressor: 318000.\n" | sb_mem 25769803776; date -j -f %Y-%m-%d 2026-11-11 "+%a %-d %b"; echo "${LC_ALL:-unset}"; sb_graph_value 1024; sb_gb 13332152320; sb_watts 7730; sb_batt_power < "$2/ioreg-battery.txt"; sb_loadavg < "$2/sysctl.txt"; sb_top_cpu 1 < "$2/ps.txt"' _ "$lib" "$FX"
    [ "$status" -eq 0 ]
    [ "${lines[0]}" = "1.2M" ] || { echo "$how: ${lines[0]}"; false; }
    [ "${lines[1]}" = "8.9 MB" ]
    [ "${lines[2]}" = "2.3 GB" ]
    [ "${lines[3]}" = "52" ]
    [ "${lines[4]}" = "Wed 11 Nov" ] || { echo "$how: ${lines[4]}"; false; }
    [ "${lines[5]}" = "unset" ]
    [ "${lines[6]}" = "0.401" ] || { echo "$how: ${lines[6]}"; false; }
    [ "${lines[7]}" = "12.4" ]
    [ "${lines[8]}" = "7.7" ]
    [ "${lines[9]}" = "4.2" ]
    [ "${lines[10]}" = "1.85 1.93 1.97" ]
    [ "${lines[11]}" = "launchd"$'\t'"18.7" ]
  done
}

@test "sb_transparent: no fill, from colors.sh or bg0 without its alpha" {
  [ "$(TRANSPARENT=0x00000000 BG0=0xff2D353B sb_transparent)" = 0x00000000 ]
  [ "$(unset TRANSPARENT; BG0=0xff2D353B sb_transparent)" = 0x002D353B ]
}

@test "sb_pill: the pill each item of the bar sits in" {
  [ "$(sb_pill grove)" = pill.grove ]
  [ "$(sb_pill cpu)" = pill.sys ]
  [ "$(sb_pill mem)" = pill.sys ]
  [ "$(sb_pill battery)" = pill.battery ]
  [ "$(sb_pill wifi)" = pill.wifi ]
  [ "$(sb_pill volume)" = pill.volume ]
  [ "$(sb_pill clock)" = pill.clock ]
  [ "$(sb_pill ws.3)" = pill.ws.3 ]
  [ "$(sb_pill ws.7.2)" = pill.ws.7 ]
  [ "$(sb_pill ws.7.end)" = pill.ws.7 ]
  [ "$(sb_pill front_app)" = "" ]
  [ "$(sb_pill gap.r1)" = "" ]
  [ "$(sb_pill "")" = "" ]
}

@test "sb_hover: fills the item's pill on enter, clears it on exit; any other event is not a hover" {
  SB="$BATS_TEST_TMPDIR/sketchybar"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$SB"
  chmod +x "$SB"
  BG0=0xff2D353B BG1=0xff343F44 HOVER_FILL=0xffE6E2CC TRANSPARENT=0x00000000
  NAME=cpu SENDER=mouse.entered sb_hover
  NAME=cpu SENDER=mouse.exited sb_hover
  NAME=front_app SENDER=mouse.entered sb_hover
  NAME=front_app SENDER=mouse.exited sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.sys background.color=0xffE6E2CC
--set pill.sys background.color=0x00000000
--set front_app background.drawing=on background.color=0xffE6E2CC
--set front_app background.drawing=off" ]
  : > "$BATS_TEST_TMPDIR/calls"
  # A colors.sh without the hover role: bg1.
  unset HOVER_FILL
  NAME=clock SENDER=mouse.entered sb_hover
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set pill.clock background.color=0xff343F44" ]
  : > "$BATS_TEST_TMPDIR/calls"
  local sender
  for sender in "" routine mouse.clicked front_app_switched; do
    ! NAME=cpu SENDER="$sender" sb_hover || { echo "$sender"; false; }
  done
  [ ! -s "$BATS_TEST_TMPDIR/calls" ]
}

@test "sb_popup_open: the item whose popup is open, nothing when none is" {
  SB_POPUP="$BATS_TEST_TMPDIR/popup"
  [ "$(sb_popup_open)" = "" ]
  echo wifi > "$SB_POPUP"
  [ "$(sb_popup_open)" = "wifi" ]
  echo 'x; rm -rf y' > "$SB_POPUP"
  [ "$(sb_popup_open)" = "" ]
}

@test "sb_popup_close: closes the open popup and forgets it; nothing to run when none is open" {
  SB_POPUP="$BATS_TEST_TMPDIR/popup"
  SB="$BATS_TEST_TMPDIR/sketchybar"
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >> "%s"\n' "$BATS_TEST_TMPDIR/calls" > "$SB"
  chmod +x "$SB"
  sb_popup_close
  [ ! -e "$BATS_TEST_TMPDIR/calls" ]
  echo clock > "$SB_POPUP"
  sb_popup_close
  [ "$(cat "$BATS_TEST_TMPDIR/calls")" = "--set clock popup.drawing=off" ]
  [ ! -e "$SB_POPUP" ]
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

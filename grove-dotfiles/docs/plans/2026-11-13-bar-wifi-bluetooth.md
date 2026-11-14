# Bar Wi-Fi + Bluetooth Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Bluetooth joins Wi-Fi in one bar pill with a stacked dropdown, the power pill moves beside the clock, and the CPU & memory dropdown's middle line turns orange.

**Architecture:** Grove Keys' Core parses `system_profiler SPBluetoothDataType -json` and decides the bar icon state; the app reads it, draws a Bluetooth section under the Wi-Fi panel, toggles power, and writes `$GROVE_STATE/bluetooth` for the bar (like `wifi-name`). SketchyBar's config reorders the right side and adds a `bt` item to the Wi-Fi pill.

**Tech Stack:** Swift 6, SwiftUI, IOBluetooth (power only), Swift Testing; bash + bats for SketchyBar.

**Spec:** grove-dotfiles/docs/specs/2026-11-13-bar-wifi-bluetooth-design.md

## Global Constraints
- Order left to right: `cpu/mem · wifi+bt · sound · power · clock`.
- Bluetooth icon states `off` / `on` / `connected`; files `bt-off`, `bt-on`, `bt-connected` (`-dark.png`/`-light.png`) from `config/sketchybar/icons/make.swift`.
- State file `$GROVE_STATE/bluetooth` holding exactly `off`, `on` or `connected`; event `bluetooth_change`.
- Copy: header `Bluetooth`; `No devices connected`; `Bluetooth is off`; `Grove Keys needs Bluetooth permission`; usage string `Grove Keys shows your Bluetooth devices and their batteries in the Grove bar.`
- Orange only on the CPU/memory middle line and the Wi-Fi/Bluetooth line inside the dropdowns.
- No real device names or Bluetooth addresses in committed fixtures, tests, renders' sample data or docs (public repo).
- grove-ui skill (`~/.claude/skills/grove-ui/SKILL.md`). GroveKeys binary only with `--render-panel`, `--check-menu`, `--render-aerospace`, `--render-keys`; never relaunch the installed apps; never install; never toggle the real Bluetooth. Never commit the private working folders; never touch `config/grove-keys/keys.toml`, `config/grove/local.env`.
- Commits: `area: summary` + body + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, by explicit path.

## Review Focus
1. `system_profiler` output with no `SPBluetoothDataType` entry (no controller, permission refused, or an error) must give "off/unknown" without crashing (Task 1 test `missingControllerIsOff`).
2. A device with a battery reported in several fields (left/right/case for AirPods) shows one sensible number — the lowest — not three rows (Task 1 test `airPodsShowTheLowestBattery`).
3. The state file is written only on change, never every 30 s, so the bar isn't redrawn needlessly (Task 2 step).
4. SketchyBar reload with the dropdown open keeps the Wi-Fi pill filled (the existing `sb_panel_open` path; Task 2 bats test).
5. Bluetooth permission refused: no repeated prompts, the section explains and links to the setting (Task 3 step).

---

### Task 1: Bluetooth in Core
**Files:** Create `grove-keys/app/Sources/GroveKeysCore/Bluetooth.swift`; Test `grove-keys/app/Tests/GroveKeysCoreTests/BluetoothTests.swift`, fixtures `Fixtures/bluetooth-on.json`, `bluetooth-off.json`.

**Interfaces — Produces:**
- `public struct BluetoothDevice: Equatable, Sendable, Identifiable { public let id: String; public let name: String; public let kind: Kind; public let battery: Int? }` with `public enum Kind: Sendable { case headphones, keyboard, mouse, trackpad, speaker, other }` (from `device_minorType` / name).
- `public struct BluetoothState: Equatable, Sendable { public var power: Bool?; public var connected: [BluetoothDevice] }`, `public static func parse(systemProfilerJSON: Data) -> BluetoothState`.
- `public enum BluetoothIcon: String { case off, on, connected }`, `public static func icon(for: BluetoothState) -> BluetoothIcon` (nil power → off).

- [ ] **Step 1:** Record `system_profiler SPBluetoothDataType -json` on this Mac once, then anonymise it into the two fixtures by hand: device names → `Headphones`, `Keyboard`, `Mouse`, addresses → `00:00:00:00:00:0N`, keep the structure and battery fields. Never commit the raw output.
- [ ] **Step 2: Failing tests:** `parsesConnectedDevices` (names, kinds, batteries from `bluetooth-on.json`), `powerOff` (`bluetooth-off.json` → `power == false`, no devices), `missingControllerIsOff` (`{}` and garbage → `power == nil`, icon `.off`), `airPodsShowTheLowestBattery` (left 80, right 60, case 100 → 60), `iconStates` (off / on with none / connected).
- [ ] **Step 3:** Run `cd grove-keys/app && swift test --filter BluetoothTests` — FAIL; implement; run again — PASS; `swift test` once.
- [ ] **Step 4: Commit** `keys: Bluetooth state from system_profiler, in Core`.

### Task 2: The bar
**Files:** Modify `grove-dotfiles/config/sketchybar/sketchybarrc`, `config/sketchybar/icons/make.swift` (+ generated PNGs), Create `config/sketchybar/plugins/bluetooth.sh`; Modify `grove-keys/app/Sources/GroveKeys/` — a `BluetoothWriter.swift` beside `WifiNameWriter.swift`; Test `grove-dotfiles/tests/sketchybar_config.bats`.

**Interfaces — Consumes:** Task 1 `BluetoothState.parse`, `icon(for:)`. **Produces:** `$GROVE_STATE/bluetooth`, event `bluetooth_change`, item `bt` in bracket `pill.wifi`.

- [ ] **Step 1: Failing bats:** right-side items in order `clock`, `battery`, `volume`, `bt`, `wifi`, `mem`, `cpu` (as SketchyBar adds them right to left); `pill.wifi` brackets `wifi bt`; `bt`'s click opens the same panel as `wifi`; `bt` subscribes `bluetooth_change`; `bluetooth.sh` maps the three file values to the three icons and a missing file to `bt-off`.
- [ ] **Step 2:** Implement the reorder (gaps renumbered), the `bt` item and `bluetooth.sh` (follow `wifi.sh`'s hover and icon pattern), the three icons in `make.swift` (`bluetooth` symbols, sized as the Wi-Fi fan), regenerate PNGs.
- [ ] **Step 3:** `BluetoothWriter`: reads every 30 s off the main thread, writes the file atomically only when the icon state changes (Review Focus 3), then `sketchybar --trigger bluetooth_change`.
- [ ] **Step 4:** `bats tests/sketchybar_config.bats tests/sketchybar_lib.bats`, `shellcheck` on the plugin — PASS; `swift build`. Commit `bar: Bluetooth beside Wi-Fi, power beside the clock`.

### Task 3: The dropdowns
**Files:** Modify `grove-keys/app/Sources/GroveKeys/Panels/WifiPanel.swift`, `SystemPanel.swift` (~:332 middle line), `BarPanels.swift` (sample data), `grove-dotfiles/modules/96-keys-app/module.sh` (usage string), Create `Panels/BluetoothSection.swift`, `BluetoothPower.swift`; docs `docs/manual/` (the bar chapter).

- [ ] **Step 1:** CPU & memory: the middle line `theme.orange`, others unchanged.
- [ ] **Step 2:** Wi-Fi panel: an orange line, then `BluetoothSection` (header with a native `Toggle` `.switch` tinted green; rows: kind icon via GroveIcon, name, battery % in quiet text; the empty and off texts). Data from `BluetoothState` read when the panel opens.
- [ ] **Step 3:** `BluetoothPower.set(_ on: Bool) -> Bool` via `dlsym` of `IOBluetoothPreferenceSetControllerPowerState`; false → open `x-apple.systempreferences:com.apple.preference.Bluetooth`. Permission refused (`CBManager.authorization == .denied`) → the permission text and a button to the privacy pane; never re-asks (Review Focus 5).
- [ ] **Step 4:** Usage string in the 96 module's Info.plist; bats for that module still pass.
- [ ] **Step 5:** Sample data in `BarPanels` (anonymised devices); renders `--render-panel wifi` (on with devices, off, permission refused) and `system`, dark-medium and light-medium, into a private folder; look at each.
- [ ] **Step 6:** Manual: the bar chapter's pill list and a Bluetooth paragraph. `swift test`; commit `keys: Bluetooth under Wi-Fi in its dropdown; orange CPU/memory line`.
- [ ] **Step 7: STOP.** Hand back renders and a by-hand list: macOS's Bluetooth prompt; the pill's icon on/off/connected; the switch turns Bluetooth off and on; device batteries; the new order; the orange lines. The controller installs (96 and 99-sketchybar) only on the owner's word.

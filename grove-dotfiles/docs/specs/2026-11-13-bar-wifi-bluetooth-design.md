# Bar: Wi-Fi + Bluetooth pill, power pill moved, orange CPU/memory separator

Date: 2026-11-13. Status: approved in conversation (short design).

## Intent
Three changes the owner decided on 2026-11-12 (roadmap): Bluetooth gets a place in the bar next to Wi-Fi, the power pill moves next to the clock, and the CPU & memory dropdown's middle line is orange. The grove-lab VPN icon and the cloud storage icon are separate pieces, designed later.

## Decided
- **Order** (left to right on the right side): `cpu/mem · wifi+bt · sound · power · clock` (today: `cpu/mem · power · wifi · sound · clock`).
- **CPU & memory dropdown:** the line between the CPU half and the memory half is orange (the owner's exception to "no orange inside a panel"); other lines keep `theme.line`.
- **Wi-Fi + Bluetooth pill:** one pill with both icons side by side, as CPU and memory share theirs. The Bluetooth icon has three states: off, on (nothing connected), connected (at least one device connected). A click on either icon opens one stacked dropdown: today's Wi-Fi panel on top, an orange line, then Bluetooth underneath.
- **Bluetooth section:** a header "Bluetooth" with an on/off switch; the connected devices, one row each (name, kind icon, battery % when the device reports one); "No devices connected" when none; "Bluetooth is off" when off.

## Approaches
One sensible way: Grove Keys (which already owns every dropdown and writes `$GROVE_STATE/wifi-name` for the bar) reads Bluetooth, draws the section, and keeps a small state file for the bar's icon, exactly like the Wi-Fi name. Rejected: a bar script polling `system_profiler` itself (slow, ~1 s, and the bar's scripts should stay cheap); a third-party tool such as `blueutil` (a new dependency for one switch).

## How (the builder's frame)
- Reading: `system_profiler SPBluetoothDataType -json` off the main thread when the panel opens and every 30 s while Grove Keys runs (controller state, connected devices, battery levels); parsing is pure Core, tested with an anonymised fixture (no real device names or addresses in the repo — the repo is public).
- The switch: `IOBluetoothPreferenceSetControllerPowerState` (IOBluetooth, looked up at run time); if it isn't there, the switch opens System Settings ▸ Bluetooth instead.
- Bar icon: Grove Keys writes `off` / `on` / `connected` to `$GROVE_STATE/bluetooth` on change and triggers a `bluetooth_change` event; a `bt` item in the Wi-Fi pill reads it. Icons `bt-off`, `bt-on`, `bt-connected` (dark and light) come from the existing `icons/make.swift` (SF Symbols), sized as the Wi-Fi fan.
- Permission: macOS asks once for Bluetooth (`NSBluetoothAlwaysUsageDescription` in Grove Keys' Info.plist: "Grove Keys shows your Bluetooth devices and their batteries in the Grove bar."). The prompt is the owner's to answer; refused, the section says "Grove Keys needs Bluetooth permission" with a button to the privacy setting.
- Renders of the stacked dropdown (on with devices, off, permission refused) and the CPU & memory dropdown, dark and light, via `--render-panel`; the bar pill order checked in the bats config test.

## Non-goals
The VPN icon, the cloud icon, pairing new devices, Wi-Fi changes beyond stacking.

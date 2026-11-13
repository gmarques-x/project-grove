# Bar: the grove-lab VPN pill

Date: 2026-11-13. Status: approved in conversation (short design).

## Intent
Start and stop the grove-lab tunnel (WireGuard to Warden; it carries only the lab's own subnet) from the Grove bar, without Terminal and without a password.

## Approaches (the owner picked 1)
1. **The official WireGuard app (App Store)** with the profile imported as a macOS VPN configuration named `grove-lab`; the bar uses `scutil --nc start|stop|status "grove-lab"`. No root, no password; macOS does the connecting. **Chosen.**
2. A password-free sudo rule for `wg-quick`: rejected after discussion — every tool in the chain (wg-quick, wg, wireguard-go, Homebrew bash) is in user-owned Homebrew folders, so the rule would let anything running as the owner become root.
3. macOS's admin password dialog on each click: rejected — a prompt every time.

## The owner's one-time setup (his steps)
Install WireGuard from the App Store; `sudo wg-quick down ~/Developer/grove-lab/wireguard/warden-air.conf`; in WireGuard, *Import tunnel(s) from file…* → `warden-air.conf`, name it `grove-lab`, allow the VPN configuration. Nothing in Grove ever reads the profile (it holds the private key).

## Design
- **Pill:** its own pill with a shield icon, order `cpu/mem · vpn · wifi+bt · sound · power · clock`. Icon states: `vpn-off` (grey, as the other "off" icons), `vpn-connecting` (yellow), `vpn-on` (purple — the free per-pill hue). Files from `config/sketchybar/icons/make.swift` (SF Symbol `lock.shield`), dark and light. The existing `vpn` icon used by the Wi-Fi pill for a full-tunnel VPN stays as it is.
- **State:** the bar's plugin runs `scutil --nc status "grove-lab"` every 10 s and after a click; first line `Connected` / `Connecting` / `Disconnecting` / `Disconnected` / `No service` (and anything else → off). `No service` keeps the pill shown, grey.
- **Dropdown** (Grove Keys, like the others): header "grove-lab VPN" with an on/off switch (`scutil --nc start` / `stop`, off the main thread); a status line — "Connected · 10.0.0.2 · since 14:05" (address and time from scutil's extended status when present), "Connecting…", "Disconnecting…", "Not connected"; after a start or stop that didn't happen (or scutil exiting with an error), in the warning yellow until the next switch or opening, "Didn't start · see WireGuard" / "Didn't stop · see WireGuard"; footer "Manage Tunnels…": WireGuard is a menu-bar app (LSUIElement, no URL scheme or AppleScript; opening it again shows no window), so Grove Keys launches it if needed and presses its status item's "Manage Tunnels" through Accessibility, the panel put away first; WireGuard is then brought forward either way. If the press fails, the panel says why in yellow: "Grove Keys needs Accessibility permission" with a "Privacy Settings…" button when Grove Keys isn't trusted, else "WireGuard's menu didn't open"; the line outlives the panel closing and clears at the opening after the one that showed it, or at the next click. Not set up (`No service`): the line "Import warden-air.conf into WireGuard as grove-lab" and a "Manage Tunnels…" button doing the same (WireGuard's App Store page if it isn't installed).
- **Pure Core, tested:** parsing `scutil --nc status` output (first line + the IPv4 address and connect time from the extended dictionary), the icon state, and the status line's words.

## Non-goals
Reachability of the lab hosts, on-demand rules (macOS's VPN settings have them), any other VPN.

## Constraints
No lab addresses in committed fixtures, samples or docs (the repo is public): samples and fixtures use `10.0.0.2`; the real address only appears at run time. grove-ui rules; renders for the owner before install.

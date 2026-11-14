# 2. The desktop

[Contents](README.md) · Previous: [Getting started](01-getting-started.md) · Next: [The Grove menu](03-the-grove-menu.md)

Windows are tiled: they share the screen side by side with a gap between them and a coloured border on the one in focus. The borders step aside while Mission Control, App Exposé or Show Desktop is up, and come back when it ends. You move between them, and between nine numbered workspaces, with ⌥ (Option).

## Workspaces

| Press | To |
| --- | --- |
| ⌥1 … ⌥9 | Go to workspace 1 … 9 |
| ⌥⇧1 … ⌥⇧9 | Send the focused window to that workspace |
| ⌥Tab | Go back to the workspace you were on before |
| ⌥⇧Tab | Move the whole workspace to the next monitor |

A workspace exists only while it has a window or is in front, so the bar shows just the ones in use. No app is tied to a workspace: a new window opens where you are, and you send it elsewhere with ⌥⇧ and a number.

With more than one monitor, you can give each workspace a home monitor in the Grove Keys window (the Monitors group). That choice is kept for this Mac only.

## Windows

| Press | To |
| --- | --- |
| ⌥H ⌥J ⌥K ⌥L | Focus the window to the left, below, above, right |
| ⌥⇧H ⌥⇧J ⌥⇧K ⌥⇧L | Move the window left, down, up, right |
| ⌥- and ⌥= | Make the window smaller or larger |
| ⌥/ | Tiles: windows side by side (press again to switch between columns and rows) |
| ⌥, | Accordion: windows stacked with their edges showing (press again to turn it) |

## Floating a window, and other rare jobs

Press ⌥⇧; to enter service mode, then one more key. You are back in the normal mode afterwards.

| Then press | To |
| --- | --- |
| F | Float the window, or tile it again |
| R | Reset the workspace's layout |
| ⌫ | Close every window on the workspace except this one |
| ⌥⇧H ⌥⇧J ⌥⇧K ⌥⇧L | Join the window with its neighbour on that side |
| Esc | Reload the configuration and leave service mode |

Finder, System Settings, Grove Keys, Grove Themes and the Grove window always float.

## The bar

The bar replaces the macOS menu bar. From left to right:

| Part | Shows | Click |
| --- | --- | --- |
| Pine | The Grove logo | Opens the [Grove menu](03-the-grove-menu.md) |
| Workspace numbers | The workspaces in use; the one in front is a green pill | Goes to that workspace |
| App icons after a number | The apps open on that workspace (up to six) | Goes to that window |
| App name | The app in front | Opens that app's menus (File, Edit, View …) |
| Tray | The menu-bar items of other apps (WireGuard, OneDrive…), which the Grove bar covers: a menu bar with an arrow and how many items are in the tray; the symbol alone when there are none or Grove Keys isn't running | Opens the tray |
| Processor and memory | Two icons with their use in percent | Opens the CPU and memory panel |
| Cloud | Whether your files in iCloud Drive and OneDrive have finished syncing: green with a tick when everything is up to date, yellow with the number of files still uploading or downloading, red when something is wrong (an upload error, a conflict, a file stuck for 30 minutes, or OneDrive not running), grey while Grove Keys is still checking or isn't running | Opens the cloud panel |
| Shield | The grove-lab VPN (its own pill, not the Wi-Fi pill's shield): grey when off (or not set up yet), yellow while it connects or disconnects, purple when connected | Opens the VPN panel |
| Wi-Fi and Bluetooth | The connection in use: signal strength on Wi-Fi, a cable on Ethernet, a shield when a VPN carries all your traffic (the grove-lab VPN, which carries only the lab's, has its own pill), a slashed fan when offline. Beside it, the Bluetooth rune: struck out in grey when Bluetooth is off, blue when on, with a dot on each side while a device is connected | Opens the network panel, with Bluetooth under it |
| Speaker | Volume: the speaker fills with the level, and is slashed when muted | Opens the sound panel |
| Bolt | Battery level: the bolt fills with the charge, and turns red when low | Opens the battery panel |
| Clock | Day, date and time | Opens this month's calendar |

Each group sits in a pill with an orange outline. Parts that react to a click light up under the pointer.

### The panels

A click on a pill at the right opens its panel under it; the pine opens the Grove menu the same way at the left. All of them look alike and line up with the borders of the windows below.

| Panel | What is in it |
| --- | --- |
| Tray | One row per menu-bar item of another app, left to right as in the macOS menu bar: the app's icon and name, and the item's own text when it has one ("Sync issue"). A click opens the item. **Hidden (n)** opens the hidden items; **Menu Bar Settings…** opens Menu Bar in System Settings |
| CPU and memory | Use now and over the last minute, the load of each core, memory by kind with its pressure, the three busiest apps of each, and a link to Activity Monitor. An orange line divides the CPU half from the memory half |
| Battery | Charge and time left, power, health, and three rows: **Keep Awake** stops the Mac and its display from sleeping, until you turn it off or for 1, 2 or 4 hours. **Ignore Lid** keeps the Mac running with the lid shut; macOS asks for your password or Touch ID each time it changes, and it is offered only while Keep Awake is on and not under 20% on battery. **Low Power Mode** opens Battery Settings |
| Network | The network's name with a switch for Wi-Fi, download and upload speed over the last minute, and the IP, router and DNS addresses (a click copies one). **Run speed test** measures the connection in about 15 seconds. **Show apps** lists the three apps using the network most. Under an orange line, Bluetooth: a switch to turn it on and off, and the connected devices with their battery level |
| VPN | A switch that starts and stops the grove-lab VPN, and one line: "Connected" with the tunnel's address and since when, "Connecting…", "Disconnecting…" or "Not connected". **Manage Tunnels…** opens WireGuard's tunnels window |
| Cloud storage | One section per cloud, iCloud Drive first: its state ("Up to date", "Uploading 3 files · Downloading 1", "1 problem"), up to five files still on their way or in trouble (a click shows the file in Grove Explorer), **Open in Grove Explorer** and **Settings…** |
| Sound | A volume slider, Mute, the output devices (a click switches), and the input device |
| Calendar | This month, Monday first, with week numbers; the arrows or ← → change the month, T returns to today |

A panel closes when you press Esc, click its pill again, click anywhere else, or switch app or workspace. Its pill stays lit while it is open. Inside one, Tab moves between the controls; in the sound panel ← → change the volume and M mutes; in the tray ↑ ↓ or an app's first letter pick a row and Return opens it.

If Ignore Lid was left on (by Grove after a dismissed password prompt, or by another tool), the battery panel says "Ignore Lid is still on" with a **Turn off** button.

The network panel shows the network's name only if Grove Keys is allowed Location Services (System Settings > Privacy & Security > Location Services); macOS hides the name otherwise, and the panel says "Wi-Fi". Your position is not read.

Bluetooth sits under Wi-Fi in the same panel. Its switch turns Bluetooth on and off; if macOS doesn't let Grove Keys do that, the switch opens Bluetooth Settings instead. Each connected device has a row with its kind (headphones, keyboard, mouse…), its name and its battery level when it reports one; for earphones with a case, the lowest of the two earphones. "No devices connected" and "Bluetooth is off" say the rest. The list is read when the panel opens and every 30 seconds, so a device that just connected can take a moment to show. The first time you open the network panel, macOS asks whether Grove Keys may use Bluetooth. If you say no, the panel says "Grove Keys needs Bluetooth permission" with a **Privacy Settings…** button (System Settings > Privacy & Security > Bluetooth) and has no switch, and Grove Keys doesn't ask again. To pair a new device, use **Bluetooth Settings…** at the bottom of the panel.

### Menu-bar tray

The Grove bar covers the macOS menu bar, and with it the icons other apps put there. The tray pill lists them instead. A click on a row (or Return) closes the tray and clicks that app's icon for you, so its menu or window opens at the top right as if you had clicked it in the menu bar; if nothing opens, the app comes forward instead. Grove Keys does this with its Accessibility permission; without it the tray says "Grove Keys needs Accessibility permission" with a **Privacy Settings…** button. Apple's own items (Wi-Fi, battery, Control Center, the clock and the like) are left out, since the Grove bar has pills for them; "No other menu-bar items" means there is nothing else.

Right-click a row for **Open**, **Hide from tray** (or **Show in tray**) and **Bring <app> forward**. Hidden items move under **Hidden (n)**, aren't counted on the pill, and still open on a click; Grove Keys, Grove Themes and AeroSpace start there. To remove an item for good, quit its app or use **Menu Bar Settings…**. The count follows apps opening and quitting within a few seconds, and is checked again whenever you open the tray.

### The grove-lab VPN

The shield is the tunnel to the grove lab: a WireGuard connection that carries only the lab's addresses, so the rest of your traffic goes on as before. The switch in its panel starts and stops it with no password; macOS does the connecting. The switch can't be used while the tunnel is connecting or disconnecting. If a start or stop doesn't happen, the panel says "Didn't start · see WireGuard" (or "Didn't stop") in yellow until you try again or reopen it. Starting it from the WireGuard app works too: the shield follows within ten seconds.

It needs a one-time setup. Install WireGuard from the App Store; if the tunnel is up from Terminal, take it down with `sudo wg-quick down` followed by the tunnel's profile; then in WireGuard choose *Import tunnel(s) from file…*, pick the lab's tunnel profile, name the tunnel `grove-lab`, and allow the VPN configuration when macOS asks. Until then the panel says "Import the lab's tunnel profile into WireGuard as grove-lab" with a **Manage Tunnels…** button (the App Store page if WireGuard isn't installed). WireGuard lives in the macOS menu bar, which the Grove bar hides, so **Manage Tunnels…** starts WireGuard if needed and chooses Manage Tunnels in its menu for you (Grove Keys uses its Accessibility permission for this). If that doesn't work, WireGuard still comes forward and the panel says "WireGuard's menu didn't open", or "Grove Keys needs Accessibility permission" with a **Privacy Settings…** button. Grove never reads the tunnel's file: it holds the private key.

### Cloud storage

The cloud pill follows iCloud Drive and every cloud folder in `~/Library/CloudStorage` (OneDrive, and Dropbox or Google Drive if you add them). It counts only files that are uploading, waiting to upload, or downloading right now; files kept online only are normal and never count. Grove Keys reads only what macOS says about each file, never its contents, so looking never downloads anything. After you log in the cloud is grey for a little while as Grove Keys checks what was already pending.

In its panel, **Open in Grove Explorer** opens that cloud's folder and **Settings…** opens iCloud in System Settings, or OneDrive's settings. OneDrive lives in the macOS menu bar, which the Grove bar hides, so Grove Keys clicks its menu-bar icon for you (with its Accessibility permission, as for WireGuard). If that doesn't work, OneDrive comes forward and the panel says "Open OneDrive's settings from its activity window". "OneDrive isn't running" means OneDrive was quit; **Settings…** starts it again. The first time, macOS may ask whether Grove Keys may access files managed by OneDrive; if you say no, the panel says "Grove Keys can't see OneDrive's files" with a **Privacy Settings…** button, and the pill leaves OneDrive out.

The app name is how you reach an app's menus now that the menu bar is hidden. The same menus are in the Grove menu under Global Menu. Other apps' menu-bar icons are in the [tray](#menu-bar-tray); for what is not reachable yet, see [Coming from stock macOS](08-coming-from-stock-macos.md#what-you-cannot-reach-yet).

All of these keys can be changed: see [Hotkeys](05-hotkeys.md).

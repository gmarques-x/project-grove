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
| Processor and memory | Two icons with their use in percent | Opens the CPU and memory panel |
| Bolt | Battery level: the bolt fills with the charge, and turns red when low | Opens the battery panel |
| Wi-Fi | The connection in use: signal strength on Wi-Fi, a cable on Ethernet, a shield on a VPN, a slashed fan when offline | Opens the network panel |
| Speaker | Volume: the speaker fills with the level, and is slashed when muted | Opens the sound panel |
| Clock | Day, date and time | Opens this month's calendar |

Each group sits in a pill with an orange outline. Parts that react to a click light up under the pointer.

### The panels

A click on a pill at the right opens its panel under it; the pine opens the Grove menu the same way at the left. All of them look alike and line up with the borders of the windows below.

| Panel | What is in it |
| --- | --- |
| CPU and memory | Use now and over the last minute, the load of each core, memory by kind with its pressure, the three busiest apps of each, and a link to Activity Monitor |
| Battery | Charge and time left, power, health, and three rows: **Keep Awake** stops the Mac and its display from sleeping, until you turn it off or for 1, 2 or 4 hours. **Ignore Lid** keeps the Mac running with the lid shut; macOS asks for your password or Touch ID each time it changes, and it is offered only while Keep Awake is on and not under 20% on battery. **Low Power Mode** opens Battery Settings |
| Network | The network's name with a switch for Wi-Fi, download and upload speed over the last minute, and the IP, router and DNS addresses (a click copies one). **Run speed test** measures the connection in about 15 seconds. **Show apps** lists the three apps using the network most |
| Sound | A volume slider, Mute, the output devices (a click switches), and the input device |
| Calendar | This month, Monday first, with week numbers; the arrows or ← → change the month, T returns to today |

A panel closes when you press Esc, click its pill again, click anywhere else, or switch app or workspace. Its pill stays lit while it is open. Inside one, Tab moves between the controls; in the sound panel ← → change the volume and M mutes.

If Ignore Lid was left on (by Grove after a dismissed password prompt, or by another tool), the battery panel says "Ignore Lid is still on" with a **Turn off** button.

The network panel shows the network's name only if Grove Keys is allowed Location Services (System Settings > Privacy & Security > Location Services); macOS hides the name otherwise, and the panel says "Wi-Fi". Your position is not read.

The app name is how you reach an app's menus now that the menu bar is hidden. The same menus are in the Grove menu under Global Menu. For what is not reachable yet, see [Coming from stock macOS](08-coming-from-stock-macos.md).

All of these keys can be changed: see [Hotkeys](05-hotkeys.md).

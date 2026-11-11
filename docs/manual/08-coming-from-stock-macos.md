# 8. Coming from stock macOS

[Contents](README.md) · Previous: [Updates and undo](07-updates-and-undo.md)

Most of macOS is untouched. This is where the things Grove moved have gone.

| On a stock Mac | With Grove |
| --- | --- |
| The menu bar (File, Edit, View …) | Click the app's name in the bar, or Pine › Global Menu. Keyboard shortcuts such as ⌘S and ⌘, work as before |
| The Apple menu | The first item in those same menus. For Sleep, Restart, Shut Down, Log Out and Lock, Pine › System is quicker, or ⌘Space and type the word |
| System Settings | Pine › System › System Settings…, or ⌘Space and type `settings` |
| Spotlight | ⌘Space opens the Grove Launcher now: it opens apps and runs Grove menu rows, and does not search files. Spotlight is still in Finder's search field; to have ⌘Space back for it, see [The Grove menu](03-the-grove-menu.md#the-grove-launcher) |
| The Dock | Still there and unchanged, except that Ghostty has Terminal's place |
| ⌘Tab | Still works. Switching to an app whose window is on another workspace takes you to that workspace |
| Mission Control and Spaces | Use workspaces instead: ⌥1 … ⌥9, or click a number or an app icon in the bar. See [The desktop](02-the-desktop.md) |
| Full screen and Split View (the green button) | Tiling does this job: a window alone on a workspace fills the screen, and ⌥/ and ⌥, arrange several |
| Minimise (⌘M) and Hide (⌘H) | Still work; sending a window to another workspace (⌥⇧ and a number) is usually tidier |
| Caps Lock | It is the Hyper key now: tap for Escape, hold for shortcuts. See [Hotkeys](05-hotkeys.md) |
| ⌥ plus a letter or digit for a special character | Use the **right ⌥**: it types the character in every app (right ⌥2 is `@` on a Portuguese keyboard). The left ⌥ is for shortcuts: ⌥H J K L, ⌥1 … 9, ⌥- = / , move windows. See [Hotkeys](05-hotkeys.md) |
| The clock and calendar | The clock at the right of the bar; click it for this month |
| The battery menu | The `bat` figure in the bar. It is a read-out only; settings are in System Settings › Battery |
| The Wi-Fi menu | The bar shows `wifi`, `eth`, `vpn` or `off`, not the network's name. To choose a network, open System Settings › Wi-Fi |
| The volume menu | The `vol` figure in the bar; change it with the keyboard's volume keys. Choose an output in System Settings › Sound |
| Force Quit | ⌥⌘Esc, as before, or Apple menu › Force Quit |
| Screenshots | ⌘⇧3, ⌘⇧4, ⌘⇧5, as before |
| Terminal | Ghostty; ⌃` from anywhere. See [The terminal](06-the-terminal.md) |
| Finder | Unchanged, and its windows float. In a terminal, `y` opens Yazi |

## What you cannot reach yet

Said plainly:

- **Third-party menu-bar icons are hidden.** Apps that live in the menu bar (password managers, VPN clients, cloud-storage clients, chat apps' status icons) still run, but their icons are behind the Grove bar and cannot be clicked. Open the app's own window or settings instead, where it has one. A "tray" in the bar that shows these icons is planned and not built.
- **Control Centre and the system status icons are hidden** for the same reason: Wi-Fi, Bluetooth, Focus, AirDrop, screen mirroring and the rest. Use System Settings for each.
- **The bar's status figures are read-outs.** Battery, Wi-Fi, volume, memory and processor show a value and do nothing on click. Only the network speeds and the clock open a popup.
- **Notification Centre has no button.** Notifications still arrive as banners.

If you need the real menu bar for a moment, macOS's own shortcut ⌃F2 (⌃fn F2 on a laptop keyboard) moves the keyboard focus to it; then use the arrow keys.

To have the menu bar back for good without removing Grove, stop the bar: `brew services stop felixkratz/formulae/sketchybar`, then set System Settings › Control Centre › Automatically hide and show the menu bar to Never. `grove install` will put the bar back.

# Global Menu · the Grove button's dropdown, with the front app's menus

**Status:** design for review, 2026-11-11
**Builds on:** [2026-11-11-sketchybar-design.md](2026-11-11-sketchybar-design.md) (the bar, its pine button and app name), [2026-11-10-grove-keys-design.md](2026-11-10-grove-keys-design.md) (Grove Keys, its Accessibility permission, `grovekeys://`)

## 1. Goal

The Grove bar's pine button opens a native dropdown with two choices:
- **Themes…** opens the Grove Themes window.
- **Global Menu ▸** holds the menus of the app in front, read live through Accessibility.

Every menu item works as it does in the native menu bar, which stays hidden behind the bar. Clicking the front app's name in the bar opens its menus directly. This also fixes "Themes" opening nothing today.

**Success looks like this:**
- Clicking the pine shows Themes… and Global Menu.
- Global Menu lists the front app's menus, starting with the Apple menu. Picking New Window in Ghostty, Copy in Chrome, or a View toggle in VS Code does exactly what the native menu does.
- Themes… opens and brings forward the Grove Themes window.
- Clicking "Ghostty" in the bar opens Ghostty's menus straight away.
- Nothing needs the hidden menu bar any more.

## 2. Decisions

| Topic | Decision | Why |
| --- | --- | --- |
| Entry point | The pine button's dropdown: Themes… and Global Menu ▸ | Chosen by the user. |
| Menu style | One dropdown with the app's menus as submenus | Chosen by the user. |
| Home | Grove Keys (`grovekeys://grove-menu`, `grovekeys://app-menu`) | It already has Accessibility permission and a pointer menu; no new app or permission. |
| Apple menu | The first submenu, from the app's own Accessibility menu bar | Every app's menu bar starts with it. |
| App name | Opens the app's menus directly (the Global Menu, one level up) | A shortcut, proposed and accepted. |
| Grove Themes | Gains `grovethemes://gallery`, which opens and brings forward its window | `open -b` only activates the running menu bar app, so nothing showed. |

## 3. Out of scope

- Searching the menus, and recent items.
- Menus of apps that aren't in front.
- Changing or binding shortcuts (they're only shown).
- Menu bar extras (other apps' status icons).

## 4. The dropdowns

```
pine click → open grovekeys://grove-menu
   Themes…            → open grovethemes://gallery
   ───────
   Global Menu ▸      ▸ · <App> ▸ · File ▸ · Edit ▸ · View ▸ · Window ▸ · Help ▸ …

app-name click → open grovekeys://app-menu
   ▸ · <App> ▸ · File ▸ · Edit ▸ · …   (the same list, one level up)
```

- Both pop up at the pointer, as the ⌘ glyph's menu does (Grove Keys' `PointerMenu`).
- **Which app:** the one in front when clicked. SketchyBar never takes focus, and Grove Keys pops its menu without activating (it's an accessory app). The app is captured before the menu opens.
- **Items mirror the real ones:**
  - title;
  - enabled or disabled;
  - checkmark;
  - shortcut shown (⌃⌥⇧⌘ + key);
  - separators;
  - nested submenus.
- **Lazy reading:** only the top level is read when the menu opens. Each submenu is filled when it opens (`NSMenuDelegate.menuNeedsUpdate`), so a big app (VS Code, Chrome) opens instantly.
- **Pressing:** choosing an item re-finds it by its title path (for example `Edit › Copy`) in the app's live menu bar and runs `AXPress`. The press runs after the dropdown has closed.

## 5. Pieces

- **GroveKeysCore**, pure and tested:
  - `MenuNode` (title, enabled, checked, shortcut, isSeparator, path, hasChildren).
  - `MenuSource` protocol (`children(of path: [String]) -> [MenuNode]?`, `press(path:) -> Bool`).
  - `MenuShortcut.text(char:modifiers:glyph:)`, for the `AXMenuItemCmdModifiers` bits: none = ⌘ only, 1 shift, 2 option, 4 control, 8 no command.
  - `KeysURL` gains `.groveMenu` and `.appMenu`.
- **GroveKeys** (the app):
  - `AXMenuSource` (AXUIElement calls with a 1 s messaging timeout).
  - `GlobalMenu`, which builds the `NSMenu` tree from a `MenuSource`: lazy submenus, items that press.
  - `PointerMenu` gains the two menus.
- **grove-themes/app:**
  - `ThemesURL` (`.gallery`) in GroveThemesCore.
  - The app handles it through `application(_:open:)`, opening the gallery window with an `openWindow` captured from the menu bar label, as in Grove Keys.
- **grove-dotfiles:**
  - Module 97's Info.plist registers the `grovethemes` scheme.
  - `sketchybarrc`: the pine's click becomes `open grovekeys://grove-menu`, and `front_app` gains `click_script="open grovekeys://app-menu"` plus hover.

## 6. Errors

| Situation | What happens |
| --- | --- |
| Grove Keys lacks Accessibility | Global Menu holds one disabled line, "Grove Keys needs Accessibility", and Open Settings. Themes… still works. |
| The front app has no menus | One disabled line: "No menus for <app>". |
| A read takes over 1 s | That submenu shows a disabled "Couldn't read this menu". |
| The item vanished before the press | Nothing happens; it's logged. |
| Grove Themes isn't running | `grovethemes://gallery` starts it, then opens the window. |

## 7. Testing

- **Swift (GroveKeysCore):**
  - A fake `MenuSource` tree builds the expected nodes.
  - Shortcut text for each modifier combination and for special keys (glyph).
  - Path resolution with a renamed or missing item (press returns false).
  - The `KeysURL` cases.
- **Swift (GroveThemesCore):** `ThemesURL` parsing.
- **bats:** module 97's plist has `grovethemes`; `sketchybarrc` wires the pine and the app name to the links.
- **By hand, with the user:**
  - The pine dropdown and Themes… opening the window.
  - Global Menu in Ghostty, Chrome and VS Code, with real items pressed.
  - The Apple menu.
  - The app-name shortcut.
  - Grove Keys without permission.

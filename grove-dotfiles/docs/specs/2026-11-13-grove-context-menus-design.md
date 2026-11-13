# Grove-style context menus, everywhere

Date: 2026-11-13. Status: approved in conversation; written up for the owner's review.

## Intent
Right-click menus in Grove's apps are the system's (`NSMenu` / SwiftUI `.contextMenu`): SF, macOS's grey, macOS's spacing. Grove already has its own menu — the Grove menu in the bar (JetBrains Mono, theme roles, submenus, keys, VoiceOver). The owner wants every right-click menu in Grove to be that menu ("everywhere").

Success: a right-click (or ⌃-click, the context-menu key, Shift-F10) anywhere in Grove Explorer, Grove Keys or Grove Themes, a Grove dropdown picker, or the Grove menu at the pointer opens a menu that looks and behaves like the Grove menu, and nothing that the system menus did today is lost.

## Goals, non-goals, anti-goals
- Goals: one shared menu component in GroveUI; every right-click menu in the three apps uses it; keyboard and VoiceOver at least as good as today's native menus; submenus (Explorer's Open With, with app icons) work.
- Non-goals: the apps' menu-bar menus (File, Edit…) and the bar's Global Menu stay native (macOS draws them); macOS Services / Share / Quick Actions entries (none of today's menus have them).
- Anti-goals: a menu that can't be driven from the keyboard; one that steals focus from the window in a way that breaks the next keystroke; a menu drawn off-screen.

## Approaches
1. **Move Grove Keys' `MenuList` (model, panel drawing, pure rules) into GroveUI and host it in a small borderless panel at the pointer. Chosen** (the owner agreed to "built from the same component"): one component, already tested for keys, hover timing and submenu placement.
2. A second, simpler menu for context menus: rejected — two menus to keep alike, and the Grove menu already does submenus.
3. Restyle `NSMenu` (custom views per item): rejected — macOS still draws the frame, background and keyboard focus; the result is half-native.

## Design
- **GroveUI gains `GroveMenuList`** (not `GroveMenu`: GroveKeysCore already has `GroveMenu`/`GroveMenuRow` for the menu file): the rows type (title, icon or app icon, separator, kind action/submenu/note/link, enabled, checked, a shortcut hint), the model (highlight per level, keys, hover intent), the drawing (rows, separators, chevrons, checkmarks) and the pure rules (move, jump-to-letter, hover timing, submenu placement) — moved from grove-keys' `MenuList` with their tests. Grove Keys' Grove menu in the bar keeps its own host (`BarPanelHost` and its side panels) but draws with the shared rows, model and rules — no visible change; only the window hosting is not shared.
- **`GroveMenuList.popUp(rows:at:in:onChoose:onClose:)`** (AppKit host, asynchronous: it returns at once; `onClose` runs when the menu closes, chosen or not — call sites that relied on `NSMenu.popUp` blocking move their after-work there): a borderless, non-activating `NSPanel` at the pointer (or under the focused row/field for the keyboard) that **never becomes key** — the document window stays key, as with `NSMenu`; keys reach the menu through a local event monitor while it is open (↑↓, →← into and out of submenus, Return, Esc, type-to-jump) and nothing else gets them. Card style as the Grove menu panel (theme `bg1` fill, outline, radius `GroveRadius.card`); content-sized width; flips to stay on screen; a submenu opens beside its row (as a child panel). A click outside, Esc, the window closing or the app deactivating closes it without choosing.
- **Rows the move adds:** a disabled state; icons (incl. app icons) at any level, not only the top; submenu rows filled when the submenu opens (Open With asks NSWorkspace then); no shortcut hints (no right-click menu shows them today, as in Finder).
- **VoiceOver**: the panel is a menu to the accessibility server (`AXMenu` with `AXMenuItem`s, checked/disabled/submenu states); rows that lose `.contextMenu` keep a "Show Menu" accessibility action that opens it. Grove Explorer's `--audit-accessibility` gains a state that opens the list menu offscreen and checks it.
- **Call sites switched**:
  - Grove Explorer: list rows (`ListMenu`, incl. Open With with app icons), sidebar rows (`KeyboardReach.menuRows` and the sidebar's `.contextMenu`), and the keyboard paths (`contextMenu`, `contextMenuF10`). Tabs and the path bar have no right-click menu today and get none here.
  - Grove Keys: Bindings rows (`.contextMenu` in BindingsView).
  - Grove Themes: none (it has no right-click menus).
  - Also in scope (owner, 2026-11-13: "include both"): **GroveSelect's dropdown list** (GroveUI; used e.g. by Grove Keys' Monitors view and Hyper settings) opens a `GroveMenuList` with a check on the current choice instead of a native menu; and **the Grove menu at the pointer** (`grovekeys://menu`, PointerMenu.swift) pops `GroveMenuList` instead of an `NSMenu` (its rows, tests and the Global Menu row's behaviour unchanged; the Global Menu itself stays native).
- **UI rules**: the grove-ui skill's table rows "right-click menus use `.contextMenu`" and "Don't build by hand: … context menus" change to "right-click menus use GroveUI's `GroveMenu`"; native stays for menu-bar menus.

## Constraints
grove-ui tokens and roles; JetBrains Mono; dark and light; renders of each converted menu (list row menu with Open With open, sidebar menu, Bindings row menu) for the owner before anything is installed. GroveKeys binary only with its render flags.

## Calls made (for the owner to check)
- The menu's look is the Grove menu's own (card with the bar panels' outline), so all Grove menus look alike.
- Menu-bar menus and the Global Menu stay native.
- Tabs and the path bar get no new menu (they have none today).
- The menu never takes keyboard focus from the window; keys reach it through an event monitor while open.
- No shortcut hints in rows.

## Left to the builder
Where the pure rules live in grove-themes (GroveThemesCore or a GroveUI file with tests); how the panel finds the screen and the window to return focus to; how app icons are drawn in rows.

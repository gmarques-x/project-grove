# Bar: the menu-bar tray

Date: 2026-11-14. Status: approved in conversation; written up for the owner's review.
Background: `~/Developer/artifacts/menu-bar-tray/research.md` (private; facts measured on macOS 27.2).

## Intent
"A hidden items button": one pill in the Grove bar that lists the menu-bar items of other apps (WireGuard, OneDrive, Docker…) hidden behind the Grove bar, and opens them on click. The Grove bar covers the native menu bar (auto-hidden, SketchyBar `topmost`), so those items are unreachable today; on macOS 27 every status item is drawn by one process (`com.apple.MenuBarAgent`), so SketchyBar aliases and item-moving tools no longer work.

Success: one click on the pill shows every other app's item; one click on a row opens it as if clicked in the menu bar.

## Goals, non-goals, anti-goals
- Goals: a tray pill with a count; a dropdown listing items (app icon, app name, the item's own text); click opens; keyboard navigation; hide/show items in the tray.
- Non-goals: real item images (no Screen Recording — owner, 2026-11-14: "app icons only"); Apple's own extras (Wi-Fi, battery, Control Center, clock, Siri, Spotlight — owner: "leave them out"; Grove has pills for them); moving, reordering or removing real items; a keyboard shortcut for the tray (later, through Grove Keys' bindings).
- Anti-goals: simulated clicks or keystrokes; changing any system setting (incl. revealing the native menu bar); polling the accessibility tree on a timer.

## Approaches (the owner agreed to A)
- **A. A Grove Keys dropdown from the accessibility tree. Chosen:** read the items from MenuBarAgent's tree when needed; show app icon + name; click = `AXPress` on the app's own element. Only the Accessibility permission Grove Keys already has; no setting changed; same panel family as Wi-Fi, VPN and cloud.
- B. Captured item images drawn in the bar: rejected — needs Screen Recording always, images go stale, eats bar width.
- C. Reveal the native bar for a moment: rejected — changes a system setting / fights the Grove bar.

## Design
**Pill.** New pill left of CPU/memory (leftmost of the right group, the usual gap). Item `tray`, pill `pill.tray`, event `tray_change`, panel `tray`. A tray SF Symbol in fg (no state colour) and the count of items shown in the tray (hidden ones not counted) in a fixed-width label; symbol alone at 0. Click opens panel `tray` like every pill (pill filled while open). Grove Keys writes `$GROVE_STATE/tray` (the count, one line) only when it changes and removes it when it stops; missing file → symbol without a count. The count is refreshed on app launch/quit (NSWorkspace notifications, after a short settle) and when the panel opens — never on a timer.

**Dropdown** (bar panel frame as the others):
- One row per item, in the native bar's left-to-right order: app icon (`NSRunningApplication.icon`), app name, and at the right in quiet text the item's own title/description when it has one and it differs from the name. An app with several items shows several rows.
- Click a row (or Return) → the panel closes, then `AXPress` on that item's element (as the WireGuard/OneDrive openers do, through the shared `StatusItemLocator`). If the press fails or nothing opens, the app is brought forward and the tray shows nothing more (no stuck panel).
- Keys: ↑/↓, Return, a letter jumps, Esc closes.
- Right-click a row → `GroveMenuList`: "Open", "Hide from tray" (or "Show in tray"), separator, "Bring <App> forward".
- **Hidden:** a "Hidden (n)" disclosure below the list, collapsed by default, rows in quiet ink; they still open on click. Default hidden: Grove Keys, Grove Themes, AeroSpace (already in the Grove bar). The hidden list is Grove Keys' own setting, keyed by bundle id plus the item's identifier, or its index when it has none.
- Footer: "Menu Bar Settings…" (System Settings ▸ Menu Bar, where items are really removed).
- States: reading shows the last list at once and refreshes in place; no Accessibility → one line and "Privacy Settings…" (as the VPN panel); nothing to show → "No other menu-bar items".
- Excluded always: Apple's extras (items owned by MenuBarAgent itself, Control Center, SystemUIServer, Spotlight, Siri, the clock) and Grove's own SketchyBar.

**Where opened items appear.** A menu or popover opens at the item's native position (top right), above the Grove bar; Grove doesn't move it. Unverified until by hand: whether AXPress opens popovers (OneDrive's activity window, others) on macOS 27, and whether a short delay is needed after the panel closes.

## Constraints
grove-ui rules (GroveMenuList for the row menu, PanelKit for the panel); JetBrains Mono; renders of the pill and the dropdown (items, hidden expanded, no access, empty) dark and light into `~/Developer/artifacts/sketchybar/renders/tray/`; invented app lists in samples and fixtures; reuse `StatusItemLocator` and extract the AX helpers it, WireGuardOpener and OneDriveSettingsOpener duplicate into one shared helper (the tray would be a fourth copy); the locator skips reading other apps' elements beyond what matching needs. GroveKeys binary only with its render/check flags; never press other apps' UI in tests or renders.

**Rules settled after the builder check:**
- *Opened or not:* after the press, "opened" means a new `AXMenu` or window owned by that app's pid appears within 1 s (AXPress returning success isn't proof). If nothing appears, the wrapper group is pressed once; if still nothing, the app is brought forward. The by-hand check of popovers isn't a gate: apps whose popovers AXPress can't open get "bring forward".
- *Item key for Hide:* bundle id + the item's `AXIdentifier` when it is non-empty and differs from its title/description (a stable identifier); otherwise bundle id + its index among that app's items. Stored as strings next to Grove Keys' other settings.
- *Row text:* only the matched item elements of the listed apps are read further, timed like every AX read: `AXTitle`, then `AXDescription`, then `AXHelp`; the first non-empty one that isn't the app's name is shown. Other apps' elements stay at role/subrole/identifier/pid.
- *Count freshness:* event-driven only. App launch/quit (after a 2 s settle), the panel opening, and an AX observer on MenuBarAgent's item window (created/destroyed/children changed) if MenuBarAgent sends those notifications. If it doesn't, the count can be stale until the next launch, quit or open; that's accepted.
- *Apple's extras:* every item whose owner is MenuBarAgent itself or has a `com.apple.` bundle id is left out, as are SketchyBar's own items.

## Calls made in writing this (for the owner to check)
- The count is the number of items shown (not hidden ones); no colour on the pill.
- Grove Keys, Grove Themes and AeroSpace start hidden.
- A list, not a grid, so each row can carry the item's own text and the Grove menu's keys.
- A press that opens nothing falls back to bringing the app forward.
- "Apple's own" means every Apple app's item (Time Machine, input sources and the like included), not only Wi-Fi, battery, Control Center and the clock.
- The count may lag if an app adds or removes its item without launching or quitting, and MenuBarAgent doesn't announce it.

## Left to the builder
The SF Symbol, how the hidden list is stored (next to Grove Keys' other settings), the settle delay after launch/quit, how identifiers are matched for apps with several items.

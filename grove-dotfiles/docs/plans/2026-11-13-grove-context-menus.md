# Grove-style Menus Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every in-window menu in Grove — right-click menus in Grove Explorer and Grove Keys, GroveSelect dropdowns, and the Grove menu at the pointer — is the Grove menu (`GroveMenuList`), not a native one.

**Architecture:** The Grove menu's rows, model, drawing and pure rules move from grove-keys into grove-themes (pure rules in GroveThemesCore with tests; rows, model and drawing in GroveUI). A new GroveUI host pops it at a point in a non-key panel that takes keys through a local event monitor. Call sites switch one app at a time; the bar's Grove menu keeps its own host but draws with the shared parts.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Swift Testing, Command Line Tools only (no `@State` macro).

**Spec:** grove-dotfiles/docs/specs/2026-11-13-grove-context-menus-design.md

## Global Constraints
- Type name `GroveMenuList` (GroveKeysCore already has `GroveMenu` / `GroveMenuRow`).
- `GroveMenuList.popUp(rows:at:in:onChoose:onClose:)` returns at once; `onClose` runs once when the menu closes, chosen or not.
- The menu panel never becomes key; the document window stays key. Keys while open: ↑↓, → into a submenu, ← out, Return, Esc, type-to-jump; nothing else receives them.
- Closes without choosing on: a click outside, Esc, the owning window closing, the app deactivating.
- Look: the Grove menu panel's card (theme `bg1`, its outline, `GroveRadius.card`), content-sized width, flips to stay on screen; submenus open beside their row.
- Rows: action / submenu / note / link, enabled or disabled, checked, icon or app icon at any level, submenus fillable when opened; no shortcut hints.
- VoiceOver: `AXMenu` / `AXMenuItem` with checked, disabled and submenu states; rows that lose `.contextMenu` keep a "Show Menu" accessibility action.
- Native stays: app menu-bar menus and the Global Menu.
- grove-ui skill rules; renders dark-medium and light-medium into a private folder (files for the owner stay out of the repo). Never commit them.
- Binaries only with their render/audit flags: GroveKeys `--render-panel|--render-keys|--render-aerospace|--check-menu` (anything else starts a second app and clears the owner's Caps Lock mapping); GroveExplorer `--render|--time-list|--audit-accessibility`. Never launch, quit or install the apps. Never touch `config/grove-keys/keys.toml`.
- Commits: `area: summary` + body + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, by explicit path.

## Review Focus
1. A second right-click or context-menu key while a menu is open must replace it, not stack two menus (Task 2 step: one open menu per app; Task 3 test of the call-site guard).
2. A menu opened near the bottom-right corner of the screen, with a submenu, must stay fully on screen (Task 2 pure placement tests with a screen rect).
3. Type-to-jump with accented titles ("Música") and repeated letters cycles as the Grove menu does today (Task 1 tests carried over + one accented case).
4. Closing the window or switching apps while a menu (or its submenu) is open closes both panels and calls `onClose` exactly once (Task 2 step).
5. VoiceOver: opening a menu moves VoiceOver focus into it and closing returns it to the row (Task 3 audit state + by-hand check).

---

### Task 1: Move the Grove menu's parts into grove-themes
**Files:** Create `grove-themes/app/Sources/GroveThemesCore/MenuListRules.swift` (+ tests `Tests/GroveThemesCoreTests/MenuListRulesTests.swift`), `grove-themes/app/Sources/GroveUI/GroveMenuList.swift` (rows, model, drawing); Modify `grove-keys/app/Sources/GroveKeys/Panels/MenuList.swift` and `GroveMenuPanel.swift` to use them; delete the moved code and tests from grove-keys (`GroveKeysCore/MenuList.swift`, its tests) or leave thin adapters (`MenuListRowKind.init(GroveMenuRow)` stays in GroveKeysCore).
**Interfaces — Produces:** `public struct GroveMenuListRow` (id, title, icon: `GroveMenuListIcon?` = `.symbol(GroveIcon.Name)` | `.image(NSImage)`, separator, kind: action|link|submenu([Row])|note, enabled, checked); `public final class GroveMenuListModel: ObservableObject` (levels, highlight per level, keys, hover intent); `public struct GroveMenuListPanel: View` (one level); pure `MenuListMove`, `MenuHoverIntent`, `MenuListRowKind.showsChevron`, `MenuPlacement.submenu(...)` in GroveThemesCore.
- [ ] Step 1: move the pure rules with their tests unchanged into GroveThemesCore; add the accented type-to-jump test (Review Focus 3); run `swift test` in grove-themes — PASS.
- [ ] Step 2: move rows/model/drawing into GroveUI; add `enabled` (disabled rows drawn quiet, skipped by keys) and icons at every level; Grove Keys' Grove menu uses them.
- [ ] Step 3: `--render-panel grove` dark and light before and after; they must match pixel for pixel or differ only by antialiasing — say which. `swift test` in grove-themes and grove-keys — PASS. Commit `ui: the Grove menu's rows, model and rules move to GroveUI`.

### Task 2: The pop-up host
**Files:** Create `grove-themes/app/Sources/GroveUI/GroveMenuListHost.swift`; pure placement additions in `MenuListRules.swift` (+ tests).
**Interfaces — Produces:** `@MainActor public enum GroveMenuList { public static func popUp(rows: [GroveMenuListRow], at point: NSPoint, in view: NSView, onChoose: @escaping (String) -> Void, onClose: @escaping () -> Void); public static func close(); public static var isOpen: Bool }`; submenu rows may carry `fill: (() -> [GroveMenuListRow])?`, called when opened.
- [ ] Step 1: failing tests for `MenuPlacement.menu(origin:size:screen:)` (flip left/up at the edges, Review Focus 2) and submenu beside its row; implement.
- [ ] Step 2: the host: a borderless non-activating `NSPanel` (`.nonactivatingPanel`, `canBecomeKey == false`), a local `NSEvent` monitor for keys and outside clicks while open, child panels for submenus, closes on Esc/outside click/window close/app deactivate; a new `popUp` while one is open closes the old one first (Review Focus 1); `onClose` exactly once (Review Focus 4).
- [ ] Step 3: accessibility: the panel's content is an `AXMenu` with `AXMenuItem`s (title, enabled, `AXMenuItemMarkChar` for checked, submenu children); posts `menuOpened` / `menuClosed`.
- [ ] Step 4: `swift test` (grove-themes) — PASS. Commit `ui: GroveMenuList pops up at a point, without taking the window's keys`.

### Task 3: Grove Explorer's menus
**Files:** Modify `grove-explorer/app/Sources/GroveExplorer/ContextMenu.swift` (`ListMenu` → rows, Open With as a `fill` submenu with app icons and "No Application Opens This" as a note), `KeyboardReach.swift` (`popUp`, `menuIsUp`, `showSidebarMenu` → `onClose`), `Sidebar.swift` (`.contextMenu` → right-click handler + "Show Menu" accessibility action), `FileListCells.swift` (`menu(for:)` → GroveMenuList), `AccessibilityAudit.swift` / `Render.swift` (a `menu` state with the list menu and Open With open offscreen).
- [ ] Step 1: switch each site; keep every row, title, enablement and action exactly as today.
- [ ] Step 2: the audit's `menu` state checks the menu through the accessibility server (roles, titles, the submenu); `--audit-accessibility all` exits 0.
- [ ] Step 3: renders: the list menu with Open With open; the sidebar menu (a share row and a disk row), dark and light, into a private folder; look at each. `swift test` — PASS. Commit `explorer: right-click menus are Grove menus`.

### Task 4: Grove Keys' menus, GroveSelect, the pointer menu, the rules
**Files:** Modify `grove-keys/app/Sources/GroveKeys/BindingsView.swift` (row `.contextMenu` → GroveMenuList + "Show Menu" action), `grove-themes/app/Sources/GroveUI/GroveSelect.swift` (its list → GroveMenuList with a check on the current choice), `grove-keys/app/Sources/GroveKeys/PointerMenu.swift` (`grovekeys://menu` pops GroveMenuList with the Grove menu's rows; the Global Menu row still opens the native Global Menu), `~/.claude/skills/grove-ui/SKILL.md` (table rows: right-click menus and in-window dropdown lists use `GroveMenuList`; "Don't build by hand: context menus" reworded to "don't build another menu: use GroveMenuList"), manual chapters that describe these menus.
- [ ] Step 1: switch the three sites; GroveSelect keeps its button look and keyboard behaviour; the pointer menu keeps its rows, checks and `--check-menu` results.
- [ ] Step 2: renders (`--render-panel` / `--render-keys` paths, or a new render state if needed): a Bindings row menu, a GroveSelect list open, the pointer Grove menu, dark and light, into a private folder; look at each.
- [ ] Step 3: `swift test` in grove-themes, grove-keys, grove-explorer; bats `modules_keys_app.bats`; commit `keys: Grove menus for Bindings, GroveSelect and the pointer menu; the UI rules`.
- [ ] Step 4: STOP. Hand back the renders and a by-hand list: right-click in Explorer's list and sidebar (keys, Esc, outside click, Open With); context-menu key / Shift-F10; a Bindings row's menu; a GroveSelect list; the pointer Grove menu; VoiceOver reading a menu. The controller installs (94, 96, 97) only on the owner's word.

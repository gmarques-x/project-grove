# Global Menu Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The Grove bar's pine opens a dropdown (Themes… · Global Menu ▸ with the front app's live menus), the app name opens those menus directly, and Grove Themes opens its window from a `grovethemes://gallery` link.

**Architecture:** Grove Keys reads the front app's menu bar through Accessibility behind a `MenuSource` protocol. A pure Core model builds `MenuNode`s, shortcut text and path lookups. An app-side `GlobalMenu` turns them into a lazy `NSMenu` whose items press the real ones (`AXPress`). Grove Themes gains a URL handler. The bar wires its pine and app name to `grovekeys://` links.

**Tech Stack:** Swift 6 (Command Line Tools), AppKit + ApplicationServices (AXUIElement), Swift Testing; bash, bats.

**Spec:** `grove-dotfiles/docs/specs/2026-11-11-global-menu-design.md`

## Global Constraints

- Work on branch `global-menu`; merge on "merge it". Never commit the private working folders.
- Links: `grovekeys://grove-menu`, `grovekeys://app-menu`, `grovethemes://gallery` (case-insensitive scheme and host; any extra path → ignored).
- Each AX read has a 1 s messaging timeout (`AXUIElementSetMessagingTimeout`).
- `AXMenuItemCmdModifiers` bits: 0 = ⌘; 1 = ⇧; 2 = ⌥; 4 = ⌃; 8 = no ⌘. Shown in the order ⌃⌥⇧⌘ + key.
- Tests never touch the real Accessibility tree, the live `~/.config` or the real apps. `swift test` in bats runs with `PATH=/usr/bin:/bin:/usr/sbin:/sbin` and requires "Test run with".
- Never run grove-themes and grove-dotfiles bats files in one call.

## Review Focus

- **An app whose menu changes while the dropdown is open** (for example a window closes): the press re-resolves the path and does nothing if the item is gone. Test in Task 2.
- **Menus with duplicate titles at one level** (for example two "Show Tab Bar" items): the path also records the index among equal titles. Test in Task 2.
- **Grove Keys without Accessibility:** a disabled line plus Open Settings, never a crash. Checked by hand in Task 5. The model test in Task 3 covers the empty case.
- **Very large menus** (Chrome's History, VS Code's View): submenus fill only when opened. Checked by hand in Task 5.
- **Clicking the pine while Grove Keys' own window is in front:** the "front app" shown must not be Grove Keys itself; use the last app in front other than Grove Keys. Test in Task 3.

---

### Task 0: Spike: read and press a real menu from Grove Keys (throwaway)

- [ ] **Step 1:** In a scratch Swift script (run from Ghostty, which has Accessibility), read Ghostty's `AXMenuBar`: print the top-level titles, then the File menu's items with `AXEnabled`, `AXMenuItemCmdChar`, `AXMenuItemCmdModifiers` and `AXMenuItemMarkChar`.
- [ ] **Step 2:** Press `File › New Window` with `AXPress`, after a 1 s delay. Ask the user to watch: a new Ghostty window opens.
- [ ] **Step 3:** Record the attributes seen and what worked in the private notes. If `AXPress` doesn't work for menu items, stop and bring the options to the user.

### Task 1: Links: `KeysURL` cases and `ThemesURL`

**Files:**
- Modify `grove-keys/app/Sources/GroveKeysCore/KeysURL.swift` (`.groveMenu`, `.appMenu`) and its tests.
- Create `grove-themes/app/Sources/GroveThemesCore/ThemesURL.swift` (`enum ThemesURL { case gallery; init?(_ url: URL) }`) and `Tests/GroveThemesCoreTests/ThemesURLTests.swift`.

- [ ] **Step 1: Failing tests:** `grovekeys://grove-menu` → `.groveMenu`; `grovekeys://app-menu` → `.appMenu`; `grovekeys://menu` is still `.menu`; `grovethemes://gallery` → `.gallery`; other hosts, extra paths and other schemes → nil.
- [ ] **Step 2: Run** `swift test` in both packages → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `grove-keys, grove-themes: links for the grove menu and the gallery`.

### Task 2: Core menu model, shortcut text and paths

**Files:** Create `grove-keys/app/Sources/GroveKeysCore/MenuModel.swift` and `Tests/GroveKeysCoreTests/MenuModelTests.swift`.

**Interfaces:**
- `public struct MenuPath: Hashable, Sendable { public var steps: [Step]; public struct Step: Hashable, Sendable { public var title: String; public var index: Int /* among equal titles at its level */ } }`
- `public struct MenuNode: Equatable, Sendable { public var title: String; public var enabled: Bool; public var checked: Bool; public var shortcut: String?; public var isSeparator: Bool; public var hasChildren: Bool; public var path: MenuPath }`
- `public struct RawItem: Sendable { title: String?, enabled: Bool, markChar: String?, cmdChar: String?, cmdModifiers: Int?, cmdGlyph: Int?, hasChildren: Bool }`: what a source reports per item.
- `public protocol MenuSource: Sendable { func items(at path: MenuPath) -> [RawItem]?; func press(_ path: MenuPath) -> Bool }`
- `public enum MenuModel { public static func nodes(at path: MenuPath, from source: any MenuSource) -> [MenuNode]? }`. An empty title with no children is a separator. Equal titles get indexes 0, 1, ….
- `public enum MenuShortcut { public static func text(char: String?, modifiers: Int?, glyph: Int?) -> String? }`. `modifiers` follows Global Constraints. The glyph covers the arrows, return, delete, tab, escape and F1–F12 (the codes used by `kMenu*Glyph`).

- [ ] **Step 1: Failing tests:**
  - A fake source tree with separators, a disabled item, a checked item, a submenu and two equal titles; the nodes and paths come out as expected.
  - Shortcut text: (`N`, 0) → `⌘N`; (`N`, 1) → `⇧⌘N`; (`T`, 2) → `⌥⌘T`; (`F`, 4|2) → `⌃⌥⌘F`; (`Q`, 8) → `Q`; glyph return → `⌘↩`; nil → nil.
  - `press` on a vanished path returns false (Review Focus).
  - The duplicate-title index (Review Focus).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** → PASS.
- [ ] **Step 5: Commit** `grove-keys: menu model`.

### Task 3: The app: `AXMenuSource`, `GlobalMenu` and the two pointer menus

**Files:**
- Create `grove-keys/app/Sources/GroveKeys/AXMenuSource.swift` and `GlobalMenu.swift`.
- Modify `PointerMenu.swift` and `GroveKeysApp.swift` (handle `.groveMenu` and `.appMenu`).
- Create `Sources/GroveKeysCore/FrontApp.swift` (`FrontAppTracker`: remembers the last frontmost app that isn't Grove Keys) with tests.

**Interfaces:**
- `AXMenuSource(pid:)` implements `MenuSource`. It walks `AXMenuBar` → `AXChildren` (menu bar items) → `AXChildren[0]` (the menu) → `AXChildren` (items), with a 1 s messaging timeout. `press` re-resolves the path and calls `AXUIElementPerformAction(kAXPressAction)`.
- `GlobalMenu.menu(for app: NSRunningApplication, source: any MenuSource) -> NSMenu`: lazy submenus through a delegate; each item's action presses its path after the menu closes (`DispatchQueue.main.async`). Without permission: one disabled line plus Open Settings. With no menus: "No menus for <app>".
- `FrontAppTracker` (Core, pure): `func update(_ bundleID: String?, pid: Int32)` ignores `com.projectgrove.keys`; `var current: (bundleID: String, pid: Int32)?`. The app feeds it `NSWorkspace.didActivateApplicationNotification`.

- [ ] **Step 1: Failing tests:** `FrontAppTracker` keeps the last app that isn't Grove Keys (Review Focus).
- [ ] **Step 2: Run** → FAIL. **Step 3: Implement** the tracker, then the app files. **Step 4: Run** `swift test` and `swift build -c release` → PASS.
- [ ] **Step 5: Commit** `grove-keys: global menu`.

### Task 4: Grove Themes opens its window from the link, and the bar wiring

**Files:**
- Modify `grove-themes/app/Sources/GroveThemes/GroveThemesApp.swift`: an `NSApplicationDelegateAdaptor` with `application(_:open:)` that opens the gallery through an `openWindow` captured from the menu bar label's `.onAppear`, then `NSApp.activate`.
- Modify `grove-dotfiles/modules/97-themes-app/module.sh` (Info.plist `CFBundleURLTypes` with `grovethemes`).
- Modify `grove-dotfiles/config/sketchybar/sketchybarrc`: grove's click becomes `open grovekeys://grove-menu`; `front_app` gains `click_script="open grovekeys://app-menu"`, hover and the `HOVER` background.
- Test: `modules_themes_app.bats` (the plist has the scheme) and `sketchybar_config.bats` (the click scripts).

- [ ] **Step 1: Failing tests** (both bats files). **Step 2: Run** → FAIL. **Step 3: Implement.** **Step 4: Run** both, plus grove-themes `swift test` → PASS.
- [ ] **Step 5: Commit** `grove-themes, grove-dotfiles: the gallery link and the bar's menus`.

### Task 5: Install and check by hand

- [ ] **Step 1:** `grove install themes-app keys-app`, then `sketchybar --reload`. Run the full grove-dotfiles suite in the background → all pass. Then `grove check`.
- [ ] **Step 2: With the user:**
  - The pine dropdown, and Themes… opening the window.
  - Global Menu in Ghostty, Chrome and VS Code, with real items pressed.
  - The Apple menu items.
  - The app-name shortcut.
  - Clicking the pine with the Grove Keys window in front.
- [ ] **Step 3:** One fresh final review on the most capable model, then a fix pass. Copy the ledger to the private notes and wait for "merge it".

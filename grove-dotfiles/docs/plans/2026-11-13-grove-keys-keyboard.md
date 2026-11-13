# Grove Keys Keyboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Grove Keys draws the keyboard in its physical shape (ANSI/ISO) with each key's base and Shift characters from the current input source, in every view that shows a key.

**Architecture:** Core gains `KeyboardShape` (rows per shape, with key codes) and `Legends` (pure: raw translations → what a cap and a shortcut show). The app reads raw translations with `UCKeyTranslate` (beside `TypingLayout`) and the keyboard type with `KBGetLayoutType`, keeps both in `AppModel`, refreshes them on input-source change, and passes them to every view. Shortcut text goes through one function, `Shortcut.symbols(using:)`.

**Tech Stack:** Swift 6, SwiftUI + AppKit, Carbon (TIS/UCKeyTranslate), Swift Testing, Command Line Tools only (no `@State` macro: `State(initialValue:)`).

**Spec:** grove-dotfiles/docs/specs/2026-11-13-grove-keys-keyboard-design.md

## Global Constraints

- Shapes: `.ansi`, `.iso` only; JIS reads as ANSI.
- Caps show base and Shift (`1 !`, `º ª`, `< >`); letters one capital (`Ç`); no right-⌥ characters.
- `keys.toml`: `[keyboard] shape = "auto" | "iso" | "ansi"`; absent = auto; written only when not auto; unknown value = auto and reported like other bad values.
- `keys.toml` binding names never change; recording a shortcut stays by key code.
- ISO key codes: `section` 10 (top left), `backtick` 50 (beside left Shift), `backslash` 42 (beside Return, row 3). `KeyNames` gains `("section", 10)`.
- Row widths: every row adds up to 14.5 key units on both shapes; the board's outer size doesn't change.
- UI per the grove-ui skill (`~/.claude/skills/grove-ui/SKILL.md`): GroveUI tokens and roles only, JetBrains Mono via `GroveFont`, `GroveSegmented` for the shape setting.
- Never run the GroveKeys binary except `--check-menu`, `--render-aerospace`, `--render-panel` and the new `--render-keys` (a second running copy clears the Caps Lock mapping). Never commit `artifacts/`; never touch `grove-dotfiles/config/grove-keys/keys.toml` (the owner's uncommitted edit), `config/ssh/config`, `config/grove/local.env`.
- Commits: `area: summary` + body + `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`, staged by explicit path.

## Review Focus

1. An input source with no key table, or one whose translations are empty for most keys (an input method), must fall back to the US legends for the whole board, not show blank caps (Task 2 test `noTableFallsBackToUS`, Task 3 reader returns nil → `Legends.us`).
2. A translation that is a combining mark (dead keys can give U+0301 etc.) or more than one character must still show a visible, spacing character on the cap (Task 2 test `combiningMarksShowTheirSpacingAccent`).
3. A binding on a key the drawn shape doesn't have (`section` on ANSI) must be listed under the keyboard as "not on the keyboard", never dropped; `backtick` on ISO draws beside left Shift (Task 1 test `namesPerShape`, Task 3 extras use `KeyboardLayout.names(for:)`).
4. Changing the shape setting while a key is focused that the new board lacks moves focus to `KeyboardLayout.firstKey`, never to nothing (Task 3 step).
5. Arrows across the tall Return: ↓ from `rightSquareBracket`/`backslash` area and ↑ from right Shift reach `enter`; →/← from `enter` in either row reach that row's neighbour (Task 1 test `tallReturnNavigation`).

---

### Task 1: Keyboard shapes in Core, and the shape setting

**Files:**
- Modify: `grove-keys/app/Sources/GroveKeysCore/KeyboardLayout.swift`
- Modify: `grove-keys/app/Sources/GroveKeysCore/KeyNames.swift`
- Modify: `grove-keys/app/Sources/GroveKeysCore/KeysFile.swift`
- Test: `grove-keys/app/Tests/GroveKeysCoreTests/KeyboardLayoutTests.swift`, `KeysFileTests.swift`

**Interfaces:**
- Produces:
  - `public enum KeyboardShape: String, Sendable, CaseIterable { case ansi, iso; static func from(layoutType: Int32) -> KeyboardShape }` (`kKeyboardISO` = 1 → `.iso`, anything else `.ansi`; take the constant's value from Carbon's headers, don't import Carbon in Core).
  - `public enum KeyboardShapeSetting: String, Sendable, CaseIterable { case auto, iso, ansi; func resolved(detected: KeyboardShape) -> KeyboardShape }`
  - `KeyboardLayout.Cap` gains `public var keyCode: UInt16?` (every named cap; nil for modifiers/fn/caps) and `public var tall: Tall?` with `public enum Tall: Sendable { case top, bottom }` (the ISO Return: its `.top` part in row 2, `.bottom` in row 3, both named `enter`).
  - `KeyboardLayout.rows(for: KeyboardShape) -> [[Cap]]`, `names(for:) -> Set<String>`, `neighbor(of:_:shape:)`, `neighbor(of:_:extras:shape:)`. The existing static `rows`, `names`, `neighbor` stay as the ANSI ones (callers move to the shape-taking ones in Task 3).
  - `KeyNames.code(for name: String) -> UInt16?` if not already there; `("section", 10)` added.
  - `KeysFile.keyboardShape: KeyboardShapeSetting` (read) and `mutating func setKeyboardShape(_:)` (auto removes the key/section; others write `[keyboard] shape`). Unknown value → `.auto` plus the file's existing bad-value report path.

- [ ] **Step 1: Write the failing tests** in `KeyboardLayoutTests.swift`:
  - `isoRowsAddUpAndMatchTheSpec`: for both shapes every row's widths sum to 14.5; ISO row 1 starts with `section` (keyCode 10); ISO row 3 ends `[…, "semicolon", "quote", "backslash"(42), "enter"(.bottom)]`; ISO row 4 is `[shift 1.25, "backtick"(50), "z"…"m", "comma", "period", "slash", shift 2.25]`; ISO row 2 ends with `"enter"(.top)`.
  - `ansiRowsAreToday`: `rows(for: .ansi) == rows` (names, legends, widths).
  - `namesPerShape`: `names(for: .iso).contains("section")`, `!names(for: .ansi).contains("section")`, both contain `"backtick"`.
  - `everyNamedCapHasItsKeyCode`: for each named cap, `cap.keyCode == KeyNames.code(for: cap.name!)`.
  - `tallReturnNavigation` (ISO): `neighbor(of: "rightSquareBracket", .right, shape: .iso) == "enter"`, `neighbor(of: "backslash", .right, shape: .iso) == "enter"`, `neighbor(of: "enter", .left, shape: .iso)` is `"rightSquareBracket"` (top row first), `neighbor(of: "enter", .down, shape: .iso)` is the row-4 cap under it (right Shift is a modifier → the nearest named cap, `"slash"`), `neighbor(of: "delete"… )` — use `"backspace"`, `.down` → `"enter"`.
  - `shapeFromLayoutType`: `from(layoutType: 1) == .iso`, `0` and `2` → `.ansi`.
  In `KeysFileTests.swift`: `keyboardShapeAbsentIsAuto`, `keyboardShapeParses` (iso/ansi/auto), `keyboardShapeUnknownIsAutoAndReported` (`"jis"`), `settingAutoRemovesTheKey`, `settingIsoWritesTheSection` (round-trip keeps comments), `resolvedUsesDetectedOnlyForAuto`.

- [ ] **Step 2: Run:** `cd grove-keys/app && swift test --filter 'KeyboardLayoutTests|KeysFileTests'` — Expected: FAIL (no `KeyboardShape`).

- [ ] **Step 3: Implement.** ISO widths: row 1 `section` 1, digits, minus, equal 1 each, backspace 1.5; row 2 tab 1.5, 12 keys, `enter` top 1.0; row 3 caps 1.75, 11 keys + `backslash` 1, `enter` bottom 0.75; row 4 left shift 1.25, `backtick` 1, 10 keys, right shift 2.25; row 5 as ANSI. Navigation: the two `enter` parts are one stop — treat a slot named `enter` in either row as the same key (from `enter`, ←/→ use the top row; ↑/↓ from `enter` go to row 1 / row 4 using the union of both parts' extents). Keep the slot computation per shape (`slots(for:)`).

- [ ] **Step 4: Run** the same filter — Expected: PASS. Then `swift test` once — Expected: all pass.

- [ ] **Step 5: Commit** `KeyboardLayout.swift KeyNames.swift KeysFile.swift` and the two test files: `keys: ANSI and ISO keyboard shapes, and the [keyboard] shape setting`.

### Task 2: Legends in Core, and shortcut text with them

**Files:**
- Create: `grove-keys/app/Sources/GroveKeysCore/Legends.swift`
- Modify: `grove-keys/app/Sources/GroveKeysCore/Shortcut.swift`
- Create: `grove-keys/app/scripts/record-legends.swift` (one-off recorder, not part of any target)
- Create: `grove-keys/app/Tests/GroveKeysCoreTests/Fixtures/legends-pt-PT.json`, `legends-US.json`
- Test: `grove-keys/app/Tests/GroveKeysCoreTests/LegendsTests.swift`, `ShortcutTests.swift`

**Interfaces:**
- Consumes: `KeyNames.code(for:)` (Task 1).
- Produces:
  - `public struct RawTranslation: Codable, Sendable, Equatable { public var base: String?; public var shift: String? }` (what `UCKeyTranslate` gave with no modifiers / Shift, dead keys not composed).
  - `public struct Legend: Sendable, Equatable { public var base: String; public var shift: String? }` (shift nil = one-line cap).
  - `public struct Legends: Sendable, Equatable { public init(raw: [UInt16: RawTranslation]); public static let us: Legends; public func legend(keyCode: UInt16) -> Legend?; public func symbol(forKey name: String) -> String? }` — `legend` is nil for keys that type nothing printable (the cap keeps its name); `symbol(forKey:)` is the single character a shortcut shows (`"Ç"`, `";"`), nil to fall back to the name table.
  - `Shortcut.symbols(using legends: Legends) -> String`; `symbols` (no argument) becomes `symbols(using: .us)`.
  - JSON fixture format: `{ "<keyCode>": { "base": "…", "shift": "…" }, … }` for key codes 0–50 that have a name in `KeyNames`.

- [ ] **Step 1: Record the fixtures.** Write `scripts/record-legends.swift` (Carbon): for input source IDs given as arguments, find the source with `TISCreateInputSourceList([kTISPropertyInputSourceID: id], true)`, read `kTISPropertyUnicodeKeyLayoutData`, and for each key code in `KeyNames` call `UCKeyTranslate` with no modifiers and with Shift (`kUCKeyTranslateNoDeadKeysMask`, keyboard type `LMGetKbdType()`), printing the JSON. Run `swift scripts/record-legends.swift com.apple.keylayout.US > Tests/GroveKeysCoreTests/Fixtures/legends-US.json` and the same for the Portuguese layout (find its exact ID with the script's `--list`). Check by eye: pt-PT key 41 base `ç`, key 10 base `§`, key 50 base `<` shift `>`, key 29/18 etc. digits with `!"#`.
- [ ] **Step 2: Write the failing tests** in `LegendsTests.swift` (load with `fixture(_:)` and `JSONDecoder` into `[String: RawTranslation]`, keys → `UInt16`):
  - `ptLetterIsOneCapital`: pt `legend(keyCode: 41) == Legend(base: "Ç", shift: nil)`; `legend(keyCode: 0) == Legend(base: "A", shift: nil)`.
  - `ptBaseAndShift`: key 18 → `("1", "!")`; key 50 → `("<", ">")`; key 10 → `("§", "±")`.
  - `deadKeysShowTheirAccent`: the pt acute/tilde keys' legends are non-empty spacing characters (`´`, `~`/`^` as the fixture gives).
  - `combiningMarksShowTheirSpacingAccent`: `Legends(raw: [33: RawTranslation(base: "\u{301}", shift: "\u{300}")])` gives `("´", "`")`.
  - `sameShiftShowsBaseOnly`: raw `("+", "+")` → `Legend(base: "+", shift: nil)`.
  - `nothingPrintableIsNil`: raw base `"\t"`, `"\r"`, `" "`, `"\u{7f}"`, empty, nil → `legend == nil`.
  - `noTableFallsBackToUS`: `Legends(raw: [:]) == .us`; and a raw table where fewer than 10 of the letter keys print → `.us`.
  - `usLegendsMatchTodaysCaps`: for every named ANSI cap with a one-character legend today, `Legends.us` gives that legend (base) — the US board doesn't change.
  In `ShortcutTests.swift`: `symbolsUseLegends`: `Shortcut(aerospace: "hyper-semicolon")!.symbols(using: pt) == "⌃⌥⇧⌘ Ç"`, `.symbols(using: .us) == "⌃⌥⇧⌘ ;"`; `specialKeysKeepTheirGlyphs` (`tab`, `enter`, `backspace`, `esc`, `space`, arrows identical with pt); `symbolsWithoutArgumentIsUS`.
- [ ] **Step 3: Run:** `swift test --filter 'LegendsTests|ShortcutTests'` — Expected: FAIL.
- [ ] **Step 4: Implement** `Legends.swift`; `Legends.us` is built from `legends-US.json`'s content embedded as a Swift literal (Core can't read test fixtures). Combining marks map to their spacing forms (U+0301→´, U+0300→`, U+0302→^, U+0303→~, U+0308→¨; anything else combining → prefix U+00A0). Change `Shortcut.keySymbol` to ask `legends.symbol(forKey:)` first, the existing table second.
- [ ] **Step 5: Run** the filter, then `swift test` — Expected: PASS.
- [ ] **Step 6: Commit** the new/changed files and fixtures: `keys: legends from the input source's table, and shortcut text with them`.

### Task 3: The app reads the keyboard and draws it

**Files:**
- Create: `grove-keys/app/Sources/GroveKeys/KeyboardReader.swift`
- Modify: `AppModel.swift`, `KeyboardGrid.swift`, `KeyCapView.swift`, `KeyboardView.swift`, `CheatSheetPanel.swift`, `TypingLayout.swift` (share the table lookup), `main.swift`
- Create: `grove-keys/app/Sources/GroveKeys/KeysRender.swift`

**Interfaces:**
- Consumes: Task 1 `KeyboardShape`, `KeyboardShapeSetting`, `KeyboardLayout.rows(for:)/names(for:)/neighbor(…shape:)`, `KeysFile.keyboardShape/setKeyboardShape`; Task 2 `RawTranslation`, `Legends`, `Legend`.
- Produces:
  - `@MainActor enum KeyboardReader { static func legends(inputSourceID: String? = nil) -> Legends; static func detectedShape() -> KeyboardShape }` (nil ID = current input source; no table → `.us`).
  - `AppModel`: `@Published var legends: Legends`, `@Published var detectedShape: KeyboardShape`, `var shape: KeyboardShape` (setting resolved), `func setKeyboardShape(_ setting: KeyboardShapeSetting)` (saves through the existing keys.toml save path). Refreshed on `TypingLayout.changed` (distributed notification) — the same observer that refreshes `TypingLayout`.
  - `GroveKeys --render-keys <keyboard|cheatsheet> <out.png> [scheme] [iso|ansi] [inputSourceID]`, same conventions as `--render-panel` (no window, `.prohibited`, sample keys.toml from the app's fixture, exits).

- [ ] **Step 1: `KeyboardReader`** — move the `UCKeyTranslate` call into one helper used by both `TypingLayout.optionText` and `KeyboardReader.legends` (modifiers none / Shift, dead keys not composed). `detectedShape()` = `KeyboardShape.from(layoutType: KBGetLayoutType(Int16(LMGetKbdType())))`.
- [ ] **Step 2: `AppModel`** holds `legends`, `detectedShape`, the setting from `KeysFile.keyboardShape`; refresh both on input-source change. Changing the shape (setting or detection) while `focused` names a key not in `KeyboardLayout.names(for: shape)` sets focus to `KeyboardLayout.firstKey` (Review Focus 4).
- [ ] **Step 3: Drawing.** `KeyboardGrid` takes `shape` and `legends`, iterates `rows(for: shape)`; the ISO Return is one cap drawn as an inverted L (a GroveUI-radius `Shape` spanning the row-2 part and the row-3 part; the `.bottom` cap draws nothing of its own and isn't hit-tested separately). `KeyCapView` shows a two-line legend when `legend.shift != nil` (Shift above base, smaller: `GroveType.finePrint` for Shift, existing size for base), one line otherwise; caps without a legend keep their names. Extras ("not on the keyboard") use `names(for: shape)`; arrows use `neighbor(…shape:)`.
- [ ] **Step 4: The setting.** On the Keyboard tab beside the layer picker: `GroveSegmented` "Keyboard" with "Automatic (ISO)"/"Automatic (ANSI)" (the detected one), "ISO", "ANSI" → `model.setKeyboardShape`.
- [ ] **Step 5: `--render-keys`** in `KeysRender.swift`, wired in `main.swift` next to `--render-panel` and before anything that touches the HID mapping. Render keyboard and cheatsheet for `iso` + Portuguese ID and `ansi` + `com.apple.keylayout.US`, in `dark-medium` and `light-medium`, to `/Users/gmarques/Developer/project-grove/artifacts/grove-keys/renders/keyboard/{keyboard,cheatsheet}-{iso-pt,ansi-us}-{dark,light}.png`; look at every one. The ANSI US renders must look like today's apart from nothing.
- [ ] **Step 6: Run** `swift build` and `swift test` in grove-keys/app and grove-themes/app — Expected: all pass.
- [ ] **Step 7: Commit** by explicit path: `keys: the board in the keyboard's shape with its legends`.

### Task 4: Every shortcut text uses the legends; the Global Menu row; docs

**Files:**
- Modify: `GroveKeysCore/BindingRows.swift:68`, `CheatSheet.swift:199`, `Layers.swift:117`, `GhosttyKeybinds.swift:105` (each takes `legends: Legends = .us` and passes it to `symbols(using:)`); app `BindingsView.swift:184,262,470`, `KeyEditorPopover.swift:79,96`, `KeyboardView.swift:210,231`, `CheatSearchPanel.swift`, `Panels/GroveMenuPanel.swift` / `Panels/MenuList.swift`
- Modify: `grove-dotfiles/docs/manual/` (the Grove Keys chapter), `grove-dotfiles/docs/specs/2026-11-13-grove-keys-keyboard-design.md` only if something built differs
- Test: `BindingRowsTests.swift`, `CheatSheetTests.swift`, `LayersTests.swift`, `MenuListTests.swift` / `GroveMenuTests.swift`

**Interfaces:**
- Consumes: Task 2 `Legends`, `Shortcut.symbols(using:)`; Task 3 `AppModel.legends`.
- Produces: no new names; every `.symbols` call site in Sources passes `model.legends` (or the Core function's `legends` parameter). `grep -rn "\.symbols\b" Sources` afterwards finds only `symbols(using:` calls.

- [ ] **Step 1: Failing tests:** `bindingRowsShowLegends` (a `hyper-semicolon` row's shortcut text with pt legends is `⌃⌥⇧⌘ Ç`), `cheatSheetSearchShowsLegends` (`CheatSheet` line for key `semicolon` with pt → `Hyper Ç`), `globalMenuRowHasNoChevron` (whatever Core decides the row's kind/chevron — if the chevron decision is app-only, move it into `MenuList` Core as `MenuListRow.Kind.showsChevron` with `.link` → false, `.submenu` → true, and test that).
- [ ] **Step 2: Run** those tests — Expected: FAIL.
- [ ] **Step 3: Implement** the parameter threading and the chevron rule (the `global-menu` builtin keeps kind `.link` and its behaviour; only the arrow goes).
- [ ] **Step 4: Run** `swift test` (grove-keys) — Expected: PASS; `grep -rn "\.symbols\b" Sources` — Expected: no bare `.symbols`.
- [ ] **Step 5: Renders:** `--render-panel grove-menu …` dark and light into `artifacts/grove-keys/renders/keyboard/grove-menu-{dark,light}.png` (Global Menu row without arrow); re-render Task 3's set; look at all.
- [ ] **Step 6: Docs:** manual chapter: one paragraph "The keyboard you type on" (shape, legends, `[keyboard] shape`), and the `section` key name in the key-name list if the manual has one.
- [ ] **Step 7: Installer check:** `cd grove-dotfiles && bats tests/modules_keys_app.bats` — Expected: all ok.
- [ ] **Step 8: Commit** by explicit path: `keys: shortcut text with the layout's characters everywhere; Global Menu without an arrow`.
- [ ] **Step 9: STOP.** Hand back the renders' paths and a by-hand list for the owner: (1) the board matches the physical keys, § top left and < beside Shift; (2) switch to US input source in the menu bar: legends change live, also with the Hyper cheat sheet open; (3) a binding recorded by pressing ç saves `semicolon`; (4) the shape setting's three choices; (5) the Global Menu row. The controller shows the owner the renders and installs only on his word (`zsh -lc 'grove --yes install 96-keys-app'`).

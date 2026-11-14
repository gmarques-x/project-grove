# Grove Keys shows the keyboard you type on

Date: 2026-11-13. Status: approved in conversation; this document for review.

## 1. Goal

Grove Keys draws a hard-coded MacBook ANSI US keyboard. The owner's Macs have
Portuguese (pt-PT) ISO keyboards, so the drawn board and the shortcut text don't
match the keys under his hands. After this change, Grove Keys draws the board
in the keyboard's physical shape, with each key showing what it types on the
current input source, everywhere a key or shortcut is shown.

Success: on the owner's Mac the Keyboard tab matches the physical keyboard key
for key, and every binding shows the character he would actually press. On a US
ANSI Mac nothing looks different from today.

Also in this change, from the roadmap: the Grove menu's "Global Menu" row loses
its submenu arrow (it opens the native menus; it is not a side submenu).

## 2. Owner's decisions

- Each key shows its **base and Shift** characters, as printed on Apple keys
  (`1 !`, `º ª`, `< >`); right-⌥ characters are not shown.
- The shape is **automatic** (macOS says what kind of keyboard it is), with a
  setting to pin it. Neither Mac has an external keyboard or a JIS keyboard, so
  only **ANSI and ISO** are drawn; JIS falls back to ANSI.
- Bindings keep their AeroSpace names in `keys.toml` (they are physical keys):
  a `keys.toml` written on one Mac works on another.

## 3. Shapes

`KeyboardShape` (Core): `.ansi`, `.iso`. Each gives the rows of physical keys
without the function row, each key carrying its macOS key code and its
AeroSpace name (nil for modifiers, fn, caps).

- **ANSI** is exactly today's `KeyboardLayout.rows`.
- **ISO** (Apple's ISO MacBook layout):
  - row 1: `section` (key code 10) where ANSI has `backtick`, then 1…0,
    `minus`, `equal`, delete;
  - row 2: tab, q…p, `leftSquareBracket`, `rightSquareBracket`, then the top
    half of a tall Return;
  - row 3: caps, a…l, `semicolon`, `quote`, `backslash` (key code 42, here on
    ISO), then the bottom half of Return;
  - row 4: a short left Shift (1.25), `backtick` (key code 50, beside left Shift
    on ISO Macs), z…m, `comma`, `period`, `slash`, right Shift;
  - row 5 as ANSI.
  - Return is drawn as one tall cap spanning rows 2–3, as on the keyboard.
- The ISO key codes above (10 top left, 50 beside left Shift, 42 beside
  Return) are Apple's documented ISO behaviour; the build confirms them with
  the Portuguese layout's own table (code 10 types §, code 50 types <) before
  the renders, and the owner confirms the drawn board against his keys before
  install.
- Row widths add up as today, so the board's outer size doesn't change.
- Keyboard navigation (arrows, ⌃H/J/K/L) works on both shapes: the tall Return
  is one stop reachable from both rows.
- AeroSpace 0.21.3 knows `section` as a key name, so every ISO key is bindable.
  `KeyNames` gains `("section", 10)`.

## 4. Legends

`Legends` (Core): a plain table from key code to `Legend { base, shift }`, plus
the names shown when a key types nothing.

- Read in the app from the current input source's `UCKeyboardLayout` (the same
  table `TypingLayout` already reads for right ⌥), with `UCKeyTranslate` for no
  modifiers and for Shift, dead keys not composed (an accent key gives its
  accent: `´`, `~`, `^`, `¨`).
- Turning raw translations into legends is pure Core logic, tested:
  - a letter shows one capital (`Ç`, not `ç Ç`);
  - a key whose Shift character is the capital of its base, or the same as its
    base, shows the base only;
  - a key that types nothing, a control character or whitespace shows its name
    (tab, delete, return, space shows nothing as today);
  - modifiers, fn, caps and the arrows keep today's legends (`⇪` / `⇪ hyper`).
- No key table (some input methods): the US legends are used.
- Live: on `kTISNotifySelectedKeyboardInputSourceChanged` the legends are read
  again and every open view redraws (Keyboard tab, cheat sheets, popover).

## 5. Choosing the shape

- Automatic: `KBGetLayoutType(LMGetKbdType())` → ISO for `kKeyboardISO`, ANSI
  otherwise (JIS included).
- Setting in `keys.toml`: `[keyboard] shape = "auto" | "iso" | "ansi"`. Absent
  means auto; the app writes the section only when the owner picks something
  other than auto. An unknown value reads as auto and is reported like other
  bad values in `keys.toml`.
- In the app: a "Keyboard" setting with Automatic (shows what it found, e.g.
  "Automatic (ISO)"), ISO, ANSI, using the app's existing segmented control.

## 6. Where keys are shown

All key text goes through one function, `Shortcut.symbols(using: Legends)`:

- the Keyboard tab (caps: base and Shift legends, binding below as today; the
  "Not on the keyboard" list);
- the cheat sheet on Hyper hold and the searchable cheat sheet (Hyper+K: the
  Hyper and AeroSpace rows; Ghostty's rows whose trigger is a W3C physical key
  name such as `backquote` or `arrow_up`, while its one-character triggers
  (`w`, `,`, `[`) match the character typed and are written as they are; the
  shell list's quick terminal, `ctrl+grave_accent`, a place: `⌃ <` on the
  owner's Mac. zsh's ⌃R, ⌃T, ⌥C match by character and macOS's list is fixed
  text);
- the key editor popover;
- the Bindings rows and their clash lines.

(As built: the Grove menu writes no shortcut hints, so it has none to change.)

`hyper-semicolon` reads `⌃⌥⇧⌘ Ç` on the owner's Mac and `⌃⌥⇧⌘ ;` on a US Mac.
Special keys keep their glyphs (⇥ ↩ ⌫ Esc Space ← → ↑ ↓). Letters show as
capitals, as today.

Recording a shortcut (`ShortcutRecorder`) stays by key code: pressing `ç`
records `semicolon`, the key at that position.

## 7. Global Menu row

The Grove menu panel draws no submenu arrow on the `global-menu` builtin row
(today it gets one because the row opens a menu). Other rows with children keep
theirs.

## 8. What doesn't change

- `keys.toml` names and the AeroSpace config written from it.
- The Hyper engine, launchers, right ⌥ typing.
- The board's outer size and the cap style (GroveUI tokens, JetBrains Mono).

## 9. Testing

- Core tests:
  - both shapes' rows: names, key codes, widths adding up, the tall Return,
    navigation stops;
  - legends from a recorded pt-PT key table and a US one (fixtures saved as
    bytes, so the tests don't depend on the Mac's settings): dead keys, letter
    capitals, base-only keys, keys that type nothing;
  - shortcut text with legends;
  - the shape setting: parse, absent, unknown value.
- Renders (existing `--render-panel` path): the Keyboard tab and the Hyper cheat
  sheet in pt-PT ISO and US ANSI, dark and light, into
  a private folder. The owner reviews them before install.
- Grove menu render showing the Global Menu row without its arrow.
- `swift test` for grove-keys and grove-themes; the installer's bats for
  96-keys-app.

## 10. Out of scope

JIS drawing; external keyboards with a different shape from the built-in one
(the setting covers it); showing right-⌥ characters; translating `keys.toml`
names to the layout.

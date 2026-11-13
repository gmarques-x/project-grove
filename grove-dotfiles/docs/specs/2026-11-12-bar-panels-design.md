# The bar's panels (one frame for every dropdown)

Date: 2026-11-12. Status: approved by the owner from rendered mock-ups (the choices are in §2). Built in stages: stage 1 is the foundation, the clock and the bar's wiring; the other panels follow, one file each.

## 1. Goal

Every dropdown of the Grove bar (the pine's Grove menu, CPU & memory, battery, Wi-Fi, sound, the clock) looks like one family and hangs exactly where its button is: one frame, one orange outline, aligned with its pill and with the tiled windows under the bar. Their content is cut down to what is read at a glance, and Wi-Fi gains a speed test.

Until now the Grove menu was a native menu at the pointer and the others were SketchyBar popups (a bg1 box of text rows, hung from the item, drawn by shell plugins). SketchyBar's popups can't hold a control, a chart with two series, a hover row or a calendar, and can't be placed to the half point; they go.

## 2. The owner's decisions

- One style for all six, with an **orange 1 pt outline** (the pills' colour), fill **bg0** (the bar's own colour; bg1 was the other mock-up).
- Right-side dropdowns are **right-aligned with their pill**; only the Grove menu is left-aligned (with the pine pill).
- Less in each: CPU, battery, Wi-Fi and sound as in §6. Wi-Fi gets a **speed test**.
- From the mock-ups: the Grove menu **with icons** (variant B), the calendar **with week numbers** (variant A), CPU and memory **stacked** in one panel.
- "I want the menus to align perfectly with the open windows, as in **border over border**" (§5).
- Battery: Low Power Mode is a row that **opens Battery Settings** (macOS lets no app flip it without admin rights). Later the same day: the battery panel also gets **Keep Awake** and **Ignore Lid**, "the same options that Vorssaint has" (§6).

## 3. Architecture

Every dropdown is a panel drawn by **Grove Keys**: it is always running, signed, and already answers `grovekeys://` links from the bar. The bar (SketchyBar) draws the pills and sends a link on click; it has no popups.

- `grovekeys://panel/<name>` toggles the panel `<name>`: `clock`, `system`, `battery`, `wifi`, `sound`, `grove`. Opening one closes any other; a second link for the open one closes it. `grovekeys://panel/close` closes whichever is open. A name nobody registered is ignored. `grovekeys://grove-menu`, the pine's link while its menu was native, is the same as `panel/grove`.
- The bar sends them with `open -g`, so macOS doesn't bring Grove Keys forward for a link.
- A panel is a borderless, non-activating window above the normal windows that can take the keyboard without Grove Keys becoming the front app.
- The shared drawing (frame, rows, charts, meters) is in `GroveUI`; the host, the registry and each panel are in Grove Keys (`Sources/GroveKeys/Panels/`); what a panel computes (a month's grid, the placement) is pure code in `GroveKeysCore`, tested.

## 4. The common frame

- Fill bg0. Outline 1 pt in the role `panelOutline`: the palette's `orange`, exposed as a role in `GroveUI`'s `Theme.swift`. No palette change: the colour is the pills' and already in all six files; the role only names the job.
- Orange inside a panel: none. The outline is the dropdowns' identity, and the rules give orange the meaning "warning", so a warning inside a panel is a dot and a word, never an outline, and **no chart line, bar or meter is orange**.
- Corner radius 10 (`GroveRadius.card`), except a corner that lies on a window border's corner (§5).
- 12 pt inside; sections 12 pt apart with a 1 pt `line` between; no boxes inside.
- Header: the item's symbol in its bar colour, the title (heading size, semibold), the headline value or control at the right (title size).
- Labels quiet, values fg, JetBrains Mono on the scale (10/11/12/13/15).
- Rows that do something fill with `hoverFill` under the pointer (the fill reaches 4 pt from the outline; the text stays on the 12 pt inset). The last row is a footer link ("Battery Settings…").
- Controls are the system's: `Toggle` (switch) and `Slider`, tinted green; buttons are Grove's pill.
- Fixed width per panel, as tall as its content; the height may change while open (Wi-Fi's "Show apps").
- While a panel is open its pill is filled with the hover fill (§7).

## 5. Alignment: border over border

### What was measured (2026-11-12, built-in display, 1920 × 1243 pt at 2x)

From 2x screen captures of the top-left and top-right corners (`screencapture -x -R`), reading the pixel rows and columns, and from the window list (`CGWindowListCopyWindowInfo`):

| What | Where |
| --- | --- |
| The bar's strip | y 0 to 48 |
| A pill's outline | exactly its bracket's rectangle from `sketchybar --query pill.<x>` (`bounding_rects`): pine pill x 12 to 56, clock pill x 1758 to 1908, y 12 to 36; the 1 pt line is the rectangle's outermost point |
| Top-row tiled windows (AeroSpace) | left window x 8, right window's right edge x 1912, top y 52 (the notch's 37.5 + the 14 pt gap, rounded up) |
| The window border (JankyBorders, `width=5.0`, `style=round`) | visible for 2.5 pt outside the window: outer edge at **x 5.5** (left), **x 1914.5** (right), **y 49.5** (top) |
| The border's outer corner | radius **18.5** (the window's 16 + 2.5), fitted to the arc's pixels |
| A `borders` window | the bordered window's frame grown by 13 on every side (the width + JankyBorders' 8 pt padding): the outer line is that rectangle **inset by 8 + width / 2 = 10.5** |

So the border's outer edge is 1.5 pt below the strip, and 6.5 pt outside the pills' end outlines as the bar was (12 and 1908).

### The rule

1. **Top.** A panel's top outer edge is the top border's outer edge (y 49.5). The orange line and the border's top line are one line; the panel's fill covers the border under it.
2. **Flush, not centred.** The panel's 1 pt line sits flush with the border's outer edge, not centred on the 2.5 pt band. Decided from zoomed composites on real captures: centred, a 0.75 pt sliver of the border shows above and beside the panel and reads as a misfit; flush, the border runs into the orange line with one outer edge.
3. **Sides.** A right-side panel's right outer edge is its pill's right outline; the Grove menu's left outer edge is the pine pill's left outline. Where the pill is the bar's last one (the pine at the left, the clock at the right: its end outline within 2 pt of the border's line), the panel's side edge is the window border's outer side line instead (x 5.5 or 1914.5), and that top corner takes the border's corner radius (18.5), so the outline follows the window border round the corner.
4. **Never outside the lines.** A panel wider than the room is moved in, not cut: it stays between the left and right lines and above the screen's bottom gap.
5. **The bar agrees.** The pine pill's left outline and the clock pill's right outline sit on the borders' side lines, so pill, border and panel edge are one vertical line: the bar's end padding goes from 8 + 4 to **0 + 6** (`padding_left`/`padding_right` 0, `gap.l0`/`gap.r0` 6), which puts the pills' ends at x 6 and 1914. SketchyBar places items on whole points and the border's line is on a half point (5.5), so the pill's line (6 to 7) and the panel's (5.5 to 6.5) overlap by half a point rather than coincide; the panel follows the border exactly. **Later the same day** the owner chose a border width of 6.0: every line is now on a whole point (5, 49, 1915), the bar's end gaps are 5, and pill, border and panel edge coincide. The measurements above were taken at width 5.0; the app reads the configured width, so the rule is unchanged.

### How the app knows the lines

At opening, from the windows on screen: those owned by `borders`, each inset by 8 + width / 2 (the width read from `~/.config/borders/bordersrc`, 5 when it can't be). The ones whose top is within 12 pt below the strip are the top row; the top line is their smallest top, the left line the smallest left if it is within 16 pt of the screen's left edge, the right line likewise. With no tiled window on the workspace (or a floating one alone) the lines come from the configured gaps: the window's top at 51 (the strip + 3), or the notch's inset + 14 rounded up on the built-in display, sides 8, each less width / 2. The fallback's numbers are held to `aerospace.base.toml` and `bordersrc.tmpl` by a test.

The pill's rectangle comes from `sketchybar --query pill.<x>` at opening (a bracket reports its own `bounding_rects`). If the bar doesn't answer, the panel hangs from the screen's own corner on its side, on the lines.

Placement is pure code (`BarPanelPlacement` in GroveKeysCore): the screen's frame, the strip's height, the pill's rectangle, the lines and the panel's size give the panel's frame and which corner follows the border. The window that holds the panel is the frame grown to whole points; the panel is drawn inside it at the half point.

## 6. The six panels (as approved)

**CPU & memory** (`system`, from the CPU and memory pill; stacked). CPU: the percentage; a 60 s chart; each core's load as a small bar, grouped by core type (Performance, Efficiency); the three busiest processes with their share. A line. Memory: the percentage; a 60 s chart; one segmented bar (app, wired, compressed, free) with its legend in GB; Pressure as a dot and a word (green Normal, a warning, red critical); Swap only when in use; the three largest processes. Footer: "Activity Monitor…" (opens it), with the uptime and the load average at its right, quiet.

**Battery** (`battery`). Glanceable first: the percentage; the charge bar; one state sentence ("Charging · 0:13 to full"). Then three detail rows: Power ("94 W adapter · Mac using 17.7 W"), Health ("100% · 96 cycles"), Temperature. Then, in this order:

- **Keep Awake**: a switch (the native `Toggle`, green) that keeps the Mac and its display from sleeping while on. Grove Keys holds two IOKit power assertions (`IOPMAssertionCreateWithName`: `PreventUserIdleSystemSleep` and `PreventUserIdleDisplaySleep`): no admin rights; released when switched off, when the duration ends and when Grove Keys quits. Beside it a duration, a `GroveSelect`: "Until turned off" (default), "1 hour", "2 hours", "4 hours". While on with a duration, the row shows the time left.
- **Ignore Lid**: a switch that keeps the Mac running with the lid closed (`pmset -a disablesleep 1` / `0`). That needs admin rights: flipping it runs the change through macOS's own authorization prompt (e.g. `osascript -e 'do shell script "/usr/bin/pmset -a disablesleep 1" with administrator privileges'`), so the owner types the password or uses Touch ID in the system's dialog each time. Grove never handles a password, and nothing is installed to skip the prompt. Its state is read from `pmset -g` (`SleepDisabled`) each time the panel opens, never remembered. Safety: it is only offered while Keep Awake is on. Switching Keep Awake off, its duration ending or Grove Keys quitting must turn `disablesleep` back off (the prompt again, when the app does it); if the owner cancels that prompt or the app is killed, the next opening shows Ignore Lid as still on in the warning style (a dot and words, not an outline) with one click to turn it off. On battery below 20 % it is refused with a one-line reason ("battery protection"), as Vorssaint does.
- **Low Power Mode**: a row that opens Battery Settings (§2).
- Footer: "Battery Settings…".

Open detail for stage 2: both Keep Awake and Ignore Lid must show on the bar while active, so the owner can tell the Mac won't sleep: the battery pill's bolt gains a small mark, or a small indicator pill appears beside it. No orange outline for it.

**Wi-Fi** (`wifi`). Header: the network's name and the on/off switch. The live rates, down and up, over one chart of the last 60 s (down blue, up purple). IP, Router and DNS rows; a click copies the value. Speed test, through `/usr/bin/networkQuality`: idle (a "Run speed test" button); running (Cancel and a bar of the elapsed time); a result (down, up, latency, with its age and "Run again"). "Show apps", closed by default; opened, the three apps using the network most. Footer: "Wi-Fi Settings…". (Ethernet, a tunnel and offline change the header's symbol and name.)

**Sound** (`sound`, new: the volume pill had no dropdown). Header with the level; the volume slider; Mute (a switch); Output: the devices, the current one ticked, a click switches; an Input row with the current device; footer "Sound Settings…".

**Clock** (`clock`, variant A, 248 pt). The month and year as the title, with chevrons to the previous and next month. A grid, Monday first: a quiet "wk" column with ISO week numbers; the neighbouring months' days shown fainter instead of blanks; today a green disc with the on-accent ink. A line, then the footer: today spelt out ("Thursday 12 November") and "week 46". ←/→ change the month; a click on the footer (or Home, or T) comes back to today. It opens on the current month every time. Month and day names follow the user's language; the layout (Monday first, ISO weeks, day before month) doesn't follow the region.

**Grove menu** (`grove`, variant B, 200 pt; built 2026-11-12). The rows of `menu.toml` and `menu.local.toml` (the same merged tree the launcher lists: file order, separators, hidden rows, a broken file as a quiet first row, Grove Keys' own items in place of the `keys` builtin). No header: a menu's rows are its content. Left edge on the pine pill's left outline, which is the window border's line, so the top-left corner follows the border's.

- **Rows.** Label size, 24 pt each, the hover fill reaching 4 pt from the outline; a separator is a 1 pt line with 4 pt above and below; a row that can't be chosen is quiet and wraps. At the right: a green tick on a row whose `checked` test succeeded, a quiet chevron on a row that opens something.
- **Icons.** Before each top-level row, quiet, in a 16 pt column: the row's `icon` in the menu file (an SF Symbol's name that is one of `GroveIcon.Name`'s; the seven shipped rows have one). A top-level row without one keeps the indent. Submenus have no icon column.
- **Submenus.** A second panel (and a third: the tree can be deeper), same frame, as wide as its titles need between 190 and 408 pt. Its left outline is the parent's right outline (the two 1 pt lines are one) and its first row is level with the row that opened it; near the screen's right or bottom it goes to the parent's left or moves up, inside the lines of §5. It opens when the pointer has rested about 150 ms on its row, at once on a click, → or Return, and stays while the pointer moves toward it across other rows (300 ms of grace).
- **Keys.** ↑/↓ move, skipping lines and rows that can't be chosen, wrapping; Home and End go to the ends; Return or Space runs the row; → opens a submenu and goes into it; ← or Escape closes the submenu the keys are in (Escape at the top level closes the menu); a letter jumps to the next row starting with it. One highlighted row per level, the pointer's and the keys' alike.
- **Global Menu.** The front app's own menus can't be restyled: the row has a submenu's chevron, and choosing it puts the panel away and pops the native Global Menu with its top-left corner where the panel's was.
- **Running a row.** What `MenuRunner` does for the launcher (`run`, `present`, `open`, a builtin), after putting the panel away: through `leave` when the row brings something forward, `close` otherwise, so the previous app keeps the keyboard as it did with the native menu.
- `checked` tests run when their level is shown, 0.5 s each at most, all at once; nothing runs while the menu is closed.

## 7. The host (Grove Keys)

- **Window.** A borderless `NSPanel`, `.nonactivatingPanel`, at the status-bar level (above normal windows and the window borders; it starts 1.5 pt below the strip, so nothing of the bar is covered), on every Space, no shadow. It takes the keyboard (`canBecomeKey`) without Grove Keys coming forward, so sliders, switches and the arrow keys work. It opens on the screen the pointer is on.
- **Closing.** Escape; a click anywhere outside it; another app coming forward; an AeroSpace workspace change (the bar's workspaces plugin sends `grovekeys://panel/close`, only while a panel is open: one file test otherwise); a Space change; a change of the screens; `panel/close`; the toggle link.
- **The click on its own pill.** That click is first a click outside (the panel closes), then the toggle link arrives. A toggle for the panel that an outside click closed within the last half second is that same "put away", not a new "show" (`BarPanelToggle`, pure, tested).
- **Focus.** The app in front is never deactivated by opening a panel; if macOS did bring Grove Keys forward, the app that was in front gets the keyboard back on closing. Not when the panel closed because of what was chosen (a footer that opens Settings, Activity Monitor) or because another app came forward.
- **Cost.** A panel's model is made the first time it opens and kept; `start()` runs at each opening and `stop()` at each closing. Closed, a panel runs nothing: no timer, no process.
- **The open pill.** On opening, Grove Keys writes the pill's name to `$GROVE_STATE/bar-panel` and fills the pill (`sketchybar --set pill.<x> background.color=<hover fill>`); on closing it removes the file and clears the fill (unless the pointer is still over the pill, whose hover keeps it). The bar's hover helper (`sb_hover`) leaves the open pill filled when the pointer leaves; a reload of the bar fills it again.
- **Side panels.** A panel whose model has them (the Grove menu's submenus) gets each as a child window of the panel's own: same level, never key (the keys stay the main panel's model's), so a click in one is not a click outside and closing the panel closes them. The host places them (`MenuListPlacement.submenu`) and follows the model as they open and close.
- **Escape** is offered to the model first (`escape()`): a menu closes its submenu; any other panel is put away.
- **One-shot.** `GroveKeys --render-panel <name> <out.png> [scheme] [left|right]` draws a panel with its sample data to a PNG at 2x and exits, without starting the app or showing a window (as `--check-menu`). A sample with side panels is drawn with them beside it.

## 8. The bar

- Every pill's click sends its link: clock → `panel/clock`; cpu and mem → `panel/system`; battery → `panel/battery`; wifi → `panel/wifi`; volume → `panel/sound`. The pine sends `grovekeys://grove-menu`, which the app with the Grove menu's panel answers as `panel/grove` and the app before it as the native menu, so the bar works with either. It is still sent without `-g`: the native menu of an app not yet updated needs Grove Keys brought forward. Once the new app is installed the pine's click becomes `open -g grovekeys://panel/grove`, like the other pills (one line of `sketchybarrc` and one of `tests/sketchybar_config.bats`).
- Gone: the popups and what only they used (`plugins/popup.sh`, `clock_popup.sh`, `network_popup.sh`, `system_popup.sh`, `battery_popup.sh`, `net_sample.sh` and its hidden item, the popup and chart items, the popup helpers and the parsers only they called). The bar's own labels and icons are as they were.
- The end gaps of §5.

## 9. For panel authors

A panel is one file in `grove-keys/app/Sources/GroveKeys/Panels/`. The four placeholders (`SystemPanel.swift`, `BatteryPanel.swift`, `WifiPanel.swift`, `SoundPanel.swift`) are registered and open from their pills already: building one means replacing that file's model and body, and touching neither `BarPanels.swift` (the list) nor `BarPanelHost.swift` (the window). `ClockPanel.swift` is the worked example.

**Registering.** The file's view declares

```swift
static let registration = BarPanelRegistration("battery", pill: "pill.battery", width: width,
                                               model: BatteryModel.init) { BatteryPanel(model: $0) }
```

`name` is the link's (`grovekeys://panel/battery`), `pill` the bar's bracket the panel hangs from, `width` the same number its `BarPanel(width:)` is given, `anchor:` `.trailing` by default (`.leading` is the Grove menu's). A new panel also adds its registration to `BarPanels.all`.

**The model.** A `@MainActor final class …: ObservableObject, BarPanelModel` with `init(_ data: BarPanelData)`:

- `.live`: made once, the first time the panel opens, and kept (so a speed test's last result survives a closing). `start()` runs at every opening, before the panel is drawn: read what it shows, start what keeps it current. `stop()` runs at every closing: every timer, process and observer ends there. Closed, a panel must cost nothing.
- `.sample`: fixed data for the render (below); `start()` is never called on it, and it must read nothing from the Mac.
- `key(_:) -> Bool` (optional): a key pressed while the panel has the keyboard, offered to the model before any control (`.left`, `.right`, `.up`, `.down`, `.home`, `.end`, `.pageUp`, `.pageDown`, `.enter`, `.space`, `.character("t")`). Return true when used. Escape never arrives there.
- `escape() -> Bool` (optional): Escape was pressed. False, the default, closes the panel; true when the model used it (a menu closing its submenu).
- State in views: the Command Line Tools have no `@State` macro; use the model's `@Published` properties, or `State(initialValue:)` with a comment.

**The view.** A `BarPanel(width:)` from `GroveUI` holding sections separated by `PanelRule()`. The parts (all in `GroveUI`, `PanelKit.swift` and `PanelCharts.swift`): `PanelHeader(icon, accent:, title:) { trailing }`, `PanelValue`, `PanelCaption`, `PanelDetail(label, value)`, `PanelStatus(text, accent:)` (a dot and a word: how a panel says "warning"), `PanelRows { PanelRow(action:) { … } }` (rows with the hover fill), `PanelFooter(title, note:, action:)`, `PanelPairs` (name and value lines), `PanelButton`, `PanelSwitch(label, isOn:)`, `PanelSlider(label, value:)`, `Sparkline` (one or two series, values 0...1; `SparklineGeometry.normalized` for rates), `PanelMeter` and `PanelLegend` (`MeterPart`s), `CoreBars`. Icons are `GroveIcon.Name` cases; the ones the six panels need are there. Colours from `@Environment(\.theme)`, roles only; nothing orange inside.

**Height.** A panel is as tall as its content, and may change while open (a section opened, a row appearing): nothing to call. The host sees the new size and re-places the window with the top and the anchored edge where they were. No popover inside a panel (it takes the keyboard, which closes the panel); a `GroveSelect`'s menu is fine.

**The host's actions.** `@Environment(\.barPanel) private var panel`:

- `panel.close()`: puts the panel away; the app in front keeps the keyboard.
- `panel.open(url)`: opens a link in its app and puts the panel away, leaving the keyboard with what opened: a Settings pane, e.g. `x-apple.systempreferences:com.apple.Battery-Settings.extension`.
- `panel.openApp(bundleID:)`: the same for an app ("Activity Monitor…", `com.apple.ActivityMonitor`).
- `panel.leave { … }`: the general form, for anything else that brings a window forward.

**Seeing it without the live UI.**

```
swift build
"$(swift build --show-bin-path)/GroveKeys" --render-panel battery out.png                 # dark-medium
"$(swift build --show-bin-path)/GroveKeys" --render-panel battery out.png light-medium
"$(swift build --show-bin-path)/GroveKeys" --render-panel clock out.png ../../grove-dotfiles/theme/everforest-light-medium right
```

Draws the panel's `.sample` model at 2x on a bg0 ground and exits; no window is shown and the app is not started, so it is safe beside the installed Grove Keys (never run the binary without a one-shot flag). The scheme is a name (through the installed `grove-themes`) or a theme file's path; `left` or `right` draws that top corner as it follows a window border. Switches and sliders are drawn as stand-ins there (`\.panelStandIns`), since AppKit leaves their tint out off screen. To feed it data, make `.sample` build the model's published state from fixed values (the mock-ups' numbers are a good set); to see a second state (a running speed test), switch on an environment variable inside `.sample`.

**Side panels and menus.** A model that conforms to `BarPanelWithSides` gets a `link` from the host at each opening, before `start()` (`link.actions`: the same `close`/`leave`/`open` for a row run from the keyboard; `link.frame()`: the panel's outline on screen; `link.sidesChanged()`: call it when `sides` changes), and lists its side panels in `sides`: each a `BarPanelSide` (a view, its size, the row of the panel before it that it opens from, and where its own first row starts). The host shows each as a child window with its outline on its parent's.

A menu doesn't build that by hand: `GroveMenuListModel` (GroveUI's `GroveMenuList.swift`, shared with every Grove app since 2026-11-13) holds the levels (the menu and each open submenu), one highlighted row per level, the keys (`key(_:)`, `escape()`) and the pointer (followed by AppKit over the whole panel, since a side panel never has the keyboard); `GroveMenuListPanel(model:level:)` draws one level in a `BarPanel`. Give the model `GroveMenuListRow`s (title, icon, separator, enabled, checked; an action, a submenu's rows, a link drawn without a chevron, or a note), set `onChoose`, `onShow` (a level was shown) and `onLevels` (pass it to `link.sidesChanged`), turn `list.submenus` into `sides`, and pass the keys on. `GroveMenuPanel.swift` is the worked example. The pure parts are GroveThemesCore's `MenuListRules.swift`: `MenuListMove` (the keys' moves, type-to-jump), `MenuHoverIntent` (when a submenu opens and closes under the pointer), `MenuListLayout` (the rows' rectangles, from fixed row heights) and `MenuPlacement` (a submenu's frame); `MenuListRowKind.init(GroveMenuRow)` stays in `GroveKeysCore/MenuList.swift`.

**Pure logic** (parsing a tool's output, a grid, a rate) goes in `GroveKeysCore` with tests, as `MonthGrid` does; the model in the app target only reads the Mac and publishes.

## Out of scope (stage 1)

The content of the system, battery, Wi-Fi and sound panels (each is a placeholder in the frame, registered), the Grove menu as a panel (built in stage 2, see §6), the bar's Keep Awake mark.

## Testing

- GroveUI: the chart's point mapping, the meter's fractions, the icon list.
- GroveKeysCore: the menu list (the keys' moves, type-to-jump, the hover timing, the rows' rectangles, a submenu's frame); the links; the toggle's "own click" rule; the placement, as a table with the measured numbers; the lines from `borders` windows and the fallback, held to the config files; the month grid (Monday first, ISO weeks, neighbouring days, today, previous and next).
- bats: the click links, the open pill and hover, the end gaps, the workspace change's close; nothing left of the popups.
- By eye: `--render-panel` in dark-medium and light-medium against the approved mock-ups. The live panel (placement on screen, focus, closing) is checked by the owner after installing.

# Grove mod for Claude Code: design

Date: 2026-11-14. Status: draft, waiting for the owner's yes.

## Goal

Make Claude Code feel like part of Grove. The main feature is a live **Agents** pane
beside the chat that shows every agent Claude starts and what it is doing.
Its colors follow the scheme grove-themes has set.

## What it is

A Claude Code mod named `grove`: a plugin with one hooks module (TypeScript/TSX).
It is built and tested in the session's dev-mods folder. Once it has been
accepted, a grove-dotfiles module installs it (see "Later").

## Pieces

### 1. Agents pane

- A pane titled **Agents**, beside the chat. It needs a window at least 144
  columns wide to open on its own (Ghostty opens at 150).
- **When it shows:** it opens when the first agent starts in a session and stays
  open until you close it. `/grove-agents` opens or closes it. Sessions that
  never start an agent never see it.
- **One row per agent:**
  `● Explore   find theme state files       reading 3 files   0:42`
  The columns are a status dot, the agent type, its description, what it is
  doing right now (its latest tool call, made readable: "reading X",
  "running: git log", "searching 'foo'"), and the time it has run.
  - Status dot: running = green (pulses with the 1 s clock), idle = yellow,
    done = muted grey, failed or stopped = red.
  - Below the row, dim: how many tool calls it has made, and its result
    (first line) once it is done.
- **Workflows:** one group row with the workflow's name, and its agents indented
  under it as they show up.
- **Tasks section** (only when the task list has items): pending, in progress and
  done counts, plus the in-progress task's subject.
- Finished agents stay listed (dimmed) for this session; at most 30 rows, the
  oldest finished ones drop off first.

**Where the data comes from:** the `agent.spawn` hook (start, type, description),
`tool.call` hooks tagged with `agentId` (what it is doing now, call count), and
`$.agent.list()` once a second while any agent is running (status, end). Tasks
come from TaskCreate and TaskUpdate tool results. The state lives in `$.state`
atoms so a reload keeps the list.

### 2. Status line

`$.ui.status`: `🌲 2 agents running · 1 done`. It shows nothing when no agent
has run.

### 3. Colors that follow grove-themes

- The pane reads `~/.local/state/grove/theme` (for example `dark-medium`) and
  `grove-dotfiles/theme/everforest-<scheme>`. It checks every 3 s and redraws
  when the scheme changes. There is no restart and nothing to wire into
  grove-themes itself.
- Roles: green = running, yellow = idle, red = failed, aqua = agent type,
  grey1 = dim text. The pane paints no background of its own, since Ghostty
  already paints bg0.
- If either file is missing, it uses the Dark Medium hexes built into the mod.

## Not in scope (decided)

- **Recoloring Claude Code's own terminal UI.** A mod can't do it. Claude Code's
  `/theme` presets set those colors, and Ghostty already gives the terminal its
  Grove background and text colors.
- **Desktop/mobile app theme and moving background.** Supported by the engine,
  but only in those apps. Comes later, if the owner uses them.

## Later

- `93-claude-mod` grove-dotfiles module (98 is AeroSpace; 91–93 are free): links the mod into Claude Code's plugin
  folder so it is reproducible on a fresh Mac.
- Desktop look (`$.theme.set` from the same palettes) and a pine-forest
  backdrop scene.

## Testing

- `claude plugin validate` and `tsc -p` must both be clean.
- `claude plugin test` cases cover: a spawn adds a row; a tool call by that agent
  updates "now doing"; the end marks it done; the row cap; the scheme change
  swaps colors; fallback when the state file is missing.
- Then the owner's by-eye check: start a few Explore agents and watch the pane.

## Added after the first look (2026-11-14, owner's asks)

- **The grove-lab MOTD look** (`hooks/motd.ts`). The head is a small seasonal
  pixel grove, redrawn hourly from the MOTD's own seed rule, beside `model`,
  `agents`, `now`, `tasks` and `time` rows with 7-wide labels and 16-cell `━`
  bars. A `❝` line of the MOTD's wisdom closes the pane. The seasonal colors are
  the MOTD's (exempt from the palette test, as the fastfetch art is).
- **A box per agent.** The title edge carries the dot, the type and the task
  kind, with calls and time at the right. Rows: `task`, `model`, then `now`
  and a `calls` bar while it runs, or its `result` once done. Running boxes use
  the season's accent, done boxes the track grey, failed ones red. Finished
  boxes fold to one line when they'd overflow.
- **Background = Ghostty's.** The pane opens with `backgroundColor` = the
  scheme's `bg0`, and a scheme switch reopens it with the new one.
- **Models.** The main loop's (`$.session.model()`, refreshed every 3 s and on
  `PostModelSwitch`) and each agent's (the spawn's resolved model), shown as
  `Opus 5.5 (1M)`, `Haiku 5.5`.
- **Task kind** per agent: research, coding, testing, review, planning, ops or
  writing. It's guessed from the agent type and its description/prompt at
  spawn, then refined by its calls (an edit turns research into coding; a test
  run or an edit to a test file turns it into testing).
- **Usage**, the status line's figures (`$.session.usage()` at start, then
  every `session.measure`): one row per rate-limit window (`session` =
  five_hour, `week` = seven_day, `fable` for a Fable window when the account
  reports one) with % and reset time, amber from 75 %, red from 90 %. Then the
  context fill and the session's cost. When no Fable window is reported, the
  row says so rather than guessing.

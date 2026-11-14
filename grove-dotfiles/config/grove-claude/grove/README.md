# grove (Claude Code mod)

A Claude Code mod (a plugin of function hooks) that makes Claude Code part of Project Grove.

- **Agents pane.** It opens beside the chat when Claude starts its first agent. The head is drawn like grove-lab's message of the day: a small pixel grove in the season's colours (redrawn every hour) beside `agents`, `now`, `tasks` and `time` rows with `━` bars. Each agent gets its own box with its task, what it is doing right now, its tool calls and its time. A finished box turns grey with the first line of its result. A workflow's agents sit under its name. The pane needs 144 columns to open by itself; `/grove-agents` opens or closes it at any width.
- **Status line.** `🌲 2 agents running · 1 done`.
- **Colours that follow Grove Themes.** Every 3 s the mod reads `~/.local/state/grove/theme` and `theme/everforest-<scheme>` in grove-dotfiles (three folders up from here). Text, labels, bars and the pane's background (`bg0`, Ghostty's background) switch with the scheme. Only the grove art keeps the MOTD's own seasonal colours. `GROVE_STATE` and `GROVE_DOTFILES` override the two places.
- **Desktop and mobile look.** In the Claude desktop and mobile apps (the terminal draws no look) the whole interface takes the current scheme and its partner of the other mode at the same contrast (dark-medium ↔ light-medium), built with the plugin kit's `makeColors` (`hooks/make-colors.js`, copied as it is; copy it again when Claude Code updates). Behind it is an animated pine forest (`hooks/forest.ts`): stands of pines at the edges, drifting mist and the season's particles (petals, fireflies, leaves, snow) in the MOTD's colours. It's CSS only, follows light/dark by itself, and keeps the middle clear on any screen shape. A scheme switch sets it all again.

Installed by grove-dotfiles' `93-claude-mod` module: this folder's parent is a local marketplace named `grove`, and Claude Code reads the plugin straight from here, so an edit plus `/reload-plugins` takes effect.

Develop with `claude plugin validate .` and `claude plugin test .` (the tests are `hooks/grove.test.tsx`; the `preview` test prints the pane in ANSI).

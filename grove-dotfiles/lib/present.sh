# shellcheck shell=bash
# grove present and grove about. Meant to be sourced; sets no shell options.
#
# grove present opens the Grove window: a Ghostty window of its own process,
# titled "Grove · <title>" (AeroSpace floats those), that runs
# `grove __present <title> <command...>` (grove_present_run below) and quits
# when it closes. Without Ghostty the same runner starts in Terminal.app.

# The Grove window's size in cells.
GROVE_PRESENT_COLS=128
GROVE_PRESENT_ROWS=32

# _grove_shq STRING: STRING as one single-quoted /bin/sh word.
_grove_shq() {
  local q="'" r="'\\''"
  printf "'%s'" "${1//$q/$r}"
}

_grove_ghostty_app() {
  local a
  for a in "${GROVE_GHOSTTY_APP:-/Applications/Ghostty.app}" "$HOME/Applications/Ghostty.app"; do
    if [ -d "$a" ]; then printf '%s' "$a"; return 0; fi
  done
  return 1
}

# _grove_present_position: print "X Y", the top-left corner that centres the
# Grove window on the screen in front, or fail. A floating window stays where
# Ghostty puts it, and Ghostty would reuse the last normal window's corner.
# Ghostty sizes windows in cells, so the size in points is an estimate for the
# Ghostty config Grove ships (JetBrains Mono 12: a cell is 7.38 x 17.32 pt;
# padding 24 and 20 a side; a 28 pt title bar).
_grove_present_position() {
  local scr sw sh w h x y
  scr="$(osascript -l JavaScript -e 'ObjC.import("AppKit"); var f = $.NSScreen.mainScreen.visibleFrame; Math.round(f.size.width) + " " + Math.round(f.size.height)' 2>/dev/null)" || return 1
  case "$scr" in
    ""|*[!0-9\ ]*) return 1 ;;
    [0-9]*\ [0-9]*) ;;
    *) return 1 ;;
  esac
  sw="${scr%% *}"; sh="${scr##* }"
  w=$(( GROVE_PRESENT_COLS * 738 / 100 + 48 ))
  h=$(( GROVE_PRESENT_ROWS * 1732 / 100 + 68 ))
  x=$(( (sw - w) / 2 )); y=$(( (sh - h) / 2 ))
  [ "$x" -ge 0 ] || x=0
  [ "$y" -ge 0 ] || y=0
  printf '%s %s' "$x" "$y"
}

# _grove_present_global_keys: the triggers of the global keybinds in the user's
# Ghostty config, one per line. The Grove window is a second Ghostty process
# reading the same config; left alone it would also answer them (Grove's
# Ctrl+` quick terminal), so grove_present unbinds them for that process.
_grove_present_global_keys() {
  local f="${XDG_CONFIG_HOME:-$HOME/.config}/ghostty/config"
  [ -r "$f" ] || return 0
  sed -n 's/^[[:space:]]*keybind[[:space:]]*=[[:space:]]*\(global:[^=]*\)=.*/\1/p' "$f"
}

# grove_present [--title T] COMMAND...: open the Grove window on COMMAND and
# return at once.
grove_present() {
  local title="" a app cmd pos tmp k
  local -a args
  while [ $# -gt 0 ]; do
    case "$1" in
      --title)
        [ $# -ge 2 ] || { echo "grove present: --title needs a value" >&2; return 2; }
        title="$2"; shift 2 ;;
      --title=*) title="${1#--title=}"; shift ;;
      --) shift; break ;;
      -*) echo "grove present: unknown option: $1" >&2; return 2 ;;
      *) break ;;
    esac
  done
  if [ $# -eq 0 ]; then
    echo "usage: grove present [--title T] <command...>" >&2
    return 2
  fi
  if [ -z "$title" ]; then
    title="${1%%[[:space:]]*}"
    title="${title##*/}"
  fi

  cmd="$(_grove_shq "$GROVE_ROOT/bin/grove") __present $(_grove_shq "$title")"
  for a in "$@"; do cmd="$cmd $(_grove_shq "$a")"; done

  if app="$(_grove_ghostty_app)"; then
    # --initial-command and not -e: with -e Ghostty 1.4 opens a second, empty
    # window that keeps the process alive. `shell:` has /bin/sh split the words.
    args=(
      "--title=Grove · $title"
      "--initial-command=shell:$cmd"
      "--window-width=$GROVE_PRESENT_COLS"
      "--window-height=$GROVE_PRESENT_ROWS"
      "--quit-after-last-window-closed=true"
    )
    if pos="$(_grove_present_position)"; then
      args+=("--window-position-x=${pos%% *}" "--window-position-y=${pos##* }")
    fi
    while IFS= read -r k; do
      [ -z "$k" ] || args+=("--keybind=$k=unbind")
    done <<EOF_KEYS
$(_grove_present_global_keys)
EOF_KEYS
    open -na "$app" --args "${args[@]}"
  else
    # Terminal.app: a .command file that removes itself and starts the runner.
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/grove-present.XXXXXX")" || return 1
    printf '#!/bin/bash\nrm -rf %s\nexec %s\n' "$(_grove_shq "$tmp")" "$cmd" > "$tmp/grove.command"
    chmod +x "$tmp/grove.command"
    open -a Terminal "$tmp/grove.command"
  fi
}

# _grove_present_say SGR TEXT: a line in the terminal's own palette colour
# (the scheme's green and red in a Grove terminal, readable on light schemes).
_grove_present_say() {
  if _grove_color_on 1; then
    printf '\033[%sm%s\033[0m\n' "$1" "$2"
  else
    printf '%s\n' "$2"
  fi
}

# grove_present_run TITLE COMMAND...: what runs inside the Grove window. A
# header, the command with the login environment (zsh -l: Homebrew and
# ~/.local/bin on PATH), Done or Failed (N), then any key closes the window.
# One COMMAND argument is a shell command line; several are run as they are.
# Returns the command's exit code.
grove_present_run() {
  local title="$1" rc
  shift
  # Terminal.app has no --title; Ghostty's --title wins over this.
  [ ! -t 1 ] || printf '\033]0;Grove · %s\007' "$title"
  _grove_present_say '1;32' "Grove · $title"
  printf '\n'
  # Ctrl+C stops the command, not this runner (a trap, unlike ignoring, is not
  # inherited by the command).
  trap : INT
  if [ $# -eq 1 ]; then
    /bin/zsh -lc "$1"
  else
    /bin/zsh -lc '"$@"' grove "$@"
  fi
  rc=$?
  trap - INT
  printf '\n'
  if [ "$rc" -eq 0 ]; then
    _grove_present_say '32' "Done"
  else
    _grove_present_say '31' "Failed ($rc)"
  fi
  _grove_present_say '90' "Press any key to close"
  # shellcheck disable=SC2162
  read -s -n 1 || true
  return "$rc"
}

# _grove_about_fetch: the fetch as new terminals show it
# (config/zsh/conf.d/95-fetch.zsh.tmpl): the config's image in a wide Ghostty
# window, the text art when narrower or elsewhere, no logo when narrow or not
# on a terminal. Nothing without fastfetch or the rendered config.
_grove_about_fetch() {
  local dir="${XDG_CONFIG_HOME:-$HOME/.config}/fastfetch" cols=0 img width
  command -v fastfetch >/dev/null 2>&1 || return 0
  [ -r "$dir/config.jsonc" ] || return 0
  # The terminal's width, asked of the terminal on stdout (inside $(...) fd 1
  # is a pipe, hence fd 3).
  if [ -t 1 ]; then
    { cols="$(stty size 2>/dev/null <&3)"; } 3>&1
    cols="${cols##* }"
  fi
  case "$cols" in ""|*[!0-9]*) cols=0 ;; esac
  # The logo image and its width in cells; the stats box beside it takes 62.
  img="$(sed -n 's|.*"source": *"~/\.config/fastfetch/\([^"]*\)".*|\1|p' "$dir/config.jsonc" | head -1)"
  width="$(sed -n 's/.*"width": *\([0-9][0-9]*\).*/\1/p' "$dir/config.jsonc" | head -1)"
  printf '\n'
  if [ "${TERM_PROGRAM:-}" = ghostty ] && [ -n "$img" ] && [ -r "$dir/$img" ] \
     && [ -n "$width" ] && [ "$cols" -ge $(( width + 62 )) ]; then
    fastfetch || true
  elif [ "$cols" -ge 125 ] && [ -r "$dir/grove.ascii" ]; then
    fastfetch --logo-type file --logo "$dir/grove.ascii" --logo-color-1 cyan || true
  else
    fastfetch --logo none || true
  fi
}

# _grove_about_row LABEL VALUE
_grove_about_row() {
  if _grove_color_on 1; then
    printf '\033[32m%-9s\033[0m%s\n' "$1" "$2"
  else
    printf '%-9s%s\n' "$1" "$2"
  fi
}

# grove_about VERSION: the fetch, then the version, the current scheme (when
# grove-themes is there) and when grove install or update last finished
# ($GROVE_STATE/updated, written by bin/grove).
grove_about() {
  local scheme updated="never"
  _grove_about_fetch
  printf '\n'
  _grove_about_row Grove "$1"
  if command -v grove-themes >/dev/null 2>&1 && scheme="$(grove-themes current 2>/dev/null)" && [ -n "$scheme" ]; then
    _grove_about_row Scheme "$scheme"
  fi
  if [ -r "$GROVE_STATE/updated" ]; then
    IFS= read -r updated < "$GROVE_STATE/updated" || true
    [ -n "$updated" ] || updated="never"
  fi
  _grove_about_row Updated "$updated"
}

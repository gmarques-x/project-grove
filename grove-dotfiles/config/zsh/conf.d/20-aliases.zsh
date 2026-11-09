# Aliases. Edit with `zalias`; open a new shell (or `exec zsh`) to load changes.
# $EDITOR is read when an alias runs, so setting it later takes effect.

alias zalias='${EDITOR:-vim} "$ZDOTDIR/conf.d/20-aliases.zsh"'   # edit this file
alias zedit='${EDITOR:-vim} "$ZDOTDIR"'                          # edit the zsh config folder
alias cls='clear && GROVE_FETCHED= exec zsh -l'                  # clear and reload, like a new window

# Listings: folders first, then files, each A→Z ignoring case. Icons only where
# the terminal can draw them (not Terminal.app). The originals stay as \ls, \cat.
if (( $+commands[eza] )); then
  _grove_icons=(--icons=auto)
  [[ "$TERM_PROGRAM" == Apple_Terminal ]] && _grove_icons=()
  alias ls="eza -l --group-directories-first --sort=name --git ${_grove_icons[*]}"   # long listing
  alias ll="eza -la --group-directories-first --sort=name --git ${_grove_icons[*]}"  # ls plus hidden files
  alias lt="eza --tree --level=2 --group-directories-first ${_grove_icons[*]}"       # two-level tree
  unset _grove_icons
fi
if (( $+commands[bat] )); then
  alias cat='bat --paging=never'
fi

# y (or finder): yazi, and when you quit, the shell moves to the folder you were in.
# Plain `yazi` still leaves the shell where it was.
if (( $+commands[yazi] )); then
  y() {
    local tmp cwd
    tmp="$(mktemp -t yazi-cwd.XXXXXX)" || return
    command yazi "$@" --cwd-file="$tmp"
    cwd="$(<"$tmp")"
    [[ -n "$cwd" && "$cwd" != "$PWD" && -d "$cwd" ]] && builtin cd -- "$cwd"
    command rm -f -- "$tmp"
  }
  alias finder='y'                                                # the same, by a friendlier name
fi

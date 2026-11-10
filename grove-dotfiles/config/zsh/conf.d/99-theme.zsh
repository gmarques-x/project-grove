# Open shells follow `grove-themes set`: at each prompt, compare the state file's
# scheme with the one this shell loaded, and re-source the colour files when it
# changed. Builtins only (no subshell per prompt); prints nothing.
_grove_theme_read() {
  local s=""
  [[ -r "${GROVE_STATE:-$HOME/.local/state/grove}/theme" ]] \
    && read -r s < "${GROVE_STATE:-$HOME/.local/state/grove}/theme" 2>/dev/null
  [[ "$s" == (dark|light)-(hard|medium|soft) ]] || s=dark-medium
  _grove_theme_now=$s
}

_grove_theme_precmd() {
  _grove_theme_read
  [[ "$_grove_theme_now" == "$_grove_theme_loaded" ]] && return 0
  _grove_theme_loaded=$_grove_theme_now
  local f
  for f in 40-tools 85-autosuggest 98-highlight; do
    [[ -r "$ZDOTDIR/conf.d/$f.zsh" ]] && source "$ZDOTDIR/conf.d/$f.zsh" >/dev/null 2>&1
  done
  return 0
}

_grove_theme_read
_grove_theme_loaded=$_grove_theme_now
autoload -Uz add-zsh-hook
add-zsh-hook precmd _grove_theme_precmd

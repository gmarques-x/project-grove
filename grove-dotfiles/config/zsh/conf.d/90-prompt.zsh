# Terminal.app can't draw Nerd Font glyphs, so it gets the icon-free prompt.
if [[ "$TERM_PROGRAM" == Apple_Terminal ]]; then
  export STARSHIP_CONFIG="$XDG_CONFIG_HOME/starship-plain.toml"
fi
if (( $+commands[starship] )); then
  eval "$(starship init zsh)"
fi

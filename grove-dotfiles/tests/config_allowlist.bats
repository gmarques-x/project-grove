load helpers

setup() { grove_test_setup; }

@test "untracked app files in config are ignored" {
  git -C "$GROVE_ROOT" check-ignore -q config/gh/hosts.yml
}

@test "tracked config entries are not ignored" {
  local p
  for p in config/zsh/.zshrc config/git/config config/ssh/config config/starship.toml.tmpl config/starship-plain.toml.tmpl config/vscode/settings.json.tmpl; do
    run git -C "$GROVE_ROOT" check-ignore -q "$p"
    [ "$status" -ne 0 ]
  done
}

@test "generated personal files are ignored" {
  local p
  for p in config/git/local config/git/allowed_signers config/grove/local.env; do
    git -C "$GROVE_ROOT" check-ignore -q "$p"
  done
}

@test "only ssh/config is tracked under ssh" {
  git -C "$GROVE_ROOT" check-ignore -q config/ssh/id_ed25519
  git -C "$GROVE_ROOT" check-ignore -q config/ssh/known_hosts
  run git -C "$GROVE_ROOT" check-ignore -q config/ssh/config
  [ "$status" -ne 0 ]
}

@test "terminal session and history files in zsh are ignored" {
  local p
  for p in config/zsh/.zsh_sessions config/zsh/.zsh_history config/zsh/.zcompdump config/zsh/.zcompdump-host-5.9; do
    git -C "$GROVE_ROOT" check-ignore -q "$p"
  done
}

@test "the sessions link in zsh is ignored even though it isn't a folder" {
  local d
  d="$(mktemp -d "$BATS_TEST_TMPDIR/repo.XXXX")"
  git -C "$d" init -q
  mkdir -p "$d/config/zsh"
  cp "$GROVE_ROOT/config/.gitignore" "$d/config/.gitignore"
  ln -s /nowhere "$d/config/zsh/.zsh_sessions"
  git -C "$d" check-ignore -q config/zsh/.zsh_sessions
}

@test "ghostty and fastfetch configs are tracked" {
  local p
  for p in config/ghostty/config.tmpl config/fastfetch/config.jsonc.tmpl config/fastfetch/grove.png config/fastfetch/grove.ascii; do
    run git -C "$GROVE_ROOT" check-ignore -q "$p"
    [ "$status" -ne 0 ] || { echo "ignored: $p"; false; }
  done
}

@test "macchina's config is gone" {
  [ ! -e "$GROVE_ROOT/config/macchina" ]
  [ -z "$(git -C "$GROVE_ROOT" ls-files config/macchina)" ]
}

@test "eza and bat configs are tracked" {
  local p
  for p in config/eza/theme.yml.tmpl config/bat/config; do
    run git -C "$GROVE_ROOT" check-ignore -q "$p"
    [ "$status" -ne 0 ] || { echo "ignored: $p"; false; }
  done
}

@test "yazi configs are tracked" {
  local p
  for p in config/yazi/yazi.toml config/yazi/theme.toml.tmpl config/yazi/init.lua.tmpl; do
    run git -C "$GROVE_ROOT" check-ignore -q "$p"
    [ "$status" -ne 0 ] || { echo "ignored: $p"; false; }
  done
}

@test "generated files are ignored, templates are tracked" {
  local f
  for f in ghostty/config starship.toml starship-plain.toml fastfetch/config.jsonc \
           eza/theme.yml yazi/theme.toml yazi/init.lua vscode/settings.json \
           zsh/conf.d/40-tools.zsh zsh/conf.d/85-autosuggest.zsh \
           zsh/conf.d/95-fetch.zsh zsh/conf.d/98-highlight.zsh; do
    git -C "$GROVE_ROOT" check-ignore -q "config/$f" || { echo "not ignored: $f"; false; }
    [ -z "$(git -C "$GROVE_ROOT" ls-files "config/$f")" ] || { echo "still tracked: $f"; false; }
    run git -C "$GROVE_ROOT" check-ignore -q "config/$f.tmpl"
    [ "$status" -ne 0 ] || { echo "ignored: $f.tmpl"; false; }
    [ -n "$(git -C "$GROVE_ROOT" ls-files "config/$f.tmpl")" ] || { echo "not tracked: $f.tmpl"; false; }
  done
}

@test "the theme hook is tracked" {
  run git -C "$GROVE_ROOT" check-ignore -q config/zsh/conf.d/99-theme.zsh
  [ "$status" -ne 0 ] || false
  [ -n "$(git -C "$GROVE_ROOT" ls-files config/zsh/conf.d/99-theme.zsh)" ] || false
}

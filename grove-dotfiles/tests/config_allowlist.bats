load helpers

setup() { grove_test_setup; }

@test "untracked app files in config are ignored" {
  git -C "$GROVE_ROOT" check-ignore -q config/gh/hosts.yml
}

@test "tracked config entries are not ignored" {
  local p
  for p in config/zsh/.zshrc config/git/config config/ssh/config config/starship.toml; do
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

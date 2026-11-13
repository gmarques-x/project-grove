# shellcheck disable=SC2016,SC2030,SC2031,SC1090,SC1091,SC2154
load helpers

load_module() {
  local f
  for f in "$GROVE_ROOT"/lib/*.sh; do
    # shellcheck source=/dev/null
    . "$f"
  done
  MODULE_DIR="$GROVE_ROOT/modules/$1"
  # shellcheck source=/dev/null
  . "$MODULE_DIR/module.sh"
}

setup() {
  grove_test_setup
  grove_copy_tracked_config "$BATS_TEST_TMPDIR/config"
  export GROVE_CONFIG="$BATS_TEST_TMPDIR/config"
  export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
  : > "$GIT_CONFIG_GLOBAL"
  unset XDG_CONFIG_HOME
  export GROVE_NAME=gmarques-x GROVE_EMAIL=gm@example.com GROVE_GITHUB_USER=gmx
  # Never touch the real agent.
  stub ssh-add 'if [ "$1" = "-l" ]; then cat "$BATS_TEST_TMPDIR/agent" 2>/dev/null || exit 1; else echo "$@" >> "$BATS_TEST_TMPDIR/ssh-add.log"; fi'
}

make_key() {
  mkdir -p "$HOME/.ssh" && chmod 700 "$HOME/.ssh"
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -C "$GROVE_EMAIL" -f "$HOME/.ssh/id_ed25519"
}

load_agent() {
  /usr/bin/ssh-keygen -lf "$HOME/.ssh/id_ed25519.pub" > "$BATS_TEST_TMPDIR/agent"
}

# ---- 40-ssh

@test "ssh config file is tracked with mode 644" {
  [ "$(stat -f %Lp "$GROVE_ROOT/config/ssh/config")" = "644" ]
  grep -q '^    IdentityFile ~/.ssh/id_ed25519$' "$GROVE_ROOT/config/ssh/config"
}

@test "ssh needs you without a key" {
  load_module 40-ssh
  run check
  [ "$status" -eq 4 ]
}

@test "ssh needs work when the config isn't linked" {
  load_module 40-ssh
  make_key; load_agent
  run check
  [ "$status" -eq 3 ]
}

@test "ssh is ok after a restart: not in the agent, but apply stored it in the Keychain" {
  load_module 40-ssh
  make_key
  run apply
  [ "$status" -eq 0 ]
  rm -f "$BATS_TEST_TMPDIR/agent"
  run check
  [ "$status" -eq 0 ]
  # A different key needs its own ssh-add.
  rm "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"; make_key
  run check
  [ "$status" -eq 3 ]
}

@test "ssh needs work when the key isn't in the agent and was never stored" {
  load_module 40-ssh
  make_key
  mkdir -p "$HOME/.ssh"; ln -s "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config"
  run check
  [ "$status" -eq 3 ]
}

@test "ssh is ok when linked and loaded" {
  load_module 40-ssh
  make_key; load_agent
  ln -s "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config"
  run check
  [ "$status" -eq 0 ]
}

@test "ssh apply creates ~/.ssh as 700, links, loads the key, leaves the key alone" {
  load_module 40-ssh
  # key made first in a 755 folder: apply must not chmod it
  mkdir "$HOME/.ssh"; chmod 755 "$HOME/.ssh"
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -f "$HOME/.ssh/id_ed25519"
  before="$(cksum < "$HOME/.ssh/id_ed25519")"
  run apply
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$HOME/.ssh")" = "755" ]
  [ "$(cksum < "$HOME/.ssh/id_ed25519")" = "$before" ]
  [ "$(stat -f %Lp "$HOME/.ssh/id_ed25519")" = "600" ]
  [ "$(readlink "$HOME/.ssh/config")" = "$GROVE_CONFIG/ssh/config" ]
  grep -q -- "--apple-use-keychain $HOME/.ssh/id_ed25519" "$BATS_TEST_TMPDIR/ssh-add.log"
}

@test "ssh apply makes a fresh ~/.ssh with mode 700 and generates a missing key" {
  load_module 40-ssh
  stub ssh-keygen '/usr/bin/ssh-keygen "$@" -q -N ""'
  run apply
  [ "$status" -eq 0 ]
  [ "$(stat -f %Lp "$HOME/.ssh")" = "700" ]
  [ -f "$HOME/.ssh/id_ed25519.pub" ]
}

# ---- 40-ssh: where ~/.ssh lives

onedrive() { mkdir -p "$HOME/Library/CloudStorage/$1"; echo "$HOME/Library/CloudStorage/$1"; }

@test "ssh asks nothing when there is no OneDrive" {
  load_module 40-ssh
  make_key; load_agent
  ln -s "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config"
  run check
  [ "$status" -eq 0 ]
}

@test "ssh needs you when a OneDrive is there and nobody chose where ~/.ssh lives" {
  load_module 40-ssh
  make_key; load_agent
  ln -s "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config"
  onedrive OneDrive-Personal >/dev/null
  run check
  [ "$status" -eq 4 ]
}

@test "ssh apply moves ~/.ssh into the chosen OneDrive as dot-ssh and links it" {
  load_module 40-ssh
  make_key
  echo hosts > "$HOME/.ssh/known_hosts"
  before="$(cksum < "$HOME/.ssh/id_ed25519")"
  od="$(onedrive OneDrive-Personal)"
  printf '1\n' > "$GROVE_TTY"
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.ssh")" = "$od/dot-ssh" ]
  [ "$(stat -f %Lp "$od/dot-ssh")" = "700" ]
  [ "$(cksum < "$od/dot-ssh/id_ed25519")" = "$before" ]
  [ "$(stat -f %Lp "$od/dot-ssh/id_ed25519")" = "600" ]
  [ "$(cat "$od/dot-ssh/known_hosts")" = "hosts" ]
  [ "$(readlink "$od/dot-ssh/config")" = "$GROVE_CONFIG/ssh/config" ]
  [ -f "$GROVE_STATE/backup/test/.ssh/id_ed25519" ]
  load_agent
  run check
  [ "$status" -eq 0 ]
}

@test "ssh apply on another Mac picks that Mac's OneDrive by number, keeping dot-ssh's own files" {
  load_module 40-ssh
  onedrive OneDrive-Personal >/dev/null
  od="$(onedrive "OneDrive-Contoso Ltd")"
  mkdir -m 700 "$od/dot-ssh"
  /usr/bin/ssh-keygen -q -t ed25519 -N '' -f "$od/dot-ssh/id_ed25519"
  cloud="$(cksum < "$od/dot-ssh/id_ed25519")"
  mkdir -m 700 "$HOME/.ssh"; echo local-only > "$HOME/.ssh/extra"; echo other > "$HOME/.ssh/id_ed25519"
  printf '1\n' > "$GROVE_TTY"   # sorted: "OneDrive-Contoso Ltd" comes first
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.ssh")" = "$od/dot-ssh" ]
  [ "$(cksum < "$od/dot-ssh/id_ed25519")" = "$cloud" ]
  [ "$(cat "$od/dot-ssh/extra")" = "local-only" ]
}

@test "ssh apply takes a typed folder path" {
  load_module 40-ssh
  onedrive OneDrive-Personal >/dev/null
  mkdir -p "$BATS_TEST_TMPDIR/elsewhere"
  printf '%s\n' "$BATS_TEST_TMPDIR/elsewhere/" > "$GROVE_TTY"
  stub ssh-keygen '/usr/bin/ssh-keygen "$@" -q -N ""'
  run apply
  [ "$status" -eq 0 ]
  [ "$(readlink "$HOME/.ssh")" = "$BATS_TEST_TMPDIR/elsewhere/dot-ssh" ]
}

@test "ssh apply keeps ~/.ssh on this Mac when 0 is chosen, and doesn't ask again" {
  load_module 40-ssh
  make_key
  onedrive OneDrive-Personal >/dev/null
  printf '0\n' > "$GROVE_TTY"
  run apply
  [ "$status" -eq 0 ]
  [ ! -L "$HOME/.ssh" ]
  [ "$(cat "$GROVE_STATE/ssh-place")" = "local" ]
  load_agent
  run check
  [ "$status" -eq 0 ]
}

@test "ssh apply refuses a choice that isn't on the list and changes nothing" {
  load_module 40-ssh
  make_key
  onedrive OneDrive-Personal >/dev/null
  printf '7\n' > "$GROVE_TTY"
  run apply
  [ "$status" -eq 1 ]
  [ ! -L "$HOME/.ssh" ]
  [ ! -e "$HOME/Library/CloudStorage/OneDrive-Personal/dot-ssh" ]
}

@test "ssh apply under --yes asks nothing and moves nothing" {
  load_module 40-ssh
  make_key
  onedrive OneDrive-Personal >/dev/null
  export GROVE_YES=1
  run apply
  [ "$status" -eq 1 ]
  [ ! -L "$HOME/.ssh" ]
}

@test "ssh is settled when ~/.ssh already links to a dot-ssh folder" {
  load_module 40-ssh
  od="$(onedrive OneDrive-Personal)"
  mkdir -m 700 "$od/dot-ssh"
  ln -s "$od/dot-ssh" "$HOME/.ssh"
  make_key; load_agent
  ln -s "$GROVE_CONFIG/ssh/config" "$HOME/.ssh/config"
  run check
  [ "$status" -eq 0 ]
}

# ---- 50-git

@test "git config parses" {
  run git config --file "$GROVE_ROOT/config/git/config" --list
  [ "$status" -eq 0 ]
  [[ "$output" == *"gpg.format=ssh"* ]] || false
  [[ "$output" == *"commit.gpgsign=true"* ]] || false
}

@test "git writes identity and allowed_signers from local values" {
  load_module 50-git
  make_key
  run apply
  [ "$status" -eq 0 ]
  pub="$(cut -d' ' -f1,2 "$HOME/.ssh/id_ed25519.pub")"
  grep -q 'gmarques-x' "$GROVE_CONFIG/git/local"
  grep -q 'gm@example.com' "$GROVE_CONFIG/git/local"
  grep -qF "signingkey = $HOME/.ssh/id_ed25519.pub" "$GROVE_CONFIG/git/local"
  [ "$(cat "$GROVE_CONFIG/git/allowed_signers")" = "gm@example.com $pub" ]
  run git config --file "$GROVE_CONFIG/git/local" user.name
  [ "$output" = "gmarques-x" ]
  run check
  [ "$status" -eq 0 ]
}

@test "git second apply changes nothing" {
  load_module 50-git
  make_key
  apply
  touch -t 200001010000 "$GROVE_CONFIG/git/local" "$GROVE_CONFIG/git/allowed_signers"
  apply
  [ "$(stat -f %Sm -t %Y "$GROVE_CONFIG/git/local")" = "2000" ]
  [ "$(stat -f %Sm -t %Y "$GROVE_CONFIG/git/allowed_signers")" = "2000" ]
}

@test "git retires a real ~/.gitconfig into the backup" {
  load_module 50-git
  make_key
  echo "[user]
    name = old" > "$HOME/.gitconfig"
  run check
  [ "$status" -eq 3 ]
  run apply
  [ "$status" -eq 0 ]
  [ ! -e "$HOME/.gitconfig" ]
  grep -q old "$GROVE_STATE/backup/test/.gitconfig"
  run check
  [ "$status" -eq 0 ]
}

@test "git check notices a changed email" {
  load_module 50-git
  make_key
  apply
  GROVE_EMAIL=other@example.com
  run check
  [ "$status" -eq 3 ]
}

@test "git check notices a changed key" {
  load_module 50-git
  make_key
  apply
  rm "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_ed25519.pub"
  make_key
  run check
  [ "$status" -eq 3 ]
}

@test "git needs you without a public key" {
  load_module 50-git
  run check
  [ "$status" -eq 4 ]
}

@test "git needs you when name or email is empty" {
  load_module 50-git
  make_key
  GROVE_NAME=""
  run check
  [ "$status" -eq 4 ]
  GROVE_NAME=x; GROVE_EMAIL=""
  run check
  [ "$status" -eq 4 ]
}

@test "git apply refuses an empty name or email and writes nothing" {
  load_module 50-git
  make_key
  GROVE_EMAIL=""
  run apply
  [ "$status" -eq 1 ]
  [[ "$output" == *"set your name and email"* ]] || false
  [ ! -e "$GROVE_CONFIG/git/local" ]
  [ ! -e "$GROVE_CONFIG/git/allowed_signers" ]
}

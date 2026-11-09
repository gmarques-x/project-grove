#!/bin/bash
# Project Grove bootstrap: the one-line start for a fresh Mac.
#   curl -fsSL https://raw.githubusercontent.com/gmarques-x/project-grove/main/grove-dotfiles/bootstrap.sh | bash
# Runs before anything is installed, so it uses only built-in macOS tools and
# cannot source lib/. The body sits in a function that is called on the last
# line: a download cut short never reaches that call, so half a script can't run.
set -euo pipefail

grove_bootstrap() {
  local poll="${GROVE_POLL_SECONDS:-5}"
  local clone_dir="${GROVE_CLONE_DIR:-$HOME/Developer/project-grove}"
  local repo_url="${GROVE_REPO_URL:-https://github.com/gmarques-x/project-grove.git}"
  local waited=0

  # 1. Command Line Tools (provides git).
  if ! xcode-select -p >/dev/null 2>&1; then
    echo "Waiting for the Command Line Tools installer... finish Apple's dialog, or press Ctrl-C to stop"
    # Fails when a request is already pending; waiting below covers both cases.
    xcode-select --install >/dev/null 2>&1 || true
    until xcode-select -p >/dev/null 2>&1; do
      sleep "$poll"
      waited=$((waited + poll))
      if [ "$waited" -ge 60 ]; then
        waited=0
        echo "Still waiting for the Command Line Tools installer... (Ctrl-C to stop)"
      fi
    done
    echo "Command Line Tools are installed."
  fi

  # 2. Clone the repo, unless it is already there. Never delete or overwrite.
  if [ -e "$clone_dir" ]; then
    local origin=""
    if [ -d "$clone_dir/.git" ]; then
      origin="$(git -C "$clone_dir" remote get-url origin 2>/dev/null || true)"
    fi
    case "$origin" in
      *project-grove*) ;;
      *)
        echo "Stopping: $clone_dir already exists but is not a clone of project-grove." >&2
        echo "Nothing was changed. Move it aside or set GROVE_CLONE_DIR to another folder, then run this again." >&2
        return 1
        ;;
    esac
    echo "Using the existing clone at $clone_dir"
  else
    mkdir -p "$(dirname "$clone_dir")"
    echo "Cloning project-grove into $clone_dir"
    git clone "$repo_url" "$clone_dir"
  fi

  # 3. Hand over to grove. When piped from curl, stdin is this script, so
  # prompts need the terminal.
  local grove="$clone_dir/grove-dotfiles/bin/grove"
  if [ -r /dev/tty ] && : </dev/tty 2>/dev/null; then
    exec "$grove" install </dev/tty
  fi
  exec "$grove" install
}

grove_bootstrap "$@"

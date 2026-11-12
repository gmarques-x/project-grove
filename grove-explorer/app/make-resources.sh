#!/bin/bash
# Copies the Grove Icons font and map (the ones the VS Code theme uses) into
# the app's resources. The folder is git-ignored: run this once after a
# checkout and whenever grove-icons changes. Module 94-explorer-app runs it
# before it builds.
set -euo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
icons="$here/../../grove-dotfiles/config/vscode/grove-icons"
resources="$here/Sources/GroveExplorer/Resources"

for file in seti.woff grove-icon-theme.json; do
    [[ -f "$icons/$file" ]] || { echo "make-resources: $icons/$file is missing" >&2; exit 1; }
done
mkdir -p "$resources"
cp "$icons/seti.woff" "$icons/grove-icon-theme.json" "$resources/"
echo "Grove Icons copied to $resources"

#!/usr/bin/env bash
# The fullscreen key on a game that runs its own fullscreen (tests/rice-keymap.lua): it must ask the game to leave
# it instead of forcing a compositor resize under a running swapchain. Needs lua; skipped when it is not there.
set -Euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
command -v lua >/dev/null || { echo "lua is not installed: skipped"; exit 0; }
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
HOME="$tmp" XDG_RUNTIME_DIR="$tmp" lua "$root/tests/rice-keymap.lua" "$root/lua/rice-keymap.lua"

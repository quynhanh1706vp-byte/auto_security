#!/usr/bin/env bash
# safe_heredoc_write.sh — atomic write helper (anti paste-dính)
# Usage:
#   source ./bin/safe_heredoc_write.sh
#   safe_write /path/to/file <<'EOF'
#   content...
#   EOF
set -euo pipefail

safe_write(){
  local out="${1:?missing output path}"
  local dir tmp
  dir="$(dirname "$out")"
  mkdir -p "$dir"
  tmp="$(mktemp "$dir/.tmp.$(basename "$out").XXXXXX")"
  cat >"$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$out"
}

# Optional: write + chmod +x (useful for scripts)
safe_write_exec(){
  local out="${1:?missing output path}"
  safe_write "$out"
  chmod +x "$out"
}

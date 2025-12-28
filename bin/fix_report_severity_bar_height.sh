#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE"
echo "[i] ROOT = $ROOT"

old='height: calc(12px + min(var(--sev-count, 0) * 0.02px, 180px));'
new='height: calc(6px + min(var(--sev-count, 0) * 1px, 190px));'

patch_one() {
  local f="$1"
  if ! grep -q "$old" "$f"; then
    echo "  [SKIP] $f (không thấy dòng height cũ, có thể đã patch trước đó)."
    return
  fi

  echo "  [PATCH] $f"
  python3 - "$f" <<PY
import sys, pathlib
path = pathlib.Path(sys.argv[1])
html = path.read_text(encoding="utf-8")
old = "$old"
new = "$new"
html = html.replace(old, new)
path.write_text(html, encoding="utf-8")
PY
}

export -f patch_one
export old new

find "$ROOT/out" -maxdepth 3 -type f -path "*/report/*.html" | while read -r f; do
  patch_one "$f"
done

echo "[DONE] Đã chỉnh lại chiều cao cột severity trong tất cả report HTML."

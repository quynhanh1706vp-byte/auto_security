#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_runs_fullscan_panel_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy file JS panel: $FILE" >&2
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP="${FILE}.bak_target_required_${TS}"
cp "$FILE" "$BACKUP"
echo "[BACKUP] Đã backup file gốc thành: $BACKUP"

FILE="$FILE" python - << 'PY'
import os, pathlib, re, sys

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

# Xoá mọi block if (...) { alert('Vui lòng nhập Target URL'); return; }
pattern = r"if\s*\([^)]*\)\s*{\s*alert\(['\"]Vui lòng nhập Target URL['\"]\);\s*return;\s*}"
regex = re.compile(pattern, re.MULTILINE | re.DOTALL)

new_txt, n = regex.subn("// [PATCH] removed 'Target URL' required check\n", txt)

if n == 0:
    print("[WARN] Không tìm thấy block alert('Vui lòng nhập Target URL') để xoá.", file=sys.stderr)
else:
    print(f"[OK] Đã xoá {n} block check 'Target URL' bắt buộc.")

path.write_text(new_txt, encoding="utf-8")
PY

echo "[DONE] vsp_runs_fullscan_panel_v1.js đã được patch remove Target URL required."

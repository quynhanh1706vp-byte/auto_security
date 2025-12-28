#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
FILE="$UI_ROOT/static/js/vsp_runs_fullscan_panel_v1.js"

if [ ! -f "$FILE" ]; then
  echo "[ERR] Không tìm thấy file JS panel: $FILE" >&2
  exit 1
fi

# Ưu tiên backup bản trước khi overwrite
BACKUP_SRC="$(ls -1 "${FILE}.bak_overwrite_"* 2>/dev/null | head -n1 || true)"

if [ -z "$BACKUP_SRC" ]; then
  # fallback: dùng backup extonly (lần patch regex trước)
  BACKUP_SRC="$(ls -1 "${FILE}.bak_extonly_"* 2>/dev/null | head -n1 || true)"
fi

if [ -z "$BACKUP_SRC" ]; then
  echo "[ERR] Không tìm thấy backup (.bak_overwrite_* hoặc .bak_extonly_*) để restore." >&2
  exit 1
fi

echo "[RESTORE] Dùng backup: $BACKUP_SRC"
cp "$BACKUP_SRC" "$FILE"

TS="$(date +%Y%m%d_%H%M%S)"
BACKUP2="${FILE}.bak_restore_v2_${TS}"
cp "$FILE" "$BACKUP2"
echo "[BACKUP2] Sao lưu bản sau restore vào: $BACKUP2"

FILE="$FILE" python - << 'PY'
import os, pathlib, re, sys

path = pathlib.Path(os.environ["FILE"])
txt = path.read_text(encoding="utf-8")

# Gỡ bỏ check 'bắt buộc Target URL'
pattern = r"if\s*\(\s*!getUrl\s*\)\s*{\s*alert\(['\"]Vui lòng nhập Target URL['\"]\);\s*return;\s*}"

regex = re.compile(pattern, re.MULTILINE)
new_txt, n = regex.subn("// [PATCH] removed strict Target URL check\n", txt, count=1)

if n == 0:
    print("[WARN] Không tìm thấy block if (!getUrl) ... để xoá. Nội dung file có thể đã đổi.", file=sys.stderr)
else:
    print(f"[OK] Đã xoá strict Target URL check (thay {n} block).")

path.write_text(new_txt, encoding="utf-8")
PY

echo "[DONE] vsp_runs_fullscan_panel_v1.js đã được restore + patch."

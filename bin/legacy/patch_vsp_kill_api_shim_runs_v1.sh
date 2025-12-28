#!/usr/bin/env bash
set -euo pipefail

BIN_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
UI_ROOT="$(cd "$BIN_DIR/.." && pwd)"
JS="$UI_ROOT/static/js/vsp_api_shim_v1.js"

if [ ! -f "$JS" ]; then
  echo "[ERR] Không tìm thấy $JS"
  exit 1
fi

BACKUP="${JS}.bak_disable_runs_$(date +%Y%m%d_%H%M%S)"
cp "$JS" "$BACKUP"
echo "[BACKUP] $JS -> $BACKUP"

export JS

python - << 'PY'
import os, pathlib

js = pathlib.Path(os.environ["JS"])
txt = js.read_text(encoding="utf-8")

old = 'if (url.includes("/api/vsp/runs_index_v3")) {'
new = 'if (false && url.includes("/api/vsp/runs_index_v3")) {'

if old not in txt:
    print("[WARN] Không thấy block shim runs_index_v3 trong", js)
else:
    txt = txt.replace(old, new)
    js.write_text(txt, encoding="utf-8")
    print("[OK] Đã vô hiệu hóa shim /api/vsp/runs_index_v3 trong", js)
PY

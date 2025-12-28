#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
cd "$ROOT"

TPL="templates/index.html"
echo "[i] TPL = $TPL"

if [ ! -f "$TPL" ]; then
  echo "[ERR] Không tìm thấy $TPL" >&2
  exit 1
fi

python3 - "$TPL" << 'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")
orig = data

css_block = """
  <!-- PATCH_FORCE_DISABLE_LOADING_OVERLAY -->
  <style>
    body.sb-loading, body.loading {
      overflow: auto !important;
    }
    #sb-loading-overlay, .sb-loading-overlay,
    #loadingOverlay, .loading-overlay {
      display: none !important;
      opacity: 0 !important;
      visibility: hidden !important;
      pointer-events: none !important;
      z-index: -1 !important;
    }
  </style>
"""

marker = "</head>"

if "PATCH_FORCE_DISABLE_LOADING_OVERLAY" in data:
    print("[OK] CSS patch đã có, skip")
else:
    if marker not in data:
        raise SystemExit("[ERR] Không thấy </head> trong templates/index.html")
    data = data.replace(marker, css_block + "\n" + marker)
    path.write_text(data, encoding="utf-8")
    print("[DONE] Đã chèn CSS patch tắt overlay trước </head>.")
PY

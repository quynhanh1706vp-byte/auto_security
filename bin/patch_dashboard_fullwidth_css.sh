#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/index.html"
cp "$TPL" "$TPL.bak_fullwidth_$(date +%Y%m%d_%H%M%S)" || true

python3 - <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

marker = "</style>"
extra_css = """
    /* FORCE main element FULL WIDTH (override old template) */
    main {
      max-width: 100% !important;
      margin: 0 !important;
      width: 100% !important;
    }
"""

if marker in data:
    data = data.replace(marker, extra_css + "\n" + marker, 1)
else:
    data = data + "\\n<style>\\n" + extra_css + "\\n</style>\\n"

path.write_text(data, encoding="utf-8")
print("[OK] injected main{max-width:100%} override")
PY

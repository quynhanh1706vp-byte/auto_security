#!/usr/bin/env bash
set -euo pipefail

cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/index.html"
cp "$TPL" "$TPL.bak_force_green_$(date +%Y%m%d_%H%M%S)" || true

python3 - <<'PY'
from pathlib import Path

path = Path("templates/index.html")
data = path.read_text(encoding="utf-8")

marker = "</style>"
extra_css = """
    /* === FORCE PURE GREEN THEME (override old purple styles) === */
    .nav-item.active {
      background: linear-gradient(90deg,#22c55e,#16a34a) !important;
      color:#052e16 !important;
      border-color: rgba(74,222,128,.9) !important;
    }
    .nav-item.active span.dot {
      background:#052e16 !important;
      opacity:1 !important;
    }

    .main {
      background: radial-gradient(circle at top left,#022c22,#020617 60%,#020617 100%) !important;
    }
    .layout {
      background: transparent !important;
    }
    .kpi-card,
    .panel {
      background: radial-gradient(circle at top left, rgba(22,163,74,.42), rgba(5,46,22,.98)) !important;
      border-color: rgba(34,197,94,.55) !important;
    }
"""

if marker in data:
    data = data.replace(marker, extra_css + "\n" + marker)
else:
    # nếu vì lý do gì không có </style> thì append luôn
    data = data + "\\n<style>\\n" + extra_css + "\\n</style>\\n"

path.write_text(data, encoding="utf-8")
print("[OK] injected FORCE GREEN CSS")
PY

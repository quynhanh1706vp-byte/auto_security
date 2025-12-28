#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[PATCH_CHARTJS] Không thấy $TPL"
  exit 1
fi

cp "$TPL" "$TPL.bak_chartjs_$(date +%Y%m%d_%H%M%S)"
echo "[PATCH_CHARTJS] Backup -> $TPL.bak_chartjs_*"

python - << 'PY'
from pathlib import Path
import re

tpl = Path("templates/vsp_dashboard_2025.html")
txt = tpl.read_text(encoding="utf-8")

# Nếu đã có Chart.js rồi thì thôi
if "cdn.jsdelivr.net/npm/chart.js" in txt or "Chart.bundle" in txt:
    print("[PATCH_CHARTJS] Đã có Chart.js, không sửa gì.")
else:
    snippet = '''
  <!-- Chart.js for VSP dashboard charts -->
  <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
'''

    new_txt, n = re.subn(
        r"(</head>)",
        snippet + r"\n\1",
        txt,
        count=1,
        flags=re.IGNORECASE
    )

    if n == 0:
        # Không tìm thấy </head> thì chèn lên đầu file
        new_txt = snippet + "\n" + txt
        print("[PATCH_CHARTJS] Không tìm thấy </head>, đã chèn Chart.js lên đầu file.")
    else:
        print("[PATCH_CHARTJS] Đã chèn Chart.js trước </head>.")

    tpl.write_text(new_txt, encoding="utf-8")
PY

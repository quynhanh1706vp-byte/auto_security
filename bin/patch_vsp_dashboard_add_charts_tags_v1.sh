#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"  # ROOT = .../SECURITY_BUNDLE/ui
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [ ! -f "$TPL" ]; then
  echo "[PATCH] Không tìm thấy $TPL"
  exit 1
fi

cp "$TPL" "$TPL.bak_charts_tags_$(date +%Y%m%d_%H%M%S)"

python - << 'PY'
from pathlib import Path
import re, textwrap

root = Path(__file__).resolve().parents[1]  # .../SECURITY_BUNDLE/ui
tpl_path = root / "templates" / "vsp_dashboard_2025.html"
txt = tpl_path.read_text(encoding="utf-8")

snippet = '''
<script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
<script src="/static/js/vsp_dashboard_charts_v2.js" defer></script>
'''

if "vsp_dashboard_charts_v2.js" in txt:
    print("[PATCH] Script charts đã tồn tại, bỏ qua.")
else:
    pattern = r'(<script src="/static/js/vsp_dashboard_enhance_v1.js"[^>]*></script>)'
    if re.search(pattern, txt):
        def repl(m):
            return m.group(1) + textwrap.dedent(snippet)
        new_txt = re.sub(pattern, repl, txt, count=1)
        print("[PATCH] Đã chèn script charts ngay sau vsp_dashboard_enhance_v1.js")
    else:
        new_txt = txt.replace('</body>', textwrap.dedent(snippet) + '\n</body>')
        print("[PATCH] Không tìm thấy script enhance, chèn trước </body>")

    tpl_path.write_text(new_txt, encoding="utf-8")
PY

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TPL="$ROOT/templates/vsp_dashboard_2025.html"

if [[ ! -f "$TPL" ]]; then
  echo "[ERR] Không tìm thấy template $TPL"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp "$TPL" "${TPL}.bak_force_charts_${TS}"
echo "[BACKUP] ${TPL}.bak_force_charts_${TS}"

python - << 'PY'
import pathlib, re

tpl = pathlib.Path("templates/vsp_dashboard_2025.html")
text = tpl.read_text(encoding="utf-8")

# 1) Bỏ mọi script chart cũ để tránh nhân bản
text = re.sub(r'\s*<script src="https://cdn.jsdelivr.net/npm/chart\.js"></script>\s*', '\n', text)
text = re.sub(r'\s*<script src="/static/js/vsp_dashboard_charts_v1.js"></script>\s*', '\n', text)

# 2) Chuẩn hoá KPI block + chèn lại 3 script trước </body>
block = '''    <script src="/static/js/vsp_dashboard_kpi_v1.js"></script>
    <script src="https://cdn.jsdelivr.net/npm/chart.js"></script>
    <script src="/static/js/vsp_dashboard_charts_v1.js"></script>
'''

m = re.search(r'</body>\s*</html>', text, flags=re.IGNORECASE)
if not m:
    raise SystemExit("[ERR] Không tìm thấy </body></html> để chèn block charts.")

new_text = text[:m.start()] + block + "\n" + text[m.start():]
tpl.write_text(new_text, encoding="utf-8")
print("[PATCH] Đã chèn block KPI + Chart.js + vsp_dashboard_charts_v1.js vào", tpl)
PY

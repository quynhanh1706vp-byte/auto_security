#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TPL="templates/vsp_dashboard_2025.html"
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$TPL" "$TPL.bak_charts_order_${TS}"
echo "[BACKUP] $TPL.bak_charts_order_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html")
t = tpl.read_text(encoding="utf-8", errors="ignore")

# Remove existing tags (so we can reinsert cleanly)
targets = [
  "/static/js/vsp_dashboard_charts_v2.js",
  "/static/js/vsp_dashboard_charts_pretty_v3.js",
  "/static/js/vsp_dashboard_charts_bootstrap_v1.js",
  "/static/js/vsp_dashboard_enhance_v1.js",
]

def rm_script(src, txt):
  pat = re.compile(r'\s*<script\s+[^>]*src="'+re.escape(src)+r'"\s+defer[^>]*>\s*</script>\s*\n?', re.I)
  return pat.sub("", txt)

t2 = t
for s in targets:
  t2 = rm_script(s, t2)

block = """
  <!-- DASHBOARD CHARTS ORDER (commercial) -->
  <script src="/static/js/vsp_dashboard_charts_v2.js" defer></script>
  <script src="/static/js/vsp_dashboard_charts_pretty_v3.js" defer></script>
  <script src="/static/js/vsp_dashboard_charts_bootstrap_v1.js" defer></script>
  <script src="/static/js/vsp_dashboard_enhance_v1.js" defer></script>
"""

# Insert the block near the end of body (best for DOM ready), before </body>
m = re.search(r'</body\s*>', t2, flags=re.I)
if m:
  t3 = t2[:m.start()] + "\n" + block + "\n" + t2[m.start():]
else:
  t3 = t2.rstrip() + "\n" + block + "\n"

tpl.write_text(t3, encoding="utf-8")
print("[OK] reordered scripts: charts_v2 -> pretty_v3 -> bootstrap -> enhance (before </body>)")
PY

echo "[OK] done"

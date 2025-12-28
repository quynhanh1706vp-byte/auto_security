#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

echo "== [A] JS parse check =="
for f in \
  static/js/vsp_dashboard_charts_pretty_v3.js \
  static/js/vsp_dashboard_charts_bootstrap_v1.js \
  static/js/vsp_dashboard_enhance_v1.js \
  static/js/vsp_runs_commercial_panel_v1.js \
  static/js/vsp_tabs_hash_router_v1.js
do
  [ -f "$f" ] || { echo "[MISS] $f"; continue; }
  echo "-- node --check $f"
  node --check "$f"
done

echo
echo "== [B] API sanity =="
echo "-- dashboard data should HIT by_severity --"
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3 | jq -e '..|objects|select(has("by_severity"))|.by_severity' >/dev/null && echo "HIT /api/vsp/dashboard_v3" || echo "MISS /api/vsp/dashboard_v3"

echo "-- dashboard_v3_latest is status/progress (expected keys stage_name/progress_pct) --"
curl -sS http://127.0.0.1:8910/api/vsp/dashboard_v3_latest | jq '{ok, status, stage_name, progress_pct, final, http_code}' 2>/dev/null || true

echo
echo "== [C] Served HTML includes scripts =="
curl -sS http://127.0.0.1:8910/ | grep -n "vsp_dashboard_charts_pretty_v3.js\|vsp_dashboard_charts_bootstrap_v1.js\|vsp_dashboard_enhance_v1.js" || true

echo
echo "== [D] Duplicate id quick lint (template) =="
python3 - <<'PY'
import re
from collections import Counter
from pathlib import Path

tpl = Path("templates/vsp_dashboard_2025.html").read_text(encoding="utf-8", errors="ignore")
ids = re.findall(r'\bid\s*=\s*"([^"]+)"', tpl)
c = Counter(ids)
dups = [(k,v) for k,v in c.items() if v>1]
dups.sort(key=lambda x:(-x[1], x[0]))
print("ids_total=", len(ids), "dups_n=", len(dups))
for k,v in dups[:20]:
  print("DUP", v, k)
PY

echo
echo "== DONE =="

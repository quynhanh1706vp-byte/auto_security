#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need ss; need sed; need grep

TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

cp -f "$W" "${W}.bak_rm_kpi_v3proxy_${TS}"
echo "[BACKUP] ${W}.bak_rm_kpi_v3proxy_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove our bad proxy block (it attaches @app.route while app is a wrapped function)
markers = [
  ("# ===================== VSP_P2_KPI_V3_PROXY_HTTP_V1", "# ===================== /VSP_P2_KPI_V3_PROXY_HTTP_V1"),
  ("# ===================== VSP_P2_RUNS_KPI_V3_PROXY_V1", "# ===================== /VSP_P2_RUNS_KPI_V3_PROXY_V1"),
  ("# ===================== VSP_P2_RUNS_KPI_V3_PROXY_V1_APPEND", "# ===================== /VSP_P2_RUNS_KPI_V3_PROXY_V1_APPEND"),
]
orig = s
for a,b in markers:
    s = re.sub(r'(?s)\n' + re.escape(a) + r'.*?' + re.escape(b) + r'\n', "\n", s)

# Extra safety: if any leftover decorator+func name exists, remove that small section
s = re.sub(r'(?s)\n@app\.route\(\s*["\']\/api\/ui\/runs_kpi_v3["\']\s*\)\s*\n(def\s+vsp_ui_runs_kpi_v3_proxy\s*\(.*?\)\s*:\s*\n.*?)(?=\n@|\ndef\s|\Z)', "\n", s)

p.write_text(s, encoding="utf-8")
print("[OK] removed proxy blocks:", (orig != s))
PY

echo "== py_compile =="
python3 -m py_compile "$W" && echo "[OK] py_compile OK"

echo "== import smoke (must NOT raise) =="
python3 - <<'PY'
import importlib, traceback
try:
    m = importlib.import_module("wsgi_vsp_ui_gateway")
    print("[IMPORT] OK", "app=", type(getattr(m,"app",None)), "application=", type(getattr(m,"application",None)))
except Exception as e:
    print("[IMPORT] FAIL:", e)
    traceback.print_exc()
    raise SystemExit(3)
PY

echo "== restart service =="
systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.8

echo "== port check =="
ss -ltnp 2>/dev/null | grep -E ':8910\b' || true

echo "== sanity /vsp5 and KPI v2 =="
curl -fsS "$BASE/vsp5" >/dev/null && echo "[OK] /vsp5 reachable" || echo "[ERR] /vsp5 not reachable"
curl -sS "$BASE/api/ui/runs_kpi_v2?days=30" | head -c 260; echo

echo "[DONE] p2_remove_kpi_v3_proxy_block_and_boot_v1"

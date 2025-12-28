#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need grep; need sed; need awk; need curl

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_allowfix_${TS}"
echo "[BACKUP] ${W}.bak_allowfix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

marker_begin = r"# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 ====================="
marker_end   = r"# ===================== /VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 ====================="

# Replace ONLY the buggy _dash_allow_exact() function body inside that contract block
pat = re.compile(
    r"(# ===================== VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================.*?\n)"
    r"(def _dash_allow_exact\(path: str\) -> bool:\n.*?\n)"
    r"(# ===================== /VSP_P0_DASHBOARD_RUNFILEALLOW_CONTRACT_V1 =====================)",
    re.DOTALL
)

def_fixed = """def _dash_allow_exact(path: str) -> bool:
  \"\"\"Exact allow-check for Dashboard run_file_allow contract (no glob).\"\"\"
  try:
    p = (path or \"\").strip()
    if not p:
      return False
    # normalize
    p = p.replace(\"\\\\\", \"/\").lstrip(\"/\")
    # basic traversal hard-block
    if \"..\" in p:
      return False
    return p in _DASHBOARD_ALLOW_EXACT
  except Exception:
    return False
"""

m = pat.search(s)
if not m:
    raise SystemExit("[ERR] cannot find contract block + _dash_allow_exact to patch")

s2 = pat.sub(lambda mm: mm.group(1) + def_fixed + "\n" + mm.group(3), s, count=1)

# Optional: add a tiny self-test comment (no crash)
if "VSP_P0_DASH_ALLOW_SELFTEST_V1" not in s2:
    inject = "\n# VSP_P0_DASH_ALLOW_SELFTEST_V1\n" \
             "# self-check (expected True): run_gate_summary.json, reports/run_gate_summary.json\n"
    s2 = s2.replace(marker_end, inject + marker_end)

p.write_text(s2, encoding="utf-8")
print("[OK] patched _dash_allow_exact (removed recursion)")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile"

systemctl restart vsp-ui-8910.service 2>/dev/null || true
sleep 0.5
echo "[OK] restarted (or attempted)"

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
echo "== quick probe =="
curl -sS "$BASE/api/vsp/runs?limit=1" | head -c 180; echo

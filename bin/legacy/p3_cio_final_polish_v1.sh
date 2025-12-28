#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need grep; need head; need curl

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [A] Patch JS: fix *_v3_v3 typos + replace top_findings_v1 calls =="
python3 - <<'PY'
from pathlib import Path
import time, re

ts=time.strftime("%Y%m%d_%H%M%S")
files=[
  Path("static/js/dashboard_render.js"),
  Path("static/js/vsp_dashboard_luxe_v1.js"),
]
def backup(p, orig):
    b=p.with_name(p.name+f".bak_finalpolish_{ts}")
    b.write_text(orig, encoding="utf-8")
    print("[BACKUP]", b.name)

for p in files:
    if not p.exists():
        print("[SKIP] missing", p); continue
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s

    # 1) Fix accidental double suffix
    s=s.replace("/api/vsp/dashboard_v3_v3", "/api/vsp/dashboard_v3")
    s=s.replace("/api/vsp/rid_latest_v3_v3", "/api/vsp/rid_latest_v3")

    # 2) Replace top_findings_v1 with findings_v3 (client-side “top” = first N)
    # Handle patterns:
    #   jget('/api/vsp/top_findings_v1?limit=10')
    s=re.sub(r"jget\(\s*['\"]/api/vsp/top_findings_v1\?limit=(\d+)['\"]\s*\)",
             r"jget('/api/vsp/findings_v3?limit=\1&offset=0')", s)
    # or fetchJson("/api/vsp/top_findings_v1?limit=10")
    s=re.sub(r"fetchJson\(\s*['\"]/api/vsp/top_findings_v1\?limit=(\d+)['\"]\s*\)",
             r"fetchJson('/api/vsp/findings_v3?limit=\1&offset=0')", s)

    if s != orig:
        backup(p, orig)
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p.name)
    else:
        print("[OK] no change", p.name)
PY

echo
echo "== [B] Backend: add CIO alias endpoints (safe) in vsp_demo_app.py =="
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_alias_${TS}"
echo "[BACKUP] ${APP}.bak_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO ALIASES (AUTO) ==="
END ="### === END CIO ALIASES (AUTO) ==="

block=textwrap.dedent(r'''
### === CIO ALIASES (AUTO) ===
# Purpose: keep UI stable while we migrate legacy calls to v3.
# These aliases do NOT expose internal file paths and simply forward to v3 endpoints.

from flask import request

@app.get("/api/vsp/rid_latest")
def api_vsp_rid_latest_alias_to_v3():
    # preserve old contract but return canonical latest
    return api_vsp_rid_latest_v3()

@app.get("/api/vsp/run_gate_summary_v1")
def api_vsp_run_gate_summary_v1_alias():
    # forward to v3 gate
    rid=request.args.get("rid","")
    return api_vsp_run_gate_v3()

@app.get("/api/vsp/top_findings_v1")
def api_vsp_top_findings_v1_alias():
    # map to findings_v3 paging; caller usually wants limit only
    # We do not guarantee sorting here (UI can sort). Just return first page.
    return api_vsp_findings_v3()

@app.get("/api/vsp/trend_v1")
def api_vsp_trend_v1_alias():
    # Provide trend from dashboard_v3 to avoid legacy computation
    return api_vsp_dashboard_v3()

### === END CIO ALIASES (AUTO) ===
''').strip("\n")+"\n"

if MARK in s and END in s:
    s=re.sub(rf'{re.escape(MARK)}.*?{re.escape(END)}\n?', block, s, flags=re.S)
else:
    s=s.rstrip()+"\n\n"+block

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] vsp_demo_app.py py_compile ok")
PY

echo
echo "== [C] Restart service + smoke the fixed endpoints =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

curl -fsS "$BASE/api/vsp/dashboard_v3" | head -c 120; echo
curl -fsS "$BASE/api/vsp/rid_latest_v3" | head -c 120; echo
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 120; echo
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=3" | head -c 120; echo

echo
echo "== [D] Verify no *_v3_v3 remains in active JS =="
if grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '_v3_v3' static/js >/dev/null; then
  echo "[ERR] still has _v3_v3:"
  grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '_v3_v3' static/js | head -n 80
  exit 4
else
  echo "[OK] no _v3_v3 in active JS"
fi

echo "[DONE] Hard refresh browser (Ctrl+Shift+R) and re-check F12 Network."

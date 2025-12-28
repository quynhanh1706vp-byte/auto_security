#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need grep; need head; need curl

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [A] Patch FE: runs_index_v3_v3 -> runs_v3 (no plumbing) =="

"$PY" - <<'PY'
from pathlib import Path
import time

ts=time.strftime("%Y%m%d_%H%M%S")
targets = [
  Path("static/js/vsp_fetch_shim_v1.js"),
  Path("static/js/vsp_fulltabs_bind_v1.js"),
  Path("static/js/vsp_dashboard_comm_enhance_v1.js"),
  Path("static/js/vsp_dashboard_live_v2.V1_baseline.js"),
  Path("static/js/dashboard_render.js"),
  Path("static/js/vsp_dashboard_luxe_v1.js"),
]

def backup(p, orig):
    b=p.with_name(p.name+f".bak_runsfix_{ts}")
    b.write_text(orig, encoding="utf-8")
    print("[BACKUP]", b.name)

for p in targets:
    if not p.exists():
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s

    # Replace the bad endpoint
    s=s.replace("/api/vsp/runs_index_v3_v3", "/api/vsp/runs_v3?limit=200&offset=0")
    s=s.replace("/api/vsp/runs_index_v3",    "/api/vsp/runs_v3?limit=200&offset=0")

    # Some files might store it in constants without quotes
    s=s.replace("runs_index_v3_v3", "runs_v3?limit=200&offset=0")
    s=s.replace("runs_index_v3",    "runs_v3?limit=200&offset=0")

    # Keep error messages CIO-clean (no leaking internal API names)
    s=s.replace("API /api/vsp/runs_index_v3_v3", "API /api/vsp/runs_v3")

    if s != orig:
        backup(p, orig)
        p.write_text(s, encoding="utf-8")
        print("[OK] patched", p.name)
    else:
        print("[OK] no change", p.name)
PY

echo
echo "== [B] Backend alias: runs_index_v3(_v3) -> redirect runs_v3 =="

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
cp -f "$APP" "${APP}.bak_runs_index_alias_${TS}"
echo "[BACKUP] ${APP}.bak_runs_index_alias_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO RUNS_INDEX ALIAS (AUTO) ==="
END ="### === END CIO RUNS_INDEX ALIAS (AUTO) ==="

block=textwrap.dedent(r'''
### === CIO RUNS_INDEX ALIAS (AUTO) ===
from flask import redirect, request

def _cio_redirect_runs_v3():
    # preserve limit/offset if provided
    q=[]
    limit=request.args.get("limit","200")
    offset=request.args.get("offset","0")
    try:
        int(limit); int(offset)
    except Exception:
        limit="200"; offset="0"
    return redirect(f"/api/vsp/runs_v3?limit={limit}&offset={offset}", code=302)

@app.get("/api/vsp/runs_index_v3")
def api_vsp_runs_index_v3_alias():
    return _cio_redirect_runs_v3()

@app.get("/api/vsp/runs_index_v3_v3")
def api_vsp_runs_index_v3_v3_alias():
    return _cio_redirect_runs_v3()

### === END CIO RUNS_INDEX ALIAS (AUTO) ===
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
echo "== [C] Restart + smoke =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

# Smoke: alias should 302 -> runs_v3 (curl -L follows)
curl -fsSL "$BASE/api/vsp/runs_index_v3_v3?limit=2&offset=0" | head -c 220; echo
curl -fsS  "$BASE/api/vsp/runs_v3?limit=2&offset=0" | head -c 220; echo

echo
echo "== [D] Final checks (exclude backups) =="
if grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '_v3_v3' static/js >/dev/null; then
  echo "[ERR] still has _v3_v3:"
  grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' '_v3_v3' static/js | head -n 80
  exit 4
else
  echo "[OK] no _v3_v3 in active JS"
fi

if grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' 'runs_index_v3' static/js >/dev/null; then
  echo "[WARN] still mentions runs_index_v3 somewhere (should be fine due to alias):"
  grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' 'runs_index_v3' static/js | head -n 80
else
  echo "[OK] no runs_index_v3 in active JS"
fi

echo "[DONE] Hard refresh (Ctrl+Shift+R) and re-check /vsp5 + /runs."

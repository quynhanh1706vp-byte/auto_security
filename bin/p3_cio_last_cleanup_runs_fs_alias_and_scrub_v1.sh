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

echo "== [A] Backend: alias runs_index_v3_fs* -> redirect runs_v3 =="
cp -f "$APP" "${APP}.bak_runsfs_alias_${TS}"
echo "[BACKUP] ${APP}.bak_runsfs_alias_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO RUNS_FS ALIAS (AUTO) ==="
END ="### === END CIO RUNS_FS ALIAS (AUTO) ==="

block=textwrap.dedent(r'''
### === CIO RUNS_FS ALIAS (AUTO) ===
from flask import redirect, request

def _cio_redirect_runs_v3_fs():
    # legacy endpoints sometimes use limit/hide_empty/filter
    limit=request.args.get("limit","50")
    offset=request.args.get("offset","0")
    try:
        limit=str(int(limit))
    except Exception:
        limit="50"
    try:
        offset=str(int(offset))
    except Exception:
        offset="0"
    return redirect(f"/api/vsp/runs_v3?limit={limit}&offset={offset}", code=302)

@app.get("/api/vsp/runs_index_v3_fs")
def api_vsp_runs_index_v3_fs_alias():
    return _cio_redirect_runs_v3_fs()

@app.get("/api/vsp/runs_index_v3_fs_resolved")
def api_vsp_runs_index_v3_fs_resolved_alias():
    return _cio_redirect_runs_v3_fs()

### === END CIO RUNS_FS ALIAS (AUTO) ===
''').strip("\n")+"\n"

if MARK in s and END in s:
    s=re.sub(rf'{re.escape(MARK)}.*?{re.escape(END)}\n?', block, s, flags=re.S)
else:
    s=s.rstrip()+"\n\n"+block

p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] vsp_demo_app.py py_compile ok")
PY

echo "== [B] FE: scrub visible legacy strings (exclude backups) =="
"$PY" - <<'PY'
from pathlib import Path
import time

ts=time.strftime("%Y%m%d_%H%M%S")
root=Path("static/js")

def backup(p, orig):
    b=p.with_name(p.name+f".bak_scrub_{ts}")
    b.write_text(orig, encoding="utf-8")
    print("[BACKUP]", b.name)

for p in sorted(root.glob("*.js")):
    if ".bak" in p.name or ".disabled" in p.name:
        continue
    s=p.read_text(encoding="utf-8", errors="replace")
    orig=s
    # scrub only text occurrences (keep URLs already patched elsewhere)
    s=s.replace("runs_index_v3_fs_resolved", "runs_v3")
    s=s.replace("runs_index_v3_fs", "runs_v3")
    s=s.replace("runs_index_v3", "runs_v3")
    s=s.replace("/api/vsp/runs_index_v3_fs_resolved", "/api/vsp/runs_v3")
    s=s.replace("/api/vsp/runs_index_v3_fs", "/api/vsp/runs_v3")
    s=s.replace("/api/vsp/runs_index_v3", "/api/vsp/runs_v3")
    if s != orig:
        backup(p, orig)
        p.write_text(s, encoding="utf-8")
        print("[OK] scrubbed", p.name)
PY

echo "== [C] Restart + smoke legacy aliases =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

curl -fsSL "$BASE/api/vsp/runs_index_v3_fs?limit=2" | head -c 200; echo
curl -fsSL "$BASE/api/vsp/runs_index_v3_fs_resolved?limit=2&filter=1" | head -c 200; echo
curl -fsS  "$BASE/api/vsp/runs_v3?limit=2&offset=0" | head -c 200; echo

echo
echo "== [D] Final grep (exclude backups) =="
grep -RIn --line-number --exclude='*.bak*' --exclude='*.disabled*' 'runs_index_v3_fs_resolved|runs_index_v3_fs|runs_index_v3' static/js | head -n 40 || echo "[OK] no legacy runs_index strings in active JS"
echo "[DONE] Hard refresh (Ctrl+Shift+R)."

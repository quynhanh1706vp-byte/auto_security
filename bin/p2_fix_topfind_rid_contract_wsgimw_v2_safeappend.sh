#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ls; need head; need grep; need curl

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

echo "== [0] Backup current broken file =="
cp -f "$WSGI" "${WSGI}.bak_before_topfind_contract_v2_${TS}"
echo "[BACKUP] ${WSGI}.bak_before_topfind_contract_v2_${TS}"

echo "== [1] Rescue: restore newest backup that py_compile OK =="
python3 - <<'PY'
import glob, os, py_compile, shutil, sys
w="wsgi_vsp_ui_gateway.py"

cands = []
# prefer recent backups first
for pat in [
  w+".bak_topfind_rid_contract_*",
  w+".bak_*",
]:
    cands += glob.glob(pat)

# sort newest first by mtime
cands = sorted(set(cands), key=lambda p: os.path.getmtime(p), reverse=True)

def ok(p):
    try:
        py_compile.compile(p, doraise=True)
        return True
    except Exception:
        return False

if ok(w):
    print("[OK] current file already parses OK:", w)
    sys.exit(0)

for b in cands:
    if ok(b):
        shutil.copy2(b, w)
        print("[RESTORE] using:", b)
        # ensure restored parses
        py_compile.compile(w, doraise=True)
        print("[OK] restored file parses:", w)
        sys.exit(0)

print("[ERR] no parseable backup found for", w)
sys.exit(2)
PY

echo "== [2] Append safe middleware: TopFindings RID contract fix (idempotent) =="
python3 - <<'PY'
from pathlib import Path
import py_compile

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P2_TOPFIND_RID_CONTRACT_WSGI_MW_V2_SAFEAPPEND"
if MARK in s:
    print("[OK] already patched:", MARK)
else:
    patch = f"""

# {MARK}
def _vsp__topfind_rid_contract(resp):
    try:
        from flask import request
        if request.path != "/api/vsp/top_findings_v1":
            return resp

        ct = (resp.headers.get("Content-Type","") if hasattr(resp, "headers") else "")
        if "application/json" not in ct:
            return resp

        raw = resp.get_data(as_text=True) if hasattr(resp, "get_data") else None
        if not raw:
            return resp

        import json
        j = json.loads(raw)

        ru = j.get("rid_used")
        r  = j.get("rid")
        if ru and r and ru != r:
            j["rid_raw"] = r
            j["rid"] = ru
            out = json.dumps(j, ensure_ascii=False)
            if hasattr(resp, "set_data"):
                resp.set_data(out)
            try:
                resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
            except Exception:
                pass
        return resp
    except Exception:
        return resp

try:
    _app = globals().get("app") or globals().get("application")
    if _app and hasattr(_app, "after_request"):
        _app.after_request(_vsp__topfind_rid_contract)
except Exception:
    pass
# /{MARK}
"""
    s = s + patch
    p.write_text(s, encoding="utf-8")

py_compile.compile("wsgi_vsp_ui_gateway.py", doraise=True)
print("[OK] patched + py_compile ok")
PY

echo "== [3] Restart service =="
if systemctl list-units --full -all | grep -qF "$SVC"; then
  sudo systemctl restart "$SVC"
  echo "[OK] restarted $SVC"
else
  echo "[WARN] service '$SVC' not found; skip restart"
fi

echo "== [4] Verify contract =="
curl -fsS --max-time 3 "$BASE/api/vsp/top_findings_v1?limit=5" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("rid=",j.get("rid"),"rid_used=",j.get("rid_used"),"rid_raw=",j.get("rid_raw"))'

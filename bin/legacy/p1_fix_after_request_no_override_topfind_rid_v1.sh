#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_afterreq_nooverride_${TS}"
echo "[BACKUP] ${APP}.bak_afterreq_nooverride_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_AFTER_REQUEST_NO_OVERRIDE_TOPFIND_RID_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find ALL @app.after_request blocks and inject early return at top of function body
# Pattern: @app.after_request \n def name(resp):
pat = re.compile(r'(@app\.after_request\s*\n)([ \t]*def[ \t]+\w+\s*\(\s*([A-Za-z_]\w*)\s*\)\s*:\s*\n)', re.M)

matches=list(pat.finditer(s))
if not matches:
    print("[ERR] no @app.after_request found; cannot patch safely")
    raise SystemExit(2)

out=[]
last=0
inj_count=0

for m in matches:
    out.append(s[last:m.end()])
    resp_var=m.group(3)  # the function param name
    # indent = indentation of next line after def (assume 4 spaces)
    # We'll use 4 spaces to be safe; python tolerates consistent indent in block.
    indent="    "
    guard = (
        f"{indent}# {MARK}\n"
        f"{indent}try:\n"
        f"{indent}    from flask import request as _req\n"
        f"{indent}    if getattr(_req,'path','') == '/api/vsp/top_findings_v1':\n"
        f"{indent}        # if rid is explicitly requested, NEVER override it in after_request rewriting\n"
        f"{indent}        if (_req.args.get('rid') or '').strip():\n"
        f"{indent}            return {resp_var}\n"
        f"{indent}except Exception:\n"
        f"{indent}    pass\n"
    )
    out.append(guard)
    inj_count += 1
    last = m.end()

out.append(s[last:])
s2="".join(out)
p.write_text(s2, encoding="utf-8")
print(f"[OK] injected guard into after_request blocks: {inj_count}")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile PASS"

sudo systemctl restart "$SVC"
echo "[OK] restarted: $SVC"

echo
echo "== [TEST] rid must be honored (rid_used == rid_requested) =="
RID_TEST="${1:-VSP_CI_20251218_114312}"
curl -fsS "$BASE/api/vsp/top_findings_v1?limit=3&rid=$RID_TEST" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"rid_requested=",j.get("rid_requested"),"rid_used=",j.get("rid_used"),"items_len=",len(j.get("items") or []))'

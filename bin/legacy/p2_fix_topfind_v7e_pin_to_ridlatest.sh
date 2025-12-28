#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_topfind_v7e_${TS}"
echo "[BACKUP] ${W}.bak_topfind_v7e_${TS}"

python3 - "$W" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

# Ensure V7D exists
if "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7D" not in s:
    print("[ERR] V7D marker not found; abort")
    raise SystemExit(2)

# Patch the header marker ok-v7d -> ok-v7e
s2 = s.replace('("X-VSP-TOPFIND-RUNID-FIX", "ok-v7d")', '("X-VSP-TOPFIND-RUNID-FIX", "ok-v7e")')

# Inject pin logic inside the JSON patch block (after rid_used resolved)
needle = r'(?s)(if isinstance\(j, dict\):\s+?\n\s+?if j\.get\("ok"\) is True.*?\n\s+?rid_used = .*?\n\s+?if rid_used:\s+?\n\s+?j\["run_id"\] = rid_used\s+?\n\s+?j\["marker"\] = _V7D_MARKER\s+?\n\s+?body = json\.dumps\(j, ensure_ascii=False\)\.encode\("utf-8"\)\n)'
m = re.search(needle, s2)
if not m:
    # v7d might already have slightly different structure; do a simpler, safer injection:
    # Find where j["marker"]=_V7D_MARKER is set, insert pin right after.
    m2 = re.search(r'(?m)^\s+j\["marker"\]\s*=\s*_V7D_MARKER\s*$', s2)
    if not m2:
        print("[ERR] cannot locate injection point in V7D")
        raise SystemExit(2)
    ins = '\n' + '\n'.join([
        '                        # V7E: pin rid_used/run_id to rid in query (rid_latest when missing rid)',
        '                        rid_q = _qs_get(environ.get("QUERY_STRING",""), "rid")',
        '                        if rid_q:',
        '                            j["rid_used"] = rid_q',
        '                            j["run_id"] = rid_q',
        '                            j["marker"] = "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7E"',
    ]) + '\n'
    s2 = s2[:m2.end()] + ins + s2[m2.end():]
else:
    # If the exact block matched, just pin after run_id assignment.
    block = m.group(1)
    if "V7E: pin" not in block:
        pinned = block + '\n' + '\n'.join([
            '                    # V7E: pin rid_used/run_id to rid in query (rid_latest when missing rid)',
            '                    rid_q = _qs_get(environ.get("QUERY_STRING",""), "rid")',
            '                    if rid_q:',
            '                        j["rid_used"] = rid_q',
            '                        j["run_id"] = rid_q',
            '                        j["marker"] = "VSP_P2_TOPFIND_FORCE_RIDLATEST_WSGI_MW_V7E"',
        ]) + '\n'
        s2 = s2.replace(block, pinned)

p.write_text(s2, encoding="utf-8")
print("[OK] patched V7D => V7E pin rid_used/run_id to rid query")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "[INFO] restarting: $SVC"
sudo systemctl restart "$SVC"
sleep 0.6
sudo systemctl is-active --quiet "$SVC" && echo "[OK] service active" || { echo "[ERR] service not active"; exit 2; }

echo "== PROOF top_findings (must match rid_latest) =="
RID_LATEST="$(curl -sS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json;print(json.load(sys.stdin).get("rid",""))')"
echo "rid_latest=$RID_LATEST"

curl --http1.1 -sSI "$BASE/api/vsp/top_findings_v1?limit=1" | egrep -i 'http/|content-type|content-length|x-vsp-topfind-runid-fix'
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"),"marker=",j.get("marker"))'

echo "== CHECK should equal rid_latest =="
curl --http1.1 -sS "$BASE/api/vsp/top_findings_v1?limit=1" \
 | python3 - "$RID_LATEST" <<'PY'
import sys,json
rid_latest = sys.argv[1]
j=json.load(sys.stdin)
print("rid_latest=",rid_latest)
print("rid_used=",j.get("rid_used"),"run_id=",j.get("run_id"))
if j.get("rid_used")!=rid_latest or j.get("run_id")!=rid_latest:
    raise SystemExit(2)
print("[OK] pinned to rid_latest")
PY

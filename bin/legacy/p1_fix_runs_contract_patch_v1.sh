#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need curl; need jq

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== restore latest backup (bak_runs_contract_*) =="
python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
baks=sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_runs_contract_*"),
            key=lambda x: x.stat().st_mtime, reverse=True)
if not baks:
    print("[ERR] no bak_runs_contract_* found; abort for safety")
    raise SystemExit(2)
bak=baks[0]
p.write_text(bak.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
print("[OK] restored:", bak.name)
PY

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_fix_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_fix_${TS}"

echo "== repatch contract fields (safe insert) =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_FIELDS_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

# Find anchor inside the /api/vsp/runs after_request hook: X-VSP-RUNS-HAS header line
m = re.search(r'(?m)^(?P<indent>\s*)resp\.headers\["X-VSP-RUNS-HAS"\]\s*=\s*"VSP_RUNS_HAS_DETECT_P0_V1"\s*$', s)
if not m:
    # try single quotes variant
    m = re.search(r"(?m)^(?P<indent>\s*)resp\.headers\['X-VSP-RUNS-HAS'\]\s*=\s*'VSP_RUNS_HAS_DETECT_P0_V1'\s*$", s)
if not m:
    print("[ERR] cannot find X-VSP-RUNS-HAS anchor line; abort")
    raise SystemExit(2)

indent = m.group("indent")
pos = m.start()  # insert BEFORE this header assignment

inject = f"""{indent}# ==== {MARK} ====
{indent}# P1 contract: enrich runs index response with stable fields for UI/commercial
{indent}try:
{indent}    from flask import request as _req
{indent}    import os as _os
{indent}    # effective limit: requested (cap)
{indent}    try:
{indent}        _lim_req = int((_req.args.get("limit") or "50").strip())
{indent}    except Exception:
{indent}        _lim_req = 50
{indent}    _hard_cap = 120
{indent}    _lim_eff = max(1, min(_lim_req, _hard_cap))
{indent}    data["limit"] = _lim_eff
{indent}
{indent}    items = data.get("items") or []
{indent}    rid_latest = ""
{indent}    if isinstance(items, list) and items:
{indent}        try:
{indent}            rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
{indent}        except Exception:
{indent}            rid_latest = ""
{indent}    data["rid_latest"] = rid_latest
{indent}
{indent}    # cache TTL hint
{indent}    try:
{indent}        data["cache_ttl"] = int(_os.environ.get("VSP_RUNS_CACHE_TTL", "2"))
{indent}    except Exception:
{indent}        data["cache_ttl"] = 2
{indent}
{indent}    # roots used (best-effort, don't break if unknown)
{indent}    roots_used = []
{indent}    try:
{indent}        # common names you may have in gateway
{indent}        for nm in ("VSP_RUNS_ROOTS", "RUNS_ROOTS", "VSP_DATA_ROOTS"):
{indent}            if nm in globals() and isinstance(globals()[nm], (list, tuple)):
{indent}                roots_used = [str(x) for x in globals()[nm]]
{indent}                break
{indent}    except Exception:
{indent}        roots_used = []
{indent}    data["roots_used"] = roots_used
{indent}
{indent}    # scan cap hit
{indent}    try:
{indent}        scanned = int(data.get("_scanned") or 0)
{indent}    except Exception:
{indent}        scanned = 0
{indent}    scan_cap = int(data.get("_scan_cap") or 500)
{indent}    data["scan_cap"] = scan_cap
{indent}    data["scan_cap_hit"] = bool(scanned >= scan_cap)
{indent}except Exception:
{indent}    pass
{indent}# ==== /{MARK} ====
"""

s = s[:pos] + inject + s[pos:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

echo "== py_compile =="
python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== restart =="
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

echo "== contract test =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
j="$(curl -sS "$BASE/api/vsp/runs?limit=20")"
echo "$j" | jq -e '
  .ok==true
  and (.items|type=="array")
  and (.limit|type=="number")
  and (.rid_latest|type=="string")
  and (.cache_ttl|type=="number")
  and (.roots_used|type=="array")
  and (.scan_cap_hit|type=="boolean")
' >/dev/null
echo "[OK] runs contract schema OK"
echo "$j" | jq -r '.limit,.rid_latest,.cache_ttl,.scan_cap_hit, (.roots_used|length)'

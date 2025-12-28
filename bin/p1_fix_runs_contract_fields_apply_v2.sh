#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_applyv2_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_applyv2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_POSTPROCESS_V2"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# anchor to the existing after_request handler marker/header
m = re.search(r'(?m)^(?P<indent>\s*)resp\.headers\["X-VSP-RUNS-HAS"\]\s*=\s*"VSP_RUNS_HAS_DETECT_P0_V1"\s*$', s)
if not m:
    m = re.search(r"(?m)^(?P<indent>\s*)resp\.headers\['X-VSP-RUNS-HAS'\]\s*=\s*'VSP_RUNS_HAS_DETECT_P0_V1'\s*$", s)
if not m:
    print("[ERR] cannot find X-VSP-RUNS-HAS anchor; abort")
    raise SystemExit(2)

indent=m.group("indent")
pos=m.start()

inject = f"""{indent}# ==== {MARK} ====
{indent}# Ensure contract fields are actually present in response JSON (post-process body)
{indent}try:
{indent}    import json as _json
{indent}    from flask import request as _req
{indent}    import os as _os
{indent}    _txt = resp.get_data(as_text=True) or ""
{indent}    _data = _json.loads(_txt)
{indent}    if isinstance(_data, dict) and _data.get("ok") is True and isinstance(_data.get("items"), list):
{indent}        # limit normalize
{indent}        try:
{indent}            _lim_req = int((_req.args.get("limit") or "50").strip())
{indent}        except Exception:
{indent}            _lim_req = 50
{indent}        _hard_cap = 120
{indent}        _lim_eff = max(1, min(_lim_req, _hard_cap))
{indent}        _data["limit"] = _lim_eff
{indent}
{indent}        items = _data.get("items") or []
{indent}        rid_latest = ""
{indent}        if items:
{indent}            try:
{indent}                rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
{indent}            except Exception:
{indent}                rid_latest = ""
{indent}        _data["rid_latest"] = rid_latest
{indent}
{indent}        try:
{indent}            _data["cache_ttl"] = int(_os.environ.get("VSP_RUNS_CACHE_TTL", "2"))
{indent}        except Exception:
{indent}            _data["cache_ttl"] = 2
{indent}
{indent}        # best-effort roots_used
{indent}        roots_used = []
{indent}        try:
{indent}            for nm in ("VSP_RUNS_ROOTS", "RUNS_ROOTS", "VSP_DATA_ROOTS"):
{indent}                if nm in globals() and isinstance(globals()[nm], (list, tuple)):
{indent}                    roots_used = [str(x) for x in globals()[nm]]
{indent}                    break
{indent}        except Exception:
{indent}            roots_used = []
{indent}        _data["roots_used"] = roots_used
{indent}
{indent}        try:
{indent}            scanned = int(_data.get("_scanned") or 0)
{indent}        except Exception:
{indent}            scanned = 0
{indent}        scan_cap = int(_data.get("_scan_cap") or 500)
{indent}        _data["scan_cap"] = scan_cap
{indent}        _data["scan_cap_hit"] = bool(scanned >= scan_cap)
{indent}
{indent}        _out = _json.dumps(_data, ensure_ascii=False)
{indent}        resp.set_data(_out.encode("utf-8"))
{indent}        resp.headers["Content-Length"] = str(len(resp.get_data()))
{indent}except Exception:
{indent}    pass
{indent}# ==== /{MARK} ====
"""

s = s[:pos] + inject + s[pos:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

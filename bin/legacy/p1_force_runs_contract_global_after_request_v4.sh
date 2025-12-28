#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_global_ar_v4_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_global_ar_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_GLOBAL_AR_V4"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# find Flask app creation
m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
if not m:
    print("[ERR] cannot find line like: app = Flask(...). Abort for safety.")
    raise SystemExit(2)

# insert right AFTER that line
line_end = s.find("\n", m.end())
if line_end < 0:
    raise SystemExit(2)
ins = line_end + 1

inject = f'''
# ==== {MARK} ====
# P1 contract: ensure /api/vsp/runs always returns stable fields for UI/commercial.
@app.after_request
def _vsp_runs_contract_global_after_request(resp):
    try:
        from flask import request as _req
        if (_req.path or "") != "/api/vsp/runs":
            return resp

        # only touch JSON
        mt = getattr(resp, "mimetype", "") or ""
        if "json" not in mt:
            return resp

        try:
            resp.direct_passthrough = False
        except Exception:
            pass

        import json as _json, os as _os
        raw = resp.get_data()  # buffer body
        txt = raw.decode("utf-8", "replace") if isinstance(raw, (bytes, bytearray)) else str(raw)
        data = _json.loads(txt)

        if isinstance(data, dict) and data.get("ok") is True and isinstance(data.get("items"), list):
            # effective limit = requested (cap)
            try:
                lim_req = int((_req.args.get("limit") or "50").strip())
            except Exception:
                lim_req = 50
            hard_cap = 120
            lim_eff = max(1, min(lim_req, hard_cap))
            data["limit"] = lim_eff

            items = data.get("items") or []
            rid_latest = ""
            if items:
                try:
                    rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
                except Exception:
                    rid_latest = ""
            data["rid_latest"] = rid_latest

            # cache ttl hint
            try:
                data["cache_ttl"] = int(_os.environ.get("VSP_RUNS_CACHE_TTL", "2"))
            except Exception:
                data["cache_ttl"] = 2

            # roots used (from env for now; helps debug why items empty)
            roots_used = []
            v = _os.environ.get("VSP_RUNS_ROOTS", "").strip()
            if v:
                roots_used = [x.strip() for x in v.split(":") if x.strip()]
            data["roots_used"] = roots_used

            # scan cap hit
            try:
                scanned = int(data.get("_scanned") or 0)
            except Exception:
                scanned = 0
            scan_cap = int(data.get("_scan_cap") or 500)
            data["scan_cap"] = scan_cap
            data["scan_cap_hit"] = bool(scanned >= scan_cap)

            out = _json.dumps(data, ensure_ascii=False)
            resp.set_data(out.encode("utf-8"))
            resp.headers["Content-Length"] = str(len(resp.get_data()))
            resp.headers["X-VSP-RUNS-CONTRACT"] = "P1_V4"

    except Exception:
        pass
    return resp
# ==== /{MARK} ====
'''

s = s[:ins] + inject + s[ins:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

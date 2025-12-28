#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date; need bash

F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_runs_contract_${TS}"
echo "[BACKUP] ${F}.bak_runs_contract_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_RUNS_CONTRACT_FIELDS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find the after_request handler and inject before "return resp" success path.
# We anchor near the header X-VSP-RUNS-HAS which you already have.
anchor = 'resp.headers["X-VSP-RUNS-HAS"] = "VSP_RUNS_HAS_DETECT_P0_V1"'
i = s.find(anchor)
if i < 0:
    print("[ERR] anchor not found:", anchor)
    raise SystemExit(2)

# Insert just BEFORE setting Content-Length / X-VSP-RUNS-HAS (so JSON already updated).
# We'll locate a safe spot a bit earlier: right before the header block.
# Find previous line where resp.set_data(...) happened in that function.
m = list(re.finditer(r"\n\s*resp\.set_data\(", s[:i]))
if not m:
    print("[ERR] cannot find resp.set_data(...) before anchor (unexpected layout)")
    raise SystemExit(2)
ins_pos = m[-1].end()

inject = r'''
        # ==== {MARK} ====
        # P1 contract: enrich runs index response with stable fields for UI/commercial
        try:
            # requested limit (cap)
            try:
                _lim_req = int((_vsp_req.args.get("limit") or "50").strip())
            except Exception:
                _lim_req = 50
            _hard_cap = 120
            _lim_eff = max(1, min(_lim_req, _hard_cap))

            # keep existing keys but normalize 'limit' to effective (prevents UI confusion)
            data["limit"] = _lim_eff

            items = data.get("items") or []
            rid_latest = ""
            if isinstance(items, list) and items:
                try:
                    rid_latest = (items[0].get("run_id") or items[0].get("rid") or "").strip()
                except Exception:
                    rid_latest = ""
            data["rid_latest"] = rid_latest

            # cache TTL hint (read env if exists; default 2s)
            try:
                import os as _os
                data["cache_ttl"] = int(_os.environ.get("VSP_RUNS_CACHE_TTL", "2"))
            except Exception:
                data["cache_ttl"] = 2

            # roots used (best effort)
            roots_used = []
            try:
                if "_vsp__runs_roots" in globals():
                    for r in (_vsp__runs_roots() or []):
                        roots_used.append(str(r))
                elif "_vsp_runs_roots" in globals():
                    for r in (_vsp_runs_roots() or []):
                        roots_used.append(str(r))
            except Exception:
                roots_used = []
            data["roots_used"] = roots_used

            # scan cap hit (best effort from _scanned)
            try:
                scanned = int(data.get("_scanned") or 0)
            except Exception:
                scanned = 0
            scan_cap = 500
            data["scan_cap"] = scan_cap
            data["scan_cap_hit"] = bool(scanned >= scan_cap)

        except Exception:
            pass
        # ==== /{MARK} ====
'''.format(MARK=MARK)

s = s[:ins_pos] + inject + s[ins_pos:]
p.write_text(s, encoding="utf-8")
print("[OK] injected:", MARK)
PY

bash -n "$F"
echo "[OK] bash -n OK: $F"

# restart UI (reuse your single-owner starter)
rm -f /tmp/vsp_ui_8910.lock || true
bin/p1_ui_8910_single_owner_start_v2.sh

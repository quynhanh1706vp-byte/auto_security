#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_rfa_after_${TS}"
echo "[BACKUP] ${W}.bak_rfa_after_${TS}"

python3 - "$W" <<'PY'
import sys
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

TAG="VSP_P0_WSGIGW_RFA_AFTER_REQUEST_PROMOTE_V1"
if TAG in s:
    print("[OK] already patched"); raise SystemExit(0)

addon = f"""

# --- {TAG} ---
# Promote /api/vsp/run_file_allow JSON contract:
# if findings is empty but items (or nested data.*) exists -> copy into top-level findings
def __vsp_promote_findings_contract(j):
    try:
        if not isinstance(j, dict):
            return j
        f = j.get("findings")
        if isinstance(f, list) and f:
            return j

        cands = []
        it = j.get("items")
        if isinstance(it, list) and it:
            cands = it

        dt = j.get("data")
        if not cands and isinstance(dt, list) and dt:
            cands = dt

        if not cands and isinstance(dt, dict):
            for k in ("findings","items","data"):
                v = dt.get(k)
                if isinstance(v, list) and v:
                    cands = v
                    break

        j["findings"] = cands if isinstance(cands, list) else []
    except Exception:
        pass
    return j

def __vsp_attach_rfa_after_request(_app):
    try:
        import json
        from flask import request

        @_app.after_request
        def _vsp_rfa_promote_after(resp):
            try:
                # only this endpoint
                if request.path != "/api/vsp/run_file_allow":
                    return resp
                # only JSON 200
                ct = (resp.headers.get("Content-Type") or "").lower()
                if resp.status_code != 200 or "application/json" not in ct:
                    return resp

                raw = resp.get_data(as_text=True) or ""
                if not raw.strip():
                    return resp

                j = json.loads(raw)
                before = j.get("findings")
                j2 = __vsp_promote_findings_contract(j)

                # set header always when JSON ok (commercial signal)
                try:
                    resp.headers["X-VSP-RFA-PROMOTE"] = "v2"
                except Exception:
                    pass

                # if changed -> rewrite body
                if j2 is not j or before != j2.get("findings"):
                    resp.set_data(json.dumps(j2, ensure_ascii=False))
                return resp
            except Exception:
                return resp

    except Exception:
        return

# bind to gunicorn-exported app (preferred), fallback to 'app'
try:
    __vsp_attach_rfa_after_request(application)
except Exception:
    try:
        __vsp_attach_rfa_after_request(app)
    except Exception:
        pass
# --- /{TAG} ---

"""

# Append at end (safe; app/application already defined by then)
s = s.rstrip() + "\n" + addon
p.write_text(s, encoding="utf-8")
print("[OK] appended after_request promoter to wsgi gateway")
PY

python3 -m py_compile "$W"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC" 2>/dev/null || systemctl restart "$SVC" 2>/dev/null || true
echo "[OK] restarted (if service exists)"

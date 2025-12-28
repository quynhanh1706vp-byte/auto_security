#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_afterreq_rfa_normv2_${TS}"
echo "[BACKUP] ${WSGI}.bak_afterreq_rfa_normv2_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_AFTERREQ_RFA_NORMV2_SAFE"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Append at EOF: safest (no messing with try/except blocks)
addon = r'''
# ===================== VSP_P0_AFTERREQ_RFA_NORMV2_SAFE =====================
try:
    # Attach to whichever Flask app object exists (application/_app/app)
    _fl = None
    for _name in ("application", "_app", "app"):
        if _name in globals():
            _fl = globals().get(_name)
            break

    if _fl is not None:
        @_fl.after_request
        def __vsp_afterreq_rfa_normv2(resp):
            try:
                from flask import request
                import json

                # Only for run_file_allow
                if getattr(request, "path", "") != "/api/vsp/run_file_allow":
                    return resp

                ct = (resp.headers.get("Content-Type","") or "").lower()
                if "application/json" not in ct:
                    return resp

                raw = resp.get_data(as_text=True) or ""
                if not raw.strip():
                    return resp

                obj = json.loads(raw)

                def _norm_dict(d: dict):
                    # Normalize either root dict or nested dict in "data"
                    root = d.get("data") if isinstance(d.get("data"), dict) else d

                    # Candidates
                    f = root.get("findings")
                    it = root.get("items")
                    dt = root.get("data")  # sometimes list

                    # If findings missing/empty -> take items or data(list)
                    if not f:
                        if isinstance(it, list) and it:
                            root["findings"] = list(it)
                        elif isinstance(dt, list) and dt:
                            root["findings"] = list(dt)

                    # Promote back to top-level for UI compatibility
                    if isinstance(root.get("findings"), list):
                        d["findings"] = root.get("findings")

                    # Also normalize top-level "items" if absent but present in root
                    if "items" not in d and isinstance(root.get("items"), list):
                        d["items"] = root.get("items")

                    return d

                if isinstance(obj, dict):
                    obj = _norm_dict(obj)

                # Write body back
                out = json.dumps(obj, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
                resp.headers["Cache-Control"] = "no-store"
                resp.headers["X-VSP-RFA-NORM"] = "v2"
            except Exception:
                pass
            return resp
except Exception:
    pass
# ===================== /VSP_P0_AFTERREQ_RFA_NORMV2_SAFE ====================
'''
s2 = s + ("\n" if not s.endswith("\n") else "") + addon
p.write_text(s2, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" >/dev/null 2>&1 || systemctl restart "$SVC" || true
  echo "[OK] restarted (if service exists)"
fi

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"

echo "== verify =="
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=reports/findings_unified.json&limit=3" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"findings_len=",len(j.get("findings") or []),"items_len=",len(j.get("items") or []),"hdr=",j.get("from"))'

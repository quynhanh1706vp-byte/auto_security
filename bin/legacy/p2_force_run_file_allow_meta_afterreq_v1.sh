#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1"

cp -f "$F" "${F}.bak_afterreq_meta_${TS}"
echo "[BACKUP] ${F}.bak_afterreq_meta_${TS}"

python3 - <<'PY'
from pathlib import Path
import sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")
MARK = "VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = r'''
# ===================== VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1 =====================
import json as _json
try:
    from flask import request
except Exception:
    request = None

def _vsp__should_patch_runfileallow() -> bool:
    try:
        if request is None:
            return False
        if request.path != "/api/vsp/run_file_allow":
            return False
        p = (request.args.get("path") or "")
        return p.endswith("findings_unified.json")
    except Exception:
        return False

try:
    _VSP_APP2 = app
except Exception:
    try:
        _VSP_APP2 = application
    except Exception:
        _VSP_APP2 = None

if _VSP_APP2 is not None:
    @_VSP_APP2.after_request
    def _vsp__afterreq_runfileallow_meta(resp):
        try:
            if not _vsp__should_patch_runfileallow():
                return resp
            ct = (resp.content_type or "").lower()
            if "application/json" not in ct:
                return resp
            body = resp.get_data(as_text=True) or ""
            j = _json.loads(body)

            # only patch if response has findings but lacks meta
            if isinstance(j, dict) and ("findings" in j) and ("meta" not in j):
                # if backend already had counts_total somewhere, do minimal meta
                meta = {"counts_by_severity": j.get("counts_total") or {}}
                j["meta"] = meta
                j["__patched__"] = MARK
                resp.set_data(_json.dumps(j, ensure_ascii=False))
        except Exception:
            pass
        return resp
# ===================== /VSP_P2_AFTERREQ_RUNFILEALLOW_META_V1 =====================
'''
p.write_text(s + "\n\n" + block + "\n")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$F"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify meta exists now =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("has_meta=", "meta" in j, "patched=", j.get("__patched__"))'

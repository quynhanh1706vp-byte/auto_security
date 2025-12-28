#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl; need grep; need sed
command -v systemctl >/dev/null 2>&1 || true

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P2_SAFE_AFTERREQ_ANCHOR_META_V3"

cp -f "$F" "${F}.bak_safe_afterreq_${TS}"
echo "[BACKUP] ${F}.bak_safe_afterreq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, sys

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(errors="ignore")

MARK = "VSP_P2_SAFE_AFTERREQ_ANCHOR_META_V3"
if MARK in s:
    print("[OK] marker already present -> skip")
    sys.exit(0)

block = f'''
# ===================== {MARK} =====================
def _vsp__safe_register_after_request(_app):
    try:
        from flask import request
        import json as _json

        def _after(resp):
            try:
                # --- (A) force anchor for /vsp5 html ---
                if getattr(request, "path", "") == "/vsp5":
                    ct = (getattr(resp, "content_type", "") or "").lower()
                    if "text/html" in ct:
                        body = resp.get_data(as_text=True)
                        if isinstance(body, str) and 'id="vsp-dashboard-main"' not in body:
                            if '<div id="vsp5_root"></div>' in body:
                                body = body.replace(
                                    '<div id="vsp5_root"></div>',
                                    '<!-- {MARK} -->\\n  <div id="vsp-dashboard-main"></div>\\n\\n  <div id="vsp5_root"></div>',
                                    1
                                )
                                resp.set_data(body)

                # --- (B) ensure meta exists for findings_unified via run_file_allow ---
                if getattr(request, "path", "") == "/api/vsp/run_file_allow":
                    qpath = (request.args.get("path") or "")
                    if qpath.endswith("findings_unified.json"):
                        ct = (getattr(resp, "content_type", "") or "").lower()
                        if "application/json" in ct:
                            body = resp.get_data(as_text=True) or ""
                            j = _json.loads(body)
                            if isinstance(j, dict) and ("findings" in j) and ("meta" not in j):
                                j["meta"] = {{"counts_by_severity": j.get("counts_total") or {{}}}}
                                j["__patched__"] = "{MARK}"
                                resp.set_data(_json.dumps(j, ensure_ascii=False))
            except Exception:
                pass
            return resp

        _app.after_request(_after)
        return True
    except Exception:
        return False

# best-effort find app object
try:
    _app_obj = app
except Exception:
    try:
        _app_obj = application
    except Exception:
        _app_obj = None

if _app_obj is not None:
    _vsp__safe_register_after_request(_app_obj)
# ===================== /{MARK} =====================
'''

# insert after a stable anchor: "app = application" if exists, else append end
m = re.search(r'(^\\s*app\\s*=\\s*application\\s*$)', s, flags=re.M)
if m:
    idx = m.end(1)
    s2 = s[:idx] + "\n\n" + block + s[idx:]
    print("[OK] inserted after 'app = application'")
else:
    s2 = s + "\n\n" + block + "\n"
    print("[WARN] 'app = application' not found -> appended to end")

p.write_text(s2)
print("[OK] wrote patch:", MARK)
PY

python3 -m py_compile "$F"

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC"
fi

echo "== verify anchor on /vsp5 =="
curl -fsS "$BASE/vsp5" | grep -n 'vsp-dashboard-main' | head -n 3 || echo "[ERR] anchor missing"

echo "== verify meta on run_file_allow findings_unified =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=findings_unified.json&limit=1" \
| python3 -c 'import sys,json; j=json.load(sys.stdin); print("has_meta=",("meta" in j),"patched=",j.get("__patched__"))'

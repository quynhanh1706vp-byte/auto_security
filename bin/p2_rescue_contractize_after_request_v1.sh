#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need grep; need sed; need awk; need tail; need head; need date

ok(){ echo "[OK] $*"; }
warn(){ echo "[WARN] $*" >&2; }
err(){ echo "[ERR] $*" >&2; exit 2; }

[ -f "$APP" ] || err "missing $APP"

# 1) Restore latest backup created by the failed patch
bak="$(ls -1t vsp_demo_app.py.bak_contractize_v3_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  # fallback: any recent bak
  bak="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null | head -n 1 || true)"
fi
[ -n "$bak" ] || err "no backup found (vsp_demo_app.py.bak_*)"

cp -f "$bak" "$APP"
ok "restored $APP from $bak"

python3 -m py_compile "$APP"
ok "py_compile OK after restore"

# 2) Add after_request contractizer (single safe patch)
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_AFTER_REQUEST_CONTRACTIZE_V1 ====="
tag_end   = "# ===== /VSP_AFTER_REQUEST_CONTRACTIZE_V1 ====="

if tag_begin in s and tag_end in s:
    print("[OK] after_request contractizer already present")
else:
    patch = f"""

{tag_begin}
# Commercial hardening: normalize JSON response shapes so UI never hangs.
# Applies to selected /api/vsp/* endpoints only.

try:
    import json as _vsp_json
except Exception:
    _vsp_json = None

try:
    from flask import request as _vsp_request
except Exception:
    _vsp_request = None

_VSP_CONTRACTIZE_PATHS = set([
    "/api/vsp/dashboard_v3",
    "/api/vsp/findings_page_v3",
    "/api/vsp/findings_v3",
    "/api/vsp/run_gate_v3",
    "/api/vsp/artifact_v3",
    "/api/vsp/run_file",
    "/api/vsp/runs_v3",
    # dash_kpis route may not exist; harmless to include:
    "/api/vsp/dash_kpis",
])

def _vsp_norm_sev(d=None):
    d = d if isinstance(d, dict) else {{}}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_contractize_dict(obj):
    if not isinstance(obj, dict):
        return obj
    obj.setdefault("ok", True)

    # unify list payload to "items"
    if "items" not in obj:
        if isinstance(obj.get("findings"), list):
            obj["items"] = obj.get("findings")
        elif isinstance(obj.get("rows"), list):
            obj["items"] = obj.get("rows")
        elif isinstance(obj.get("data"), list):
            obj["items"] = obj.get("data")

    # ensure total
    if obj.get("total") is None:
        it = obj.get("items")
        if isinstance(it, list):
            obj["total"] = len(it)

    # normalize sev (6-level)
    if "sev" in obj:
        obj["sev"] = _vsp_norm_sev(obj.get("sev"))
    elif isinstance(obj.get("severity"), dict):
        obj["sev"] = _vsp_norm_sev(obj.get("severity"))
    elif isinstance(obj.get("severity_counts"), dict):
        obj["sev"] = _vsp_norm_sev(obj.get("severity_counts"))

    return obj

try:
    @app.after_request
    def vsp_after_request_contractize_v1(resp):
        try:
            if _vsp_request is None or _vsp_json is None:
                return resp
            path = getattr(_vsp_request, "path", "") or ""
            if path not in _VSP_CONTRACTIZE_PATHS:
                return resp

            # only JSON-ish responses
            mt = (getattr(resp, "mimetype", "") or "").lower()
            ct = (resp.headers.get("Content-Type","") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                return resp

            j = _vsp_json.loads(body)
            if isinstance(j, dict):
                _vsp_contractize_dict(j)
                out = _vsp_json.dumps(j, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                # content length may be cached
                try:
                    resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
                except Exception:
                    pass
            return resp
        except Exception:
            return resp
except Exception:
    # If app is not defined yet at import time, do nothing.
    pass

{tag_end}
"""
    s2 = s + patch
    p.write_text(s2, encoding="utf-8")
    print("[OK] appended after_request contractizer V1")
PY

python3 -m py_compile "$APP"
ok "py_compile OK after patch"

# 3) Restart service
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && ok "service active: $SVC" || warn "service not active; check systemctl status $SVC"
else
  warn "no systemctl; restart manually"
fi

# 4) Quick API sanity (no crash)
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
ok "RID=$RID"
for ep in dashboard_v3 findings_page_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_items=","items" in j,"total=",j.get("total"),"sev_type=",type(j.get("sev")).__name__)'
done

ok "DONE. Now Ctrl+F5 on /vsp5?rid=$RID"

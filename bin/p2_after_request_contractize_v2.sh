#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

cp -f "$APP" "${APP}.bak_afterreq_v2_${TS}"
echo "[OK] backup: ${APP}.bak_afterreq_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_AFTER_REQUEST_CONTRACTIZE_V2 ====="
tag_end   = "# ===== /VSP_AFTER_REQUEST_CONTRACTIZE_V2 ====="

if tag_begin in s and tag_end in s:
    print("[OK] V2 already present (skip append)")
else:
    patch = f"""

{tag_begin}
# Stronger contractizer than V1:
# - Unwrap common wrappers: data/result/payload/page
# - Always provide: items(list), total(int), sev(dict 6-level) at top-level
# - Prevent UI infinite Loading even when backend returns partial shapes.

try:
    import json as _vsp_json2
except Exception:
    _vsp_json2 = None

try:
    from flask import request as _vsp_request2
except Exception:
    _vsp_request2 = None

_VSP_CONTRACTIZE_PATHS_V2 = set([
    "/api/vsp/dashboard_v3",
    "/api/vsp/findings_page_v3",
    "/api/vsp/findings_v3",
    "/api/vsp/run_gate_v3",
    "/api/vsp/artifact_v3",
    "/api/vsp/run_file",
    "/api/vsp/runs_v3",
    "/api/vsp/dash_kpis",
])

def _vsp_norm_sev_v2(d=None):
    d = d if isinstance(d, dict) else {{}}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_pick_inner_dict(obj):
    if not isinstance(obj, dict):
        return None
    # unwrap common single-layer wrappers
    for key in ("data","result","payload","page"):
        v = obj.get(key)
        if isinstance(v, dict):
            return v
    return None

def _vsp_extract_items(obj):
    if not isinstance(obj, dict):
        return None
    for k in ("items","findings","rows","data","list"):
        v = obj.get(k)
        if isinstance(v, list):
            return v
    # sometimes nested: obj["page"]["items"]
    pg = obj.get("page")
    if isinstance(pg, dict):
        v = pg.get("items")
        if isinstance(v, list):
            return v
    return None

def _vsp_extract_total(obj, items):
    if not isinstance(obj, dict):
        return None
    for k in ("total","count","total_count","n","size"):
        v = obj.get(k)
        if isinstance(v, int):
            return v
    # nested page total
    pg = obj.get("page")
    if isinstance(pg, dict) and isinstance(pg.get("total"), int):
        return pg.get("total")
    if isinstance(items, list):
        return len(items)
    return 0

def _vsp_extract_sev(obj):
    if not isinstance(obj, dict):
        return None
    for k in ("sev","severity","severity_counts","sev_counts","by_severity"):
        v = obj.get(k)
        if isinstance(v, dict):
            return v
    sm = obj.get("summary")
    if isinstance(sm, dict):
        for k in ("sev","severity","severity_counts","sev_counts","by_severity"):
            v = sm.get(k)
            if isinstance(v, dict):
                return v
    return None

def _vsp_force_contract_top(j):
    \"\"\"Return a dict with guaranteed keys ok/items/total/sev (top-level).\"\"\"
    if not isinstance(j, dict):
        j = {{"ok": True}}
    j.setdefault("ok", True)

    inner = _vsp_pick_inner_dict(j)
    items = _vsp_extract_items(j) or (_vsp_extract_items(inner) if inner else None) or []
    sev = _vsp_extract_sev(j) or (_vsp_extract_sev(inner) if inner else None) or {{}}
    total = _vsp_extract_total(j, items)
    if inner and total == 0:
        total = _vsp_extract_total(inner, items)

    j["items"] = items if isinstance(items, list) else []
    j["total"] = int(total) if isinstance(total, int) else (len(j["items"]) if isinstance(j["items"], list) else 0)
    j["sev"] = _vsp_norm_sev_v2(sev)

    return j

try:
    @app.after_request
    def vsp_after_request_contractize_v2(resp):
        try:
            if _vsp_request2 is None or _vsp_json2 is None:
                return resp
            path = getattr(_vsp_request2, "path", "") or ""
            if path not in _VSP_CONTRACTIZE_PATHS_V2:
                return resp

            mt = (getattr(resp, "mimetype", "") or "").lower()
            ct = (resp.headers.get("Content-Type","") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                # empty body -> make minimal json
                j = _vsp_force_contract_top({{"ok": True}})
                out = _vsp_json2.dumps(j, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                return resp

            j = _vsp_json2.loads(body)
            if isinstance(j, dict):
                j2 = _vsp_force_contract_top(j)
                out = _vsp_json2.dumps(j2, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                try:
                    resp.headers["Content-Length"] = str(len(out.encode("utf-8")))
                except Exception:
                    pass
            return resp
        except Exception:
            return resp
except Exception:
    pass

{tag_end}
"""
    s = s + patch
    p.write_text(s, encoding="utf-8")
    print("[OK] appended V2")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.4
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in dashboard_v3 findings_page_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"has_items=","items" in j,"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"sev_type=",type(j.get("sev")).__name__)'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

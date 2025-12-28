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

cp -f "$APP" "${APP}.bak_v3_br_override_${TS}"
echo "[OK] backup: ${APP}.bak_v3_br_override_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_b = "# ===== VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 ====="
tag_e = "# ===== /VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 ====="

if tag_b in s and tag_e in s:
    print("[OK] override already present (skip)")
else:
    patch = r"""

# ===== VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 =====
# Commercial rescue: avoid gunicorn worker crashes (Empty reply) by overriding fragile V3 handlers.
# Serve minimal, stable JSON from existing reliable sources:
# - /api/vsp/run_file_allow?path=findings_unified.json (list)
# - /api/vsp/run_gate_summary_v1 (sev)
# - /api/vsp/top_findings_v1 (total)
# - /api/vsp/trend_v1 (trend)

try:
    import json as _vsp_json_or
except Exception:
    _vsp_json_or = None

try:
    from flask import request as _vsp_req_or, jsonify as _vsp_jsonify_or
except Exception:
    _vsp_req_or = None
    _vsp_jsonify_or = None

def _vsp_norm_sev_or(d=None):
    d = d if isinstance(d, dict) else {}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_tc_get_or(path_qs):
    try:
        c = app.test_client()
        r = c.get(path_qs)
        if r.status_code != 200:
            return None
        return r.get_json(silent=True)
    except Exception:
        return None

def _vsp_pick_rid_or():
    try:
        rid = (_vsp_req_or.args.get("rid") or "").strip() if _vsp_req_or else ""
    except Exception:
        rid = ""
    if rid:
        return rid
    # fallback rid_latest
    j = _vsp_tc_get_or("/api/vsp/rid_latest")
    if isinstance(j, dict):
        r = (j.get("rid") or "").strip()
        return r
    return ""

def _vsp_get_int_or(name, default):
    try:
        v = (_vsp_req_or.args.get(name) if _vsp_req_or else None)
        if v is None or str(v).strip()=="":
            return default
        return int(v)
    except Exception:
        return default

def _vsp_total_findings_or(rid):
    if not rid:
        return 0
    tf = _vsp_tc_get_or("/api/vsp/top_findings_v1?rid=%s&limit=1&offset=0" % rid)
    if isinstance(tf, dict) and tf.get("ok") and isinstance(tf.get("total"), int):
        return tf.get("total")
    return 0

def _vsp_sev_or(rid):
    if not rid:
        return _vsp_norm_sev_or({})
    g = _vsp_tc_get_or("/api/vsp/run_gate_summary_v1?rid=%s" % rid)
    if isinstance(g, dict) and g.get("ok") and isinstance(g.get("sev"), dict):
        return _vsp_norm_sev_or(g.get("sev"))
    return _vsp_norm_sev_or({})

def _vsp_items_from_rfallow_or(rid, limit, offset):
    # emulate offset by overfetch+slice; cap to keep response small
    if not rid:
        return ([], 0)
    if limit <= 0: limit = 50
    if limit > 200: limit = 200
    if offset < 0: offset = 0
    want = limit + offset
    if want > 500:
        want = 500
    rf = _vsp_tc_get_or("/api/vsp/run_file_allow?rid=%s&path=findings_unified.json&limit=%d" % (rid, want))
    if not isinstance(rf, dict):
        return ([], _vsp_total_findings_or(rid))
    arr = rf.get("findings") or rf.get("items") or rf.get("rows") or []
    if not isinstance(arr, list):
        arr = []
    items = arr[offset:offset+limit] if offset else arr[:limit]
    total = _vsp_total_findings_or(rid) or len(arr)
    return (items, total)

def _vsp_trend_or(rid):
    if not rid:
        return []
    t = _vsp_tc_get_or("/api/vsp/trend_v1?rid=%s&limit=60" % rid)
    if isinstance(t, dict) and t.get("ok"):
        pts = t.get("points") or t.get("items") or t.get("data") or []
        return pts if isinstance(pts, list) else []
    return []

try:
    @app.before_request
    def vsp_before_request_override_v3_v1():
        if _vsp_req_or is None or _vsp_jsonify_or is None:
            return None
        path = (_vsp_req_or.path or "")
        if path not in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3", "/api/vsp/dashboard_v3", "/api/vsp/run_gate_v3"):
            return None

        rid = _vsp_pick_rid_or()
        limit = _vsp_get_int_or("limit", 50)
        offset = _vsp_get_int_or("offset", 0)

        sev = _vsp_sev_or(rid)
        total_findings = _vsp_total_findings_or(rid)

        if path in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3"):
            items, total = _vsp_items_from_rfallow_or(rid, limit, offset)
            return _vsp_jsonify_or(ok=True, rid=rid, items=items, total=int(total), sev=sev, total_findings=int(total_findings))

        # dashboard / run_gate
        kpis = {
            "rid": rid,
            "critical": int(sev.get("CRITICAL",0) or 0),
            "high": int(sev.get("HIGH",0) or 0),
            "medium": int(sev.get("MEDIUM",0) or 0),
            "low": int(sev.get("LOW",0) or 0),
            "info": int(sev.get("INFO",0) or 0),
        }
        trend = _vsp_trend_or(rid)
        # keep items empty but valid (UI won’t hang)
        return _vsp_jsonify_or(ok=True, rid=rid, items=[], total=0, sev=sev, kpis=kpis, trend=trend, total_findings=int(total_findings))
except Exception:
    pass

# ===== /VSP_V3_BEFORE_REQUEST_OVERRIDE_V1 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended BEFORE_REQUEST override V1")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.6
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in findings_page_v3 findings_v3 dashboard_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"total_findings=",j.get("total_findings"),"sev_CRIT=",(j.get("sev") or {}).get("CRITICAL"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

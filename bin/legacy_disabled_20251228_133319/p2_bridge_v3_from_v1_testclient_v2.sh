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

cp -f "$APP" "${APP}.bak_bridge_tc_v2_${TS}"
echo "[OK] backup: ${APP}.bak_bridge_tc_v2_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 ====="
tag_end   = "# ===== /VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 ====="

if tag_begin in s and tag_end in s:
    print("[OK] TESTCLIENT bridge already present")
    raise SystemExit(0)

# Ensure dash_kpis exists (JS calls it). Add only if not found.
need_dash = ("/api/vsp/dash_kpis" not in s)

patch = r"""

# ===== VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 =====
# Fix: Use Flask app.test_client() instead of loopback HTTP to avoid gunicorn deadlock.
# Also ensure /api/vsp/dash_kpis exists for dashboard JS.

try:
    import json as _vsp_json_tc
except Exception:
    _vsp_json_tc = None

try:
    from flask import request as _vsp_req_tc, jsonify as _vsp_jsonify_tc
except Exception:
    _vsp_req_tc = None
    _vsp_jsonify_tc = None

def _vsp_norm_sev_tc(d=None):
    d = d if isinstance(d, dict) else {}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_get_rid_tc():
    try:
        return ((_vsp_req_tc.args.get("rid") or "").strip() if _vsp_req_tc else "")
    except Exception:
        return ""

def _vsp_get_int_tc(name, default):
    try:
        v = (_vsp_req_tc.args.get(name) if _vsp_req_tc else None)
        if v is None or str(v).strip()=="":
            return default
        return int(v)
    except Exception:
        return default

def _vsp_force_contract_top_tc(j):
    if not isinstance(j, dict):
        j = {"ok": True}
    j.setdefault("ok", True)
    if "items" not in j or not isinstance(j.get("items"), list):
        j["items"] = []
    if "total" not in j or not isinstance(j.get("total"), int):
        j["total"] = len(j["items"])
    if "sev" not in j or not isinstance(j.get("sev"), dict):
        j["sev"] = _vsp_norm_sev_tc(j.get("sev"))
    else:
        j["sev"] = _vsp_norm_sev_tc(j["sev"])
    return j

def _vsp_local_json_get_tc(path_qs, timeout_ms=2500):
    # Internal call, no network.
    try:
        c = app.test_client()
        r = c.get(path_qs)
        if r.status_code != 200:
            return None
        return r.get_json(silent=True)
    except Exception:
        return None

def _vsp_fill_findings_page_tc(j):
    rid = _vsp_get_rid_tc()
    if not rid:
        return j
    lim = _vsp_get_int_tc("limit", 50)
    off = _vsp_get_int_tc("offset", 0)
    if lim <= 0: lim = 50
    if lim > 200: lim = 200
    if off < 0: off = 0

    src = _vsp_local_json_get_tc(f"/api/vsp/top_findings_v1?rid={rid}&limit={lim}&offset={off}")
    if not isinstance(src, dict) or not src.get("ok"):
        return j

    items = src.get("items") or src.get("findings") or []
    if not isinstance(items, list):
        items = []
    tot = src.get("total")
    j["items"] = items
    j["total"] = tot if isinstance(tot, int) else len(items)
    return j

def _vsp_fill_dash_or_gate_tc(j):
    rid = _vsp_get_rid_tc()
    if not rid:
        return j

    g = _vsp_local_json_get_tc(f"/api/vsp/run_gate_summary_v1?rid={rid}")
    if isinstance(g, dict) and g.get("ok"):
        j["sev"] = _vsp_norm_sev_tc(g.get("sev"))

    tf = _vsp_local_json_get_tc(f"/api/vsp/top_findings_v1?rid={rid}&limit=1&offset=0")
    if isinstance(tf, dict) and tf.get("ok") and isinstance(tf.get("total"), int):
        j["total_findings"] = tf.get("total")

    t = _vsp_local_json_get_tc(f"/api/vsp/trend_v1?rid={rid}&limit=60")
    if isinstance(t, dict) and t.get("ok"):
        pts = t.get("points") or t.get("items") or t.get("data") or []
        if not isinstance(pts, list):
            pts = []
        j["trend"] = pts

    # lightweight KPIs
    k = j.get("kpis")
    if not isinstance(k, dict):
        k = {}
    k.setdefault("rid", rid)
    sev = j.get("sev") or {}
    k.setdefault("critical", int(sev.get("CRITICAL", 0) or 0))
    k.setdefault("high", int(sev.get("HIGH", 0) or 0))
    k.setdefault("medium", int(sev.get("MEDIUM", 0) or 0))
    k.setdefault("low", int(sev.get("LOW", 0) or 0))
    k.setdefault("info", int(sev.get("INFO", 0) or 0))
    j["kpis"] = k

    return j

try:
    @app.after_request
    def vsp_after_request_bridge_v3_from_v1_testclient_v2(resp):
        try:
            if _vsp_req_tc is None or _vsp_json_tc is None:
                return resp
            path = (_vsp_req_tc.path or "") if _vsp_req_tc else ""
            if path not in ("/api/vsp/findings_page_v3", "/api/vsp/dashboard_v3", "/api/vsp/run_gate_v3"):
                return resp

            ct = (resp.headers.get("Content-Type","") or "").lower()
            mt = (getattr(resp, "mimetype", "") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                return resp

            j = _vsp_json_tc.loads(body)
            if not isinstance(j, dict):
                return resp

            j = _vsp_force_contract_top_tc(j)

            # If already has items, keep
            if isinstance(j.get("items"), list) and len(j["items"]) > 0:
                out = _vsp_json_tc.dumps(j, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                return resp

            # Fill
            if path == "/api/vsp/findings_page_v3":
                j = _vsp_fill_findings_page_tc(j)
            else:
                j = _vsp_fill_dash_or_gate_tc(j)

            j = _vsp_force_contract_top_tc(j)
            out = _vsp_json_tc.dumps(j, ensure_ascii=False)
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

# Optional: provide /api/vsp/dash_kpis if missing
"""
if need_dash:
    patch += r"""
try:
    @app.get("/api/vsp/dash_kpis")
    def vsp_dash_kpis_stub_v2():
        rid = _vsp_get_rid_tc()
        g = _vsp_local_json_get_tc(f"/api/vsp/run_gate_summary_v1?rid={rid}") if rid else None
        sev = _vsp_norm_sev_tc(g.get("sev") if isinstance(g, dict) else {})
        tf = _vsp_local_json_get_tc(f"/api/vsp/top_findings_v1?rid={rid}&limit=1&offset=0") if rid else None
        total = tf.get("total") if isinstance(tf, dict) and isinstance(tf.get("total"), int) else 0
        return _vsp_jsonify_tc(ok=True, rid=rid, sev=sev, total=total,
                              critical=sev.get("CRITICAL",0), high=sev.get("HIGH",0),
                              medium=sev.get("MEDIUM",0), low=sev.get("LOW",0), info=sev.get("INFO",0))
except Exception:
    pass
"""
patch += r"""
# ===== /VSP_BRIDGE_V3_FROM_V1_TESTCLIENT_V2 =====
"""

p.write_text(s + patch, encoding="utf-8")
print("[OK] appended TESTCLIENT bridge V2; dash_kpis_added=", need_dash)
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.6
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in dash_kpis dashboard_v3 findings_page_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"sev_CRIT=",(j.get("sev") or {}).get("CRITICAL"),"total_findings=",j.get("total_findings"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

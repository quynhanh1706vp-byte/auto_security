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

cp -f "$APP" "${APP}.bak_bridge_v3_fix_${TS}"
echo "[OK] backup: ${APP}.bak_bridge_v3_fix_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_BRIDGE_V3_FROM_V1_FILL_V1 ====="
tag_end   = "# ===== /VSP_BRIDGE_V3_FROM_V1_FILL_V1 ====="

if tag_begin in s and tag_end in s:
    print("[OK] bridge already present (skip)")
else:
    patch = r"""

# ===== VSP_BRIDGE_V3_FROM_V1_FILL_V1 =====
# Commercial fallback: if V3 endpoints return empty items, fill from V1 endpoints that already have data.
# Targets: /api/vsp/findings_page_v3, /api/vsp/dashboard_v3, /api/vsp/run_gate_v3

try:
    import json as _vsp_json_b
    import urllib.request as _vsp_ureq_b
    import urllib.parse as _vsp_uparse_b
except Exception:
    _vsp_json_b = None
    _vsp_ureq_b = None
    _vsp_uparse_b = None

try:
    from flask import request as _vsp_req_b
except Exception:
    _vsp_req_b = None

def _vsp_http_get_json_local_b(url, timeout=3.8):
    if _vsp_ureq_b is None or _vsp_json_b is None:
        return None
    try:
        with _vsp_ureq_b.urlopen(url, timeout=timeout) as r:
            b = r.read().decode("utf-8", errors="replace")
        return _vsp_json_b.loads(b)
    except Exception:
        return None

def _vsp_get_rid_b():
    try:
        rid = (_vsp_req_b.args.get("rid") if _vsp_req_b else "") or ""
        return rid.strip()
    except Exception:
        return ""

def _vsp_get_int_arg_b(name, default):
    try:
        v = (_vsp_req_b.args.get(name) if _vsp_req_b else None)
        if v is None or str(v).strip() == "":
            return default
        return int(v)
    except Exception:
        return default

def _vsp_norm_sev_b(d):
    # keep consistent with 6-level normalized
    d = d if isinstance(d, dict) else {}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_force_contract_top_b(j):
    if not isinstance(j, dict):
        j = {"ok": True}
    j.setdefault("ok", True)
    if "items" not in j or not isinstance(j.get("items"), list):
        j["items"] = []
    if "total" not in j or not isinstance(j.get("total"), int):
        j["total"] = len(j["items"]) if isinstance(j["items"], list) else 0
    if "sev" not in j or not isinstance(j.get("sev"), dict):
        j["sev"] = _vsp_norm_sev_b(j.get("sev"))
    else:
        j["sev"] = _vsp_norm_sev_b(j["sev"])
    return j

def _vsp_fill_findings_page_from_top_v1_b(j):
    rid = _vsp_get_rid_b()
    if not rid:
        return j
    lim = _vsp_get_int_arg_b("limit", 50)
    off = _vsp_get_int_arg_b("offset", 0)
    if lim <= 0: lim = 50
    if lim > 200: lim = 200
    if off < 0: off = 0

    base = "http://127.0.0.1:8910"
    url = base + "/api/vsp/top_findings_v1?rid=" + _vsp_uparse_b.quote(rid) + "&limit=" + str(lim) + "&offset=" + str(off)
    src = _vsp_http_get_json_local_b(url)
    if not isinstance(src, dict) or not src.get("ok"):
        return j

    items = src.get("items") or src.get("findings") or []
    if not isinstance(items, list):
        items = []
    j["items"] = items
    tot = src.get("total")
    j["total"] = tot if isinstance(tot, int) else len(items)
    return j

def _vsp_fill_dashboard_from_gate_v1_b(j):
    rid = _vsp_get_rid_b()
    if not rid:
        return j

    base = "http://127.0.0.1:8910"

    # sev + kpis from run_gate_summary_v1
    url = base + "/api/vsp/run_gate_summary_v1?rid=" + _vsp_uparse_b.quote(rid)
    g = _vsp_http_get_json_local_b(url)
    if isinstance(g, dict) and g.get("ok"):
        sev = g.get("sev")
        j["sev"] = _vsp_norm_sev_b(sev)

        # lightweight KPIs for UI
        kpis = j.get("kpis")
        if not isinstance(kpis, dict):
            kpis = {}
        kpis.setdefault("rid", rid)
        kpis.setdefault("critical", j["sev"].get("CRITICAL", 0))
        kpis.setdefault("high", j["sev"].get("HIGH", 0))
        kpis.setdefault("medium", j["sev"].get("MEDIUM", 0))
        kpis.setdefault("low", j["sev"].get("LOW", 0))
        kpis.setdefault("info", j["sev"].get("INFO", 0))
        j["kpis"] = kpis

    # trend (optional)
    url2 = base + "/api/vsp/trend_v1?rid=" + _vsp_uparse_b.quote(rid) + "&limit=60"
    t = _vsp_http_get_json_local_b(url2)
    if isinstance(t, dict) and t.get("ok"):
        pts = t.get("points") or t.get("items") or t.get("data") or []
        if not isinstance(pts, list):
            pts = []
        j["trend"] = pts

    # total from top_findings_v1 (fast)
    url3 = base + "/api/vsp/top_findings_v1?rid=" + _vsp_uparse_b.quote(rid) + "&limit=1&offset=0"
    tf = _vsp_http_get_json_local_b(url3)
    if isinstance(tf, dict) and tf.get("ok") and isinstance(tf.get("total"), int):
        j["total_findings"] = tf.get("total")

    return j

try:
    @app.after_request
    def vsp_after_request_bridge_v3_from_v1_fill_v1(resp):
        try:
            if _vsp_req_b is None or _vsp_json_b is None:
                return resp

            path = (_vsp_req_b.path or "") if _vsp_req_b else ""
            if path not in ("/api/vsp/findings_page_v3","/api/vsp/dashboard_v3","/api/vsp/run_gate_v3"):
                return resp

            mt = (getattr(resp, "mimetype", "") or "").lower()
            ct = (resp.headers.get("Content-Type","") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                return resp

            j = _vsp_json_b.loads(body)
            if not isinstance(j, dict):
                return resp

            j = _vsp_force_contract_top_b(j)

            # If already has items, keep it
            if isinstance(j.get("items"), list) and len(j["items"]) > 0:
                out = _vsp_json_b.dumps(j, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                return resp

            # Fill based on endpoint
            if path == "/api/vsp/findings_page_v3":
                j = _vsp_fill_findings_page_from_top_v1_b(j)
            else:
                j = _vsp_fill_dashboard_from_gate_v1_b(j)

            j = _vsp_force_contract_top_b(j)

            out = _vsp_json_b.dumps(j, ensure_ascii=False)
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

# ===== /VSP_BRIDGE_V3_FROM_V1_FILL_V1 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended bridge patch safely (no f-string)")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.5
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in dashboard_v3 findings_page_v3 run_gate_v3; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"sev_CRIT=",(j.get("sev") or {}).get("CRITICAL"),"extra_total_findings=",j.get("total_findings"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

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

cp -f "$APP" "${APP}.bak_bridge_v3_${TS}"
echo "[OK] backup: ${APP}.bak_bridge_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_BRIDGE_V3_FROM_V1_FILL_V1 ====="
tag_end   = "# ===== /VSP_BRIDGE_V3_FROM_V1_FILL_V1 ====="

if tag_begin in s and tag_end in s:
    print("[OK] bridge already present")
else:
    patch = f"""

{tag_begin}
# Bridge: if V3 endpoints return empty items, fill from V1 endpoints that already have data.
# This is commercial-grade fallback to ensure dashboard always shows real data quickly.

try:
    import json as _vsp_json3
    import urllib.request as _vsp_ureq3
    import urllib.parse as _vsp_uparse3
except Exception:
    _vsp_json3 = None
    _vsp_ureq3 = None
    _vsp_uparse3 = None

def _vsp_http_get_json_local(url, timeout=3.5):
    if _vsp_ureq3 is None or _vsp_json3 is None:
        return None
    try:
        with _vsp_ureq3.urlopen(url, timeout=timeout) as r:
            b = r.read().decode("utf-8", errors="replace")
        return _vsp_json3.loads(b)
    except Exception:
        return None

def _vsp_get_rid_from_req():
    try:
        rid = (_vsp_request2.args.get("rid") if _vsp_request2 else "") or ""
        return rid.strip()
    except Exception:
        return ""

def _vsp_fill_findings_page_from_top_v1(j):
    # Use top_findings_v1 as data source for table/pagination
    rid = _vsp_get_rid_from_req()
    if not rid:
        return j
    base = "http://127.0.0.1:8910"
    # respect limit/offset if present
    try:
        lim = int((_vsp_request2.args.get("limit") if _vsp_request2 else "50") or "50")
        off = int((_vsp_request2.args.get("offset") if _vsp_request2 else "0") or "0")
    except Exception:
        lim, off = 50, 0
    lim = 50 if lim <= 0 else min(lim, 200)
    off = 0 if off < 0 else off

    url = f"{{base}}/api/vsp/top_findings_v1?rid={{_vsp_uparse3.quote(rid)}}&limit={{lim}}&offset={{off}}"
    src = _vsp_http_get_json_local(url)
    if not isinstance(src, dict) or not src.get("ok"):
        return j
    items = src.get("items") or src.get("findings") or []
    if not isinstance(items, list):
        items = []
    j["items"] = items
    j["total"] = src.get("total") if isinstance(src.get("total"), int) else len(items)
    # best-effort sev from run_gate_summary
    return j

def _vsp_fill_dashboard_from_gate_v1(j):
    rid = _vsp_get_rid_from_req()
    if not rid:
        return j
    base = "http://127.0.0.1:8910"
    url = f"{{base}}/api/vsp/run_gate_summary_v1?rid={{_vsp_uparse3.quote(rid)}}"
    src = _vsp_http_get_json_local(url)
    if isinstance(src, dict) and src.get("ok"):
        sev = src.get("sev")
        j["sev"] = _vsp_norm_sev_v2(sev)
        # quick KPIs
        j.setdefault("kpis", {})
        if isinstance(j["kpis"], dict):
            j["kpis"].setdefault("rid", rid)
            # totals from sev (approx): keep simple, UI gets meaningful numbers
            j["kpis"].setdefault("critical", j["sev"].get("CRITICAL",0))
            j["kpis"].setdefault("high", j["sev"].get("HIGH",0))
            j["kpis"].setdefault("medium", j["sev"].get("MEDIUM",0))
            j["kpis"].setdefault("low", j["sev"].get("LOW",0))
            j["kpis"].setdefault("info", j["sev"].get("INFO",0))
    # also provide a small "trend" if available
    url2 = f"{{base}}/api/vsp/trend_v1?rid={{_vsp_uparse3.quote(rid)}}&limit=60"
    t = _vsp_http_get_json_local(url2)
    if isinstance(t, dict) and t.get("ok"):
        j["trend"] = t.get("points") or t.get("items") or t.get("data") or []
        if not isinstance(j["trend"], list):
            j["trend"] = []
    return j

try:
    @app.after_request
    def vsp_after_request_bridge_v3_from_v1_fill_v1(resp):
        try:
            if _vsp_request2 is None or _vsp_json2 is None or _vsp_json3 is None:
                return resp
            path = getattr(_vsp_request2, "path", "") or ""
            if path not in ("/api/vsp/dashboard_v3","/api/vsp/findings_page_v3","/api/vsp/run_gate_v3"):
                return resp

            # only json
            mt = (getattr(resp, "mimetype", "") or "").lower()
            ct = (resp.headers.get("Content-Type","") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                return resp

            j = _vsp_json3.loads(body)
            if not isinstance(j, dict):
                return resp

            # contractize first (V2)
            j = _vsp_force_contract_top(j)

            # If already has items, keep
            items = j.get("items")
            if isinstance(items, list) and len(items) > 0:
                out = _vsp_json3.dumps(j, ensure_ascii=False)
                resp.set_data(out)
                resp.headers["Content-Type"] = "application/json; charset=utf-8"
                return resp

            # Fill from V1 based on endpoint
            if path == "/api/vsp/findings_page_v3":
                j = _vsp_fill_findings_page_from_top_v1(j)
                j = _vsp_force_contract_top(j)
            else:
                j = _vsp_fill_dashboard_from_gate_v1(j)
                j = _vsp_force_contract_top(j)

            out = _vsp_json3.dumps(j, ensure_ascii=False)
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
    print("[OK] appended bridge fill V1")
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
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"sev_CRIT=", (j.get("sev") or {}).get("CRITICAL"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

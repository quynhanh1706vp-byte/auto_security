#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_dashfb_${TS}"
echo "[BACKUP] ${WSGI}.bak_dashfb_${TS}"

python3 - <<'PY'
from pathlib import Path
import textwrap

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P0_DASH_FALLBACK_FROM_RUN_FILE_ALLOW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

blk = textwrap.dedent(r'''
# ===================== VSP_P0_DASH_FALLBACK_FROM_RUN_FILE_ALLOW_V1 =====================
def _vsp_find_real_flask_app_dashfb_v1():
    try:
        for v in list(globals().values()):
            if hasattr(v, "app_context") and hasattr(v, "route") and hasattr(v, "url_map"):
                return v
    except Exception:
        pass
    return None

def _vsp_pick_counts_from_findings_meta_v1(j):
    meta = (j or {}).get("meta") or {}
    counts = meta.get("counts_by_severity") or meta.get("counts_total") or {}
    if isinstance(counts, dict) and counts:
        # normalize keys
        out={}
        for k,v in counts.items():
            out[str(k).upper()] = int(v or 0)
        return out
    return {}

def _vsp_sum_counts_v1(counts):
    try: return sum(int(v or 0) for v in (counts or {}).values())
    except Exception: return 0

def _vsp_dash_fallback_kpis_v1(app, rid):
    # call internal run_file_allow (no network)
    paths = ["findings_unified.json","reports/findings_unified.json","report/findings_unified.json"]
    counts={}
    with app.test_client() as c:
        for path in paths:
            r = c.get(f"/api/vsp/run_file_allow?rid={rid}&path={path}&limit=1")
            try:
                j = r.get_json(silent=True) or {}
            except Exception:
                j = {}
            counts = _vsp_pick_counts_from_findings_meta_v1(j)
            if counts: break
    total=_vsp_sum_counts_v1(counts)
    # minimal KPI contract
    return {
      "ok": True,
      "rid": rid,
      "overall": "UNKNOWN",
      "total_findings": total,
      "total": total,
      "counts_total": counts,
      "counts": counts,
      "__via__": "DASH_FALLBACK_RUN_FILE_ALLOW",
    }

def _vsp_dash_fallback_charts_v1(rid, counts):
    # minimal chart contract
    sev_order=["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    sev_dist=[{"sev": s, "count": int((counts or {}).get(s,0) or 0)} for s in sev_order]
    return {
      "ok": True,
      "rid": rid,
      "severity_distribution": sev_dist,
      "sev_dist": sev_dist,
      "critical_high_by_tool": [],
      "top_cwe_exposure": [],
      "findings_trend": [],
      "__via__": "DASH_FALLBACK_RUN_FILE_ALLOW",
    }

def _vsp_install_dash_fallback_wrappers_v1():
    app = _vsp_find_real_flask_app_dashfb_v1()
    if not app:
        print("[VSP_DASH_FB] no real Flask app; skip")
        return
    # locate endpoints by route path
    ep_kpis=None; ep_charts=None
    for rule in getattr(app, "url_map", []).iter_rules():
        if str(rule.rule) == "/api/vsp/dash_kpis":
            ep_kpis = rule.endpoint
        if str(rule.rule) == "/api/vsp/dash_charts":
            ep_charts = rule.endpoint

    if not ep_kpis or not ep_charts:
        print("[VSP_DASH_FB] endpoints not found", ep_kpis, ep_charts)
        return

    from flask import request, jsonify

    orig_kpis = app.view_functions.get(ep_kpis)
    orig_charts = app.view_functions.get(ep_charts)

    def wrap_kpis(*a, **kw):
        rid = request.args.get("rid","") or ""
        try:
            resp = orig_kpis(*a, **kw)
        except Exception:
            resp = None
        # try extract json
        try:
            j = resp.get_json() if hasattr(resp, "get_json") else None
        except Exception:
            j = None
        if rid and isinstance(j, dict) and int(j.get("total",0) or 0) == 0:
            fb = _vsp_dash_fallback_kpis_v1(app, rid)
            return jsonify(fb)
        return resp

    def wrap_charts(*a, **kw):
        rid = request.args.get("rid","") or ""
        try:
            resp = orig_charts(*a, **kw)
        except Exception:
            resp = None
        try:
            j = resp.get_json() if hasattr(resp, "get_json") else None
        except Exception:
            j = None
        if rid and isinstance(j, dict):
            sev = j.get("severity_distribution") or j.get("sev_dist") or []
            if isinstance(sev, list) and all(int(x.get("count",0) or 0)==0 for x in sev):
                # reuse kpi fallback counts
                fbk = _vsp_dash_fallback_kpis_v1(app, rid)
                counts = fbk.get("counts_total") or {}
                fbc = _vsp_dash_fallback_charts_v1(rid, counts)
                return jsonify(fbc)
        return resp

    app.view_functions[ep_kpis] = wrap_kpis
    app.view_functions[ep_charts] = wrap_charts
    print(f"[VSP_DASH_FB] installed wrappers: {ep_kpis}, {ep_charts}")

_vsp_install_dash_fallback_wrappers_v1()
# ===================== /VSP_P0_DASH_FALLBACK_FROM_RUN_FILE_ALLOW_V1 =====================
''')

p.write_text(s + "\n\n" + blk, encoding="utf-8")
print("[OK] appended:", MARK)
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile passed"

systemctl restart "$SVC" 2>/dev/null || true

echo "== QUICK VERIFY =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 500; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 500; echo

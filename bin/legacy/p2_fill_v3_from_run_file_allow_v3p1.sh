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

cp -f "$APP" "${APP}.bak_fill_v3_rfallow_${TS}"
echo "[OK] backup: ${APP}.bak_fill_v3_rfallow_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

tag_begin = "# ===== VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 ====="
tag_end   = "# ===== /VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 ====="

if tag_begin in s and tag_end in s:
    print("[OK] V3P1 already present (skip)")
else:
    patch = r"""

# ===== VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 =====
# Commercial fallback:
# - If findings_page_v3/findings_v3 returns empty items, fill from /api/vsp/run_file_allow (findings_unified.json)
# - Also normalize dash_kpis totals to match top_findings_v1 / total_findings.
# NOTE: no network loopback; use app.test_client().

try:
    import json as _vsp_json_p1
except Exception:
    _vsp_json_p1 = None

try:
    from flask import request as _vsp_req_p1
except Exception:
    _vsp_req_p1 = None

def _vsp_get_rid_p1():
    try:
        return ((_vsp_req_p1.args.get("rid") or "").strip() if _vsp_req_p1 else "")
    except Exception:
        return ""

def _vsp_get_int_p1(name, default):
    try:
        v = (_vsp_req_p1.args.get(name) if _vsp_req_p1 else None)
        if v is None or str(v).strip() == "":
            return default
        return int(v)
    except Exception:
        return default

def _vsp_norm_sev_p1(d=None):
    d = d if isinstance(d, dict) else {}
    for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
        d.setdefault(k, 0)
    return d

def _vsp_force_top_contract_p1(j):
    if not isinstance(j, dict):
        j = {"ok": True}
    j.setdefault("ok", True)
    if "items" not in j or not isinstance(j.get("items"), list):
        j["items"] = []
    if "total" not in j or not isinstance(j.get("total"), int):
        j["total"] = len(j["items"])
    if "sev" not in j or not isinstance(j.get("sev"), dict):
        j["sev"] = _vsp_norm_sev_p1(j.get("sev"))
    else:
        j["sev"] = _vsp_norm_sev_p1(j["sev"])
    return j

def _vsp_tc_get_json_p1(path_qs):
    try:
        c = app.test_client()
        r = c.get(path_qs)
        if r.status_code != 200:
            return None
        return r.get_json(silent=True)
    except Exception:
        return None

def _vsp_get_total_findings_p1(rid):
    # from top_findings_v1 (fast total)
    if not rid:
        return None
    tf = _vsp_tc_get_json_p1("/api/vsp/top_findings_v1?rid=%s&limit=1&offset=0" % rid)
    if isinstance(tf, dict) and tf.get("ok") and isinstance(tf.get("total"), int):
        return tf.get("total")
    return None

def _vsp_fill_items_from_run_file_allow_p1(rid, limit, offset):
    # run_file_allow supports limit; offset may not exist -> emulate by overfetch+slice
    if not rid:
        return ([], 0)

    if limit <= 0: limit = 50
    if limit > 200: limit = 200
    if offset < 0: offset = 0

    want = limit + offset
    if want > 500:
        want = 500  # safety cap

    rf = _vsp_tc_get_json_p1("/api/vsp/run_file_allow?rid=%s&path=findings_unified.json&limit=%d" % (rid, want))
    if not isinstance(rf, dict):
        return ([], 0)

    findings = rf.get("findings") or rf.get("items") or rf.get("rows") or []
    if not isinstance(findings, list):
        findings = []

    sliced = findings[offset:offset+limit] if offset else findings[:limit]

    total = _vsp_get_total_findings_p1(rid)
    if not isinstance(total, int):
        total = len(findings)

    return (sliced, total)

def _vsp_fill_sev_from_gate_summary_p1(rid):
    if not rid:
        return {}
    g = _vsp_tc_get_json_p1("/api/vsp/run_gate_summary_v1?rid=%s" % rid)
    if isinstance(g, dict) and g.get("ok") and isinstance(g.get("sev"), dict):
        return g.get("sev")
    return {}

try:
    @app.after_request
    def vsp_after_request_fill_v3_from_run_file_allow_v3p1(resp):
        try:
            if _vsp_req_p1 is None or _vsp_json_p1 is None:
                return resp

            path = (_vsp_req_p1.path or "") if _vsp_req_p1 else ""
            if path not in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3", "/api/vsp/dashboard_v3", "/api/vsp/run_gate_v3", "/api/vsp/dash_kpis"):
                return resp

            ct = (resp.headers.get("Content-Type","") or "").lower()
            mt = (getattr(resp, "mimetype", "") or "").lower()
            if ("json" not in mt) and ("application/json" not in ct):
                return resp

            body = resp.get_data(as_text=True) or ""
            if not body.strip():
                return resp

            j = _vsp_json_p1.loads(body)
            if not isinstance(j, dict):
                return resp

            j = _vsp_force_top_contract_p1(j)

            rid = _vsp_get_rid_p1()
            lim = _vsp_get_int_p1("limit", 50)
            off = _vsp_get_int_p1("offset", 0)

            # Fill findings lists
            if path in ("/api/vsp/findings_page_v3", "/api/vsp/findings_v3"):
                if isinstance(j.get("items"), list) and len(j["items"]) == 0:
                    items, total = _vsp_fill_items_from_run_file_allow_p1(rid, lim, off)
                    j["items"] = items
                    j["total"] = total if isinstance(total, int) else len(items)
                # optional sev for list views
                if (not isinstance(j.get("sev"), dict)) or all((j["sev"].get(k,0)==0 for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"])):
                    j["sev"] = _vsp_norm_sev_p1(_vsp_fill_sev_from_gate_summary_p1(rid))

            # Fill dashboard/gate/kpis basics
            if path in ("/api/vsp/dashboard_v3", "/api/vsp/run_gate_v3", "/api/vsp/dash_kpis"):
                j["sev"] = _vsp_norm_sev_p1(_vsp_fill_sev_from_gate_summary_p1(rid))
                tf_total = _vsp_get_total_findings_p1(rid)
                if isinstance(tf_total, int):
                    j["total_findings"] = tf_total
                # keep some kpis for UI
                k = j.get("kpis")
                if not isinstance(k, dict):
                    k = {}
                k.setdefault("rid", rid)
                k["critical"] = int(j["sev"].get("CRITICAL", 0) or 0)
                k["high"] = int(j["sev"].get("HIGH", 0) or 0)
                k["medium"] = int(j["sev"].get("MEDIUM", 0) or 0)
                k["low"] = int(j["sev"].get("LOW", 0) or 0)
                k["info"] = int(j["sev"].get("INFO", 0) or 0)
                j["kpis"] = k

            j = _vsp_force_top_contract_p1(j)

            out = _vsp_json_p1.dumps(j, ensure_ascii=False)
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

# ===== /VSP_FILL_V3_FROM_RUN_FILE_ALLOW_V3P1 =====
"""
    p.write_text(s + patch, encoding="utf-8")
    print("[OK] appended V3P1 fill patch")
PY

python3 -m py_compile "$APP"

if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sleep 0.6
  systemctl is-active "$SVC" >/dev/null 2>&1 && echo "[OK] service active: $SVC" || echo "[WARN] service not active; check systemctl status $SVC"
fi

RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "[INFO] RID=$RID"

for ep in findings_page_v3 findings_v3 dashboard_v3 run_gate_v3 dash_kpis; do
  echo "== $ep =="
  curl -fsS "$BASE/api/vsp/$ep?rid=$RID&limit=10&offset=0" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"items_len=",(len(j.get("items") or []) if isinstance(j.get("items"),list) else None),"total=",j.get("total"),"total_findings=",j.get("total_findings"),"sev_CRIT=",(j.get("sev") or {}).get("CRITICAL"))'
done

echo "[OK] DONE. Ctrl+F5 /vsp5?rid=$RID"

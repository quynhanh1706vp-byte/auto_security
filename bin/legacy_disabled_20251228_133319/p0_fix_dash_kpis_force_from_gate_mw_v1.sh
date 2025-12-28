#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need curl
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID_A="${1:-VSP_CI_20251219_092640}"
RID_B="${2:-VSP_CI_20251218_113514}"

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

ok(){ echo "[OK] $*"; }
err(){ echo "[ERR] $*" >&2; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
MARK="VSP_P0_DASH_KPIS_FORCE_FROM_GATE_MW_V1"

cp -f "$WSGI" "${WSGI}.bak_${MARK}_${TS}"
ok "backup: ${WSGI}.bak_${MARK}_${TS}"

python3 - <<'PY'
from pathlib import Path
import py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="ignore")
MARK="VSP_P0_DASH_KPIS_FORCE_FROM_GATE_MW_V1"
if MARK in s:
    print("[OK] marker already present; skip")
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

mw = r'''
# --- VSP_P0_DASH_KPIS_FORCE_FROM_GATE_MW_V1 ---
# Commercial contract: dash_kpis and dash_charts must be consistent and RID-correct.
# Force them to come from run_gate_summary.json per RID (same root resolver as run_file_allow strict V2).
import json as _vsp_json_dk1
import urllib.parse as _vsp_urlparse_dk1
import os as _vsp_os_dk1

def _dk1_sum_counts(ct):
    try:
        return int(sum(int(ct.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")))
    except Exception:
        return 0

def _dk1_find_run_dir(rid: str):
    # Prefer strict V2 resolver if present
    g=globals()
    try:
        if "_rfa2_find_dir_direct" in g:
            d = g["_rfa2_find_dir_direct"](rid)
            if d: return d
        if "_rfa2_scan_find_dir" in g:
            d = g["_rfa2_scan_find_dir"](rid, max_depth=3)
            if d: return d
    except Exception:
        pass
    # Fallback to simple roots
    roots=[]
    for env in ("VSP_GATE_ROOT","VSP_RUNS_ROOT","VSP_RUN_ROOT","VSP_OUT_CI_ROOT","VSP_OUT_ROOT"):
        v=_vsp_os_dk1.environ.get(env)
        if v and _vsp_os_dk1.path.isdir(v): roots.append(v)
    for d0 in ("/home/test/Data/SECURITY_BUNDLE/out_ci","/home/test/Data/SECURITY_BUNDLE/out"):
        if _vsp_os_dk1.path.isdir(d0): roots.append(d0)
    for root in roots:
        cand=_vsp_os_dk1.path.join(root, rid)
        if _vsp_os_dk1.path.isdir(cand):
            return cand
    return None

def _dk1_resolve_gate(run_dir: str):
    for rel in ("run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"):
        fp=_vsp_os_dk1.path.join(run_dir, rel)
        if _vsp_os_dk1.path.isfile(fp):
            return fp, rel
    return None, None

class _VspDashKpisFromGateMwV1:
    def __init__(self, app):
        self.app=app

    def __call__(self, environ, start_response):
        path=(environ.get("PATH_INFO") or "")
        if path not in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
            return self.app(environ, start_response)

        qs=_vsp_urlparse_dk1.parse_qs(environ.get("QUERY_STRING",""))
        rid=(qs.get("rid",[""])[0] or "").strip()
        if not rid:
            # don't guess rid here; let downstream handle if it has policy
            return self.app(environ, start_response)

        run_dir=_dk1_find_run_dir(rid)
        if not run_dir:
            payload={"ok":False,"error":"RID_NOT_FOUND","rid_req":rid,"rid_used":rid,"from":""}
            body=_vsp_json_dk1.dumps(payload,ensure_ascii=False).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))],None)
            return [body]

        fp, rel=_dk1_resolve_gate(run_dir)
        if not fp:
            payload={"ok":False,"error":"GATE_NOT_FOUND","rid_req":rid,"rid_used":rid,"from":f"{rid}/run_gate_summary.json"}
            body=_vsp_json_dk1.dumps(payload,ensure_ascii=False).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))],None)
            return [body]

        try:
            raw=open(fp,"rb").read()
            j=_vsp_json_dk1.loads(raw.decode("utf-8","ignore") or "{}")
        except Exception as e:
            payload={"ok":False,"error":"GATE_READ_FAILED","detail":str(e)[:200],"rid_req":rid,"rid_used":rid,"from":f"{rid}/{rel}"}
            body=_vsp_json_dk1.dumps(payload,ensure_ascii=False).encode("utf-8")
            start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))],None)
            return [body]

        # gate summary may be wrapped; accept both
        data = j.get("data") if isinstance(j,dict) and isinstance(j.get("data"),dict) else j
        ct = (data.get("counts_total") or {}) if isinstance(data,dict) else {}
        payload = {
            "ok": True,
            "rid_req": rid,
            "rid_used": rid,
            "from": f"{rid}/{rel}",
            "counts_total": ct,
            "total_findings": _dk1_sum_counts(ct),
        }
        # dash_charts can reuse same payload (UI only needs counts_total)
        body=_vsp_json_dk1.dumps(payload,ensure_ascii=False).encode("utf-8")
        start_response("200 OK",[("Content-Type","application/json; charset=utf-8"),("Cache-Control","no-store"),("Content-Length",str(len(body)))],None)
        return [body]

try:
    application=_VspDashKpisFromGateMwV1(application)
except Exception:
    pass
# --- /VSP_P0_DASH_KPIS_FORCE_FROM_GATE_MW_V1 ---
# VSP_P0_DASH_KPIS_FORCE_FROM_GATE_MW_V1
'''
s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] appended dash_kpis/dash_charts force-from-gate MW + py_compile OK")
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || err "restart failed"
  sleep 0.8
fi

echo "== [VERIFY] dash_kpis must match gate counts_total now =="
for RID in "$RID_A" "$RID_B"; do
  echo "-- $RID --"
  echo "[gate]"
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID&path=run_gate_summary.json" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("counts_total"))'
  echo "[dash_kpis]"
  curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" \
  | python3 -c 'import sys,json; j=json.load(sys.stdin); print(j.get("counts_total"), "total", j.get("total_findings"))'
done

ok "DONE"

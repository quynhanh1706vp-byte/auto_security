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
cp -f "$WSGI" "${WSGI}.bak_kpigate_${TS}"
echo "[BACKUP] ${WSGI}.bak_kpigate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, textwrap, py_compile

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P0_DASH_KPI_FROM_GATE_SUMMARY_MW_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

block=textwrap.dedent(r'''
# ===================== VSP_P0_DASH_KPI_FROM_GATE_SUMMARY_MW_V1 =====================
try:
    import json, urllib.parse, urllib.request

    def _vsp__sum_counts(d):
        if not isinstance(d, dict): return 0
        out=0
        for _,v in d.items():
            try: out += int(v or 0)
            except Exception: pass
        return out

    def _vsp__internal_get_json(base, path):
        # prevent recursion by header
        req = urllib.request.Request(base + path, headers={"X-VSP-Internal":"1"})
        with urllib.request.urlopen(req, timeout=1.8) as r:
            raw = r.read().decode("utf-8","replace")
        return json.loads(raw)

    class _VspDashGateSummaryFillMW:
        def __init__(self, app, base="http://127.0.0.1:8910"):
            self.app = app
            self.base = base

        def __call__(self, environ, start_response):
            if environ.get("HTTP_X_VSP_INTERNAL") == "1":
                return self.app(environ, start_response)

            path = (environ.get("PATH_INFO") or "")
            if path not in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
                return self.app(environ, start_response)

            # capture downstream response
            status_holder = {}
            headers_holder = {}
            body_chunks = []

            def _sr(status, headers, exc_info=None):
                status_holder["status"] = status
                headers_holder["headers"] = list(headers)
                return body_chunks.append

            app_iter = self.app(environ, _sr)
            try:
                for c in app_iter:
                    body_chunks.append(c)
            finally:
                if hasattr(app_iter, "close"):
                    app_iter.close()

            raw = b"".join(body_chunks) if body_chunks else b""
            try:
                j = json.loads(raw.decode("utf-8","replace") or "{}")
            except Exception:
                # pass-through if not json
                start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                return [raw]

            # decide if we need to fill (only when counts are empty/zero)
            if path == "/api/vsp/dash_kpis":
                counts = (j.get("counts_total") or j.get("counts") or {})
                if _vsp__sum_counts(counts) > 0:
                    start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                    return [raw]

            if path == "/api/vsp/dash_charts":
                sev = j.get("severity_distribution") or j.get("sev_dist") or []
                if any(int(x.get("count",0) or 0) > 0 for x in (sev or []) if isinstance(x, dict)):
                    start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                    return [raw]

            # get rid
            qs = environ.get("QUERY_STRING") or ""
            q = urllib.parse.parse_qs(qs, keep_blank_values=True)
            rid = (q.get("rid") or [""])[0].strip()
            if not rid:
                try:
                    ridj = _vsp__internal_get_json(self.base, "/api/vsp/rid_latest")
                    rid = (ridj.get("rid") or "").strip()
                except Exception:
                    rid = ""

            if not rid:
                start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                return [raw]

            # load gate summary via run_file_allow
            gate = None
            for gp in ("run_gate_summary.json","reports/run_gate_summary.json","report/run_gate_summary.json"):
                try:
                    qp = urllib.parse.quote(gp, safe="")
                    qr = urllib.parse.quote(rid, safe="")
                    gate = _vsp__internal_get_json(self.base, f"/api/vsp/run_file_allow?rid={qr}&path={qp}")
                    if isinstance(gate, dict) and (gate.get("counts_total") or gate.get("by_tool")):
                        break
                except Exception:
                    gate = None

            if not isinstance(gate, dict):
                start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                return [raw]

            counts_total = gate.get("counts_total") or {}
            if _vsp__sum_counts(counts_total) <= 0:
                start_response(status_holder.get("status","200 OK"), headers_holder.get("headers",[]))
                return [raw]

            overall_gate = (gate.get("overall") or "").upper()
            overall = "PASS" if overall_gate == "GREEN" else "FAIL"

            if path == "/api/vsp/dash_kpis":
                j["ok"] = True
                j["rid"] = rid
                j["overall"] = overall
                j["counts_total"] = counts_total
                j["counts"] = counts_total
                j["total_findings"] = _vsp__sum_counts(counts_total)
                j["total"] = j["total_findings"]
                j["__via__"] = MARK
            else:
                sev_dist = [{"sev":k, "count":int(v or 0)} for k,v in counts_total.items()]
                j["ok"] = True
                j["rid"] = rid
                j["severity_distribution"] = sev_dist
                j["sev_dist"] = sev_dist
                j["critical_high_by_tool"] = []
                try:
                    by_tool = gate.get("by_tool") or {}
                    out=[]
                    for t,info in by_tool.items():
                        c = (info.get("counts") or {})
                        ch = int(c.get("CRITICAL",0) or 0) + int(c.get("HIGH",0) or 0)
                        if ch>0:
                            out.append({"tool": t, "critical_high": ch})
                    out.sort(key=lambda x: x["critical_high"], reverse=True)
                    j["critical_high_by_tool"] = out[:12]
                except Exception:
                    pass
                j["__via__"] = MARK

            out = (json.dumps(j, ensure_ascii=False)).encode("utf-8")
            # rewrite headers with new content-length
            hdrs=[]
            seen_len=False
            for k,v in headers_holder.get("headers",[]):
                if k.lower()=="content-length":
                    seen_len=True
                    continue
                hdrs.append((k,v))
            hdrs.append(("Content-Type","application/json; charset=utf-8"))
            hdrs.append(("Content-Length", str(len(out))))
            start_response(status_holder.get("status","200 OK"), hdrs)
            return [out]

    # wrap application if available
    _base = "http://127.0.0.1:8910"
    try:
        _base = f"http://127.0.0.1:{int((globals().get('VSP_UI_PORT') or 8910))}"
    except Exception:
        pass

    if "application" in globals():
        application = _VspDashGateSummaryFillMW(application, base=_base)
    if "app" in globals():
        app = _VspDashGateSummaryFillMW(app, base=_base)

    print(f"[{MARK}] enabled dash_kpis/charts fill from run_gate_summary (base={_base})")
except Exception as _e:
    print(f"[{MARK}] skipped:", repr(_e))
# ===================== /VSP_P0_DASH_KPI_FROM_GATE_SUMMARY_MW_V1 =====================
''').strip()+"\n"

s2 = s + "\n\n" + block
p.write_text(s2, encoding="utf-8")

py_compile.compile(str(p), doraise=True)
print("[OK] appended:", MARK)
PY

systemctl restart "$SVC" 2>/dev/null || true

echo "== QUICK VERIFY (rid_latest) =="
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 260; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 260; echo

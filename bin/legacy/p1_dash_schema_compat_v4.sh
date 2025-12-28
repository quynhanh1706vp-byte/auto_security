#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_dash_schema_compat_v4_${TS}"
echo "[BACKUP] ${GW}.bak_dash_schema_compat_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_SCHEMA_COMPAT_V4"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

addon = r"""
# __MARK__
import json as _json
from urllib.parse import parse_qs as _parse_qs

def _vsp__mk_donut(counts):
    sev = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
    vals = [int((counts or {}).get(k,0) or 0) for k in sev]
    return {"labels": sev, "values": vals}

def _vsp__mk_trend(trend_list):
    labels = [x.get("rid","") for x in (trend_list or []) if isinstance(x, dict)]
    values = [int(x.get("total",0) or 0) for x in (trend_list or []) if isinstance(x, dict)]
    return {"labels": labels, "values": values}

def _vsp__mk_bar_crit_high(ch_list):
    labels = [x.get("tool","") for x in (ch_list or []) if isinstance(x, dict)]
    crit = [int(x.get("critical",0) or 0) for x in (ch_list or []) if isinstance(x, dict)]
    high = [int(x.get("high",0) or 0) for x in (ch_list or []) if isinstance(x, dict)]
    return {"labels": labels, "series": [{"name":"CRITICAL","data":crit},{"name":"HIGH","data":high}]}

def _vsp__mk_top_list(kvs, key_name):
    labels = [k for k,_ in kvs]
    values = [int(v) for _,v in kvs]
    return {"labels": labels, "values": values, "key": key_name}

class _VSPDashSchemaCompatMW_V4:
    def __init__(self, app):
        base_wsgi = globals().get("_vsp_base_wsgi")
        self.app = base_wsgi(app) if callable(base_wsgi) else getattr(app, "wsgi_app", app)

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path not in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
            return self.app(environ, start_response)

        # reuse helpers from V3 if present
        base_fn = globals().get("_vsp__base_url_from_environ")
        base = base_fn(environ) if callable(base_fn) else "http://127.0.0.1:8910"

        qs = _parse_qs(environ.get("QUERY_STRING") or "")
        rid = (qs.get("rid") or [""])[0] or (globals().get("_vsp__get_latest_rid")(base) if callable(globals().get("_vsp__get_latest_rid")) else "")

        run_file = globals().get("_vsp__run_file_json")
        counts_from_s = globals().get("_vsp__counts_from_summary")
        counts_from_u = globals().get("_vsp__counts_from_unified")
        sum_counts = globals().get("_vsp__sum_counts")
        score_fn = globals().get("_vsp__score_from_total")
        tool_counts_fn = globals().get("_vsp__tool_counts_from_summary")
        trend_fn = globals().get("_vsp__trend_from_recent_runs")
        extract_items = globals().get("_vsp__extract_findings_list")
        pick_tool = globals().get("_vsp__pick_tool")
        pick_cwe = globals().get("_vsp__pick_cwe")
        pick_path = globals().get("_vsp__pick_path")

        summ = {}
        fu = {}
        try:
            if callable(run_file): summ = run_file(base, rid, "reports/run_gate_summary.json", timeout=4.0)
        except Exception:
            summ = {}
        try:
            if callable(run_file): fu = run_file(base, rid, "reports/findings_unified.json", timeout=4.0)
        except Exception:
            fu = {}

        cs = counts_from_s(summ) if callable(counts_from_s) else {}
        cu = counts_from_u(fu) if callable(counts_from_u) else None
        counts = cu if (cu and (sum_counts(cu) if callable(sum_counts) else 0) > 0) else cs
        total = (sum_counts(counts) if callable(sum_counts) else sum(int(counts.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")))

        overall = (summ or {}).get("overall") or "UNKNOWN"
        security_score = (summ or {}).get("security_score") or (score_fn(total) if callable(score_fn) else 0)

        # derive best-effort top_* from unified items
        items = extract_items(fu) if callable(extract_items) else []
        tool_cnt, cwe_cnt, mod_cnt = {}, {}, {}
        for f in (items or [])[:2500]:
            t = pick_tool(f) if callable(pick_tool) else None
            if t: tool_cnt[t] = tool_cnt.get(t,0)+1
            cwe = pick_cwe(f) if callable(pick_cwe) else None
            if cwe: cwe_cnt[cwe] = cwe_cnt.get(cwe,0)+1
            pth = pick_path(f) if callable(pick_path) else None
            if pth:
                key = pth.split("?")[0]
                if "/" in key: key = "/".join(key.split("/")[:4])
                mod_cnt[key] = mod_cnt.get(key,0)+1

        top_tool = sorted(tool_cnt.items(), key=lambda x:x[1], reverse=True)[0][0] if tool_cnt else None
        top_cwe = sorted(cwe_cnt.items(), key=lambda x:x[1], reverse=True)[0][0] if cwe_cnt else None
        top_mod = sorted(mod_cnt.items(), key=lambda x:x[1], reverse=True)[0][0] if mod_cnt else None

        if path == "/api/vsp/dash_kpis":
            out = {
                "ok": True,
                "rid": rid,
                "overall": overall,
                "total_findings": total,
                "total": total,
                "counts_total": counts,
                "counts": counts,
                "security_score": security_score,
                "score": security_score,
                "top_risky_tool": top_tool,
                "top_tool": top_tool,
                "top_impacted_cwe": top_cwe,
                "top_cwe": top_cwe,
                "top_vulnerable_module": top_mod,
                "top_module": top_mod,
            }
        else:
            sev_dist = [{"sev":k,"count":int(counts.get(k,0) or 0)} for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")]
            tool_counts = tool_counts_fn(summ) if callable(tool_counts_fn) else {}
            ch = [{"tool":t, "critical":int(c.get("CRITICAL",0)), "high":int(c.get("HIGH",0))} for t,c in (tool_counts or {}).items() if isinstance(c, dict)]

            trend = trend_fn(base, limit=12) if callable(trend_fn) else [{"rid":rid,"total":total,"overall":overall}]

            top_cwe_pairs = sorted(cwe_cnt.items(), key=lambda x:x[1], reverse=True)[:12]
            out = {
                "ok": True,
                "rid": rid,

                # existing keys (v3)
                "severity_distribution": sev_dist,
                "critical_high_by_tool": ch[:30],
                "top_cwe_exposure": [{"cwe":k,"count":v} for k,v in top_cwe_pairs],
                "findings_trend": trend,

                # compat aliases (to satisfy unknown JS expectations)
                "sev_dist": sev_dist,
                "sev_donut": sev_dist,
                "donut": _vsp__mk_donut(counts),

                "trend": _vsp__mk_trend(trend),
                "trend_series": _vsp__mk_trend(trend),

                "bar_crit_high": _vsp__mk_bar_crit_high(ch[:30]),
                "crit_high_bar": _vsp__mk_bar_crit_high(ch[:30]),

                "top_cwe": _vsp__mk_top_list(top_cwe_pairs, "cwe"),
                "cwe_top": _vsp__mk_top_list(top_cwe_pairs, "cwe"),

                "charts": {
                    "severity": {"distribution": sev_dist, "donut": _vsp__mk_donut(counts)},
                    "trend": {"points": trend, "series": _vsp__mk_trend(trend)},
                    "crit_high_by_tool": {"rows": ch[:30], "bar": _vsp__mk_bar_crit_high(ch[:30])},
                    "top_cwe": {"rows": [{"cwe":k,"count":v} for k,v in top_cwe_pairs], "series": _vsp__mk_top_list(top_cwe_pairs, "cwe")},
                }
            }

        body = _json.dumps(out, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-cache"),
            ("Content-Length", str(len(body))),
        ])
        return [body]

try:
    application.wsgi_app = _VSPDashSchemaCompatMW_V4(application.wsgi_app)
except Exception:
    pass
"""
addon = addon.replace("__MARK__", MARK)
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended:", MARK)
PY

echo "== py_compile =="
python3 -m py_compile "$GW" && echo "[OK] py_compile OK"

echo "== restart clean :8910 (nohup only) =="
rm -f /tmp/vsp_ui_8910.lock || true
PID="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | head -n1)"
[ -n "${PID:-}" ] && kill -9 "$PID" || true

: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

sleep 1.2
echo "== quick verify (charts aliases exist) =="
BASE=http://127.0.0.1:8910
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['run_id'])")"
curl -sS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 500; echo

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_dash_kpis_charts_v3_${TS}"
echo "[BACKUP] ${GW}.bak_dash_kpis_charts_v3_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_KPIS_CHARTS_FROM_REPORTS_V3"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

addon = r"""
# __MARK__
import json as _json
import math as _math
from urllib.parse import parse_qs as _parse_qs, urlencode as _urlencode
from urllib.request import urlopen as _urlopen, Request as _Request

def _vsp__base_url_from_environ(environ):
    scheme = environ.get("wsgi.url_scheme") or "http"
    host = environ.get("HTTP_HOST")
    if not host:
        host = environ.get("SERVER_NAME") or "127.0.0.1"
        port = environ.get("SERVER_PORT")
        if port and port not in ("80","443"):
            host = f"{host}:{port}"
    return f"{scheme}://{host}"

def _vsp__http_json(base, path, timeout=3.0):
    req = _Request(base + path, headers={"Accept":"application/json","X-VSP-Internal":"1"})
    with _urlopen(req, timeout=timeout) as r:
        body = r.read().decode("utf-8", "replace")
    return _json.loads(body)

def _vsp__get_latest_rid(base):
    j = _vsp__http_json(base, "/api/vsp/runs?limit=1", timeout=2.5)
    items = (j or {}).get("items") or []
    if items and isinstance(items[0], dict):
        return items[0].get("run_id") or ""
    return ""

def _vsp__run_file_json(base, rid, name, timeout=5.0):
    q = _urlencode({"rid": rid, "name": name})
    return _vsp__http_json(base, f"/api/vsp/run_file?{q}", timeout=timeout)

def _vsp__extract_findings_list(obj):
    if obj is None:
        return []
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        v = obj.get("items")
        if isinstance(v, list):
            return v
        for k in ("findings","data","results"):
            v = obj.get(k)
            if isinstance(v, list):
                return v
    return []

def _vsp__score_from_total(total):
    try:
        t = max(0, int(total))
        return int(max(0, min(100, round(100 - (_math.log10(t+1)*19)))))
    except Exception:
        return 0

def _vsp__pick_tool(f):
    if not isinstance(f, dict):
        return None
    for k in ("tool","source","scanner","engine","detector"):
        v = f.get(k)
        if isinstance(v, str) and v:
            return v.upper()
    # sometimes nested
    v = f.get("meta") if isinstance(f.get("meta"), dict) else None
    if v:
        for k in ("tool","source","scanner"):
            vv = v.get(k)
            if isinstance(vv, str) and vv:
                return vv.upper()
    return None

def _vsp__pick_cwe(f):
    if not isinstance(f, dict):
        return None
    for k in ("cwe","cwe_id","cweId","cwe_ids","cweIds"):
        v = f.get(k)
        if isinstance(v, str) and "CWE" in v.upper():
            vv = v.upper().replace(" ", "")
            if vv.startswith("CWE-"):
                return vv
            digits = "".join(ch for ch in vv if ch.isdigit())
            return "CWE-" + digits if digits else None
        if isinstance(v, int):
            return f"CWE-{v}"
        if isinstance(v, list):
            for x in v:
                if isinstance(x, int):
                    return f"CWE-{x}"
                if isinstance(x, str) and "CWE" in x.upper():
                    xx = x.upper().replace(" ", "")
                    if xx.startswith("CWE-"):
                        return xx
                    digits = "".join(ch for ch in xx if ch.isdigit())
                    return "CWE-" + digits if digits else None
    return None

def _vsp__pick_path(f):
    if not isinstance(f, dict):
        return None
    for k in ("path","file","filename","location","artifact","resource","uri"):
        v = f.get(k)
        if isinstance(v, str) and v:
            return v
        if isinstance(v, dict):
            for kk in ("path","file","uri"):
                vv = v.get(kk)
                if isinstance(vv, str) and vv:
                    return vv
    # sometimes sarif-ish
    loc = f.get("location")
    if isinstance(loc, dict):
        for kk in ("physicalLocation","artifactLocation"):
            vv = loc.get(kk)
            if isinstance(vv, dict):
                u = vv.get("uri") or vv.get("path")
                if isinstance(u, str) and u:
                    return u
    return None

def _vsp__counts_from_summary(summ):
    counts = (summ or {}).get("counts_total") or {}
    if isinstance(counts, dict):
        return {k:int(counts.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")}
    return {k:0 for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")}

def _vsp__counts_from_unified(fu):
    meta = (fu or {}).get("meta") if isinstance(fu, dict) else None
    c = (meta or {}).get("counts_by_severity") if isinstance(meta, dict) else None
    if isinstance(c, dict):
        return {k:int(c.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE")}
    return None

def _vsp__sum_counts(c):
    return sum(int(c.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"))

def _vsp__tool_counts_from_summary(summ):
    by = (summ or {}).get("by_tool") or {}
    out = {}
    if not isinstance(by, dict):
        return out
    for t, tv in by.items():
        if not isinstance(tv, dict):
            continue
        c = tv.get("counts") if isinstance(tv.get("counts"), dict) else {}
        out[t] = {
            "CRITICAL": int((c or {}).get("CRITICAL",0) or 0),
            "HIGH": int((c or {}).get("HIGH",0) or 0),
            "MEDIUM": int((c or {}).get("MEDIUM",0) or 0),
            "LOW": int((c or {}).get("LOW",0) or 0),
            "INFO": int((c or {}).get("INFO",0) or 0),
            "TRACE": int((c or {}).get("TRACE",0) or 0),
        }
    return out

def _vsp__trend_from_recent_runs(base, limit=12):
    trend = []
    try:
        j = _vsp__http_json(base, f"/api/vsp/runs?limit={limit}", timeout=2.5)
        items = (j or {}).get("items") or []
        for it in items:
            rid = (it or {}).get("run_id") if isinstance(it, dict) else None
            if not rid:
                continue
            try:
                summ = _vsp__run_file_json(base, rid, "reports/run_gate_summary.json", timeout=2.0)
                fu = _vsp__run_file_json(base, rid, "reports/findings_unified.json", timeout=2.0)
                cu = _vsp__counts_from_unified(fu)
                cs = _vsp__counts_from_summary(summ)
                counts = cu if (cu and _vsp__sum_counts(cu) > 0) else cs
                total = _vsp__sum_counts(counts)
                trend.append({"rid": rid, "total": total, "overall": (summ or {}).get("overall") or "UNKNOWN"})
            except Exception:
                continue
    except Exception:
        pass
    return trend

class _VSPDashKpisChartsMW_V3:
    def __init__(self, app):
        base_wsgi = globals().get("_vsp_base_wsgi")
        self.app = base_wsgi(app) if callable(base_wsgi) else getattr(app, "wsgi_app", app)

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path not in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
            return self.app(environ, start_response)

        base = _vsp__base_url_from_environ(environ)
        qs = _parse_qs(environ.get("QUERY_STRING") or "")
        rid = (qs.get("rid") or [""])[0] or _vsp__get_latest_rid(base)

        try:
            summ = _vsp__run_file_json(base, rid, "reports/run_gate_summary.json", timeout=4.0)
        except Exception:
            summ = {}

        try:
            fu = _vsp__run_file_json(base, rid, "reports/findings_unified.json", timeout=4.0)
        except Exception:
            fu = {}

        cs = _vsp__counts_from_summary(summ)
        cu = _vsp__counts_from_unified(fu)
        counts = cu if (cu and _vsp__sum_counts(cu) > 0) else cs
        total = _vsp__sum_counts(counts)

        overall = (summ or {}).get("overall") or "UNKNOWN"
        tool_counts = _vsp__tool_counts_from_summary(summ)

        # derive top tool/cwe/module from unified items (best-effort)
        items = _vsp__extract_findings_list(fu)
        cwe_cnt, mod_cnt, tool_cnt = {}, {}, {}
        for f in (items or [])[:2500]:
            t = _vsp__pick_tool(f)
            if t:
                tool_cnt[t] = tool_cnt.get(t,0)+1
            cwe = _vsp__pick_cwe(f)
            if cwe:
                cwe_cnt[cwe] = cwe_cnt.get(cwe,0)+1
            pth = _vsp__pick_path(f)
            if pth:
                key = pth.split("?")[0]
                if "/" in key:
                    key = "/".join(key.split("/")[:4])
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
                "counts_total": counts,
                "security_score": (summ or {}).get("security_score") or _vsp__score_from_total(total),
                "top_risky_tool": top_tool,
                "top_impacted_cwe": top_cwe,
                "top_vulnerable_module": top_mod,
                "notes": {
                    "counts_source": "findings_unified.meta.counts_by_severity" if (cu and _vsp__sum_counts(cu)>0) else "run_gate_summary.counts_total"
                }
            }
        else:
            sev = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
            # prefer tool counts from summary schema by_tool.*.counts
            cht = []
            for t, c in tool_counts.items():
                cht.append({"tool": t, "critical": int(c.get("CRITICAL",0)), "high": int(c.get("HIGH",0))})
            out = {
                "ok": True,
                "rid": rid,
                "severity_distribution": [{"sev":k,"count":int(counts.get(k,0) or 0)} for k in sev],
                "critical_high_by_tool": cht[:30],
                "top_cwe_exposure": [{"cwe":k,"count":v} for k,v in sorted(cwe_cnt.items(), key=lambda x:x[1], reverse=True)[:12]],
                "findings_trend": _vsp__trend_from_recent_runs(base, limit=12),
            }

        body = _json.dumps(out, ensure_ascii=False).encode("utf-8")
        start_response("200 OK", [
            ("Content-Type","application/json; charset=utf-8"),
            ("Cache-Control","no-cache"),
            ("Content-Length", str(len(body))),
        ])
        return [body]

try:
    application.wsgi_app = _VSPDashKpisChartsMW_V3(application.wsgi_app)
except Exception:
    pass
"""
addon = addon.replace("__MARK__", MARK)
p.write_text(s + "\n" + addon + "\n", encoding="utf-8")
print("[OK] appended V3 dash endpoints MW")
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
echo "== verify V3 dash endpoints =="
BASE=http://127.0.0.1:8910
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['run_id'])")"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/dash_kpis?rid=$RID"   | head -c 600; echo
curl -sS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 600; echo

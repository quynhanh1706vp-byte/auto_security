#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need ss; need awk; need sed; need tail; need curl

GW="wsgi_vsp_ui_gateway.py"
[ -f "$GW" ] || { echo "[ERR] missing $GW"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$GW" "${GW}.bak_dash_kpis_charts_${TS}"
echo "[BACKUP] ${GW}.bak_dash_kpis_charts_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P1_DASH_KPIS_CHARTS_FROM_REPORTS_V1"
if MARK in s:
    print("[OK] already present:", MARK)
    raise SystemExit(0)

addon = f"""

# {MARK}
# Provide /api/vsp/dash_kpis and /api/vsp/dash_charts used by vsp5 UI.
# Robust fallback: derive from existing /api/vsp/runs + /api/vsp/run_file reports artifacts.
import json as _json
import math as _math
from urllib.parse import parse_qs as _parse_qs, urlencode as _urlencode
from urllib.request import urlopen as _urlopen, Request as _Request

def _vsp__base_url_from_environ(environ):
    scheme = environ.get("wsgi.url_scheme") or "http"
    host = environ.get("HTTP_HOST") or environ.get("SERVER_NAME") or "127.0.0.1"
    # If HTTP_HOST missing port, use SERVER_PORT
    if ":" not in host:
        port = environ.get("SERVER_PORT")
        if port:
            host = f"{host}:{port}"
    return f"{scheme}://{host}"

def _vsp__http_json(base, path, timeout=3.0):
    req = _Request(base + path, headers={{"Accept":"application/json","X-VSP-Internal":"1"}})
    with _urlopen(req, timeout=timeout) as r:
        body = r.read().decode("utf-8", "replace")
    return _json.loads(body)

def _vsp__get_latest_rid(base):
    j = _vsp__http_json(base, "/api/vsp/runs?limit=1", timeout=3.0)
    items = (j or {{}}).get("items") or []
    if items and isinstance(items[0], dict):
        return items[0].get("run_id") or ""
    return ""

def _vsp__run_file_json(base, rid, name):
    q = _urlencode({{"rid": rid, "name": name}})
    return _vsp__http_json(base, f"/api/vsp/run_file?{q}", timeout=5.0)

def _vsp__extract_findings_list(obj):
    if obj is None:
        return []
    if isinstance(obj, list):
        return obj
    if isinstance(obj, dict):
        for k in ("items","findings","data","results"):
            v = obj.get(k)
            if isinstance(v, list):
                return v
    return []

def _vsp__pick_cwe(f):
    # returns normalized "CWE-XXX" or None
    if not isinstance(f, dict):
        return None
    for k in ("cwe","cwe_id","cweId","cwe_ids","cweIds"):
        v = f.get(k)
        if isinstance(v, str) and "CWE" in v.upper():
            vv = v.upper().replace(" ", "")
            return vv if vv.startswith("CWE-") else ("CWE-" + "".join(ch for ch in vv if ch.isdigit()))
        if isinstance(v, int):
            return f"CWE-{v}"
        if isinstance(v, list) and v:
            # take first meaningful
            for x in v:
                if isinstance(x, int):
                    return f"CWE-{x}"
                if isinstance(x, str) and "CWE" in x.upper():
                    xx = x.upper().replace(" ", "")
                    return xx if xx.startswith("CWE-") else ("CWE-" + "".join(ch for ch in xx if ch.isdigit()))
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
    return None

def _vsp__score_from_total(total):
    # log-based score: matches your sample (~20 for ~15k findings)
    try:
        t = max(0, int(total))
        return int(max(0, min(100, round(100 - (_math.log10(t+1)*19)))))
    except Exception:
        return 0

class _VSPDashKpisChartsMW:
    def __init__(self, app):
        # ensure WSGI callable (avoid recursion if Flask app was passed)
        base_wsgi = globals().get("_vsp_base_wsgi")
        self.app = base_wsgi(app) if callable(base_wsgi) else getattr(app, "wsgi_app", app)

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        if path not in ("/api/vsp/dash_kpis", "/api/vsp/dash_charts"):
            return self.app(environ, start_response)

        try:
            base = _vsp__base_url_from_environ(environ)
            qs = _parse_qs(environ.get("QUERY_STRING") or "")
            rid = (qs.get("rid") or [""])[0] or _vsp__get_latest_rid(base)

            summ = _vsp__run_file_json(base, rid, "reports/run_gate_summary.json")
            counts = (summ or {{}}).get("counts_total") or {{}}
            total = sum(int(counts.get(k,0) or 0) for k in ("CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"))
            overall = (summ or {{}}).get("overall") or (summ or {{}}).get("gate") or "UNKNOWN"

            # try parse findings for top CWE/module/tool
            findings = []
            top_cwe = None
            top_module = None
            top_tool = None
            try:
                fu = _vsp__run_file_json(base, rid, "reports/findings_unified.json")
                findings = _vsp__extract_findings_list(fu)
            except Exception:
                findings = []

            # tool counts from summary.by_tool if present
            by_tool = (summ or {{}}).get("by_tool") or {{}}
            tool_score = {{}}
            if isinstance(by_tool, dict):
                for tname, tv in by_tool.items():
                    if isinstance(tv, dict):
                        c = int(tv.get("CRITICAL",0) or 0)
                        h = int(tv.get("HIGH",0) or 0)
                        tool_score[tname] = c*10 + h*3
            if tool_score:
                top_tool = sorted(tool_score.items(), key=lambda x: x[1], reverse=True)[0][0]

            # CWE + module from findings (sample up to 5000 to be safe)
            cwe_cnt = {{}}
            mod_cnt = {{}}
            for f in findings[:5000]:
                cwe = _vsp__pick_cwe(f)
                if cwe:
                    cwe_cnt[cwe] = cwe_cnt.get(cwe,0)+1
                pth = _vsp__pick_path(f)
                if pth:
                    # coarse module bucket
                    key = pth.split("?")[0]
                    if "/" in key:
                        key = "/".join(key.split("/")[:4])  # shorten
                    mod_cnt[key] = mod_cnt.get(key,0)+1
            if cwe_cnt:
                top_cwe = sorted(cwe_cnt.items(), key=lambda x: x[1], reverse=True)[0][0]
            if mod_cnt:
                top_module = sorted(mod_cnt.items(), key=lambda x: x[1], reverse=True)[0][0]

            if path == "/api/vsp/dash_kpis":
                out = {{
                    "ok": True,
                    "rid": rid,
                    "overall": overall,
                    "total_findings": total,
                    "counts_total": counts,
                    "security_score": (summ or {{}}).get("security_score") or _vsp__score_from_total(total),
                    "top_risky_tool": top_tool or (summ or {{}}).get("top_tool"),
                    "top_impacted_cwe": top_cwe or (summ or {{}}).get("top_cwe"),
                    "top_vulnerable_module": top_module or (summ or {{}}).get("top_module"),
                }}
            else:
                sev = ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]
                out = {{
                    "ok": True,
                    "rid": rid,
                    "severity_distribution": [{{"sev":k,"count":int(counts.get(k,0) or 0)}} for k in sev],
                    "critical_high_by_tool": [
                        {{"tool":t,"critical":int((by_tool.get(t,{{}}) or {{}}).get("CRITICAL",0) or 0),
                          "high":int((by_tool.get(t,{{}}) or {{}}).get("HIGH",0) or 0)}}
                        for t in (list(by_tool.keys())[:30] if isinstance(by_tool, dict) else [])
                    ],
                    "top_cwe_exposure": [
                        {{"cwe":k,"count":v}} for k,v in sorted(cwe_cnt.items(), key=lambda x: x[1], reverse=True)[:12]
                    ],
                    "findings_trend": [{{"rid": rid, "total": total}}],
                }}

            body = _json.dumps(out, ensure_ascii=False).encode("utf-8")
            start_response("200 OK", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-cache"),
                ("Content-Length", str(len(body))),
            ])
            return [body]
        except Exception as e:
            body = _json.dumps({{"ok": False, "error": str(e)}}).encode("utf-8")
            start_response("200 OK", [
                ("Content-Type","application/json; charset=utf-8"),
                ("Cache-Control","no-cache"),
                ("Content-Length", str(len(body))),
            ])
            return [body]

try:
    application.wsgi_app = _VSPDashKpisChartsMW(application.wsgi_app)
except Exception:
    pass
"""
p.write_text(s + addon, encoding="utf-8")
print("[OK] appended dash_kpis/dash_charts MW")
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
echo "== verify dash endpoints =="
BASE=http://127.0.0.1:8910
RID="$(curl -sS "$BASE/api/vsp/runs?limit=1" | python3 -c "import sys,json;print(json.load(sys.stdin)['items'][0]['run_id'])")"
echo "[RID]=$RID"
curl -sS "$BASE/api/vsp/dash_kpis?rid=$RID"   | head -c 400; echo
curl -sS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 400; echo

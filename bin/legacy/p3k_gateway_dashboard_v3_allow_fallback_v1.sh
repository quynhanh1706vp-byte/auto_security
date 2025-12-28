#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

W="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"
[ -x "$PY" ] || PY="$(command -v python3)"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p3k_${TS}"
echo "[BACKUP] ${W}.bak_p3k_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_P3K_DASHBOARD_V3_ALLOW_FALLBACK_V1"

# idempotent remove old block
s = re.sub(r'(?s)\n?# === '+re.escape(MARK)+r' ===.*?# === END '+re.escape(MARK)+r' ===\n?', "\n", s)

block = r'''
# === __MARK__ ===
import os, json, re
from datetime import datetime
from urllib.parse import parse_qs

_P3K_SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}

def _p3k_norm_sev(x):
    x = (x or "").strip()
    x = x.replace("\t"," ").strip()
    # strip trailing punctuation like "CRITICAL."
    x = re.sub(r'[\.\,;:\s]+$', '', x)
    x = x.upper()
    if x in ("MEDIUMPLUS","MEDIUM_PLUS","MEDIUM+"): return "MEDIUM"
    if not x: return "INFO"
    return x

def _p3k_parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m: return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _p3k_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _p3k_find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid: return None
    for root in _p3k_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    return None

def _p3k_pick_best_rid():
    best = None
    for root in _p3k_roots():
        try:
            for name in os.listdir(root):
                d = os.path.join(root, name)
                if not os.path.isdir(d): 
                    continue
                # consider usable if it has any findings_unified json/csv
                ok = False
                for rel in (
                    "reports/findings_unified.json",
                    "reports/findings_unified_commercial.json",
                    "report/findings_unified.json",
                    "findings_unified.json",
                    "reports/findings_unified.csv",
                    "report/findings_unified.csv",
                    "findings_unified.csv",
                ):
                    fp = os.path.join(d, rel)
                    if os.path.isfile(fp) and (os.path.getsize(fp) > 50):
                        ok = True
                        break
                if not ok:
                    continue
                ts = _p3k_parse_ts(name) or datetime.fromtimestamp(0)
                mt = os.path.getmtime(d) if os.path.exists(d) else 0
                key = (ts, mt)
                if best is None or key > best[0]:
                    best = (key, name)
        except Exception:
            pass
    return best[1] if best else ""

def _p3k_load_items(rid: str, cap=200000):
    rid_dir = _p3k_find_rid_dir(rid)
    if not rid_dir:
        return None, []

    cands = [
        "reports/findings_unified_commercial.json",
        "reports/findings_unified.json",
        "report/findings_unified_commercial.json",
        "report/findings_unified.json",
        "findings_unified_commercial.json",
        "findings_unified.json",
    ]
    for rel in cands:
        fp = os.path.join(rid_dir, rel)
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) < 30:
                continue
        except Exception:
            continue
        try:
            with open(fp, "r", encoding="utf-8", errors="replace") as f:
                j = json.load(f)
            items = None
            for k in ("findings","items","results"):
                v = j.get(k)
                if isinstance(v, list):
                    items = v
                    break
            if items is None:
                items = []
            if len(items) > cap:
                items = items[:cap]
            return {"from": rel, "meta": {"total": j.get("total")}}, items
        except Exception:
            continue

    return None, []

def _p3k_counts(items):
    sev = {}
    tool_ch = {}
    cwe = {}
    for it in items or []:
        s = _p3k_norm_sev((it or {}).get("severity"))
        sev[s] = sev.get(s, 0) + 1

        t = str((it or {}).get("tool") or "UNKNOWN")
        if t not in tool_ch:
            tool_ch[t] = {"tool": t, "CRITICAL": 0, "HIGH": 0}
        if s in ("CRITICAL","HIGH"):
            tool_ch[t][s] = tool_ch[t].get(s, 0) + 1

        cw = (it or {}).get("cwe")
        if cw is None:
            continue
        cw = str(cw).strip()
        if not cw:
            continue
        if cw.isdigit():
            cw = "CWE-" + cw
        if not cw.upper().startswith("CWE-"):
            cw = cw
        cwe[cw] = cwe.get(cw, 0) + 1

    return sev, tool_ch, cwe

def _p3k_top_findings(items, limit=20):
    def key(it):
        return _P3K_SEV_ORDER.get(_p3k_norm_sev((it or {}).get("severity")), 99)
    arr = sorted(list(items or []), key=key)
    out = []
    for it in arr[: max(0, min(limit, 200))]:
        out.append({
            "severity": _p3k_norm_sev((it or {}).get("severity")),
            "title": (it or {}).get("title") or (it or {}).get("message") or "Finding",
            "tool": (it or {}).get("tool") or "UNKNOWN",
            "file": (it or {}).get("file") or (it or {}).get("path") or None,
            "cwe": (it or {}).get("cwe"),
        })
    return out

def _p3k_trend_points(maxn=20):
    pts = []
    cand = []
    for root in _p3k_roots():
        try:
            for name in os.listdir(root):
                d = os.path.join(root, name)
                if not os.path.isdir(d):
                    continue
                ts = _p3k_parse_ts(name)
                if not ts:
                    continue
                cand.append((ts, name))
        except Exception:
            pass
    cand = sorted(cand, key=lambda x: x[0])[-maxn:]
    for ts, rid in cand:
        src, items = _p3k_load_items(rid, cap=200000)
        total = len(items or [])
        pts.append({"label": ts.strftime("%Y-%m-%d %H:%M"), "rid": rid, "total": total})
    return pts

class _P3KDashboardV3FallbackMW:
    def __init__(self, app):
        self.app = app

    def _resp_json(self, start_response, obj, code="200 OK"):
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        start_response(code, [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(data))),
            ("Cache-Control","no-store"),
        ])
        return [data]

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")
        rid = (qs.get("rid") or [""])[0].strip() or _p3k_pick_best_rid()

        # Intercept the exact endpoints that are "not allowed" in P3J2
        if path in (
            "/api/vsp/dashboard_latest_v1",
            "/api/vsp/dashboard_v3",
            "/api/vsp/dashboard_v3_latest",
            "/api/vsp/dashboard_v3_latest_v1",
            "/api/vsp/dashboard_v3_latest_v2",
            "/api/vsp/dashboard_v3_tables",
            "/api/vsp/dashboard_v3_extras_v1",
            "/api/vsp/dashboard_v3_v2",
            "/api/vsp/dashboard_v3_v2",
            "/api/vsp/dashboard_v3_v2",
        ):
            src, items = _p3k_load_items(rid, cap=200000)
            sev, tool_ch, cwe = _p3k_counts(items)
            total = sum(sev.values()) if sev else len(items or [])
            kpis = {
                "total": total,
                "CRITICAL": sev.get("CRITICAL", 0),
                "HIGH": sev.get("HIGH", 0),
                "MEDIUM": sev.get("MEDIUM", 0),
                "LOW": sev.get("LOW", 0),
                "INFO": sev.get("INFO", 0),
                "TRACE": sev.get("TRACE", 0),
            }
            top_cwe = [{"cwe": k, "count": v} for k,v in sorted(cwe.items(), key=lambda kv: kv[1], reverse=True)[:20]]
            by_tool = sorted(tool_ch.values(), key=lambda r: -(r.get("CRITICAL",0)+r.get("HIGH",0)))[:30]
            payload = {
                "ok": True,
                "rid": rid,
                "source": (src or {}),
                "kpis": kpis,
                "charts": {
                    "severity_distribution": [{"severity": k, "count": v} for k,v in sorted(sev.items(), key=lambda kv: _P3K_SEV_ORDER.get(kv[0],99))],
                    "critical_high_by_tool": by_tool,
                    "top_cwe": top_cwe,
                    "trend": _p3k_trend_points(20),
                },
                "tables": {
                    "top_findings": _p3k_top_findings(items, limit=25)
                }
            }
            return self._resp_json(start_response, payload)

        return self.app(environ, start_response)

try:
    application = _P3KDashboardV3FallbackMW(application)
except Exception:
    pass
# === END __MARK__ ===
'''.replace("__MARK__", MARK).lstrip("\n")

s = s.rstrip() + "\n\n" + block + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] installed", MARK)
PY

"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')" >/dev/null

sudo systemctl restart "${SVC}"
sleep 0.6
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,220p'; exit 3; }

echo "== [SMOKE] dashboard_v3_latest now ok =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get(\"rid\",\"\"))')"
curl -fsS "$BASE/api/vsp/dashboard_v3_latest?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"rid=",j.get("rid"),"kpis_total=", (j.get("kpis") or {}).get("total"),"sev_dist=",len(((j.get("charts") or {}).get("severity_distribution") or [])))'
curl -fsS "$BASE/api/vsp/dashboard_v3_tables?rid=$RID" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ok=",j.get("ok"),"top_findings=",len((((j.get("tables") or {}).get("top_findings")) or [])))'
echo "[DONE] p3k_gateway_dashboard_v3_allow_fallback_v1"

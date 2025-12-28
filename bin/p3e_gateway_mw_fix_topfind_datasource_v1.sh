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
cp -f "$W" "${W}.bak_p3e_${TS}"
echo "[BACKUP] ${W}.bak_p3e_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove old P3C middleware block if present
s = re.sub(
    r'(?s)\n?# === VSP_P3C_GATEWAY_MW_RIDBEST_V1 ===.*?# === END VSP_P3C_GATEWAY_MW_RIDBEST_V1 ===\n?',
    "\n",
    s
)

# Also remove any previous P3E block (idempotent)
s = re.sub(
    r'(?s)\n?# === VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===.*?# === END VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===\n?',
    "\n",
    s
)

# Ensure imports exist (top-level safe append is fine)
# (Don't fight existing structure; just append middleware at end.)
mw = r'''
# === VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===
import os, json, re
from datetime import datetime
from urllib.parse import parse_qs

def _p3e_parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _p3e_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _p3e_find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid:
        return None
    for root in _p3e_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    return None

def _p3e_candidate_unified_files(rid_dir: str):
    return [
        os.path.join(rid_dir, "reports/findings_unified.json"),
        os.path.join(rid_dir, "report/findings_unified.json"),
        os.path.join(rid_dir, "findings_unified.json"),
        os.path.join(rid_dir, "reports/findings_unified.sarif"),
        os.path.join(rid_dir, "report/findings_unified.sarif"),
        os.path.join(rid_dir, "findings_unified.sarif"),
        os.path.join(rid_dir, "reports/findings_unified.csv"),
        os.path.join(rid_dir, "report/findings_unified.csv"),
        os.path.join(rid_dir, "findings_unified.csv"),
    ]

def _p3e_load_unified_json(fp: str):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j = json.load(f)
    # normalize list
    items = None
    for k in ("findings", "items", "results"):
        v = j.get(k)
        if isinstance(v, list):
            items = v
            break
    if items is None:
        items = []
    return j, items

def _p3e_load_unified_sarif(fp: str):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j = json.load(f)
    items = []
    for run in (j.get("runs") or []):
        for r in ((run or {}).get("results") or []):
            msg = ((r or {}).get("message") or {}).get("text") or ""
            rule = (r or {}).get("ruleId")
            lvl  = (r or {}).get("level") or ""
            items.append({
                "tool": "SARIF",
                "severity": (lvl or "").upper() or "INFO",
                "title": msg[:200] if isinstance(msg,str) else "Finding",
                "ruleId": rule,
                "file": (((r or {}).get("locations") or [{}])[0].get("physicalLocation") or {}).get("artifactLocation", {}).get("uri"),
            })
    return j, items

def _p3e_pick_best_rid():
    best = None
    for root in _p3e_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."):
                    continue
                d = os.path.join(root, name)
                if not os.path.isdir(d):
                    continue
                # usable = has any unified file non-trivial
                usable = False
                for fp in _p3e_candidate_unified_files(d):
                    if os.path.isfile(fp):
                        try:
                            if os.path.getsize(fp) > 50:
                                usable = True
                                break
                        except Exception:
                            pass
                if not usable:
                    continue
                ts = _p3e_parse_ts(name) or datetime.fromtimestamp(0)
                try:
                    mt = os.path.getmtime(d)
                except Exception:
                    mt = 0
                key = (ts, mt)
                if best is None or key > best[0]:
                    best = (key, name)
        except Exception:
            pass
    return best[1] if best else ""

def _p3e_load_findings_for_rid(rid: str):
    rid_dir = _p3e_find_rid_dir(rid)
    if not rid_dir:
        return None, []
    # prefer JSON then SARIF then CSV(header-only not helpful)
    for fp in _p3e_candidate_unified_files(rid_dir):
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) <= 30:
                continue
        except Exception:
            continue

        try:
            if fp.endswith(".json"):
                j, items = _p3e_load_unified_json(fp)
                return {"from": os.path.relpath(fp, rid_dir), "meta": j}, items
            if fp.endswith(".sarif"):
                j, items = _p3e_load_unified_sarif(fp)
                return {"from": os.path.relpath(fp, rid_dir), "meta": {"sarif": True}}, items
            if fp.endswith(".csv"):
                # minimal csv support: return empty items, but mark source
                return {"from": os.path.relpath(fp, rid_dir), "meta": {"csv": True}}, []
        except Exception:
            continue
    return None, []

_SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"LOW":3,"INFO":4,"TRACE":5}

def _sev_key(x):
    s = (x or {}).get("severity") or ""
    s = str(s).upper()
    return _SEV_ORDER.get(s, 99)

class _P3ECommercialDataMiddleware:
    def __init__(self, app):
        self.app = app

    def _json(self, start_response, obj, code="200 OK"):
        data = (json.dumps(obj, ensure_ascii=False) + "\n").encode("utf-8")
        headers = [
            ("Content-Type","application/json; charset=utf-8"),
            ("Content-Length", str(len(data))),
            ("Cache-Control","no-store"),
        ]
        start_response(code, headers)
        return [data]

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        qs = parse_qs(environ.get("QUERY_STRING") or "")

        if path in ("/api/vsp/rid_best", "/api/vsp/rid_latest"):
            rid = _p3e_pick_best_rid()
            body = {"ok": True, "rid": rid}
            if path.endswith("/rid_latest"):
                body["mode"] = "best_usable"
            return self._json(start_response, body)

        if path == "/api/vsp/top_findings_v2":
            rid = (qs.get("rid") or [""])[0] or _p3e_pick_best_rid()
            try:
                limit = int((qs.get("limit") or ["10"])[0])
            except Exception:
                limit = 10
            src, items = _p3e_load_findings_for_rid(rid)
            if not items:
                return self._json(start_response, {"ok": False, "rid": rid, "total": 0, "items": [], "err": "no findings"}, "200 OK")
            items_sorted = sorted(items, key=_sev_key)
            out = items_sorted[: max(0, min(limit, 200)) ]
            return self._json(start_response, {
                "ok": True,
                "rid": rid,
                "total": len(items),
                "items": out,
                "from": (src or {}).get("from"),
            })

        if path == "/api/vsp/datasource":
            mode = (qs.get("mode") or [""])[0]
            if mode == "dashboard":
                rid = (qs.get("rid") or [""])[0] or _p3e_pick_best_rid()
                src, items = _p3e_load_findings_for_rid(rid)
                if not items:
                    return self._json(start_response, {"ok": False, "rid": rid, "runs": [], "findings": [], "err": "no findings"}, "200 OK")
                # Minimal run stub for dashboard
                run = {"rid": rid, "label": rid, "total": len(items)}
                return self._json(start_response, {
                    "ok": True,
                    "rid": rid,
                    "runs": [run],
                    "findings": items,
                    "from": (src or {}).get("from"),
                })

        return self.app(environ, start_response)

# Wrap only if 'application' exists
try:
    _orig_application = application
except Exception:
    _orig_application = None

if _orig_application is not None:
    application = _P3ECommercialDataMiddleware(_orig_application)
# === END VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===
'''.lstrip("\n")

s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] wrote middleware P3E ->", p)
PY

echo "== [1] import check =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')"

echo "== [2] restart =="
sudo systemctl restart "${SVC}"
sleep 0.6
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,180p'; exit 3; }

echo "== [3] smoke =="
curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest:", j.get("rid"), "mode:", j.get("mode"))'
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"

curl -fsS "$BASE/api/vsp/top_findings_v2?limit=10&rid=$RID" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("top_find ok=",j.get("ok"),"total=",j.get("total"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'

curl -fsS "$BASE/api/vsp/datasource?mode=dashboard&rid=$RID" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ds ok=",j.get("ok"),"runs=",len(j.get("runs") or []),"findings=",len(j.get("findings") or []),"from=",j.get("from"))'

echo "[DONE] p3e_gateway_mw_fix_topfind_datasource_v1"

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
cp -f "$W" "${W}.bak_p3e2_${TS}"
echo "[BACKUP] ${W}.bak_p3e2_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove old P3E block (idempotent)
s = re.sub(
    r'(?s)\n?# === VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===.*?# === END VSP_P3E_GATEWAY_MW_COMMERCIAL_DATA_V1 ===\n?',
    "\n",
    s
)

mw = r'''
# === VSP_P3E2_GATEWAY_MW_COMMERCIAL_DATA_V1 ===
import os, json, re, csv, io
from datetime import datetime
from urllib.parse import parse_qs

def _p3e2_parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _p3e2_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _p3e2_find_rid_dir(rid: str):
    rid = (rid or "").strip()
    if not rid:
        return None
    for root in _p3e2_roots():
        d = os.path.join(root, rid)
        if os.path.isdir(d):
            return d
    return None

def _p3e2_candidate_unified_files(rid_dir: str):
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

def _p3e2_json_nonempty(fp: str) -> bool:
    try:
        if os.path.getsize(fp) < 20:
            return False
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        for k in ("findings","items","results"):
            v = j.get(k)
            if isinstance(v, list) and len(v) > 0:
                return True
        t = j.get("total")
        return isinstance(t, int) and t > 0
    except Exception:
        return False

def _p3e2_sarif_nonempty(fp: str) -> bool:
    try:
        if os.path.getsize(fp) < 40:
            return False
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        for run in (j.get("runs") or []):
            res = (run or {}).get("results") or []
            if isinstance(res, list) and len(res) > 0:
                return True
        return False
    except Exception:
        return False

def _p3e2_csv_nonempty(fp: str) -> bool:
    try:
        if os.path.getsize(fp) < 30:
            return False
        # count first 3 lines; must be >=2 lines
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            lines = []
            for _ in range(3):
                line = f.readline()
                if not line:
                    break
                lines.append(line)
        return len(lines) >= 2 and any(x.strip() for x in lines[1:])
    except Exception:
        return False

def _p3e2_is_usable_dir(d: str) -> bool:
    for fp in _p3e2_candidate_unified_files(d):
        if not os.path.isfile(fp):
            continue
        if fp.endswith(".json") and _p3e2_json_nonempty(fp):
            return True
        if fp.endswith(".sarif") and _p3e2_sarif_nonempty(fp):
            return True
        if fp.endswith(".csv") and _p3e2_csv_nonempty(fp):
            return True
    return False

def _p3e2_pick_best_rid():
    best = None
    for root in _p3e2_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."):
                    continue
                d = os.path.join(root, name)
                if not os.path.isdir(d):
                    continue
                if not _p3e2_is_usable_dir(d):
                    continue
                ts = _p3e2_parse_ts(name) or datetime.fromtimestamp(0)
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

def _p3e2_load_unified_json(fp: str):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j = json.load(f)
    items = []
    for k in ("findings","items","results"):
        v = j.get(k)
        if isinstance(v, list):
            items = v
            break
    return j, items

def _p3e2_load_unified_sarif(fp: str):
    with open(fp, "r", encoding="utf-8", errors="replace") as f:
        j = json.load(f)
    items = []
    for run in (j.get("runs") or []):
        for r in ((run or {}).get("results") or []):
            msg = ((r or {}).get("message") or {}).get("text") or ""
            lvl = (r or {}).get("level") or ""
            items.append({
                "tool": "SARIF",
                "severity": str(lvl).upper() if lvl else "INFO",
                "title": msg[:200] if isinstance(msg, str) else "Finding",
                "ruleId": (r or {}).get("ruleId"),
                "file": ((((r or {}).get("locations") or [{}])[0].get("physicalLocation") or {}).get("artifactLocation") or {}).get("uri"),
            })
    return j, items

def _p3e2_load_unified_csv(fp: str, cap: int = 10000):
    # Expect columns similar to findings_unified.csv (tool,severity,title,cwe,file,line,...)
    items = []
    with open(fp, "r", encoding="utf-8", errors="replace", newline="") as f:
        reader = csv.DictReader(f)
        for i, row in enumerate(reader):
            if i >= cap:
                break
            items.append({
                "tool": row.get("tool") or row.get("Tool") or "CSV",
                "severity": (row.get("severity") or row.get("Severity") or "INFO").upper(),
                "title": row.get("title") or row.get("Title") or row.get("message") or "Finding",
                "cwe": row.get("cwe") or row.get("CWE"),
                "file": row.get("file") or row.get("File") or row.get("path"),
                "line": row.get("line") or row.get("Line"),
            })
    return {"csv": True}, items

def _p3e2_load_findings_for_rid(rid: str):
    rid_dir = _p3e2_find_rid_dir(rid)
    if not rid_dir:
        return None, []
    for fp in _p3e2_candidate_unified_files(rid_dir):
        if not os.path.isfile(fp):
            continue
        try:
            if os.path.getsize(fp) <= 20:
                continue
        except Exception:
            continue
        try:
            if fp.endswith(".json") and _p3e2_json_nonempty(fp):
                j, items = _p3e2_load_unified_json(fp)
                return {"from": os.path.relpath(fp, rid_dir), "meta": j}, items
            if fp.endswith(".sarif") and _p3e2_sarif_nonempty(fp):
                _, items = _p3e2_load_unified_sarif(fp)
                return {"from": os.path.relpath(fp, rid_dir), "meta": {"sarif": True}}, items
            if fp.endswith(".csv") and _p3e2_csv_nonempty(fp):
                meta, items = _p3e2_load_unified_csv(fp)
                return {"from": os.path.relpath(fp, rid_dir), "meta": meta}, items
        except Exception:
            continue
    return None, []

_SEV_ORDER = {"CRITICAL":0,"HIGH":1,"MEDIUM":2,"MEDIUM+":2,"LOW":3,"INFO":4,"TRACE":5}

def _p3e2_sev_key(x):
    s = (x or {}).get("severity") or ""
    s = str(s).upper()
    return _SEV_ORDER.get(s, 99)

class _P3E2CommercialDataMiddleware:
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
            rid = _p3e2_pick_best_rid()
            body = {"ok": True, "rid": rid}
            if path.endswith("/rid_latest"):
                body["mode"] = "best_usable"
            return self._json(start_response, body)

        if path == "/api/vsp/top_findings_v2":
            rid = (qs.get("rid") or [""])[0] or _p3e2_pick_best_rid()
            try:
                limit = int((qs.get("limit") or ["10"])[0])
            except Exception:
                limit = 10
            src, items = _p3e2_load_findings_for_rid(rid)
            if not items:
                return self._json(start_response, {"ok": False, "rid": rid, "total": 0, "items": [], "err": "no findings"}, "200 OK")
            items_sorted = sorted(items, key=_p3e2_sev_key)
            out = items_sorted[: max(0, min(limit, 200)) ]
            return self._json(start_response, {"ok": True, "rid": rid, "total": len(items), "items": out, "from": (src or {}).get("from")})

        if path == "/api/vsp/datasource":
            mode = (qs.get("mode") or [""])[0]
            if mode == "dashboard":
                rid = (qs.get("rid") or [""])[0] or _p3e2_pick_best_rid()
                src, items = _p3e2_load_findings_for_rid(rid)
                if not items:
                    return self._json(start_response, {"ok": False, "rid": rid, "runs": [], "findings": [], "err": "no findings"}, "200 OK")
                run = {"rid": rid, "label": rid, "total": len(items)}
                return self._json(start_response, {"ok": True, "rid": rid, "runs": [run], "findings": items, "from": (src or {}).get("from")})

        return self.app(environ, start_response)

try:
    _orig_application = application
except Exception:
    _orig_application = None

if _orig_application is not None:
    application = _P3E2CommercialDataMiddleware(_orig_application)
# === END VSP_P3E2_GATEWAY_MW_COMMERCIAL_DATA_V1 ===
'''.lstrip("\n")

s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] installed P3E2 middleware")
PY

echo "== [1] import check =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')"

echo "== [2] restart =="
sudo systemctl restart "${SVC}"
sleep 0.6
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,220p'; exit 3; }

echo "== [3] smoke =="
curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest:", j.get("rid"), "mode:", j.get("mode"))'
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"

curl -fsS "$BASE/api/vsp/top_findings_v2?limit=10&rid=$RID" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("top_find ok=",j.get("ok"),"total=",j.get("total"),"items_len=",len(j.get("items") or []),"from=",j.get("from"))'

curl -fsS "$BASE/api/vsp/datasource?mode=dashboard&rid=$RID" \
  | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("ds ok=",j.get("ok"),"runs=",len(j.get("runs") or []),"findings=",len(j.get("findings") or []),"from=",j.get("from"))'

echo "[DONE] p3e2_gateway_mw_fix_pickbest_nonempty_csv_v1"

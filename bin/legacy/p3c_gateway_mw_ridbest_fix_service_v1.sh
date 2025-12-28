#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need curl
[ -x "$PY" ] || PY="$(command -v python3)"

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

echo "== [0] rollback gateway to last bak_ridbest_gateway_* =="
bakW="$(ls -1t ${W}.bak_ridbest_gateway_* 2>/dev/null | head -n 1 || true)"
if [ -z "${bakW:-}" ]; then
  echo "[ERR] cannot find ${W}.bak_ridbest_gateway_*"
  exit 2
fi
cp -f "$bakW" "$W"
echo "[RESTORE] $bakW -> $W"

echo "== [1] patch gateway with WSGI middleware (no Flask app needed) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$W" "${W}.bak_p3c_mw_${TS}"
echo "[BACKUP] ${W}.bak_p3c_mw_${TS}"

"$PY" - <<'PY'
from pathlib import Path
import re

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P3C_GATEWAY_MW_RIDBEST_V1"
if MARK in s:
    print("[OK] already patched", MARK)
    raise SystemExit(0)

mw = r'''
# === VSP_P3C_GATEWAY_MW_RIDBEST_V1 ===
import os, json
from datetime import datetime

def _p3c_parse_ts(name: str):
    m = re.search(r'(\d{8})_(\d{6})', name or "")
    if not m:
        return None
    try:
        return datetime.strptime(m.group(1)+m.group(2), "%Y%m%d%H%M%S")
    except Exception:
        return None

def _p3c_roots():
    roots = [
        "/home/test/Data/SECURITY_BUNDLE/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/out",
        "/home/test/Data/SECURITY_BUNDLE/ui/out_ci",
        "/home/test/Data/SECURITY_BUNDLE/ui/out",
    ]
    return [r for r in roots if os.path.isdir(r)]

def _p3c_is_json_nonempty(fp: str) -> bool:
    try:
        if os.path.getsize(fp) < 30:
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
        # if cannot parse, still treat large json as "maybe usable"
        try:
            return os.path.getsize(fp) > 500
        except Exception:
            return False

def _p3c_is_sarif_nonempty(fp: str) -> bool:
    try:
        if os.path.getsize(fp) < 50:
            return False
        with open(fp, "r", encoding="utf-8", errors="replace") as f:
            j = json.load(f)
        runs = j.get("runs") or []
        for r in runs:
            res = (r or {}).get("results") or []
            if isinstance(res, list) and len(res) > 0:
                return True
        return False
    except Exception:
        try:
            return os.path.getsize(fp) > 800
        except Exception:
            return False

def _p3c_is_usable_dir(d: str) -> bool:
    cands = [
        "findings_unified.json","reports/findings_unified.json","report/findings_unified.json",
        "findings_unified.sarif","reports/findings_unified.sarif","report/findings_unified.sarif",
        "findings_unified.csv","reports/findings_unified.csv","report/findings_unified.csv",
    ]
    for rel in cands:
        fp = os.path.join(d, rel)
        if not os.path.isfile(fp):
            continue
        if fp.endswith(".json") and _p3c_is_json_nonempty(fp):
            return True
        if fp.endswith(".sarif") and _p3c_is_sarif_nonempty(fp):
            return True
        if fp.endswith(".csv"):
            try:
                if os.path.getsize(fp) > 80:
                    return True
            except Exception:
                pass
    return False

def _p3c_pick_best_rid():
    best = None
    for root in _p3c_roots():
        try:
            for name in os.listdir(root):
                if name.startswith("."):
                    continue
                d = os.path.join(root, name)
                if not os.path.isdir(d):
                    continue
                if not _p3c_is_usable_dir(d):
                    continue
                ts = _p3c_parse_ts(name) or datetime.fromtimestamp(0)
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

class _P3CRidMiddleware:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = environ.get("PATH_INFO","") or ""
        if path in ("/api/vsp/rid_best", "/api/vsp/rid_latest"):
            rid = _p3c_pick_best_rid()
            body = {
                "ok": True,
                "rid": rid,
            }
            if path.endswith("/rid_latest"):
                body["mode"] = "best_usable"
            data = (json.dumps(body, ensure_ascii=False) + "\n").encode("utf-8")
            headers = [
                ("Content-Type","application/json; charset=utf-8"),
                ("Content-Length", str(len(data))),
                ("Cache-Control","no-store"),
            ]
            start_response("200 OK", headers)
            return [data]
        return self.app(environ, start_response)

# Wrap only if 'application' exists
try:
    _orig_application = application
except Exception:
    _orig_application = None

if _orig_application is not None:
    application = _P3CRidMiddleware(_orig_application)
# === END VSP_P3C_GATEWAY_MW_RIDBEST_V1 ===
'''.lstrip("\n")

# Ensure we have 'import re' available for middleware helper
# If file doesn't already import re at top-level, add it near top imports.
if not re.search(r'(?m)^import\s+re\b', s) and not re.search(r'(?m)^from\s+re\b', s):
    # insert after initial import block
    lines = s.splitlines(True)
    i = 0
    while i < len(lines) and (lines[i].startswith("#!") or re.match(r'^\s*#.*$', lines[i]) or re.match(r'^\s*$', lines[i])):
        i += 1
    while i < len(lines) and re.match(r'^(import|from)\s+\S+', lines[i]):
        i += 1
    lines.insert(i, "import re\n")
    s = "".join(lines)

# append middleware at end
s = s.rstrip() + "\n\n" + mw + "\n"
p.write_text(s, encoding="utf-8")
print("[OK] appended middleware:", MARK)
PY

echo "== [2] quick import check (gateway must import) =="
"$PY" -c "import wsgi_vsp_ui_gateway; print('IMPORT_OK')"

echo "== [3] restart service =="
sudo systemctl restart "${SVC}"
sudo systemctl is-active --quiet "${SVC}" && echo "[OK] service active" || { echo "[ERR] service not active"; sudo systemctl status "${SVC}" --no-pager | sed -n '1,160p'; exit 4; }

echo "== [4] smoke rid_latest / rid_best =="
curl -fsS "$BASE/api/vsp/rid_best"   | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_best:", j.get("rid"))'
curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("rid_latest:", j.get("rid"), "mode:", j.get("mode"))'

echo "== [5] smoke run_file_allow findings_unified.json (using rid_latest) =="
RID_L="$(curl -fsS "$BASE/api/vsp/rid_latest" | "$PY" -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
if [ -n "$RID_L" ]; then
  curl -fsS "$BASE/api/vsp/run_file_allow?rid=$RID_L&path=findings_unified.json&limit=5" \
    | "$PY" -c 'import sys,json; j=json.load(sys.stdin); print("from=",j.get("from"),"len=",len(j.get("findings") or []))'
fi

echo "[DONE] p3c_gateway_mw_ridbest_fix_service_v1"

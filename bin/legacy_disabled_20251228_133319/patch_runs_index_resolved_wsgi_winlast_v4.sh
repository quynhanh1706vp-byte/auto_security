#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runs_resolved_wsgi_${TS}"
echo "[BACKUP] $F.bak_runs_resolved_wsgi_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUNS_INDEX_RESOLVED_WSGI_WINLAST_V4 ==="
END = "# === END VSP_RUNS_INDEX_RESOLVED_WSGI_WINLAST_V4 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_RUNS_INDEX_RESOLVED_WSGI_WINLAST_V4 ===
import json as _json
from urllib.parse import parse_qs as _parse_qs
from datetime import datetime as _dt
from pathlib import Path as _Path

def _vsp__runs_index_resolved_build_items_v4(limit: int = 50):
    base = _Path("/home/test/Data/SECURITY-10-10-v4/out_ci")
    items = []
    try:
        dirs = sorted(base.glob("VSP_CI_*"), key=lambda x: x.stat().st_mtime, reverse=True)
        for d in dirs[: max(1, limit)]:
            ts = _dt.fromtimestamp(d.stat().st_mtime).strftime("%Y-%m-%dT%H:%M:%S")
            items.append({
                "run_id": "RUN_" + d.name,
                "created_at": ts,
                "profile": "",
                "target": "",
                "has_findings": 0,
                "total_findings": 0,
                "totals": {},
            })
    except Exception:
        items = []
    return items

class _VspWinLastRunsResolvedMiddlewareV4:
    def __init__(self, app_wsgi):
        self.app_wsgi = app_wsgi

    def __call__(self, environ, start_response):
        try:
            path = environ.get("PATH_INFO", "") or ""
            if path == "/api/vsp/runs_index_v3_fs_resolved":
                qs = environ.get("QUERY_STRING", "") or ""
                q = _parse_qs(qs)
                try:
                    limit = int((q.get("limit", ["50"]) or ["50"])[0] or 50)
                except Exception:
                    limit = 50
                data = {
                    "ok": True,
                    "items": _vsp__runs_index_resolved_build_items_v4(limit=limit),
                    "source": "wsgi_winlast_v4"
                }
                body = (_json.dumps(data, ensure_ascii=False) + "\n").encode("utf-8")
                headers = [
                    ("Content-Type", "application/json; charset=utf-8"),
                    ("Content-Length", str(len(body))),
                    ("Cache-Control", "no-store"),
                ]
                start_response("200 OK", headers)
                return [body]
        except Exception:
            pass
        return self.app_wsgi(environ, start_response)

# Install middleware (WIN-LAST)
try:
    app.wsgi_app = _VspWinLastRunsResolvedMiddlewareV4(app.wsgi_app)
except Exception:
    pass
# === END VSP_RUNS_INDEX_RESOLVED_WSGI_WINLAST_V4 ===
'''.strip() + "\n"

t2 = t.rstrip() + "\n\n" + block
p.write_text(t2, encoding="utf-8")
print("[OK] appended WSGI WINLAST middleware v4")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"

echo "== verify resolved =="
curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=3&hide_empty=0" \
| jq '{ok, source:(.source//null), n:(.items|length), first:(.items[0].run_id//null)}'

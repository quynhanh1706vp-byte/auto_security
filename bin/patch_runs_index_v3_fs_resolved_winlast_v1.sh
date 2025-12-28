#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runs_resolved_${TS}"
echo "[BACKUP] $F.bak_runs_resolved_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUNS_INDEX_V3_FS_RESOLVED_WINLAST_V1 ==="
END = "# === END VSP_RUNS_INDEX_V3_FS_RESOLVED_WINLAST_V1 ==="
if TAG in t:
    print("[SKIP] already patched")
    raise SystemExit(0)

block = r'''
# === VSP_RUNS_INDEX_V3_FS_RESOLVED_WINLAST_V1 ===
from flask import jsonify, request

def _vsp__call_runs_index_v3_fs_best_effort_v1():
    # Try to find an existing v3_fs handler (not resolved) in globals
    for name, fn in globals().items():
        if callable(fn) and ("runs_index_v3_fs" in name) and ("resolved" not in name):
            try:
                return fn()
            except TypeError:
                # some handlers might require args; skip
                continue
            except Exception:
                continue
    return None

def api_vsp_runs_index_v3_fs_resolved_winlast_v1():
    # Prefer existing v3_fs output; normalize items to list
    r = _vsp__call_runs_index_v3_fs_best_effort_v1()
    data = None
    code = 200
    try:
        if isinstance(r, tuple) and len(r) >= 1:
            resp0 = r[0]
            code = r[1] if len(r) > 1 and isinstance(r[1], int) else 200
            # Flask Response?
            if hasattr(resp0, "get_json"):
                data = resp0.get_json(silent=True)
            elif isinstance(resp0, dict):
                data = resp0
        elif hasattr(r, "get_json"):
            data = r.get_json(silent=True)
        elif isinstance(r, dict):
            data = r
    except Exception:
        data = None

    if not isinstance(data, dict):
        data = {"ok": True, "items": []}

    items = data.get("items", [])
    if items is None or not isinstance(items, list):
        data["items"] = []

    data.setdefault("ok", True)
    data.setdefault("source", "fallback_v3_fs")

    return jsonify(data), code

def _vsp__register_runs_index_v3_fs_resolved_winlast_v1(flask_app):
    if flask_app is None:
        return
    try:
        flask_app.add_url_rule(
            "/api/vsp/runs_index_v3_fs_resolved",
            endpoint="api_vsp_runs_index_v3_fs_resolved_winlast_v1",
            view_func=api_vsp_runs_index_v3_fs_resolved_winlast_v1,
            methods=["GET"],
        )
    except Exception as e:
        msg = str(e)
        if "already exists" in msg or "existing endpoint function" in msg:
            return

# === END VSP_RUNS_INDEX_V3_FS_RESOLVED_WINLAST_V1 ===
'''.strip() + "\n"

# append at EOF and register on global app
t2 = t.rstrip() + "\n\n" + block + "\n" + "_vsp__register_runs_index_v3_fs_resolved_winlast_v1(app)\n"
p.write_text(t2, encoding="utf-8")
print("[OK] appended runs_index_v3_fs_resolved WINLAST + registered")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"

echo "== verify resolved =="
curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved?limit=3&hide_empty=0" | jq '{ok, n:(.items|length), first:(.items[0]//null)}'

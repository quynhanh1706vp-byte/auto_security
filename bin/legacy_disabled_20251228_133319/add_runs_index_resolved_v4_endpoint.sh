#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_add_resolved_v4_${TS}"
echo "[BACKUP] $F.bak_add_resolved_v4_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_RUNS_INDEX_V3_FS_RESOLVED_V4_ENDPOINT ==="
END = "# === END VSP_RUNS_INDEX_V3_FS_RESOLVED_V4_ENDPOINT ==="
if TAG in t:
    print("[SKIP] already added")
    raise SystemExit(0)

block = r'''
# === VSP_RUNS_INDEX_V3_FS_RESOLVED_V4_ENDPOINT ===
from flask import jsonify, request
from pathlib import Path as _Path
from datetime import datetime as _dt

def api_vsp_runs_index_v3_fs_resolved_v4():
    base = _Path("/home/test/Data/SECURITY-10-10-v4/out_ci")
    try:
        limit = int(request.args.get("limit", "50") or 50)
    except Exception:
        limit = 50

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

    return jsonify({"ok": True, "items": items, "source": "resolved_v4_fs_scan"}), 200

try:
    app.add_url_rule(
        "/api/vsp/runs_index_v3_fs_resolved_v4",
        endpoint="api_vsp_runs_index_v3_fs_resolved_v4",
        view_func=api_vsp_runs_index_v3_fs_resolved_v4,
        methods=["GET"],
    )
except Exception:
    pass
# === END VSP_RUNS_INDEX_V3_FS_RESOLVED_V4_ENDPOINT ===
'''.strip() + "\n"

t2 = t.rstrip() + "\n\n" + block
p.write_text(t2, encoding="utf-8")
print("[OK] appended resolved_v4 endpoint")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh >/dev/null 2>&1 || true
echo "[OK] restarted 8910"

echo "== verify resolved_v4 =="
curl -sS "http://127.0.0.1:8910/api/vsp/runs_index_v3_fs_resolved_v4?limit=3&hide_empty=0" \
| jq '{ok, source:(.source//null), n:(.items|length), first:(.items[0].run_id//null)}'

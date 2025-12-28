#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
APP="vsp_demo_app.py"
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_latest_rid_fix_${TS}"
echo "[BACKUP] $APP.bak_latest_rid_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

# Replace the fragile line that indexes items[0]["run_id"]
# with robust extraction: run_id = item.get("run_id") or item.get("rid") or item.get("id")
pat = r'return\s+jsonify\(\{"ok":\s*True,\s*"rid":\s*items\[0\]\["run_id"\],\s*"ci_run_dir":\s*items\[0\]\["ci_run_dir"\]\}\),\s*200'
rep = (
    'item = items[0] if items else {}\n'
    '    rid = item.get("run_id") or item.get("rid") or item.get("id") or item.get("run")\n'
    '    ci = item.get("ci_run_dir") or item.get("run_dir") or item.get("dir")\n'
    '    return jsonify({"ok": True, "rid": rid, "ci_run_dir": ci}), 200'
)

s2, n = re.subn(pat, rep, s, count=1)
if n == 0:
    print("[WARN] pattern not found; patch not applied (show nearby manual fix around api_vsp_latest_rid_v1).")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] patched latest_rid_v1: run_id/rid fallback")
PY

python3 -m py_compile "$APP" && echo "[OK] py_compile OK"
echo "== DONE =="
echo "[NEXT] restart 8910"

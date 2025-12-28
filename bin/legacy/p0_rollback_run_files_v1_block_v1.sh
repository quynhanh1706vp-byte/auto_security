#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_rollback_run_files_${TS}"
echo "[BACKUP] ${APP}.bak_rollback_run_files_${TS}"

python3 - "$APP" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

a = "# --- VSP_P0_API_RUN_FILES_V1_WHITELIST ---"
b = "# --- /VSP_P0_API_RUN_FILES_V1_WHITELIST ---"
if a not in s or b not in s:
    print("[WARN] markers not found; nothing removed")
    raise SystemExit(0)

pat = re.compile(re.escape(a) + r"[\s\S]*?" + re.escape(b) + r"\n?", re.M)
s2, n = pat.subn("", s, count=1)
if n == 0:
    print("[WARN] failed to remove block")
else:
    p.write_text(s2, encoding="utf-8")
    print("[OK] removed run_files_v1 block")
PY

python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

sudo systemctl reset-failed "$SVC" || true
sudo systemctl restart "$SVC" || true

echo "== status (short) =="
systemctl status "$SVC" --no-pager -l | head -n 35 || true

echo "== smoke (if up) =="
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 120 && echo || true
curl -fsS "$BASE/runs" | head -c 120 && echo || true

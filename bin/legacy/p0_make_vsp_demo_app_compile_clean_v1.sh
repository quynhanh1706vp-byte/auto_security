#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
APP="vsp_demo_app.py"
PY="/home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/python3"
[ -x "$PY" ] || PY="$(command -v python3)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need tail; need curl

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_compile_clean_${TS}"
echo "[BACKUP] ${APP}.bak_compile_clean_${TS}"

echo "== [1] Remove broken CIO V3 register fragments from vsp_demo_app.py =="
"$PY" - <<'PY'
from pathlib import Path
import re, py_compile

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

# Remove any injected register blocks / stray lines that cause invalid syntax
patterns = [
    # Marker block (remove marker line + up to next 'pass' line)
    r'(?ms)^\s*#\s*===\s*CIO\s*V3\s*REGISTER\s*\(AUTO\)\s*===\s*\n.*?^\s*pass\s*\n',
    # Any stray top-level lines (safe to remove)
    r'(?m)^\s*from\s+vsp_api_v3\s+import\s+register_v3\s+as\s+_register_v3\s*$\n?',
    r'(?m)^\s*_register_v3\s*\(\s*app\s*\)\s*$\n?',
    r'(?m)^\s*try\s*:\s*$\n(?:.*\n){0,6}^\s*pass\s*$\n?',  # very conservative try/pass blocks (in case only injected one)
]

orig = s
# Apply only the high-confidence removals:
s = re.sub(patterns[0], "", s)
s = re.sub(patterns[1], "", s)
s = re.sub(patterns[2], "", s)

# Also remove a tiny try-register snippet if it references _register_v3 (high confidence)
s = re.sub(r'(?ms)^\s*try\s*:\s*\n\s*_register_v3\s*\(\s*app\s*\)\s*\n\s*except\s+Exception\s*:\s*\n\s*pass\s*\n', "", s)

if s != orig:
    p.write_text(s, encoding="utf-8")
    print("[OK] cleaned injected v3-register fragments")
else:
    print("[OK] nothing to clean (already clean)")

# Compile check
py_compile.compile(str(p), doraise=True)
print("[OK] py_compile ok")
PY

echo "== [2] If still failing, auto-restore most recent backup that compiles =="
set +e
"$PY" -m py_compile "$APP" >/dev/null 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[WARN] still not compilable; searching backups..."
  for f in $(ls -1t vsp_demo_app.py.bak_* 2>/dev/null | head -n 40); do
    set +e
    "$PY" -m py_compile "$f" >/dev/null 2>&1
    ok=$?
    set -e
    if [ "$ok" -eq 0 ]; then
      cp -f "$f" "$APP"
      echo "[RESTORE] $f -> $APP (compilable)"
      break
    fi
  done
  "$PY" -m py_compile "$APP" && echo "[OK] final py_compile ok" || { echo "[ERR] cannot find compilable backup"; exit 3; }
fi

echo "== [3] Restart service (safe) =="
sudo systemctl restart "$SVC" || {
  echo "[ERR] restart failed; tail error log"
  tail -n 120 /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log || true
  exit 4
}
echo "[OK] restarted $SVC"

echo "== [4] Smoke =="
curl -fsS "$BASE/runs" >/dev/null && echo "[OK] /runs"
curl -fsS "$BASE/api/vsp/rid_latest" | head -c 200; echo
curl -fsS "$BASE/api/vsp/dashboard_v3" | head -c 200; echo
echo "[DONE] vsp_demo_app.py compile clean + UI still OK."

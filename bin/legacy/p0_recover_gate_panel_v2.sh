#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
TS="$(date +%Y%m%d_%H%M%S)"

F="static/js/vsp_gate_panel_v1.js"

echo "== [0] locate clean backup (pre-fallback) =="
BKP="$(ls -1t ${F}.bak_p0fix_* 2>/dev/null | head -n1 || true)"
[ -n "${BKP:-}" ] || { echo "[ERR] cannot find ${F}.bak_p0fix_* backup"; exit 2; }
echo "[RESTORE] $F <= $BKP"
cp -f "$BKP" "$F"

echo "== [1] force runs_index URL to filter=0 (no empty) + strip any leftover injected fallback =="
cp -f "$F" "$F.bak_recover_${TS}" && echo "[BACKUP] $F.bak_recover_${TS}"

python3 - <<'PY'
from pathlib import Path
import re
p=Path("static/js/vsp_gate_panel_v1.js")
s=p.read_text(encoding="utf-8")

# strip any previous injected fallback block if it ever exists
s = re.sub(r'(?s)\n\s*// P0 FIX: fallback:.*?\n\s*else\s*\n', '\n', s)

# force first occurrence of runs_index endpoint to canonical params (filter=0)
pat = r'"/api/vsp/runs_index_v3_fs_resolved(\?[^"]*)?"'
rep = '"/api/vsp/runs_index_v3_fs_resolved?limit=1&hide_empty=0&filter=0"'
s2, n = re.subn(pat, rep, s, count=1)
if n != 1:
    raise SystemExit("[ERR] cannot find runs_index_v3_fs_resolved string to patch")
p.write_text(s2, encoding="utf-8")
print("[OK] patched runs_index url => filter=0, removed fallback block if present")
PY

echo "== [2] JS parse must be OK =="
node --check "$F" >/dev/null && echo "[OK] node --check OK: $F"

echo "== [3] restart gunicorn 8910 =="
PID_FILE="out_ci/ui_8910.pid"
PID="$(cat "$PID_FILE" 2>/dev/null || true)"
[ -n "${PID:-}" ] && kill -TERM "$PID" 2>/dev/null || true
pkill -f 'gunicorn .*8910' 2>/dev/null || true
sleep 0.6

nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 --pid "$PID_FILE" \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.nohup.log 2>&1 &

sleep 1.2
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
echo "[DONE] Hard refresh Ctrl+Shift+R, then re-check CI/CD Gate panel"

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

TS="$(date +%Y%m%d_%H%M%S)"
JS="static/js/vsp_ui_4tabs_commercial_v1.js"
FREEZE="static/js/vsp_ui_4tabs_commercial_v1.freeze.js"
TPL="templates/vsp_4tabs_commercial_v1.html"

[ -f "$JS" ] || { echo "[ERR] missing $JS"; exit 2; }
[ -f "$TPL" ] || { echo "[ERR] missing $TPL"; exit 2; }

echo "== [1] backup + parse check =="
cp -f "$JS" "$JS.bak_freeze_${TS}" && echo "[BACKUP] $JS.bak_freeze_${TS}"
node --check "$JS" >/dev/null && echo "[OK] node --check OK: $JS"

echo "== [2] write FREEZE file (golden) =="
{
  echo "/* VSP_UI_FREEZE build=${TS} */"
  cat "$JS"
  echo
  echo "try{ console.info('[VSP_UI_FREEZE]', 'build=${TS}'); }catch(_){ }"
} > "$FREEZE"
node --check "$FREEZE" >/dev/null && echo "[OK] node --check OK: $FREEZE"

echo "== [3] patch template to load FREEZE (with cache bust) =="
cp -f "$TPL" "$TPL.bak_freeze_tpl_${TS}" && echo "[BACKUP] $TPL.bak_freeze_tpl_${TS}"
export TS TPL
python3 - <<'PY'
from pathlib import Path
import os, re
ts = os.environ["TS"]
tpl = Path(os.environ["TPL"])
s = tpl.read_text(encoding="utf-8")
pat = r'src="/static/js/vsp_ui_4tabs_commercial_v1\.js(\?[^"]*)?"'
rep = f'src="/static/js/vsp_ui_4tabs_commercial_v1.freeze.js?v={ts}"'
s2, n = re.subn(pat, rep, s, count=1)
if n != 1:
    raise SystemExit(f"[ERR] cannot patch script src in {tpl} (matched={n})")
tpl.write_text(s2, encoding="utf-8")
print("[OK] template patched:", tpl)
PY

echo "== [4] restart gunicorn 8910 =="
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

sleep 1.0
curl -fsS http://127.0.0.1:8910/vsp4 >/dev/null && echo "[OK] UI up: /vsp4"
curl -fsS "http://127.0.0.1:8910/static/js/vsp_ui_4tabs_commercial_v1.freeze.js?v=${TS}" | head -n 2 || true

echo "[DONE] Open UI and HARD refresh: Ctrl+Shift+R"

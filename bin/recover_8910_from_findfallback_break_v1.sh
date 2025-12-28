#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

B="$(ls -1 "${F}.bak_findfallback_"* 2>/dev/null | sort | tail -n1 || true)"
[ -n "${B:-}" ] || { echo "[ERR] no backup ${F}.bak_findfallback_* found"; exit 2; }

echo "[RESTORE] $B -> $F"
cp -f "$B" "$F"

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

# restart 8910 (commercial)
if [ -x "bin/restart_8910_gunicorn_commercial_v5.sh" ]; then
  bin/restart_8910_gunicorn_commercial_v5.sh
elif [ -x "/home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh" ]; then
  /home/test/Data/SECURITY_BUNDLE/ui/bin/restart_8910_gunicorn_commercial_v5.sh
else
  echo "[WARN] restart script not found; please restart gunicorn manually"
fi

curl -sS http://127.0.0.1:8910/healthz || true
echo "[DONE]"

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
mkdir -p out_ci

# chọn đúng python (ưu tiên venv của SECURITY_BUNDLE)
PY="/home/test/Data/SECURITY_BUNDLE/.venv/bin/python3"
if [ ! -x "$PY" ]; then
  PY="$(command -v python3)"
fi
echo "[INFO] PY=$PY"

echo "== kill listeners on 8910 =="
PIDS="$(ss -ltnp 2>/dev/null | awk '/:8910/ {print $NF}' | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | sort -u | tr '\n' ' ')"
echo "PIDS=$PIDS"
for p in $PIDS; do kill -9 "$p" 2>/dev/null || true; done
sleep 1

echo "== quick import check =="
"$PY" -c "import vsp_demo_app; print('OK import vsp_demo_app', getattr(vsp_demo_app,'app',None))"

echo "== start gunicorn 8910 =="
nohup "$PY" -m gunicorn -w 1 -k gthread --threads 4 \
  --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui \
  --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910_access.log \
  --error-logfile  /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910_error.log \
  vsp_demo_app:app \
  > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910_nohup.log 2>&1 &

sleep 1
echo "== health =="
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://127.0.0.1:8910/ || true
echo "== listen =="
ss -ltnp | grep ':8910' || (echo "[ERR] 8910 not listening"; tail -n 120 out_ci/ui_8910_nohup.log; tail -n 120 out_ci/ui_8910_error.log; exit 1)

echo "[OK] 8910 up"

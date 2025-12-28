#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need awk; need sed; need curl; need python3; need pgrep; need pkill; need sleep; need tail

BASE="http://127.0.0.1:8910"
PAT="gunicorn.*wsgi_vsp_ui_gateway:application"

echo "== kill all gunicorn for 8910 =="
pkill -f "$PAT" || true
rm -f /tmp/vsp_ui_8910.lock || true

echo "== wait port free =="
for i in $(seq 1 40); do
  if ss -ltnp | grep -q ':8910'; then
    sleep 0.15
  else
    break
  fi
done

echo "== start gunicorn :8910 =="
: > out_ci/ui_8910.boot.log || true
: > out_ci/ui_8910.error.log || true
nohup /home/test/Data/SECURITY_BUNDLE/ui/.venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== wait READY /api/vsp/runs JSON =="
RID=""
for i in $(seq 1 60); do
  if curl -fsS "$BASE/api/vsp/runs?limit=1" > /tmp/vsp_runs.json 2>/dev/null; then
    if RID="$(python3 - <<'PY' 2>/dev/null
import json
j=json.load(open("/tmp/vsp_runs.json","r",encoding="utf-8",errors="replace"))
rid=j.get("rid_latest")
if not rid:
  items=j.get("items") or []
  rid=(items[0] or {}).get("run_id") if items else None
if rid:
  print(rid)
PY
)"; then
      if [ -n "${RID:-}" ]; then
        echo "[OK] READY rid=${RID}"
        break
      fi
    fi
  fi
  sleep 0.25
done

if [ -z "${RID:-}" ]; then
  echo "[ERR] server not ready or /api/vsp/runs not JSON"
  echo "== ss :8910 =="; ss -ltnp | grep ':8910' || true
  echo "== boot log tail =="; tail -n 120 out_ci/ui_8910.boot.log || true
  echo "== error log tail =="; tail -n 120 out_ci/ui_8910.error.log || true
  exit 1
fi

echo "== verify dash endpoints =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 220; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 220; echo
curl -fsS -I "$BASE/vsp5" | sed -n '1,12p'

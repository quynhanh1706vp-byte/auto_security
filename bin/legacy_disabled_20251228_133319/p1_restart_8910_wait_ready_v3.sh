#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need ss; need awk; need sed; need curl; need python3; need pgrep; need pkill; need sleep; need tail; need grep; need nohup

BASE="http://127.0.0.1:8910"
PAT="gunicorn.*wsgi_vsp_ui_gateway:application.*--bind 127.0.0.1:8910"

echo "== precheck gunicorn =="
[ -x .venv/bin/gunicorn ] || { echo "[ERR] missing .venv/bin/gunicorn"; ls -l .venv/bin/gunicorn || true; exit 2; }

echo "== kill gunicorn bind :8910 =="
pkill -f "$PAT" || true
rm -f /tmp/vsp_ui_8910.lock || true

echo "== wait port free =="
for i in $(seq 1 120); do
  if ss -ltnp 2>/dev/null | grep -q ':8910'; then
    sleep 0.15
  else
    break
  fi
done

echo "== start gunicorn :8910 =="
mkdir -p out_ci
: > out_ci/ui_8910.boot.log || true
nohup .venv/bin/gunicorn wsgi_vsp_ui_gateway:application \
  --workers 2 --worker-class gthread --threads 4 --timeout 60 --graceful-timeout 15 \
  --chdir /home/test/Data/SECURITY_BUNDLE/ui --pythonpath /home/test/Data/SECURITY_BUNDLE/ui \
  --bind 127.0.0.1:8910 \
  --access-logfile out_ci/ui_8910.access.log --error-logfile out_ci/ui_8910.error.log \
  > out_ci/ui_8910.boot.log 2>&1 &

echo "== wait READY (port + runs JSON) =="
RID=""
for i in $(seq 1 240); do
  # if gunicorn died early, break & show logs
  if ! pgrep -af "$PAT" >/dev/null 2>&1; then
    echo "[ERR] gunicorn died early"
    tail -n 160 out_ci/ui_8910.boot.log 2>/dev/null || true
    tail -n 160 out_ci/ui_8910.error.log 2>/dev/null || true
    exit 3
  fi

  if ! ss -ltnp 2>/dev/null | grep -q ':8910'; then
    sleep 0.15
    continue
  fi

  R="$(curl -fsS --max-time 2 --retry 3 --retry-delay 0 --retry-connrefused \
        "$BASE/api/vsp/runs?limit=1" 2>/dev/null || true)"

  if [ -n "${R:-}" ]; then
    RID="$(python3 - <<'PY' 2>/dev/null || true
import json,sys
try:
  o=json.loads(sys.stdin.read())
  items=o.get("items") or []
  print(items[0].get("run_id","") if items else "")
except Exception:
  print("")
PY
<<<"$R")"
    if [ -n "${RID:-}" ]; then
      echo "[OK] READY rid=$RID"
      break
    fi
  fi

  sleep 0.15
done

if [ -z "${RID:-}" ]; then
  echo "[ERR] not READY in time; last logs:"
  tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
  tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
  echo "== proc/port =="
  pgrep -af "$PAT" || true
  ss -ltnp | grep ':8910' || true
  exit 4
fi

echo "== verify dash endpoints =="
curl -fsS "$BASE/api/vsp/dash_kpis?rid=$RID" | head -c 220; echo
curl -fsS "$BASE/api/vsp/dash_charts?rid=$RID" | head -c 220; echo

echo "== verify marker in bundle file =="
JS="static/js/vsp_bundle_commercial_v2.js"
if [ -f "$JS" ] && grep -q "VSP_P1_DASH_RENDER_STABLE_V1" "$JS"; then
  echo "[OK] marker found in $JS"
else
  echo "[WARN] marker NOT found in $JS (check correct bundle path/name)"
fi

echo "== smoke /vsp5 (GET first bytes) =="
curl -fsS "$BASE/vsp5" | head -c 120; echo

echo "== done =="

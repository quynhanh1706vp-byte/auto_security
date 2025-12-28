#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/crash_triage_${TS}.txt"

{
  echo "== TS=$TS BASE=$BASE =="
  echo "== START loop =="
  for i in $(seq 1 120); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/vsp/runs?limit=20" || echo ERR)"
    echo "$i $code"
    if [ "$code" = "ERR" ] || [ "$code" = "000" ] || [[ "$code" == *ERR* ]]; then
      echo "== BREAK on i=$i code=$code =="
      break
    fi
  done

  echo
  echo "== ss -ltnp | grep 8910 =="
  ss -ltnp | grep 8910 || true

  echo
  echo "== ps grep gunicorn =="
  ps aux | egrep 'gunicorn|wsgi_vsp_ui_gateway' | grep -v egrep || true

  echo
  echo "== dmesg OOM tail =="
  dmesg -T | tail -n 200 | egrep -i 'killed process|oom|out of memory' || true

  echo
  echo "== tail boot/error/access =="
  tail -n 200 out_ci/ui_8910.boot.log 2>/dev/null || true
  echo "---"
  tail -n 200 out_ci/ui_8910.error.log 2>/dev/null || true
  echo "---"
  tail -n 50  out_ci/ui_8910.access.log 2>/dev/null || true
} | tee "$OUT"

echo "[OK] wrote $OUT"

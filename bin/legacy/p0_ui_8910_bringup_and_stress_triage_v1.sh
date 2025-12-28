#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"
OUT="out_ci/bringup_stress_triage_${TS}.txt"

dump_logs(){
  echo
  echo "== ss -ltnp | grep 8910 =="
  ss -ltnp | grep 8910 || true

  echo
  echo "== ps grep UI gunicorn =="
  ps aux | egrep 'wsgi_vsp_ui_gateway|gunicorn.*8910' | grep -v egrep || true

  echo
  echo "== tail boot/error/access =="
  tail -n 220 out_ci/ui_8910.boot.log 2>/dev/null || true
  echo "---"
  tail -n 220 out_ci/ui_8910.error.log 2>/dev/null || true
  echo "---"
  tail -n 80  out_ci/ui_8910.access.log 2>/dev/null || true

  echo
  echo "== tail nohup.out (if any) =="
  tail -n 120 nohup.out 2>/dev/null || true

  echo
  echo "== kernel OOM hints (sudo if possible) =="
  if command -v sudo >/dev/null 2>&1; then
    if sudo -n true 2>/dev/null; then
      sudo dmesg -T | tail -n 200 | egrep -i 'killed process|oom|out of memory|segfault' || true
    else
      echo "[WARN] sudo needs password; run manually: sudo dmesg -T | tail -n 200"
      journalctl -k --no-pager -n 200 2>/dev/null | egrep -i 'killed process|oom|out of memory|segfault' || true
    fi
  fi
}

{
  echo "== TS=$TS BASE=$BASE =="
  echo "== markers =="
  grep -n "VSP_P1_RUNS_CACHE_MW_V2" wsgi_vsp_ui_gateway.py 2>/dev/null || echo "[WARN] runs-cache MW not installed yet"
  grep -n "VSP_P0_GUNICORN_MAXREQ_V1" bin/p1_ui_8910_single_owner_start_v2.sh 2>/dev/null || true
  echo

  echo "== (1) try bring up 8910 =="
  rm -f /tmp/vsp_ui_8910.lock || true
  bin/p1_ui_8910_single_owner_start_v2.sh || true
  sleep 0.8

  if ! ss -ltnp | grep -q ":8910"; then
    echo "[FAIL] 8910 is NOT listening after start. Dumping logs..."
    dump_logs
    exit 2
  fi

  echo "[OK] 8910 is listening. Begin stress /api/vsp/runs ..."
  for i in $(seq 1 120); do
    code="$(curl -sS -o /dev/null -w '%{http_code}' "$BASE/api/vsp/runs?limit=20" || echo ERR)"
    echo "$i $code"
    if [[ "$code" == *ERR* ]] || [ "$code" = "000" ]; then
      echo "[FAIL] broke at i=$i code=$code"
      dump_logs
      exit 3
    fi
  done

  echo "[OK] stress finished 120/120 without crash"
} | tee "$OUT"

echo "[OK] wrote $OUT"

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

kill_listeners() {
  # kill anything LISTENing on :8910 (repeatable)
  local pids=""
  pids="$(sudo ss -ltnp 2>/dev/null | sed -n 's/.*pid=\([0-9]\+\).*/\1/p' | awk 'NF' | sort -u | tr '\n' ' ' || true)"
  if [ -n "${pids// }" ]; then
    echo "[CLEAN] listeners pids: $pids"
    for pid in $pids; do
      sudo kill -TERM "$pid" 2>/dev/null || true
    done
    sleep 1
    for pid in $pids; do
      sudo kill -KILL "$pid" 2>/dev/null || true
    done
  else
    echo "[CLEAN] no listeners found by ss (maybe none)."
  fi
}

echo "[START] 1) stop app by name"
pkill -f vsp_demo_app.py || true
sleep 1

echo "[START] 2) free port 8910 (kill listeners)"
for i in 1 2 3; do
  echo "[START] kill round $i"
  kill_listeners
  sleep 1
  if ! sudo ss -ltnp | grep -q ':8910'; then
    echo "[OK] 8910 is free"
    break
  fi
done

echo "[START] 3) verify port"
sudo ss -ltnp | grep ':8910' || echo "[OK] 8910 free"

echo "[START] 4) start"
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "[START] 5) check"
curl -sS -o /dev/null -w "HTTP=%{http_code}\n" http://localhost:8910/ || true

if ! curl -fsS http://localhost:8910/ >/dev/null 2>&1; then
  echo "[ERR] still not reachable. Diagnostics:"
  echo "== ss :8910 =="; sudo ss -ltnp | grep ':8910' || echo "no listen"
  echo "== lsof :8910 =="; sudo lsof -nP -iTCP:8910 -sTCP:LISTEN || true
  echo "== tail ui_8910.log =="; tail -n 120 out_ci/ui_8910.log | sed 's/\r/\n/g' || true
  exit 2
fi

echo "[OK] 8910 up"
tail -n 30 out_ci/ui_8910.log | sed 's/\r/\n/g' || true

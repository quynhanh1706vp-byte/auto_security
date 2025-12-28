#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
LOG_DIR="$ROOT/out_ci"
LOG_FILE="$LOG_DIR/ui_8910.log"

echo "[INFO] ROOT=$ROOT"
echo "[INFO] APP=$APP"
echo "[INFO] LOG_FILE=$LOG_FILE"

mkdir -p "$LOG_DIR"

if ! grep -q "/api/vsp/run_status" "$APP"; then
  echo "[ERR] Không thấy route /api/vsp/run_status trong $APP"
  exit 1
fi
echo "[OK] Route appears in file."

echo "[INFO] Killing old 8910 (best-effort)..."
pkill -f "vsp_demo_app.py" 2>/dev/null || true
pkill -f "my_flask_app/app.py" 2>/dev/null || true
sleep 0.4 || true

echo "[INFO] Starting vsp_demo_app.py on 8910..."
nohup python3 "$APP" > "$LOG_FILE" 2>&1 &
PID=$!
echo "[INFO] Started PID=$PID"
sleep 1.2 || true

echo "[INFO] Probe /__vsp_ui_whoami ..."
if ! curl -sS http://localhost:8910/__vsp_ui_whoami | jq; then
  echo "[ERR] 8910 not responding. Last 120 log lines:"
  tail -n 120 "$LOG_FILE" || true
  exit 2
fi
echo

REQ_ID="$(ls -1 /home/test/Data/SECURITY_BUNDLE/out_ci/ui_triggers/UIREQ_*.log 2>/dev/null \
  | sed 's#.*/##' | sed 's/\.log$//' | sort | tail -n1 || true)"

echo "[INFO] REQ_ID=$REQ_ID"
if [ -z "$REQ_ID" ]; then
  echo "[WARN] Không tìm thấy UIREQ log nào trong /home/test/Data/SECURITY_BUNDLE/out_ci/ui_triggers/"
  exit 0
fi

echo "[INFO] curl run_status:"
curl -sS -w "\nHTTP=%{http_code}\n" "http://localhost:8910/api/vsp/run_status/$REQ_ID" | head -n 220

echo
echo "[INFO] OK. If you see HTTP=200 with JSON => polling endpoint ready."

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"

echo "[INFO] ROOT=$ROOT"
echo "[INFO] APP=$APP"

if ! grep -q "/api/vsp/run_status" "$APP"; then
  echo "[ERR] Không thấy route /api/vsp/run_status trong $APP (patch chưa vào file?)"
  exit 1
fi
echo "[OK] Route appears in file."

# Kill old 8910 process
echo "[INFO] Killing old 8910 (best-effort)..."
pkill -f "vsp_demo_app.py" 2>/dev/null || true
pkill -f "port=8910" 2>/dev/null || true
pkill -f "0.0.0.0:8910" 2>/dev/null || true
sleep 0.3 || true

# Start server in background (dev)
echo "[INFO] Starting vsp_demo_app.py on 8910..."
nohup python3 "$APP" > "$ROOT/out_ci/ui_8910.log" 2>&1 &
sleep 0.8 || true

# Whoami check
echo "[INFO] whoami:"
curl -sS http://localhost:8910/__vsp_ui_whoami | jq || true
echo

# Pick latest REQ_ID
REQ_ID="$(ls -1 /home/test/Data/SECURITY_BUNDLE/out_ci/ui_triggers/UIREQ_*.log 2>/dev/null \
  | sed 's#.*/##' | sed 's/\.log$//' | sort | tail -n1 || true)"

echo "[INFO] REQ_ID=$REQ_ID"
if [ -z "$REQ_ID" ]; then
  echo "[WARN] Không tìm thấy UIREQ log nào trong out_ci/ui_triggers/"
  exit 0
fi

echo "[INFO] curl run_status with HTTP code:"
curl -sS -w "\nHTTP=%{http_code}\n" "http://localhost:8910/api/vsp/run_status/$REQ_ID" | head -n 200
echo
echo "[INFO] If HTTP!=200, show last 80 lines of ui_8910.log:"
tail -n 80 "$ROOT/out_ci/ui_8910.log" 2>/dev/null || true

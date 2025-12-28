#!/usr/bin/env bash
set -euo pipefail

echo "== PROD 8910 (vsp-ui-8910) =="
sudo systemctl is-active vsp-ui-8910 && echo "[OK] active" || echo "[WARN] not active"
curl -sS -o /dev/null -w "healthz_8910 HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true

echo "== DEV 8911 (vsp-ui-8911-dev) =="
sudo systemctl is-active vsp-ui-8911-dev && echo "[OK] active" || echo "[WARN] not active"
sudo ss -ltnp | grep ':8911' || echo "[WARN] no LISTEN on :8911"
curl -sS -o /dev/null -w "healthz_8911 HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true

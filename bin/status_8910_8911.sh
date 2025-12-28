#!/usr/bin/env bash
set -euo pipefail
echo "== PROD (systemd) 8910 =="
sudo systemctl is-active vsp-ui-8910 && echo "[OK] vsp-ui-8910 active" || echo "[WARN] vsp-ui-8910 not active"
curl -sS -o /dev/null -w "healthz_8910 HTTP=%{http_code}\n" http://127.0.0.1:8910/healthz || true

echo "== DEV (gunicorn) 8911 =="
sudo ss -ltnp | grep ":8911" || echo "[WARN] no listener on :8911"
curl -sS -o /dev/null -w "healthz_8911 HTTP=%{http_code}\n" http://127.0.0.1:8911/healthz || true

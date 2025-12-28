#!/usr/bin/env bash
set -euo pipefail
PORT="${1:-8911}"

case "$PORT" in ''|*[!0-9]*) echo "[ERR] numeric port required"; exit 2;; esac
echo "== kill listener on :$PORT =="
sudo fuser -k "${PORT}/tcp" 2>/dev/null || true
sudo ss -ltnp | grep ":$PORT" || echo "[OK] no listener on :$PORT"

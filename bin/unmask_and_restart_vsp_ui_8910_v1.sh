#!/usr/bin/env bash
set -euo pipefail

SVC="vsp-ui-8910.service"

echo "== status =="
systemctl status "$SVC" --no-pager || true
echo "== is-enabled =="
systemctl is-enabled "$SVC" || true

echo "== unmask =="
sudo systemctl unmask "$SVC"

echo "== daemon-reload =="
sudo systemctl daemon-reload

echo "== restart =="
sudo systemctl restart "$SVC"

echo "== status after =="
systemctl status "$SVC" --no-pager | head -n 60

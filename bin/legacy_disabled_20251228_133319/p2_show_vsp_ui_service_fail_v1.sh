#!/usr/bin/env bash
set -euo pipefail
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

echo "== systemctl status =="
sudo systemctl status "$SVC" --no-pager -l || true
echo
echo "== journal last 200 lines =="
sudo journalctl -u "$SVC" -n 200 --no-pager || true

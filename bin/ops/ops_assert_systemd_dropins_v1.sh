#!/usr/bin/env bash
set -euo pipefail

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"

echo "== [OPS] assert drop-ins for $SVC =="
sudo systemctl show "$SVC" -p DropInPaths --no-pager | sed 's/DropInPaths=//'

sudo systemctl cat "$SVC" --no-pager | sed -n '1,220p'

# Must-have: 10-no-pidfile-no-startpost (or equivalent) present
if ! sudo systemctl show "$SVC" -p DropInPaths --no-pager | grep -q "10-no-pidfile-no-startpost.conf"; then
  echo "[FAIL] missing drop-in 10-no-pidfile-no-startpost.conf (PIDFile/start-post timeout may return)"
  exit 2
fi

echo "[OK] commercial drop-ins look present"

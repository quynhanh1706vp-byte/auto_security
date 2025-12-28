#!/usr/bin/env bash
set -euo pipefail
H="run_api/vsp_watchdog_hook_v1.py"
[ -f "$H" ] || { echo "[ERR] missing $H"; exit 1; }

LATEST="$(ls -1 "$H".bak_* 2>/dev/null | sort | tail -n1 || true)"
[ -n "$LATEST" ] && [ -f "$LATEST" ] || { echo "[ERR] no backup found for $H"; exit 1; }

cp -f "$LATEST" "$H"
echo "[RESTORE] $H <= $LATEST"
python3 -m py_compile "$H"
echo "[OK] py_compile restored hook OK"

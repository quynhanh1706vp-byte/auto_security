#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

BAK="$(ls -1t vsp_demo_app.py.bak_cwe_enrich_demoapp_* 2>/dev/null | head -n1 || true)"
[ -n "${BAK:-}" ] || { echo "[ERR] no backup vsp_demo_app.py.bak_cwe_enrich_demoapp_*"; exit 3; }

cp -f "$BAK" "$F"
echo "[OK] restored $F <= $BAK"

python3 -m py_compile "$F"
echo "[OK] py_compile OK => $F"

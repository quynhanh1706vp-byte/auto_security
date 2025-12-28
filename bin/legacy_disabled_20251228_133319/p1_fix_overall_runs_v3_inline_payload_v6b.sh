#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

F="wsgi_vsp_ui_gateway.py"
TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_fix_overall_runsv3_v6b_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

mark = "VSP_P1_FIX_OVERALL_RUNS_V3_INLINE_PAYLOAD_V6"
if mark not in s:
    print("[ERR] marker not found:", mark)
    raise SystemExit(2)

# Replace the __counts assignment line inside the V6 block to be type-safe
# Old: __counts  = __it.get('counts') or {}
# New: __counts = __it.get('counts'); if not isinstance(__counts, dict): __counts = {}
pat = r"(?m)^(\s*)__counts\s*=\s*__it\.get\('counts'\)\s*or\s*\{\}\s*$"
rep = r"\1__counts = __it.get('counts')\n\1if not isinstance(__counts, dict):\n\1    __counts = {}\n"
s2, n = re.subn(pat, rep, s, count=1)
if n == 0:
    # fallback: maybe spacing differs (two spaces)
    pat2 = r"(?m)^(\s*)__counts\s{0,3}=\s*__it\.get\('counts'\)\s*or\s*\{\}\s*$"
    s2, n = re.subn(pat2, rep, s, count=1)

if n == 0:
    print("[ERR] cannot find __counts assignment line to patch")
    raise SystemExit(3)

p.write_text(s2, encoding="utf-8")
print("[OK] patched __counts to be dict-safe")
PY

python3 -m py_compile wsgi_vsp_ui_gateway.py && echo "[OK] py_compile OK"

sudo systemctl restart vsp-ui-8910.service || true

echo "== verify =="
curl -sS http://127.0.0.1:8910/api/ui/runs_v3?limit=3 | python3 - <<'PY'
import sys, json
d=json.load(sys.stdin)
for it in (d.get("items") or [])[:3]:
    print(it.get("rid"), it.get("has_gate"), it.get("overall"), it.get("overall_source"), it.get("overall_inferred"))
PY

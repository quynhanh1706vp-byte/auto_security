#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date

JS="static/js/vsp_fill_real_data_5tabs_p1_v1.js"
[ -f "$JS" ] || { echo "[WARN] missing $JS (skip)"; exit 0; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$JS" "${JS}.bak_illegal_return_${TS}"
echo "[BACKUP] ${JS}.bak_illegal_return_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, time

p = Path("static/js/vsp_fill_real_data_5tabs_p1_v1.js")
s = p.read_text(encoding="utf-8", errors="replace")

# If already wrapped by us, skip
if "VSP_FILLREAL_IIFE_WRAP_V1" in s:
    print("[OK] already wrapped, skip")
    raise SystemExit(0)

# Remove any accidental BOM
s = s.lstrip("\ufeff")

# Wrap the entire file in an IIFE so top-level `return` becomes legal.
wrapped = "/* VSP_FILLREAL_IIFE_WRAP_V1 */\n(() => {\n" + s + "\n})();\n"

p.write_text(wrapped, encoding="utf-8")
print("[OK] wrapped into IIFE:", p)
PY

# Best-effort syntax check (if node exists)
if command -v node >/dev/null 2>&1; then
  node --check "$JS" && echo "[OK] node --check OK"
else
  echo "[INFO] node not found; skip syntax check"
fi

echo "[DONE] fixed illegal return by IIFE wrap."

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing cmd: $1"; exit 2; }; }
need python3; need date

TS="$(date +%Y%m%d_%H%M%S)"
F="static/js/vsp_bundle_commercial_v1.js"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

echo "== BEFORE grep marker =="
grep -n "VSP_FIX_TEXTAREA_STYLE_QUOTE_P1_3_V1" "$F" || true

cp -f "$F" "${F}.bak_rm_marker_${TS}"
echo "[BACKUP] ${F}.bak_rm_marker_${TS}"

python3 - <<'PY'
from pathlib import Path

p = Path("static/js/vsp_bundle_commercial_v1.js")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

needle = "VSP_FIX_TEXTAREA_STYLE_QUOTE_P1_3_V1"
out=[]
rm=0
for ln in lines:
    if needle in ln:
        rm += 1
        continue
    out.append(ln)

p.write_text("".join(out), encoding="utf-8")
print("[OK] removed lines:", rm)
PY

echo "== AFTER grep marker =="
grep -n "VSP_FIX_TEXTAREA_STYLE_QUOTE_P1_3_V1" "$F" && { echo "[ERR] marker still exists"; exit 3; } || echo "[OK] marker gone"

if command -v node >/dev/null 2>&1; then
  echo "== node --check $F =="
  node --check "$F"
  echo "[OK] JS parse OK"
else
  echo "[WARN] node not installed; skip parse check"
fi

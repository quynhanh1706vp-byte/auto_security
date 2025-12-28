#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date
command -v systemctl >/dev/null 2>&1 || true

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
F="wsgi_vsp_ui_gateway.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK="${F}.bak_assetv_ts_${TS}"
cp -f "$F" "$BAK"
echo "[BACKUP] $BAK"

python3 - <<'PY'
from pathlib import Path
import re, py_compile, textwrap

p = Path("wsgi_vsp_ui_gateway.py")
s = p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P1_ASSET_V_RUNTIME_TS_V1"
if MARK in s:
    print("[OK] already patched:", MARK)
    py_compile.compile(str(p), doraise=True)
    raise SystemExit(0)

# Insert near top after imports (first ~160 lines)
lines = s.splitlines(True)
ins = 0
for i in range(min(len(lines), 160)):
    if re.match(r'^\s*(from\s+\S+\s+import\s+|import\s+\S+)', lines[i]):
        ins = i+1

block = textwrap.dedent(r'''
# ===================== VSP_P1_ASSET_V_RUNTIME_TS_V1 =====================
# Ensure asset_v is a changing numeric value per process start (good for cache-busting JS/CSS).
import time as _vsp__time
try:
    # keep if already defined and looks numeric
    _cur = str(globals().get("asset_v","")).strip()
    if not _cur.isdigit() or _cur == "1":
        asset_v = str(int(_vsp__time.time()))
except Exception:
    asset_v = str(int(_vsp__time.time()))
# ===================== /VSP_P1_ASSET_V_RUNTIME_TS_V1 =====================
''').rstrip() + "\n"

lines.insert(ins, block)
out = "".join(lines)
p.write_text(out, encoding="utf-8")
py_compile.compile(str(p), doraise=True)
print("[OK] patched:", MARK)
PY

if command -v systemctl >/dev/null 2>&1; then
  systemctl restart "$SVC" 2>/dev/null || true
  systemctl --no-pager --full status "$SVC" | sed -n '1,12p' || true
else
  echo "[WARN] systemctl not found; restart service manually if needed."
fi

echo "[DONE] asset_v now runtime timestamp"

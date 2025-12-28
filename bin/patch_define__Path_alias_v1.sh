#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="./vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_define__Path_${TS}"
echo "[BACKUP] $F.bak_define__Path_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "VSP_DEFINE__PATH_ALIAS_V1"
if TAG in t:
    print("[OK] already patched")
    raise SystemExit(0)

# only patch if _Path is used
if "_Path(" not in t and " _Path" not in t:
    print("[OK] _Path not used; no change")
    raise SystemExit(0)

# Insert right after the minimal imports block if exists; else near top.
ins = f'\n# === {TAG} ===\ntry:\n    _Path\nexcept Exception:\n    _Path = Path\n# === END {TAG} ===\n'
m = re.search(r"(?ms)^# === VSP_MIN_IMPORTS_COMMERCIAL_V1 ===.*?# === END VSP_MIN_IMPORTS_COMMERCIAL_V1 ===\s*\n", t)
if m:
    pos = m.end()
else:
    # after first ~50 lines
    pos = min(len(t), 0)
    mm = re.search(r"(?ms)\A(.{0,2500}\n)", t)
    pos = mm.end(1) if mm else 0

t = t[:pos] + ins + t[pos:]
p.write_text(t, encoding="utf-8")
print("[OK] inserted _Path alias")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK: $F"
echo "[DONE] _Path alias patched"

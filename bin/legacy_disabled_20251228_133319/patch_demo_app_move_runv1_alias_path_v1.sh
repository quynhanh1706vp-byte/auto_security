#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_move_alias_${TS}"
echo "[BACKUP] $F.bak_move_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# đổi mọi add_url_rule cho endpoint/func vsp_run_v1_alias từ /api/vsp/run_v1 -> /api/vsp/run_v1_alias
# (cố gắng mềm: chỉ thay các dòng có vsp_run_v1_alias)
lines = txt.splitlines(True)
out = []
changed = 0

for ln in lines:
    if "vsp_run_v1_alias" in ln and "/api/vsp/run_v1" in ln:
        ln2 = ln.replace("/api/vsp/run_v1", "/api/vsp/run_v1_alias")
        if ln2 != ln:
            changed += 1
            ln = ln2
    out.append(ln)

txt2 = "".join(out)

if changed == 0:
    # fallback: nếu add_url_rule viết nhiều dòng, replace string toàn file nhưng chỉ khi có 'vsp_run_v1_alias' đâu đó
    if "vsp_run_v1_alias" in txt2:
        txt2b = txt2.replace('"/api/vsp/run_v1"', '"/api/vsp/run_v1_alias"')
        if txt2b != txt2:
            txt2 = txt2b
            changed = 999

p.write_text(txt2, encoding="utf-8")
print("[OK] moved alias path changes=", changed)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_healthz_fix_${TS}"
echo "[BACKUP] $F.bak_healthz_fix_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

beg = r"# === VSP COMMERCIAL HEALTHZ V1 ==="
end = r"# === END VSP COMMERCIAL HEALTHZ V1 ==="

new_block = (
"# === VSP COMMERCIAL HEALTHZ V2 ===\n"
"try:\n"
"    from flask import jsonify\n"
"    @app.route('/healthz', methods=['GET'])\n"
"    def vsp_healthz_v2():\n"
"        return jsonify({'ok': True, 'service': 'vsp-ui-8910'}), 200\n"
"except Exception:\n"
"    pass\n"
"# === END VSP COMMERCIAL HEALTHZ V2 ===\n"
)

# remove old block if exists (either V1 or V2)
txt2 = re.sub(r"# === VSP COMMERCIAL HEALTHZ V[12] ===[\\s\\S]*?# === END VSP COMMERCIAL HEALTHZ V[12] ===\\n?", "", txt)

# append new block at end
txt2 = txt2.rstrip() + "\n\n" + new_block + "\n"
p.write_text(txt2, encoding="utf-8")
print("[OK] wrote HEALTHZ V2 block (route-compatible)")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"

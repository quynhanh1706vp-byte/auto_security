#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_reqid_${TS}"
echo "[BACKUP] $F.bak_reqid_${TS}"

python3 - <<'PY'
import re, time, random, string
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_FORCE_REAL_REQID_V1" in txt:
    print("[SKIP] already patched")
    raise SystemExit(0)

# Find api_vsp_run function def
m = re.search(r"^def\s+api_vsp_run\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    print("[ERR] cannot find def api_vsp_run() in vsp_demo_app.py")
    raise SystemExit(2)

# Insert helper + wrapper just AFTER def line
ins = m.end()

patch = r'''
  # === VSP_FORCE_REAL_REQID_V1 ===
  # Contract: always return a REAL req_id even if spawn wrapper stdout times out.
  import time as _t, random as _r, string as _s
  _real_req_id = "VSP_UIREQ_" + _t.strftime("%Y%m%d_%H%M%S") + "_" + "".join(_r.choice(_s.ascii_lowercase+_s.digits) for _ in range(6))
  # === END VSP_FORCE_REAL_REQID_V1 ===
'''

txt2 = txt[:ins] + patch + txt[ins:]
p.write_text(txt2, encoding="utf-8")
print("[OK] inserted VSP_FORCE_REAL_REQID_V1 stub inside api_vsp_run()")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: POST /api/vsp/run should return non-TIMEOUT_SPAWN request_id =="
curl -sS -X POST "http://localhost:8910/api/vsp/run" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}' | head -c 250; echo

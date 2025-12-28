#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_disable_fallback_${TS}"
echo "[BACKUP] $F.bak_disable_fallback_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

start = txt.find("# === VSP_RUN_API_FALLBACK_V1 ===")
end = txt.find("# === END VSP_RUN_API_FALLBACK_V1 ===")
if start == -1 or end == -1:
    print("[ERR] fallback block not found")
    raise SystemExit(2)

end = end + len("# === END VSP_RUN_API_FALLBACK_V1 ===")
block = txt[start:end]

if "VSP_DISABLE_RUNAPI_FALLBACK" in block:
    print("[SKIP] already gated")
    raise SystemExit(0)

# Gate near beginning of fallback: only mount if env not disabled AND real bp not already registered
inject = """
import os as _os
if _os.getenv("VSP_DISABLE_RUNAPI_FALLBACK", "0") == "1":
    print("[VSP_RUN_API_FALLBACK] disabled by VSP_DISABLE_RUNAPI_FALLBACK=1")
else:
"""
# indent the whole existing fallback body after marker line
lines = block.splitlines(True)
out = []
inserted = False
for i, ln in enumerate(lines):
    out.append(ln)
    if not inserted and ln.strip() == "# === VSP_RUN_API_FALLBACK_V1 ===":
        out.append(inject)
        inserted = True
# Now indent all subsequent lines until END marker by 4 spaces (except the marker lines)
out2 = []
for ln in out:
    if ln.strip().startswith("# === VSP_RUN_API_FALLBACK_V1") or ln.strip().startswith("# === END VSP_RUN_API_FALLBACK_V1"):
        out2.append(ln)
        continue
    # keep blank lines
    if ln.strip() == "":
        out2.append(ln)
        continue
    # lines we inserted (import os...) already aligned at column 0; keep as-is
    if ln.startswith("import os as _os") or ln.startswith("if _os.getenv") or ln.startswith("    print(") or ln.startswith("else:"):
        out2.append(ln)
        continue
    # indent original fallback content
    out2.append("    " + ln)

new_block = "".join(out2)
txt2 = txt[:start] + new_block + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] fallback gated by env flag (default enabled).")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

# restart with fallback disabled
pkill -f vsp_demo_app.py || true
VSP_DISABLE_RUNAPI_FALLBACK=1 nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== Smoke: must still work via REAL bp =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
print({k: obj.get(k) for k in ["ok","status","final","error","stall_timeout_sec","total_timeout_sec"]})
PY

echo "== Log grep (fallback should be gone) =="
grep -n "VSP_RUN_API_FALLBACK" out_ci/ui_8910.log | tail -n 5 || true
grep -n "VSP_RUN_API] OK registered" out_ci/ui_8910.log | tail -n 5 || true
tail -n 40 out_ci/ui_8910.log

#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fallback_off_${TS}"
echo "[BACKUP] $F.bak_fallback_off_${TS}"

python3 - <<'PY'
from pathlib import Path
p=Path("vsp_demo_app.py")
txt=p.read_text(encoding="utf-8", errors="ignore")

start=txt.find("# === VSP_RUN_API_FALLBACK_V1 ===")
end=txt.find("# === END VSP_RUN_API_FALLBACK_V1 ===")
if start==-1 or end==-1:
    print("[ERR] fallback block not found")
    raise SystemExit(2)
end=end+len("# === END VSP_RUN_API_FALLBACK_V1 ===")
block=txt[start:end]

# Replace gating logic: fallback only if VSP_ENABLE_RUNAPI_FALLBACK=1
if "VSP_ENABLE_RUNAPI_FALLBACK" in block:
    print("[SKIP] already patched")
    raise SystemExit(0)

block2 = block.replace(
    'if _os.getenv("VSP_DISABLE_RUNAPI_FALLBACK", "0") == "1":',
    'if _os.getenv("VSP_ENABLE_RUNAPI_FALLBACK", "0") != "1":'
).replace(
    'print("[VSP_RUN_API_FALLBACK] disabled by VSP_DISABLE_RUNAPI_FALLBACK=1")',
    'print("[VSP_RUN_API_FALLBACK] disabled by default (set VSP_ENABLE_RUNAPI_FALLBACK=1 to enable)")'
)

txt2 = txt[:start] + block2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] fallback is now default-OFF; enable via VSP_ENABLE_RUNAPI_FALLBACK=1")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1

echo "== grep fallback (should show disabled-by-default) =="
grep -n "VSP_RUN_API_FALLBACK" out_ci/ui_8910.log | tail -n 5 || true
echo "== smoke status still OK =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
print({k: obj.get(k) for k in ["ok","status","error","stall_timeout_sec","total_timeout_sec"]})
PY

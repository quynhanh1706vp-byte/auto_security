#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY-10-10-v4/ci/VSP_CI_OUTER/vsp_ci_gate_core_v1.sh"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_autogate_${TS}"
echo "[BACKUP] $F.bak_autogate_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("/home/test/Data/SECURITY-10-10-v4/ci/VSP_CI_OUTER/vsp_ci_gate_core_v1.sh")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_CI_GATE_AUTOGATE_V1 ==="
if TAG in t:
    print("[OK] already patched, skip")
    raise SystemExit(0)

block = r'''
# === VSP_CI_GATE_AUTOGATE_V1 ===
# Commercial-safe: always build run_gate_summary.json after runner returns (no manual).
echo "[VSP_CI_GATE] AUTOGATE: build run_gate_summary.json (post-runner) run_dir=${RUN_DIR}"
set +e
python3 /home/test/Data/SECURITY_BUNDLE/bin/vsp_run_gate_build_v1.py "${RUN_DIR}"
_rc=$?
set -e
if [ "${_rc}" -ne 0 ] || [ ! -s "${RUN_DIR}/run_gate_summary.json" ]; then
  echo "[VSP_CI_GATE][DEGRADED] RUN_GATE build_failed rc=${_rc}"
  python3 - <<'PY2'
import json, os, time
run_dir = os.environ.get("RUN_DIR","")
rc = int(os.environ.get("_rc","1"))
path = os.path.join(run_dir, "degraded_tools.json")
item = {"tool":"RUN_GATE","reason":"build_failed","rc":rc,"ts":time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
arr=[]
try:
  if os.path.exists(path) and os.path.getsize(path)>0:
    arr=json.load(open(path,"r",encoding="utf-8")) or []
except Exception:
  arr=[]
if not isinstance(arr,list): arr=[arr]
arr.append(item)
os.makedirs(run_dir, exist_ok=True)
json.dump(arr, open(path,"w",encoding="utf-8"), ensure_ascii=False, indent=2)
print("[VSP_CI_GATE] wrote", path)
PY2
fi
# === /VSP_CI_GATE_AUTOGATE_V1 ===
'''

# Insert right after the line that actually runs the runner: "$RUNNER" ...
m = re.search(r'^\s*".*\$RUNNER.*"\s+.*\n', t, flags=re.M)
if not m:
    # fallback: after line containing "=== CHẠY RUNNER"
    m = re.search(r'^\s*echo\s+.*CHẠY RUNNER.*\n', t, flags=re.M)

if not m:
    t2 = t + "\n" + block + "\n"
else:
    t2 = t[:m.end()] + block + "\n" + t[m.end():]

p.write_text(t2, encoding="utf-8")
print("[OK] inserted AUTOGATE into gate_core")
PY

bash -n "$F"
echo "[OK] bash -n OK"
grep -n "VSP_CI_GATE_AUTOGATE_V1" -n "$F" | head -n 5 || true

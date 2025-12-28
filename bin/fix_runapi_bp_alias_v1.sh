#!/usr/bin/env bash
set -euo pipefail
ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
F="$ROOT/run_api/vsp_run_api_v1.py"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_bp_${TS}"
echo "[BACKUP] $F.bak_fix_bp_${TS}"

python3 - "$F" <<'PY'
import sys, re, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

needle = re.compile(r"^\s*bp_vsp_run_api_v1\s*=\s*bp\s*$", re.M)
m = needle.search(txt)
if not m:
    print("[ERR] cannot find exact line: 'bp_vsp_run_api_v1 = bp'")
    # show nearby hints
    for i, ln in enumerate(txt.splitlines(), 1):
        if "bp_vsp_run_api_v1" in ln and "=" in ln:
            print(f"[HINT] L{i}: {ln}")
    raise SystemExit(2)

block = r"""
# === VSP_FIX_BP_ALIAS_V1 ===
# Fix NameError: some builds referenced 'bp' without defining it.
# Contract: export bp_vsp_run_api_v1 always; keep 'bp' as alias if present.
try:
    bp_vsp_run_api_v1
except Exception:
    bp_vsp_run_api_v1 = None

try:
    bp
except Exception:
    bp = None

if bp_vsp_run_api_v1 is None and bp is not None:
    bp_vsp_run_api_v1 = bp
elif bp is None and bp_vsp_run_api_v1 is not None:
    bp = bp_vsp_run_api_v1
elif bp is None and bp_vsp_run_api_v1 is None:
    from flask import Blueprint
    bp_vsp_run_api_v1 = Blueprint("vsp_run_api_v1", __name__)
    bp = bp_vsp_run_api_v1
# === END VSP_FIX_BP_ALIAS_V1 ===
""".strip("\n")

txt2 = txt[:m.start()] + block + "\n" + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] replaced 'bp_vsp_run_api_v1 = bp' with safe alias block")
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

echo "== Re-test import (must succeed) =="
python3 - <<'PY'
import traceback
try:
    import run_api.vsp_run_api_v1 as m
    print("[OK] imported run_api.vsp_run_api_v1")
    print("bp_vsp_run_api_v1 =", getattr(m, "bp_vsp_run_api_v1", None))
except Exception as e:
    print("[ERR] import failed:", repr(e))
    traceback.print_exc()
PY

echo "== Restart UI gateway (8910) =="
pkill -f vsp_demo_app.py || true
nohup python3 "$ROOT/vsp_demo_app.py" > "$ROOT/out_ci/ui_8910.log" 2>&1 &
sleep 1

echo "== Smoke: run_status fake should be NOT_FOUND (real endpoint, not fallback 404) =="
python3 - <<'PY'
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/FAKE_REQ_ID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
keys=["ok","status","final","error","stall_timeout_sec","total_timeout_sec"]
print({k: obj.get(k) for k in keys})
PY

echo "== Log check (bp undefined must disappear) =="
grep -n "bp is not defined" -n "$ROOT/out_ci/ui_8910.log" | tail -n 5 || true
tail -n 40 "$ROOT/out_ci/ui_8910.log"
echo "[DONE]"

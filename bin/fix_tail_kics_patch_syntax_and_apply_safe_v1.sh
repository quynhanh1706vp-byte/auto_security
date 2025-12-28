#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"

echo "== [1] restore from latest bak_tail_kics =="
BAK="$(ls -1t vsp_demo_app.py.bak_tail_kics_* 2>/dev/null | head -n 1 || true)"
if [ -z "${BAK}" ]; then
  echo "[ERR] no backup vsp_demo_app.py.bak_tail_kics_* found"
  exit 1
fi
cp -f "$BAK" "$F"
echo "[OK] restored $F <= $BAK"

echo "== [2] apply SAFE tail patch inside run_status_v1 only =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

TAG = "# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ==="
if TAG in t:
    print("[OK] already patched SAFE")
    raise SystemExit(0)

SNIP = r'''
    # === VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===
    try:
        import os
        _cand = None
        for _v in locals().values():
            if isinstance(_v, dict) and ("ci_run_dir" in _v) and (("stage_name" in _v) or ("stage" in _v)):
                _cand = _v
                break
        if _cand:
            _sn = str(_cand.get("stage_name") or _cand.get("stage") or "").lower()
            _ci = str(_cand.get("ci_run_dir") or "")
            if ("kics" in _sn) and _ci:
                _klog = os.path.join(_ci, "kics", "kics.log")
                if os.path.exists(_klog):
                    with open(_klog, "rb") as _f:
                        _b = _f.read()[-4096:]
                    _cand["tail"] = _b.decode("utf-8", errors="ignore")
    except Exception:
        pass
    # === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V1_SAFE ===
'''

# Find the run_status_v1 route handler block and inject SNIP before the first "return jsonify"
# Support both "/api/vsp/run_status_v1/<rid>" and variations.
route_pat = re.compile(
    r"(@app\.route\([^\)]*run_status_v1[^\)]*\)\s*\n(?:@[^\n]*\n)*)"
    r"(def\s+[A-Za-z_]\w*\([^\)]*\)\s*:\n)",
    re.M
)

m = route_pat.search(t)
if not m:
    # fallback: patch by function name
    fn_pat = re.compile(r"(def\s+[A-Za-z_]\w*run_status_v1\w*\([^\)]*\)\s*:\n)", re.M)
    m2 = fn_pat.search(t)
    if not m2:
        print("[ERR] cannot locate run_status_v1 handler to patch")
        raise SystemExit(2)
    start = m2.end()
    # inject before first return jsonify after start
    idx = t.find("return jsonify", start)
    if idx < 0:
        print("[ERR] no 'return jsonify' found after handler")
        raise SystemExit(3)
    t = t[:idx] + SNIP + "\n" + t[idx:]
    p.write_text(t, encoding="utf-8")
    print("[OK] patched by function-name fallback")
    raise SystemExit(0)

# We have decorator+def, now locate first 'return jsonify' after def
start = m.end()
idx = t.find("return jsonify", start)
if idx < 0:
    print("[ERR] no 'return jsonify' found in run_status_v1 handler")
    raise SystemExit(4)

t = t[:idx] + SNIP + "\n" + t[idx:]
p.write_text(t, encoding="utf-8")
print("[OK] patched run_status_v1: prefer tail from kics/kics.log when stage=KICS")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [3] restart service (kill old then start) =="
pkill -f "vsp_demo_app.py" || true
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo

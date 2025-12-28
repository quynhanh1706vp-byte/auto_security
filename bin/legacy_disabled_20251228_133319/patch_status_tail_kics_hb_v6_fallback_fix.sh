#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tail_kics_hb_v6_${TS}"
echo "[BACKUP] $F.bak_tail_kics_hb_v6_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove V5 block if present
t = re.sub(
    r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===\s*\n?",
    "\n",
    t,
    flags=re.S
)

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ==="
if TAG in t:
    print("[OK] already patched V6")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

# insert V6 block right before the final return in _fallback_run_status_v1
pat_fn = r"(def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\n)"
m = re.search(pat_fn, t)
if not m:
    print("[ERR] cannot find def _fallback_run_status_v1(req_id)")
    raise SystemExit(2)

# find the return line inside this function (the one you showed at line ~2709)
pat_ret = r"(\n[ \t]+return\s+jsonify\(_vsp_contractize\(_VSP_FALLBACK_REQ\[req_id\]\)\)\s*,\s*200\s*\)\s*)"
m2 = re.search(pat_ret, t)
if not m2:
    print("[ERR] cannot find return jsonify(_vsp_contractize(_VSP_FALLBACK_REQ[req_id])), 200")
    raise SystemExit(3)

ret_line = m2.group(1)
indent = re.match(r"\n([ \t]+)return", ret_line).group(1)

block = f"""
{indent}{TAG}
{indent}try:
{indent}    import os
{indent}    st = _VSP_FALLBACK_REQ.get(req_id) or {{}}
{indent}    _stage = str(st.get("stage_name") or "").lower()
{indent}    _ci = str(st.get("ci_run_dir") or "")
{indent}    if ("kics" in _stage) and _ci:
{indent}        _klog = os.path.join(_ci, "kics", "kics.log")
{indent}        if os.path.exists(_klog):
{indent}            _raw = open(_klog, "rb").read()[-65536:].decode("utf-8", errors="ignore").replace("\\r","\\n")
{indent}            _hb = ""
{indent}            for _ln in reversed(_raw.splitlines()):
{indent}                if "][HB]" in _ln and "[KICS_V" in _ln:
{indent}                    _hb = _ln.strip()
{indent}                    break
{indent}            _lines = [x for x in _raw.splitlines() if x.strip()]
{indent}            _tail = "\\n".join(_lines[-25:])
{indent}            if _hb and (_hb not in _tail):
{indent}                _tail = _hb + "\\n" + _tail
{indent}            st["tail"] = _tail[-4096:]
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===
"""

t2 = t.replace(ret_line, block + ret_line)
p.write_text(t2, encoding="utf-8")
print("[OK] inserted V6 before fallback return")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo

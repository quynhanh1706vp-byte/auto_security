#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_tail_kics_replace_v6_${TS}"
echo "[BACKUP] $F.bak_tail_kics_replace_v6_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

pat = re.compile(
    r"^(?P<ind>[ \t]*)# === VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===\s*\n"
    r".*?"
    r"^(?P=ind)# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===\s*\n?",
    flags=re.M | re.S
)

m = pat.search(t)
if not m:
    print("[ERR] cannot find V5 marker block to replace")
    raise SystemExit(2)

ind = m.group("ind")
block = (
f"{ind}# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===\n"
f"{ind}try:\n"
f"{ind}    import os\n"
f"{ind}    st = _VSP_FALLBACK_REQ.get(req_id) or {{}}\n"
f"{ind}    _stage = str(st.get('stage_name') or '').lower()\n"
f"{ind}    _ci = str(st.get('ci_run_dir') or '')\n"
f"{ind}    if ('kics' in _stage) and _ci:\n"
f"{ind}        _klog = os.path.join(_ci, 'kics', 'kics.log')\n"
f"{ind}        if os.path.exists(_klog):\n"
f"{ind}            _raw = open(_klog, 'rb').read()[-65536:].decode('utf-8', errors='ignore').replace('\\r','\\n')\n"
f"{ind}            _hb = ''\n"
f"{ind}            for _ln in reversed(_raw.splitlines()):\n"
f"{ind}                if '][HB]' in _ln and '[KICS_V' in _ln:\n"
f"{ind}                    _hb = _ln.strip()\n"
f"{ind}                    break\n"
f"{ind}            _lines = [x for x in _raw.splitlines() if x.strip()]\n"
f"{ind}            _tail = '\\n'.join(_lines[-25:])\n"
f"{ind}            if _hb and (_hb not in _tail):\n"
f"{ind}                _tail = _hb + '\\n' + _tail\n"
f"{ind}            st['tail'] = _tail[-4096:]\n"
f"{ind}            _VSP_FALLBACK_REQ[req_id] = st\n"
f"{ind}except Exception:\n"
f"{ind}    pass\n"
f"{ind}# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===\n"
)

t2 = pat.sub(block, t, count=1)
p.write_text(t2, encoding="utf-8")
print("[OK] replaced V5 block -> V6 block")
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

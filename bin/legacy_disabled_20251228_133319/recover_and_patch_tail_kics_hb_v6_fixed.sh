#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] backup current =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_tailfix_${TS}"
echo "[BACKUP] $F.bak_before_tailfix_${TS}"

echo "== [2] recover to latest COMPILABLE backup if needed =="
if python3 -m py_compile "$F" >/dev/null 2>&1; then
  echo "[OK] current file compiles"
else
  echo "[WARN] current file does NOT compile. searching backups..."
  CANDS="$(ls -1t vsp_demo_app.py.bak_* 2>/dev/null || true)"
  [ -n "$CANDS" ] || { echo "[ERR] no backups found: vsp_demo_app.py.bak_*"; exit 2; }

  OK_BAK=""
  for B in $CANDS; do
    cp -f "$B" "$F"
    if python3 -m py_compile "$F" >/dev/null 2>&1; then
      OK_BAK="$B"
      break
    fi
  done

  [ -n "$OK_BAK" ] || { echo "[ERR] no compilable backup found"; exit 3; }
  echo "[OK] restored $F <= $OK_BAK"
fi

echo "== [3] patch _fallback_run_status_v1: override tail from kics.log + HB (V6_FIXED) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove old attempts (best-effort)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===\s*\n?", "\n", t, flags=re.S)

# locate fallback handler
m = re.search(r"(?ms)^(\s*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*\n", t)
if not m:
    print("[ERR] cannot find def _fallback_run_status_v1(req_id)")
    raise SystemExit(2)

fn_start = m.end()
# find the return line inside this handler (first return that returns fallback req)
ret = re.search(
    r"(?m)^(?P<ind>[ \t]+)return\s+jsonify\(\s*_vsp_contractize\(\s*_VSP_FALLBACK_REQ\s*\[\s*req_id\s*\]\s*\)\s*\)\s*(?:,\s*200\s*)?$",
    t[fn_start:]
)
if not ret:
    print("[ERR] cannot find return jsonify(_vsp_contractize(_VSP_FALLBACK_REQ[req_id])) in fallback handler")
    raise SystemExit(3)

ind = ret.group("ind")
ins_pos = fn_start + ret.start()

block = (
f"{ind}# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===\n"
f"{ind}try:\n"
f"{ind}    import os\n"
f"{ind}    st = _VSP_FALLBACK_REQ.get(req_id) or {{}}\n"
f"{ind}    _stage = str(st.get('stage_name') or '').lower()\n"
f"{ind}    _ci = str(st.get('ci_run_dir') or '')\n"
f"{ind}    if ('kics' in _stage) and _ci:\n"
f"{ind}        _klog = os.path.join(_ci, 'kics', 'kics.log')\n"
f"{ind}        if os.path.exists(_klog):\n"
f"{ind}            _rawb = open(_klog, 'rb').read()\n"
f"{ind}            _raw = (_rawb[-65536:] if len(_rawb) > 65536 else _rawb).decode('utf-8', errors='ignore')\n"
f"{ind}            _raw = _raw.replace('\\\\r', '\\\\n')  # IMPORTANT: keep as escapes in source\n"
f"{ind}            _hb = ''\n"
f"{ind}            for _ln in reversed(_raw.splitlines()):\n"
f"{ind}                if '][HB]' in _ln and '[KICS_V' in _ln:\n"
f"{ind}                    _hb = _ln.strip()\n"
f"{ind}                    break\n"
f"{ind}            _lines = [x for x in _raw.splitlines() if x.strip()]\n"
f"{ind}            _tail = '\\\\n'.join(_lines[-25:])\n"
f"{ind}            if _hb and (_hb not in _tail):\n"
f"{ind}                _tail = _hb + '\\\\n' + _tail\n"
f"{ind}            st['tail'] = (_tail or '')[-4096:]\n"
f"{ind}            _VSP_FALLBACK_REQ[req_id] = st\n"
f"{ind}except Exception:\n"
f"{ind}    pass\n"
f"{ind}# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===\n"
)

t2 = t[:ins_pos] + block + t[ins_pos:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted V6_FIXED block before return in _fallback_run_status_v1")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [4] restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"

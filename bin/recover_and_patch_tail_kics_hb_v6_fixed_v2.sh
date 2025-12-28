#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] backup current =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_tailfix_v2_${TS}"
echo "[BACKUP] $F.bak_before_tailfix_v2_${TS}"

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

echo "== [3] patch _fallback_run_status_v1: override tail from kics.log + HB (V6_FIXED_V2) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# cleanup old attempts (best-effort)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V5 ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6 ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V2 ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V2 ===\s*\n?", "\n", t, flags=re.S)

# locate def
m = re.search(r"(?m)^(?P<defind>[ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", t)
if not m:
    print("[ERR] cannot find def _fallback_run_status_v1(req_id)")
    raise SystemExit(2)

def_ind = m.group("defind")
start = m.end()

# compute body indent from next non-empty line
body_ind = None
for mm in re.finditer(r"(?m)^(?P<ind>[ \t]*)\S", t[start:]):
    cand = mm.group("ind")
    # must be deeper indent than def line
    if len(cand) > len(def_ind):
        body_ind = cand
        break
if body_ind is None:
    print("[ERR] cannot determine body indent")
    raise SystemExit(3)

# find function end: first line at indent <= def_ind after start (non-empty)
end = len(t)
for mm in re.finditer(r"(?m)^(?P<ind>[ \t]*)\S", t[start:]):
    ind = mm.group("ind")
    if len(ind) <= len(def_ind):
        end = start + mm.start()
        break

fn = t[start:end]

# find last "return" at body indent inside function
ret_positions = [mm.start() for mm in re.finditer(r"(?m)^" + re.escape(body_ind) + r"return\b", fn)]
if not ret_positions:
    print("[ERR] cannot find any return in _fallback_run_status_v1")
    raise SystemExit(4)

ins_rel = ret_positions[-1]
ins_pos = start + ins_rel

block = (
f"{body_ind}# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V2 ===\n"
f"{body_ind}try:\n"
f"{body_ind}    import os\n"
f"{body_ind}    st = _VSP_FALLBACK_REQ.get(req_id) or {{}}\n"
f"{body_ind}    _stage = str(st.get('stage_name') or '').lower()\n"
f"{body_ind}    _ci = str(st.get('ci_run_dir') or '')\n"
f"{body_ind}    if ('kics' in _stage) and _ci:\n"
f"{body_ind}        _klog = os.path.join(_ci, 'kics', 'kics.log')\n"
f"{body_ind}        if os.path.exists(_klog):\n"
f"{body_ind}            _rawb = open(_klog, 'rb').read()\n"
f"{body_ind}            _rawb = (_rawb[-65536:] if len(_rawb) > 65536 else _rawb)\n"
f"{body_ind}            _raw = _rawb.decode('utf-8', errors='ignore')\n"
f"{body_ind}            _raw = _raw.replace('\\\\r', '\\\\n')\n"
f"{body_ind}            _hb = ''\n"
f"{body_ind}            for _ln in reversed(_raw.splitlines()):\n"
f"{body_ind}                if '][HB]' in _ln and '[KICS_V' in _ln:\n"
f"{body_ind}                    _hb = _ln.strip()\n"
f"{body_ind}                    break\n"
f"{body_ind}            _lines = [x for x in _raw.splitlines() if x.strip()]\n"
f"{body_ind}            _tail = '\\\\n'.join(_lines[-25:])\n"
f"{body_ind}            if _hb and (_hb not in _tail):\n"
f"{body_ind}                _tail = _hb + '\\\\n' + _tail\n"
f"{body_ind}            st['tail'] = (_tail or '')[-4096:]\n"
f"{body_ind}            _VSP_FALLBACK_REQ[req_id] = st\n"
f"{body_ind}except Exception:\n"
f"{body_ind}    pass\n"
f"{body_ind}# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V2 ===\n"
)

t2 = t[:ins_pos] + block + t[ins_pos:]
p.write_text(t2, encoding="utf-8")
print("[OK] inserted V6_FIXED_V2 block before last return in _fallback_run_status_v1")
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

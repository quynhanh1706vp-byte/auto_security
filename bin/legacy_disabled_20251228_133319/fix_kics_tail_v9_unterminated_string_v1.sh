#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_kics_tail_v9_unterm_${TS}"
echo "[BACKUP] $F.bak_fix_kics_tail_v9_unterm_${TS}"

echo "== [1] ensure vsp_demo_app.py is compilable (auto-restore if needed) =="
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

echo "== [2] patch KICS tail block (replace V9 or V8 -> V9_FIXED2) =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

def build_block(ind: str) -> str:
    step = "    "
    L = []
    L.append(f"{ind}# === VSP_STATUS_TAIL_OVERRIDE_KICS_V9_FIXED2 ===")
    L.append(f"{ind}try:")
    L.append(f"{ind}{step}import os, json")
    L.append(f"{ind}{step}from pathlib import Path")
    L.append(f"{ind}{step}NL = chr(10)")
    L.append(f"{ind}{step}_stage = str(_out.get('stage_name') or '').lower()")
    L.append(f"{ind}{step}_ci = str(_out.get('ci_run_dir') or '')")
    L.append(f"{ind}{step}# fallback: read persisted uireq state to get ci_run_dir")
    L.append(f"{ind}{step}if not _ci:")
    L.append(f"{ind}{step}{step}try:")
    L.append(f"{ind}{step}{step}{step}_st = (Path(__file__).resolve().parent / 'out_ci' / 'uireq_v1' / (req_id + '.json'))")
    L.append(f"{ind}{step}{step}{step}if _st.exists():")
    L.append(f"{ind}{step}{step}{step}{step}txt = _st.read_text(encoding='utf-8', errors='ignore') or ''")
    L.append(f"{ind}{step}{step}{step}{step}j = json.loads(txt) if txt.strip() else dict()")
    L.append(f"{ind}{step}{step}{step}{step}_ci = str(j.get('ci_run_dir') or '')")
    L.append(f"{ind}{step}{step}except Exception:")
    L.append(f"{ind}{step}{step}{step}pass")
    L.append(f"{ind}{step}if _ci:")
    L.append(f"{ind}{step}{step}_klog = os.path.join(_ci, 'kics', 'kics.log')")
    L.append(f"{ind}{step}{step}if os.path.exists(_klog):")
    L.append(f"{ind}{step}{step}{step}rawb = Path(_klog).read_bytes()")
    L.append(f"{ind}{step}{step}{step}if len(rawb) > 65536:")
    L.append(f"{ind}{step}{step}{step}{step}rawb = rawb[-65536:]")
    L.append(f"{ind}{step}{step}{step}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)")
    L.append(f"{ind}{step}{step}{step}hb = ''")
    L.append(f"{ind}{step}{step}{step}for ln in reversed(raw.splitlines()):")
    L.append(f"{ind}{step}{step}{step}{step}if '][HB]' in ln and '[KICS_V' in ln:")
    L.append(f"{ind}{step}{step}{step}{step}{step}hb = ln.strip()")
    L.append(f"{ind}{step}{step}{step}{step}{step}break")
    L.append(f"{ind}{step}{step}{step}clean = [x for x in raw.splitlines() if x.strip()]")
    L.append(f"{ind}{step}{step}{step}ktail = NL.join(clean[-25:])")
    L.append(f"{ind}{step}{step}{step}if hb and (hb not in ktail):")
    L.append(f"{ind}{step}{step}{step}{step}ktail = hb + NL + ktail")
    L.append(f"{ind}{step}{step}{step}_out['kics_tail'] = (ktail or '')[-4096:]")
    L.append(f"{ind}{step}{step}{step}# only override main tail when stage is KICS")
    L.append(f"{ind}{step}{step}{step}if 'kics' in _stage:")
    L.append(f"{ind}{step}{step}{step}{step}_out['tail'] = _out.get('kics_tail','')")
    L.append(f"{ind}except Exception:")
    L.append(f"{ind}{step}pass")
    L.append(f"{ind}# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V9_FIXED2 ===")
    return "\n".join(L) + "\n"

# try replace V9 block first
pat_v9 = re.compile(
    r"(?m)^(?P<ind>[ \t]*)# === VSP_STATUS_TAIL_OVERRIDE_KICS_V9[^\n]* ===\s*\n"
    r".*?"
    r"^(?P=ind)# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V9[^\n]* ===\s*\n?",
    flags=re.M | re.S
)
m9 = pat_v9.search(t)
if m9:
    ind = m9.group("ind")
    t2 = pat_v9.sub(build_block(ind), t, count=1)
    p.write_text(t2, encoding="utf-8")
    print("[OK] replaced V9* -> V9_FIXED2")
    raise SystemExit(0)

# else replace V8 block
pat_v8 = re.compile(
    r"(?m)^(?P<ind>[ \t]*)# === VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ===\s*\n"
    r".*?"
    r"^(?P=ind)# === END VSP_STATUS_TAIL_OVERRIDE_KICS_V8 ===\s*\n?",
    flags=re.M | re.S
)
m8 = pat_v8.search(t)
if not m8:
    raise SystemExit("[ERR] cannot find V8/V9 markers to replace")

ind = m8.group("ind")
t2 = pat_v8.sub(build_block(ind), t, count=1)
p.write_text(t2, encoding="utf-8")
print("[OK] replaced V8 -> V9_FIXED2")
PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [3] restart 8910 =="
PIDS="$(lsof -ti :8910 2>/dev/null || true)"
if [ -n "${PIDS}" ]; then
  echo "[KILL] 8910 pids: ${PIDS}"
  kill -9 ${PIDS} || true
fi
nohup python3 /home/test/Data/SECURITY_BUNDLE/ui/vsp_demo_app.py > /home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz; echo
echo "[OK] done"

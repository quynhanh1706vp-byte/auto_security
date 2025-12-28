#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_force_kics_tail_${TS}"
echo "[BACKUP] $F.bak_force_kics_tail_${TS}"

echo "== [1] ensure file is compilable (auto-restore from backups if needed) =="
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

echo "== [2] sanitize stray '===' lines (comment them out) =="
python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

changed = 0
out = []
for ln in lines:
    # line only contains === / ===== / etc (optionally spaces)
    if re.match(r"^\s*={3,}\s*$", ln):
        out.append("# " + ln)
        changed += 1
    else:
        out.append(ln)

if changed:
    p.write_text("".join(out), encoding="utf-8")
print(f"[OK] sanitized === lines: {changed}")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile after sanitize OK"

echo "== [3] patch final return of _fallback_run_status_v1 to FORCE kics_tail =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("vsp_demo_app.py")
lines = p.read_text(encoding="utf-8", errors="ignore").splitlines(True)

TAG_BEG = "# === VSP_FORCE_KICS_TAIL_FINAL_RETURN_V1 ==="
TAG_END = "# === END VSP_FORCE_KICS_TAIL_FINAL_RETURN_V1 ==="

# remove old patch if exists
txt = "".join(lines)
txt2 = re.sub(r"(?s)\n?\s*# === VSP_FORCE_KICS_TAIL_FINAL_RETURN_V1 ===.*?# === END VSP_FORCE_KICS_TAIL_FINAL_RETURN_V1 ===\s*\n?", "\n", txt)
lines = txt2.splitlines(True)

# locate def _fallback_run_status_v1
def_i = None
def_ind = ""
for i, s in enumerate(lines):
    m = re.match(r"^([ \t]*)def\s+_fallback_run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", s)
    if m:
        def_i = i
        def_ind = m.group(1)
        break
if def_i is None:
    raise SystemExit("[ERR] cannot find def _fallback_run_status_v1(req_id)")

def_ind_len = len(def_ind)

# detect indent unit from first non-empty line after def
indent_unit = "    "
for j in range(def_i+1, min(def_i+80, len(lines))):
    s = lines[j]
    if s.strip() == "":
        continue
    m = re.match(r"^([ \t]+)\S", s)
    if m:
        indent_unit = m.group(1)[def_ind_len:]
    break

# find function end (next top-level def or decorator at same/below indent)
end_i = len(lines)
for k in range(def_i+1, len(lines)):
    s = lines[k]
    if re.match(r"^([ \t]*)def\s+\w+\s*\(", s):
        if len(re.match(r"^([ \t]*)", s).group(1)) <= def_ind_len:
            end_i = k
            break
    if re.match(r"^([ \t]*)@\w", s):
        if len(re.match(r"^([ \t]*)", s).group(1)) <= def_ind_len:
            end_i = k
            break

func = lines[def_i:end_i]

# find LAST "return jsonify(...), 200" inside function
ret_idx = None
ret_line = None
for idx in range(len(func)-1, -1, -1):
    s = func[idx].strip()
    if s.startswith("return jsonify(") and re.search(r"\)\s*,\s*200\s*$", s):
        ret_idx = idx
        ret_line = func[idx]
        break
if ret_idx is None:
    raise SystemExit("[ERR] cannot find 'return jsonify(...), 200' in _fallback_run_status_v1")

# derive indent of return line
ret_ind = re.match(r"^([ \t]*)", ret_line).group(1)

# extract expr inside jsonify(...)
s = ret_line.strip()
inner = s[len("return jsonify("):]
expr = re.sub(r"\)\s*,\s*200\s*$", "", inner).rstrip()

patch = []
patch.append(f"{ret_ind}{TAG_BEG}\n")
patch.append(f"{ret_ind}_out = {expr}\n")
patch.append(f"{ret_ind}try:\n")
patch.append(f"{ret_ind}{indent_unit}import os, json\n")
patch.append(f"{ret_ind}{indent_unit}from pathlib import Path\n")
patch.append(f"{ret_ind}{indent_unit}NL = chr(10)\n")
patch.append(f"{ret_ind}{indent_unit}if isinstance(_out, dict):\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}stage = str(_out.get('stage_name') or '').lower()\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}ci = str(_out.get('ci_run_dir') or '')\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}if ('kics' in stage) and ci:\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}klog = os.path.join(ci, 'kics', 'kics.log')\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}if os.path.exists(klog):\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}rawb = Path(klog).read_bytes()\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if len(rawb) > 65536:\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}rawb = rawb[-65536:]\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}raw = rawb.decode('utf-8', errors='ignore').replace(chr(13), NL)\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}hb = ''\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}for ln in reversed(raw.splitlines()):\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if '][HB]' in ln and '[KICS_V' in ln:\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}hb = ln.strip(); break\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}lines2 = [x for x in raw.splitlines() if x.strip()]\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}tail = NL.join(lines2[-30:])\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}if hb and (hb not in tail):\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}{indent_unit}tail = hb + NL + tail\n")
patch.append(f"{ret_ind}{indent_unit}{indent_unit}{indent_unit}{indent_unit}_out['kics_tail'] = tail[-4096:]\n")
patch.append(f"{ret_ind}except Exception:\n")
patch.append(f"{ret_ind}{indent_unit}pass\n")
patch.append(f"{ret_ind}{TAG_END}\n")
patch.append(f"{ret_ind}return jsonify(_out), 200\n")

# replace that one return line
new_func = func[:ret_idx] + patch + func[ret_idx+1:]
new_lines = lines[:def_i] + new_func + lines[end_i:]

p.write_text("".join(new_lines), encoding="utf-8")
print(f"[OK] patched final return in _fallback_run_status_v1 (indent_unit={repr(indent_unit)})")
PY

python3 -m py_compile "$F" >/dev/null
echo "[OK] py_compile OK"

echo "== [4] restart 8910 =="
pkill -f "vsp_demo_app.py" >/dev/null 2>&1 || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
curl -sS http://127.0.0.1:8910/healthz || true
echo
echo "[OK] done"

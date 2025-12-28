#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

echo "== [1] backup current =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_tailfix_v4_${TS}"
echo "[BACKUP] $F.bak_before_tailfix_v4_${TS}"

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

echo "== [3] patch _fallback_run_status_v1 by AST: override tail from kics.log + HB (V6_FIXED_V4_AST) =="
python3 - <<'PY'
import ast, re
from pathlib import Path

p = Path("vsp_demo_app.py")
t = p.read_text(encoding="utf-8", errors="ignore")

# remove ALL old attempts (best-effort)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_APPEND_KICS_HB_V[0-9A-Z_]+ ===[\s\S]*?# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V[0-9A-Z_]+ ===\s*\n?", "\n", t, flags=re.S)
t = re.sub(r"\n?\s*# === VSP_STATUS_TAIL_PREFER_KICS_LOG_V[0-9A-Z_]+ ===[\s\S]*?# === END VSP_STATUS_TAIL_PREFER_KICS_LOG_V[0-9A-Z_]+ ===\s*\n?", "\n", t, flags=re.S)

TAG = "# === VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V4_AST ==="
if TAG in t:
    print("[OK] already patched V6_FIXED_V4_AST")
    p.write_text(t, encoding="utf-8")
    raise SystemExit(0)

mod = ast.parse(t)

# find nested FunctionDef named _fallback_run_status_v1
target = None
for node in ast.walk(mod):
    if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef)) and node.name == "_fallback_run_status_v1":
        target = node
        break
if target is None:
    print("[ERR] cannot find function: _fallback_run_status_v1")
    raise SystemExit(2)

lines = t.splitlines(True)  # keep line endings

def_line_idx = target.lineno - 1
def_line = lines[def_line_idx]
def_ind = def_line[:len(def_line) - len(def_line.lstrip())]

# detect body indent from first non-empty line after def (fallback to def_ind + 4 spaces)
body_ind = None
for i in range(def_line_idx + 1, min(len(lines), def_line_idx + 200)):
    s = lines[i]
    if s.strip() == "":
        continue
    ind = s[:len(s) - len(s.lstrip())]
    if len(ind) > len(def_ind):
        body_ind = ind
        break
if body_ind is None:
    body_ind = def_ind + "    "

# insert AFTER docstring if exists
insert_line_idx = def_line_idx + 1
if target.body and isinstance(target.body[0], ast.Expr) and isinstance(getattr(target.body[0], "value", None), ast.Constant) and isinstance(target.body[0].value.value, str):
    ds_end = getattr(target.body[0], "end_lineno", target.body[0].lineno)
    insert_line_idx = ds_end  # 0-based will be ds_end because lineno is 1-based

block = [
    f"{body_ind}{TAG}\n",
    f"{body_ind}try:\n",
    f"{body_ind}    import os\n",
    f"{body_ind}    st = _VSP_FALLBACK_REQ.get(req_id) or {{}}\n",
    f"{body_ind}    _stage = str(st.get('stage_name') or '').lower()\n",
    f"{body_ind}    _ci = str(st.get('ci_run_dir') or '')\n",
    f"{body_ind}    if ('kics' in _stage) and _ci:\n",
    f"{body_ind}        _klog = os.path.join(_ci, 'kics', 'kics.log')\n",
    f"{body_ind}        if os.path.exists(_klog):\n",
    f"{body_ind}            _rawb = open(_klog, 'rb').read()\n",
    f"{body_ind}            _rawb = (_rawb[-65536:] if len(_rawb) > 65536 else _rawb)\n",
    f"{body_ind}            _raw = _rawb.decode('utf-8', errors='ignore').replace('\\r','\\n')\n",
    f"{body_ind}            _hb = ''\n",
    f"{body_ind}            for _ln in reversed(_raw.splitlines()):\n",
    f"{body_ind}                if '][HB]' in _ln and '[KICS_V' in _ln:\n",
    f"{body_ind}                    _hb = _ln.strip()\n",
    f"{body_ind}                    break\n",
    f"{body_ind}            _lines = [x for x in _raw.splitlines() if x.strip()]\n",
    f"{body_ind}            _tail = '\\n'.join(_lines[-25:])\n",
    f"{body_ind}            if _hb and (_hb not in _tail):\n",
    f"{body_ind}                _tail = _hb + '\\n' + _tail\n",
    f"{body_ind}            st['tail'] = (_tail or '')[-4096:]\n",
    f"{body_ind}            _VSP_FALLBACK_REQ[req_id] = st\n",
    f"{body_ind}except Exception:\n",
    f"{body_ind}    pass\n",
    f"{body_ind}# === END VSP_STATUS_TAIL_APPEND_KICS_HB_V6_FIXED_V4_AST ===\n",
]

# insert into lines
lines[insert_line_idx:insert_line_idx] = block
out = "".join(lines)

# sanity compile
ast.parse(out)

p.write_text(out, encoding="utf-8")
print(f"[OK] inserted V6_FIXED_V4_AST at line ~{insert_line_idx+1} body_ind={repr(body_ind)}")
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

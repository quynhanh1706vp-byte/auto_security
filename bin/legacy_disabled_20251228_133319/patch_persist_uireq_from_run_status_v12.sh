#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"

pick="$(grep -Rsl --include='*.py' -E 'def\s+run_status_v1\s*\(|run_status_v1\s*=' "$UI_ROOT" | head -n 1 || true)"
[ -n "${pick:-}" ] || { echo "[ERR] cannot find python file defining run_status_v1 under $UI_ROOT"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$pick" "$pick.bak_persist_uireq_status_v12_${TS}"
echo "[BACKUP] $pick.bak_persist_uireq_status_v12_${TS}"

python3 - "$pick" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_FROM_STATUS_V12" in txt:
    print("[OK] already patched V12.")
    raise SystemExit(0)

helper = r'''
# === VSP_UIREQ_PERSIST_FROM_STATUS_V12 ===
from pathlib import Path as _Path
import json as _json
import time as _time
import os as _os

def _uireq_ui_root_v12():
    # this file is usually ui/run_api/*.py -> parents[1] == ui/
    return _Path(__file__).resolve().parents[1]

def _uireq_state_dir_v12():
    d = _uireq_ui_root_v12() / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_safe_dict_v12(obj):
    return obj if isinstance(obj, dict) else {}

def _uireq_state_update_v12(req_id: str, patch: dict):
    try:
        fp = _uireq_state_dir_v12() / f"{req_id}.json"
        try:
            cur = _json.loads(fp.read_text(encoding="utf-8"))
        except Exception:
            cur = {"ok": True, "req_id": req_id}

        patch = _uireq_safe_dict_v12(patch)
        for k, v in patch.items():
            if v is None:
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or req_id
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = str(fp) + ".tmp"
        _Path(tmp).write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        _os.replace(tmp, fp)
        return True
    except Exception:
        try:
            app.logger.exception("[UIREQ][V12] persist update failed")
        except Exception:
            pass
        return False
# === END VSP_UIREQ_PERSIST_FROM_STATUS_V12 ===
'''.lstrip("\n")

# insert helper after set of imports (best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + helper + "\n" + txt[m.end():]
else:
    lines = txt.splitlines(True)
    txt = "".join(lines[:1]) + "\n" + helper + "\n" + "".join(lines[1:])

# find def run_status_v1
mm = re.search(r'^\s*def\s+run_status_v1\s*\(.*\)\s*:\s*$', txt, flags=re.M)
if not mm:
    print("[ERR] cannot find 'def run_status_v1(...)' in file.")
    raise SystemExit(3)

def_start = mm.start()
def_indent = len(mm.group(0)) - len(mm.group(0).lstrip(" \t"))

# find end of function block
lines = txt.splitlines(True)
# line index of def
li_def = 0
pos = 0
for i, ln in enumerate(lines):
    if pos <= def_start < pos + len(ln):
        li_def = i
        break
    pos += len(ln)

end = len(lines)
for j in range(li_def + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = j
        break

# locate first "return jsonify(" inside the function
ret_idx = None
for j in range(li_def, end):
    if re.match(r'^\s*return\s+jsonify\s*\(', lines[j]):
        ret_idx = j
        break
if ret_idx is None:
    print("[ERR] cannot find 'return jsonify(' inside run_status_v1.")
    raise SystemExit(4)

indent = re.match(r'^(\s*)', lines[ret_idx]).group(1)

# Try parse single-line expression inside jsonify(...)
expr = None
mret = re.match(r'^\s*return\s+jsonify\s*\(\s*(.+?)\s*\)\s*$', lines[ret_idx].rstrip("\n"))
if mret:
    expr = mret.group(1)

if expr and "{" not in expr:
    hook = f"""{indent}# === VSP_UIREQ_PERSIST_FROM_STATUS_V12 hook ===
{indent}try:
{indent}    _rid = locals().get("req_id") or locals().get("request_id") or locals().get("rid")
{indent}    if _rid:
{indent}        _uireq_state_update_v12(_rid, _uireq_safe_dict_v12({expr}))
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_UIREQ_PERSIST_FROM_STATUS_V12 hook ===
"""
else:
    # fallback: use common variable names in locals (resp/out/data/payload)
    hook = f"""{indent}# === VSP_UIREQ_PERSIST_FROM_STATUS_V12 hook ===
{indent}try:
{indent}    _rid = locals().get("req_id") or locals().get("request_id") or locals().get("rid")
{indent}    _payload = (locals().get("resp") or locals().get("out") or locals().get("data") or locals().get("payload") or {{}})
{indent}    if _rid:
{indent}        _uireq_state_update_v12(_rid, _uireq_safe_dict_v12(_payload))
{indent}except Exception:
{indent}    pass
{indent}# === END VSP_UIREQ_PERSIST_FROM_STATUS_V12 hook ===
"""

lines.insert(ret_idx, hook)
p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] patched {p.name} (V12) to persist state on run_status_v1.")
PY

echo "== PY COMPILE CHECK =="
python3 -m py_compile "$pick" && echo "[OK] py_compile passed"

echo "== QUICK GREP (V12) =="
grep -n "VSP_UIREQ_PERSIST_FROM_STATUS_V12" "$pick" | head -n 80 || true

echo "[DONE] Restart 8910 then call run_status_v1 once to create/update state file."

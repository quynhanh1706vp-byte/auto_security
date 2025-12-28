#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v5_1_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v5_1_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V5_1_BEFORE_RETURN_JSONIFY"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1() region
m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")
dindent = m.group("dindent")
start = m.start()
m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
fn = txt[start:end]

# find a one-line return jsonify(...) (optionally with , <code>)
ret = re.search(r"(?m)^(?P<ind>[ \t]*)return\s+jsonify\(\s*(?P<expr>[^)\n]+?)\s*\)\s*$", fn)
code = None
if not ret:
    ret = re.search(r"(?m)^(?P<ind>[ \t]*)return\s+jsonify\(\s*(?P<expr>[^)\n]+?)\s*\)\s*,\s*(?P<code>\d+)\s*$", fn)
    if ret:
        code = ret.group("code")
if not ret:
    raise SystemExit("[ERR] cannot find any one-line 'return jsonify(...)' inside run_status_v1() (maybe multi-line).")

ind = ret.group("ind")
expr = ret.group("expr").strip()

new_lines = []
new_lines.append(f"{ind}_st = {expr}")
new_lines.append(f"{ind}# {MARK}")
new_lines.append(f"{ind}try:")
new_lines.append(f"{ind}  _json = __import__('json')")
new_lines.append(f"{ind}  _P = __import__('pathlib').Path")
new_lines.append(f"{ind}  _req = None")
new_lines.append(f"{ind}  try:")
new_lines.append(f"{ind}    _req = (_st.get('req_id') if isinstance(_st, dict) else None) or (_st.get('request_id') if isinstance(_st, dict) else None)")
new_lines.append(f"{ind}  except Exception:")
new_lines.append(f"{ind}    _req = None")
new_lines.append(f"{ind}  if not _req:")
new_lines.append(f"{ind}    _req = locals().get('req_id') or locals().get('REQ_ID') or locals().get('request_id') or locals().get('REQUEST_ID')")
new_lines.append(f"{ind}  if _req:")
new_lines.append(f"{ind}    if '_state_file_path_v1' in globals():")
new_lines.append(f"{ind}      sp = _state_file_path_v1(_req)")
new_lines.append(f"{ind}    else:")
# IMPORTANT: escape braces so target file gets f\"{_req}.json\"
new_lines.append(f"{ind}      sp = _P(_VSP_UIREQ_DIR) / f\"{{_req}}.json\"")
new_lines.append(f"{ind}    try:")
new_lines.append(f"{ind}      sp.parent.mkdir(parents=True, exist_ok=True)")
new_lines.append(f"{ind}    except Exception:")
new_lines.append(f"{ind}      pass")
new_lines.append(f"{ind}    cur = {{}}")
new_lines.append(f"{ind}    try:")
new_lines.append(f"{ind}      if sp.exists():")
new_lines.append(f"{ind}        cur = _json.loads(sp.read_text(encoding='utf-8', errors='replace'))")
new_lines.append(f"{ind}    except Exception:")
new_lines.append(f"{ind}      cur = {{}}")
new_lines.append(f"{ind}    cur['request_id'] = cur.get('request_id') or _req")
new_lines.append(f"{ind}    cur['req_id'] = cur.get('req_id') or _req")
new_lines.append(f"{ind}    if isinstance(_st, dict):")
new_lines.append(f"{ind}      if _st.get('ci_run_dir'): cur['ci_run_dir'] = _st.get('ci_run_dir')")
new_lines.append(f"{ind}      if _st.get('runner_log'): cur['runner_log'] = _st.get('runner_log')")
new_lines.append(f"{ind}    sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding='utf-8')")
new_lines.append(f"{ind}    print('[{MARK}] persisted', str(sp), 'ci_run_dir=', cur.get('ci_run_dir'))")
new_lines.append(f"{ind}except Exception as _e:")
new_lines.append(f"{ind}  print('[{MARK}] WARN', _e)")

if code:
    new_lines.append(f"{ind}return jsonify(_st), {code}")
else:
    new_lines.append(f"{ind}return jsonify(_st)")

new_block = "\n".join(new_lines)
fn2 = fn[:ret.start()] + new_block + "\n" + fn[ret.end():]

txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v5_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v5_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V5_BEFORE_RETURN_JSONIFY"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1() function region
m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")
dindent = m.group("dindent")
start = m.start()
m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)
fn = txt[start:end]

# find a "return jsonify(EXPR)" inside run_status_v1
# prefer simple one-line return; we will rewrite it into:
#   _st = EXPR
#   (persist _st ...)
#   return jsonify(_st)
ret = re.search(r"(?m)^(?P<ind>[ \t]*)return\s+jsonify\(\s*(?P<expr>[^)\n]+?)\s*\)\s*$", fn)
if not ret:
    # fallback: tolerate trailing ", 200" etc is unlikely but handle
    ret = re.search(r"(?m)^(?P<ind>[ \t]*)return\s+jsonify\(\s*(?P<expr>[^)\n]+?)\s*\)\s*,\s*(?P<code>\d+)\s*$", fn)
if not ret:
    raise SystemExit("[ERR] cannot find any 'return jsonify(...)' inside run_status_v1() (maybe multi-line).")

ind = ret.group("ind")
expr = ret.group("expr").strip()
code = ret.groupdict().get("code")

# rewrite return to use _st
new_ret_lines = []
new_ret_lines.append(f"{ind}_st = {expr}")

# persist block (use safe imports; tolerate req_id/REQ_ID, etc.)
new_ret_lines.append(f"{ind}# {MARK}")
new_ret_lines.append(f"{ind}try:")
new_ret_lines.append(f"{ind}  _json = __import__('json')")
new_ret_lines.append(f"{ind}  _P = __import__('pathlib').Path")
new_ret_lines.append(f"{ind}  _req = None")
new_ret_lines.append(f"{ind}  try:")
new_ret_lines.append(f"{ind}    _req = (_st.get('req_id') if isinstance(_st, dict) else None) or (_st.get('request_id') if isinstance(_st, dict) else None)")
new_ret_lines.append(f"{ind}  except Exception:")
new_ret_lines.append(f"{ind}    _req = None")
new_ret_lines.append(f"{ind}  if not _req:")
new_ret_lines.append(f"{ind}    _req = locals().get('req_id') or locals().get('REQ_ID') or locals().get('request_id') or locals().get('REQUEST_ID')")
new_ret_lines.append(f"{ind}  if _req:")
new_ret_lines.append(f"{ind}    if '_state_file_path_v1' in globals():")
new_ret_lines.append(f"{ind}      sp = _state_file_path_v1(_req)")
new_ret_lines.append(f"{ind}    else:")
new_ret_lines.append(f"{ind}      sp = _P(_VSP_UIREQ_DIR) / f\"{_req}.json\"")
new_ret_lines.append(f"{ind}    try:")
new_ret_lines.append(f"{ind}      sp.parent.mkdir(parents=True, exist_ok=True)")
new_ret_lines.append(f"{ind}    except Exception:")
new_ret_lines.append(f"{ind}      pass")
new_ret_lines.append(f"{ind}    cur = {{}}")
new_ret_lines.append(f"{ind}    try:")
new_ret_lines.append(f"{ind}      if sp.exists():")
new_ret_lines.append(f"{ind}        cur = _json.loads(sp.read_text(encoding='utf-8', errors='replace'))")
new_ret_lines.append(f"{ind}    except Exception:")
new_ret_lines.append(f"{ind}      cur = {{}}")
new_ret_lines.append(f"{ind}    cur['request_id'] = cur.get('request_id') or _req")
new_ret_lines.append(f"{ind}    cur['req_id'] = cur.get('req_id') or _req")
new_ret_lines.append(f"{ind}    if isinstance(_st, dict):")
new_ret_lines.append(f"{ind}      if _st.get('ci_run_dir'): cur['ci_run_dir'] = _st.get('ci_run_dir')")
new_ret_lines.append(f"{ind}      if _st.get('runner_log'): cur['runner_log'] = _st.get('runner_log')")
new_ret_lines.append(f"{ind}    sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding='utf-8')")
new_ret_lines.append(f"{ind}    print('[{MARK}] persisted', str(sp), 'ci_run_dir=', cur.get('ci_run_dir'))")
new_ret_lines.append(f"{ind}except Exception as _e:")
new_ret_lines.append(f"{ind}  print('[{MARK}] WARN', _e)")

# final return
if code:
    new_ret_lines.append(f"{ind}return jsonify(_st), {code}")
else:
    new_ret_lines.append(f"{ind}return jsonify(_st)")

new_block = "\n".join(new_ret_lines)

# replace the matched return line (or return line with code) with the new block
fn2 = fn[:ret.start()] + new_block + "\n" + fn[ret.end():]

txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_v7_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_v7_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUN_STATUS_PERSIST_UIREQ_V7_HOOK_ALL_RETURNS"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

m = re.search(r"(?m)^(?P<dindent>[ \t]*)def\s+run_status_v1\s*\(", txt)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(")

dindent = m.group("dindent")
start = m.start()

m2 = re.search(r"(?m)^" + re.escape(dindent) + r"def\s+\w+\s*\(", txt[m.end():])
end = (m.end() + m2.start()) if m2 else len(txt)

fn = txt[start:end]

# hook before every "return ..." line inside this function block
ret_pat = re.compile(r"(?m)^(?P<ind>[ \t]+)return\b(?P<rest>.*)$")

def inject(mm):
    ind = mm.group("ind")
    rest = mm.group("rest")
    # persistence tries to use locals st/__resp if dict; otherwise no-op
    block = "\n".join([
        f"{ind}# {MARK}",
        f"{ind}try:",
        f"{ind}  _json = __import__('json')",
        f"{ind}  _P = __import__('pathlib').Path",
        f"{ind}  _payload = None",
        f"{ind}  try:",
        f"{ind}    _st = locals().get('st')",
        f"{ind}    if isinstance(_st, dict): _payload = _st",
        f"{ind}  except Exception:",
        f"{ind}    _payload = None",
        f"{ind}  if _payload is None:",
        f"{ind}    try:",
        f"{ind}      _r = locals().get('__resp')",
        f"{ind}      if isinstance(_r, dict): _payload = _r",
        f"{ind}    except Exception:",
        f"{ind}      _payload = None",
        f"{ind}  if isinstance(_payload, dict):",
        f"{ind}    _req = (_payload.get('req_id') or _payload.get('request_id') or locals().get('req_id') or locals().get('request_id'))",
        f"{ind}    if _req:",
        f"{ind}      if '_state_file_path_v1' in globals():",
        f"{ind}        sp = _state_file_path_v1(_req)",
        f"{ind}      else:",
        f"{ind}        sp = _P(_VSP_UIREQ_DIR) / f\"{_req}.json\"",
        f"{ind}      try: sp.parent.mkdir(parents=True, exist_ok=True)",
        f"{ind}      except Exception: pass",
        f"{ind}      cur = {{}}",
        f"{ind}      try:",
        f"{ind}        if sp.exists(): cur = _json.loads(sp.read_text(encoding='utf-8', errors='replace'))",
        f"{ind}      except Exception:",
        f"{ind}        cur = {{}}",
        f"{ind}      # persist only non-null fields we care about",
        f"{ind}      cur['request_id'] = cur.get('request_id') or _req",
        f"{ind}      cur['req_id'] = cur.get('req_id') or _req",
        f"{ind}      if _payload.get('ci_run_dir') is not None: cur['ci_run_dir'] = _payload.get('ci_run_dir')",
        f"{ind}      if _payload.get('runner_log') is not None: cur['runner_log'] = _payload.get('runner_log')",
        f"{ind}      if _payload.get('stage_sig') is not None: cur['stage_sig'] = _payload.get('stage_sig')",
        f"{ind}      if _payload.get('final') is not None: cur['final'] = _payload.get('final')",
        f"{ind}      if _payload.get('killed') is not None: cur['killed'] = _payload.get('killed')",
        f"{ind}      if _payload.get('kill_reason') is not None: cur['kill_reason'] = _payload.get('kill_reason')",
        f"{ind}      sp.write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding='utf-8')",
        f"{ind}      print('[{MARK}] persisted', str(sp), 'ci_run_dir=', cur.get('ci_run_dir'))",
        f"{ind}except Exception as _e:",
        f"{ind}  print('[{MARK}] WARN', _e)",
        f"{ind}return{rest}",
    ])
    return block

fn2, n = ret_pat.subn(inject, fn)
if n == 0:
    raise SystemExit("[ERR] no return statements found inside run_status_v1()")

txt2 = txt[:start] + fn2 + txt[end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "hooked_returns=", n)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_synth_literal_bootstrap_${TS}"
echo "[BACKUP] $F.bak_synth_literal_bootstrap_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_BOOTSTRAP_BY_SYNTH_LITERAL_V2"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Ensure helper exists (write into _VSP_UIREQ_DIR)
if "_vsp_write_uireq_state_v1" not in txt:
    helper = f"""
# === {MARK}_HELPER ===
def _vsp_write_uireq_state_v1(req_id: str, req_payload: dict):
  try:
    from pathlib import Path
    import json, time, os
    d = globals().get("_VSP_UIREQ_DIR", None)
    st_dir = Path(d) if d else (Path(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1")
    st_dir.mkdir(parents=True, exist_ok=True)
    st = st_dir / (str(req_id) + ".json")
    state0 = {}
    if st.is_file():
      try:
        state0 = json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{}")
        if not isinstance(state0, dict): state0 = {}
      except Exception:
        state0 = {}
    state0.setdefault("request_id", str(req_id))
    state0.setdefault("synthetic_req_id", True)
    for k in ("mode","profile","target_type","target"):
      if (not state0.get(k)) and (req_payload.get(k) is not None):
        state0[k] = req_payload.get(k) or ""
    state0.setdefault("ci_run_dir","")
    state0.setdefault("runner_log","")
    state0.setdefault("ci_root_from_pid", None)
    state0.setdefault("watchdog_pid",0)
    state0.setdefault("stage_sig","0/0||0")
    state0.setdefault("progress_pct",0)
    state0.setdefault("killed",False)
    state0.setdefault("kill_reason","")
    state0.setdefault("final",False)
    state0.setdefault("stall_timeout_sec", int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")))
    state0.setdefault("total_timeout_sec", int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")))
    state0["state_bootstrap_ts"] = int(time.time())
    st.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"[{MARK}] wrote {st}")
  except Exception as e:
    try: print(f"[{MARK}] FAILED:", e)
    except Exception: pass
# === END {MARK}_HELPER ===
"""
    m_imp = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
    if m_imp:
        txt = txt[:m_imp.end()] + helper + "\n" + txt[m_imp.end():]
    else:
        txt = helper + "\n" + txt

# Work inside run_v1() function only
m = re.search(r"^(\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def run_v1():")

fn_indent = m.group(1)
fn_start = m.start()
m2 = re.search(rf"^{re.escape(fn_indent)}def\s+\w+\s*\(", txt[m.end():], flags=re.M)
fn_end = len(txt) if not m2 else (m.end() + m2.start())
fn = txt[fn_start:fn_end]

# Find the literal line '"synthetic_req_id": True' inside run_v1
mlit = re.search(r'^\s*["\']synthetic_req_id["\']\s*:\s*True\s*,?\s*$', fn, flags=re.M)
if not mlit:
    raise SystemExit('[ERR] cannot find literal \'"synthetic_req_id": True\' inside run_v1()')

lit_pos = mlit.start()

# Find nearest dict assignment above: VAR = {
assign = None
for mm in re.finditer(r"^(\s*)([A-Za-z_]\w*)\s*=\s*\{\s*$", fn[:lit_pos], flags=re.M):
    assign = mm
if not assign:
    raise SystemExit("[ERR] cannot find dict assignment 'var = {' above synthetic_req_id literal")

var_indent = assign.group(1)
var_name = assign.group(2)
open_brace_pos = assign.end() - 1  # position of '{' in fn

# Brace matching from that '{' to its closing '}'
s = fn
depth = 0
i = open_brace_pos
end_pos = -1
while i < len(s):
    ch = s[i]
    if ch == "{":
        depth += 1
    elif ch == "}":
        depth -= 1
        if depth == 0:
            end_pos = i
            break
    i += 1
if end_pos == -1:
    raise SystemExit("[ERR] cannot match closing brace for response dict")

# Insert injection right after the dict closes
inject = f"""
{var_indent}# === {MARK} ===
{var_indent}try:
{var_indent}  try:
{var_indent}    _req_payload = request.get_json(silent=True) or {{}}
{var_indent}  except Exception:
{var_indent}    _req_payload = {{}}
{var_indent}  _rid = str(({var_name} or {{}}).get("request_id") or "")
{var_indent}  if _rid:
{var_indent}    _vsp_write_uireq_state_v1(_rid, _req_payload)
{var_indent}except Exception:
{var_indent}  pass
{var_indent}# === END {MARK} ===
"""

fn2 = fn[:end_pos+1] + "\n" + inject + fn[end_pos+1:]
txt2 = txt[:fn_start] + fn2 + txt[fn_end:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "var=", var_name)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

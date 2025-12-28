#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_wrap_bootstrap_${TS}"
echo "[BACKUP] $F.bak_wrap_bootstrap_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_WRAPPER_TIMEOUT_BOOTSTRAP_UIREQ_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

MSG = "Scan request spawned (timeout on wrapper stdout)."

# Ensure helper exists (from your previous patch), otherwise add a minimal one
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
    state0 = {{}}
    if st.is_file():
      try:
        state0 = json.loads(st.read_text(encoding="utf-8", errors="ignore") or "{{}}")
        if not isinstance(state0, dict): state0 = {{}}
      except Exception:
        state0 = {{}}
    state0.setdefault("request_id", str(req_id))
    state0.setdefault("synthetic_req_id", True)
    for k in ("mode","profile","target_type","target"):
      if (not state0.get(k)) and (req_payload.get(k) is not None):
        state0[k] = req_payload.get(k) or ""
    state0.setdefault("ci_run_dir","")
    state0.setdefault("runner_log","")
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
    print(f"[{MARK}] wrote {{st}}")
  except Exception as e:
    try: print(f"[{MARK}] FAILED:", e)
    except Exception: pass
# === END {MARK}_HELPER ===
"""
    m = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
    if m:
        txt = txt[:m.end()] + helper + "\n" + txt[m.end():]
    else:
        txt = helper + "\n" + txt

# Find the line containing the message string
mmsg = re.search(re.escape(MSG), txt)
if not mmsg:
    raise SystemExit("[ERR] cannot find wrapper message string in file")

# Find nearest dict assignment above it:  var = {
pos = mmsg.start()
window_start = max(0, pos - 4000)
window = txt[window_start:pos]

m_assign = None
for mm in re.finditer(r"^(\s*)([A-Za-z_]\w*)\s*=\s*\{\s*$", window, flags=re.M):
    m_assign = mm
if not m_assign:
    raise SystemExit("[ERR] cannot find dict assignment (var = {) above wrapper message")

indent = m_assign.group(1)
var = m_assign.group(2)

# Now find the end of that dict: first line that is exactly indent + "}" (maybe with trailing comma)
# Search forward from assignment end within a reasonable range
after = txt[window_start + m_assign.end():]
m_close = re.search(rf"^{re.escape(indent)}\}}\s*,?\s*$", after, flags=re.M)
if not m_close:
    raise SystemExit("[ERR] cannot find closing brace of wrapper dict")

insert_at = window_start + m_assign.end() + m_close.end()

inject = f"""
{indent}# === {MARK} ===
{indent}try:
{indent}  try:
{indent}    _req_payload = request.get_json(silent=True) or {{}}
{indent}  except Exception:
{indent}    _req_payload = {{}}
{indent}  _rid = ""
{indent}  try:
{indent}    _rid = str(({var} or {{}}).get("request_id") or "")
{indent}  except Exception:
{indent}    _rid = ""
{indent}  if _rid:
{indent}    _vsp_write_uireq_state_v1(_rid, _req_payload)
{indent}except Exception:
{indent}  pass
{indent}# === END {MARK} ===
"""

txt2 = txt[:insert_at] + "\n" + inject + txt[insert_at:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "var=", var)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

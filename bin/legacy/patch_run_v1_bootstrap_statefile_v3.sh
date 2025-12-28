#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_state_${TS}"
echo "[BACKUP] $F.bak_bootstrap_state_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_STATEFILE_BOOTSTRAP_V3"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Find def run_v1 block
m = re.search(r"^(\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_v1():")

fn_indent = m.group(1)
fn_start = m.start()

# Determine function end (next def at same indent)
m2 = re.search(rf"^{re.escape(fn_indent)}def\s+\w+\s*\(", txt[m.end():], flags=re.M)
fn_end = len(txt) if not m2 else (m.end() + m2.start())

fn = txt[fn_start:fn_end]

# Find first assignment to request_id inside run_v1
m_id = re.search(r"^(\s*)request_id\s*=\s*.*$", fn, flags=re.M)
if not m_id:
    raise SystemExit("[ERR] cannot find 'request_id = ...' inside run_v1()")

indent = m_id.group(1)

inject = f"""
{indent}# === {MARK} ===
{indent}try:
{indent}    _req_payload = request.get_json(silent=True) or {{}}
{indent}except Exception:
{indent}    _req_payload = {{}}
{indent}try:
{indent}    from pathlib import Path
{indent}    import json, time
{indent}    ui_root = Path(__file__).resolve().parents[1]   # .../SECURITY_BUNDLE/ui
{indent}    st_dir = ui_root / "out_ci" / "ui_req_state"
{indent}    st_dir.mkdir(parents=True, exist_ok=True)
{indent}    st_path = st_dir / (str(request_id) + ".json")
{indent}    state0 = {{}}
{indent}    if st_path.is_file():
{indent}        try:
{indent}            state0 = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{indent}            if not isinstance(state0, dict):
{indent}                state0 = {{}}
{indent}        except Exception:
{indent}            state0 = {{}}
{indent}    state0.setdefault("request_id", request_id)
{indent}    state0.setdefault("synthetic_req_id", True)
{indent}    # backfill contract fields early
{indent}    for _k in ("mode","profile","target_type","target"):
{indent}        if (not state0.get(_k)) and (_req_payload.get(_k) is not None):
{indent}            state0[_k] = _req_payload.get(_k) or ""
{indent}    state0.setdefault("ci_run_dir", "")
{indent}    state0.setdefault("runner_log", "")
{indent}    state0.setdefault("watchdog_pid", 0)
{indent}    state0.setdefault("stage_sig", "0/0||0")
{indent}    state0.setdefault("progress_pct", 0)
{indent}    state0.setdefault("killed", False)
{indent}    state0.setdefault("kill_reason", "")
{indent}    state0.setdefault("final", False)
{indent}    state0["state_bootstrap_ts"] = int(time.time())
{indent}    st_path.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
{indent}except Exception as _e:
{indent}    try:
{indent}        print("[{MARK}] state bootstrap failed:", _e)
{indent}    except Exception:
{indent}        pass
{indent}# === END {MARK} ===
"""

# Insert right after the request_id assignment line
insert_pos = m_id.end()
fn2 = fn[:insert_pos] + "\n" + inject + "\n" + fn[insert_pos:]

txt2 = txt[:fn_start] + fn2 + txt[fn_end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

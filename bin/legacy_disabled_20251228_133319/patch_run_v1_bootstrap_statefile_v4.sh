#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_state_v4_${TS}"
echo "[BACKUP] $F.bak_bootstrap_state_v4_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_STATEFILE_BOOTSTRAP_V4"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# Locate run_v1 function block
m = re.search(r"^(\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_v1():")

fn_indent = m.group(1)
fn_start = m.start()

# end at next def with same indent (or EOF)
m2 = re.search(rf"^{re.escape(fn_indent)}def\s+\w+\s*\(", txt[m.end():], flags=re.M)
fn_end = len(txt) if not m2 else (m.end() + m2.start())

fn = txt[fn_start:fn_end]

# Find first "return jsonify(" inside run_v1
mret = re.search(r"^(\s*)return\s+jsonify\s*\(", fn, flags=re.M)
if not mret:
    # fallback: "return flask.jsonify("
    mret = re.search(r"^(\s*)return\s+.*jsonify\s*\(", fn, flags=re.M)
if not mret:
    raise SystemExit("[ERR] cannot find 'return jsonify(' inside run_v1()")

ret_indent = mret.group(1)

inject = f"""
{ret_indent}# === {MARK} ===
{ret_indent}try:
{ret_indent}    import json, time
{ret_indent}    from pathlib import Path
{ret_indent}    # payload from request
{ret_indent}    try:
{ret_indent}        _req_payload = request.get_json(silent=True) or {{}}
{ret_indent}    except Exception:
{ret_indent}        _req_payload = {{}}

{ret_indent}    # discover req_id from locals or response dict
{ret_indent}    _rid = None
{ret_indent}    for _k in ("request_id","req_id","rid","REQ_ID"):
{ret_indent}        if _k in locals() and locals().get(_k):
{ret_indent}            _rid = str(locals().get(_k))
{ret_indent}            break

{ret_indent}    # common response variable names (dict contains request_id)
{ret_indent}    if not _rid:
{ret_indent}        for _name in ("out","resp","result","payload","ret","data","body"):
{ret_indent}            v = locals().get(_name)
{ret_indent}            if isinstance(v, dict) and v.get("request_id"):
{ret_indent}                _rid = str(v.get("request_id"))
{ret_indent}                break

{ret_indent}    if _rid:
{ret_indent}        ui_root = Path(__file__).resolve().parents[1]   # .../SECURITY_BUNDLE/ui
{ret_indent}        st_dir = ui_root / "out_ci" / "ui_req_state"
{ret_indent}        st_dir.mkdir(parents=True, exist_ok=True)
{ret_indent}        st_path = st_dir / (_rid + ".json")

{ret_indent}        state0 = {{}}
{ret_indent}        if st_path.is_file():
{ret_indent}            try:
{ret_indent}                state0 = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
{ret_indent}                if not isinstance(state0, dict):
{ret_indent}                    state0 = {{}}
{ret_indent}            except Exception:
{ret_indent}                state0 = {{}}

{ret_indent}        state0.setdefault("request_id", _rid)
{ret_indent}        state0.setdefault("synthetic_req_id", True)

{ret_indent}        # backfill contract fields early
{ret_indent}        for _k in ("mode","profile","target_type","target"):
{ret_indent}            if (not state0.get(_k)) and (_req_payload.get(_k) is not None):
{ret_indent}                state0[_k] = _req_payload.get(_k) or ""

{ret_indent}        state0.setdefault("ci_run_dir", "")
{ret_indent}        state0.setdefault("runner_log", "")
{ret_indent}        state0.setdefault("ci_root_from_pid", None)
{ret_indent}        state0.setdefault("watchdog_pid", 0)
{ret_indent}        state0.setdefault("stage_sig", "0/0||0")
{ret_indent}        state0.setdefault("progress_pct", 0)
{ret_indent}        state0.setdefault("killed", False)
{ret_indent}        state0.setdefault("kill_reason", "")
{ret_indent}        state0.setdefault("final", False)
{ret_indent}        state0["state_bootstrap_ts"] = int(time.time())

{ret_indent}        # keep minimal payload for debug
{ret_indent}        rp = state0.get("req_payload")
{ret_indent}        if not isinstance(rp, dict):
{ret_indent}            rp = {{}}
{ret_indent}        for _k in ("mode","profile","target_type","target"):
{ret_indent}            if _k in _req_payload:
{ret_indent}                rp[_k] = _req_payload.get(_k)
{ret_indent}        state0["req_payload"] = rp

{ret_indent}        st_path.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
{ret_indent}except Exception as _e:
{ret_indent}    try:
{ret_indent}        print("[{MARK}] bootstrap failed:", _e)
{ret_indent}    except Exception:
{ret_indent}        pass
{ret_indent}# === END {MARK} ===
"""

# insert right before return jsonify
fn2 = fn[:mret.start()] + inject + "\n" + fn[mret.start():]
txt2 = txt[:fn_start] + fn2 + txt[fn_end:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_bootstrap_state_v6_${TS}"
echo "[BACKUP] $F.bak_bootstrap_state_v6_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_V1_STATEFILE_BOOTSTRAP_V6_WRAP_RETURNS"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# ---- helper writer (module-level) ----
helper = f"""
# === {MARK} ===
def _vsp_bootstrap_statefile_v6(req_id: str, req_payload: dict):
    try:
        from pathlib import Path
        import json, time, os
        ui_root = Path(__file__).resolve().parents[1]   # .../SECURITY_BUNDLE/ui
        st_dir = ui_root / "out_ci" / "ui_req_state"
        st_dir.mkdir(parents=True, exist_ok=True)
        st_path = st_dir / (str(req_id) + ".json")

        state0 = {{}}
        if st_path.is_file():
            try:
                state0 = json.loads(st_path.read_text(encoding="utf-8", errors="ignore") or "{{}}")
                if not isinstance(state0, dict):
                    state0 = {{}}
            except Exception:
                state0 = {{}}

        state0.setdefault("request_id", str(req_id))
        state0.setdefault("synthetic_req_id", True)

        for k in ("mode","profile","target_type","target"):
            if (not state0.get(k)) and (req_payload.get(k) is not None):
                state0[k] = req_payload.get(k) or ""

        state0.setdefault("ci_run_dir", "")
        state0.setdefault("runner_log", "")
        state0.setdefault("ci_root_from_pid", None)
        state0.setdefault("watchdog_pid", 0)
        state0.setdefault("stage_sig", "0/0||0")
        state0.setdefault("progress_pct", 0)
        state0.setdefault("killed", False)
        state0.setdefault("kill_reason", "")
        state0.setdefault("final", False)

        state0.setdefault("stall_timeout_sec", int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600")))
        state0.setdefault("total_timeout_sec", int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200")))

        state0["state_bootstrap_ts"] = int(time.time())

        rp = state0.get("req_payload")
        if not isinstance(rp, dict):
            rp = {{}}
        for k in ("mode","profile","target_type","target"):
            if k in req_payload:
                rp[k] = req_payload.get(k)
        state0["req_payload"] = rp

        st_path.write_text(json.dumps(state0, ensure_ascii=False, indent=2), encoding="utf-8")
    except Exception:
        return
# === END {MARK} ===
"""

# insert helper after imports (best effort)
m_imp = re.search(r"(\n(?:from|import)\s+[^\n]+)+\n", txt, flags=re.M)
if m_imp:
    txt = txt[:m_imp.end()] + helper + "\n" + txt[m_imp.end():]
else:
    txt = helper + "\n" + txt

# ---- locate run_v1 block ----
m = re.search(r"^(\s*)def\s+run_v1\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find: def run_v1():")

fn_indent = m.group(1)
fn_start = m.start()
m2 = re.search(rf"^{re.escape(fn_indent)}def\s+\w+\s*\(", txt[m.end():], flags=re.M)
fn_end = len(txt) if not m2 else (m.end() + m2.start())
fn = txt[fn_start:fn_end]

# find all return ...jsonify( ... ) inside run_v1
rets = list(re.finditer(r"^\s*return\s+.*jsonify\s*\(", fn, flags=re.M))
if not rets:
    raise SystemExit("[ERR] no 'return ...jsonify(' found in run_v1()")

def match_parens(s, open_pos):
    depth = 0
    i = open_pos
    while i < len(s):
        ch = s[i]
        if ch == '(':
            depth += 1
        elif ch == ')':
            depth -= 1
            if depth == 0:
                return i
        i += 1
    return -1

# Replace from bottom to top (keep indices valid)
new_fn = fn
count = 0
for mm in reversed(rets):
    start = mm.start()
    # locate jsonify( position
    j = new_fn.find("jsonify", start)
    if j == -1:
        continue
    open_pos = new_fn.find("(", j)
    if open_pos == -1:
        continue
    close_pos = match_parens(new_fn, open_pos)
    if close_pos == -1:
        continue

    # statement end = end of line where close_paren is
    stmt_end = new_fn.find("\n", close_pos)
    if stmt_end == -1:
        stmt_end = len(new_fn)

    ret_stmt = new_fn[start:stmt_end]
    indent = re.match(r"^(\s*)", ret_stmt).group(1)

    jsonify_expr = new_fn[j:close_pos+1]
    suffix = new_fn[close_pos+1:stmt_end].rstrip()  # e.g. ", 202"

    block = f"""{indent}# === {MARK} APPLY ===
{indent}__resp = {jsonify_expr}
{indent}try:
{indent}    _payload = __resp.get_json(silent=True) or {{}}
{indent}except Exception:
{indent}    _payload = {{}}
{indent}try:
{indent}    _rid = str(_payload.get("request_id") or "")
{indent}    try:
{indent}        _req_payload = request.get_json(silent=True) or {{}}
{indent}    except Exception:
{indent}        _req_payload = {{}}
{indent}    if _rid:
{indent}        _vsp_bootstrap_statefile_v6(_rid, _req_payload)
{indent}except Exception:
{indent}    pass
{indent}return __resp{suffix}
{indent}# === END {MARK} APPLY ===
"""
    new_fn = new_fn[:start] + block + "\n" + new_fn[stmt_end:]
    count += 1

txt2 = txt[:fn_start] + new_fn + txt[fn_end:]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK, "rewrote_returns=", count)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

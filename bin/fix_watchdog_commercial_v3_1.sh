#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

# Restore best known-good (finalize backup) then re-apply patch cleanly
LATEST="$(ls -1 "${F}.bak_watchdog_finalize_"* 2>/dev/null | sort | tail -n1 || true)"
if [ -z "${LATEST}" ]; then
  LATEST="$(ls -1 "${F}.bak_watchdog_"* 2>/dev/null | sort | tail -n1 || true)"
fi
if [ -n "${LATEST}" ] && [ -f "${LATEST}" ]; then
  cp -f "${LATEST}" "$F"
  echo "[RESTORE] $F <= $LATEST"
else
  echo "[WARN] no backup found; keep current $F"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_watchdog_v3_1_${TS}"
echo "[BACKUP] $F.bak_fix_watchdog_v3_1_${TS}"

mkdir -p run_api out_ci/ui_req_state

# Ensure watchdog file exists (idempotent)
if [ ! -f run_api/vsp_watchdog_v1.py ]; then
  echo "[ERR] missing run_api/vsp_watchdog_v1.py (create it first)"; exit 1;
fi

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")
lines = s.splitlines(True)

def has_text(t: str) -> bool:
    return any(t in ln for ln in lines)

def find_route_def(route_fragment: str):
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("@") and route_fragment in ln:
            for j in range(i+1, len(lines)):
                if re.match(r"^\s*def\s+\w+\s*\(", lines[j]):
                    m = re.match(r"^(\s*)def\s+(\w+)\s*\(", lines[j])
                    return j, m.group(2), m.group(1)
    return None, None, None

def func_range(def_i: int, def_indent: str):
    base = len(def_indent.expandtabs(4))
    i = def_i + 1
    while i < len(lines):
        ln = lines[i]
        if ln.strip() == "":
            i += 1
            continue
        ind = len(re.match(r"^(\s*)", ln).group(1).expandtabs(4))
        if ind <= base and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@") or ln.lstrip().startswith("class ")):
            return def_i, i
        i += 1
    return def_i, len(lines)

# Ensure imports exist
imports_need = ["import os", "import json", "import time", "import subprocess", "from pathlib import Path"]
last_imp = -1
for i, ln in enumerate(lines):
    if re.match(r"^(import |from ).+\n?$", ln):
        last_imp = i
for imp in imports_need:
    if not has_text(imp):
        ins = last_imp + 1
        lines.insert(ins, imp + "\n")
        last_imp = ins

# Insert helpers once
HELP_MARK = "VSP_COMM_WATCHDOG_HELPERS_V3"
if not has_text(HELP_MARK):
    helper = """
# === VSP_COMM_WATCHDOG_HELPERS_V3 ===
VSP_UIREQ_STATE_DIR = Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state"
VSP_UIREQ_STATE_DIR.mkdir(parents=True, exist_ok=True)

def _vsp_atomic_write_json_v1(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def _vsp_spawn_watchdog_v1(state_path: Path) -> None:
    wd = Path(__file__).resolve().parent / "vsp_watchdog_v1.py"
    if not wd.exists():
        return
    try:
        subprocess.Popen(
            ["python3", str(wd), "--state", str(state_path), "--tick", "2"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
    except Exception:
        pass
# === END VSP_COMM_WATCHDOG_HELPERS_V3 ===
"""
    ins = last_imp + 1
    lines.insert(ins, helper if helper.endswith("\n") else helper + "\n")

# Patch run_v1 (only if not already patched)
d_i, fn, ind = find_route_def("/api/vsp/run_v1")
if d_i is not None:
    a,b = func_range(d_i, ind)
    body = lines[a:b]
    if not any("VSP_COMM_WATCHDOG_RUN_V3" in ln for ln in body):
        # minimal safe patch: ONLY spawn watchdog after request_id exists; no deep popen edits here
        body_indent = ind + "    "
        ip = 1
        for k in range(1, len(body)):
            if re.match(r"^\s*(request_id|req_id)\s*=\s*.+", body[k]):
                ip = k + 1
                break
        body[ip:ip] = [
            f"{body_indent}# === VSP_COMM_WATCHDOG_RUN_V3: init state ===\n",
            f"{body_indent}_rid = locals().get('request_id', locals().get('req_id', ''))\n",
            f"{body_indent}_stall = int(os.environ.get('VSP_STALL_TIMEOUT_SEC','600'))\n",
            f"{body_indent}_total = int(os.environ.get('VSP_TOTAL_TIMEOUT_SEC','7200'))\n",
            f"{body_indent}_state_path = VSP_UIREQ_STATE_DIR / (str(_rid) + '.json')\n",
            f"{body_indent}_vsp_atomic_write_json_v1(_state_path, {{'req_id': str(_rid), 'start_ts': int(time.time()), 'status': 'RUNNING', 'final': False, 'killed': False, 'kill_reason': '', 'stall_timeout_sec': _stall, 'total_timeout_sec': _total, 'progress_pct': 0, 'stage_index': 0, 'stage_total': 0, 'stage_name': '', 'stage_sig': '0/0||0', 'last_sig_change_ts': int(time.time()), 'target': str(locals().get('target', locals().get('target_path','')) or ''), 'profile': str(locals().get('profile','') or ''), 'ci_run_dir': '', 'runner_log': '', 'pid': 0}})\n",
            f"{body_indent}try:\n",
            f"{body_indent}    _vsp_spawn_watchdog_v1(_state_path)\n",
            f"{body_indent}except Exception:\n",
            f"{body_indent}    pass\n",
            f"{body_indent}# === END VSP_COMM_WATCHDOG_RUN_V3 ===\n",
        ]
        lines[a:b] = body

# Patch run_status_v1 (fix NameError bug: no f-string with undefined req_id)
d_i, fn, ind = find_route_def("/api/vsp/run_status_v1")
if d_i is None:
    print("[WARN] cannot find decorator for /api/vsp/run_status_v1")
else:
    a,b = func_range(d_i, ind)
    body = lines[a:b]
    MARK = "VSP_COMM_STATUS_FROM_STATE_V3"
    if any(MARK in ln for ln in body):
        print("[OK] status already patched:", fn)
    else:
        body_indent = ind + "    "
        inject = [
            f"{body_indent}# === {MARK} ===\n",
            f"{body_indent}try:\n",
            f"{body_indent}    if str(req_id).startswith('VSP_UIREQ_'):\n",
            f"{body_indent}        _p = VSP_UIREQ_STATE_DIR / (str(req_id) + '.json')\n",
            f"{body_indent}        if _p.exists():\n",
            f"{body_indent}            _st = json.loads(_p.read_text(encoding='utf-8', errors='ignore'))\n",
            f"{body_indent}            return jsonify({{\n",
            f"{body_indent}                'ok': True,\n",
            f"{body_indent}                'req_id': str(req_id),\n",
            f"{body_indent}                'status': _st.get('status','RUNNING'),\n",
            f"{body_indent}                'final': bool(_st.get('final', False)),\n",
            f"{body_indent}                'error': _st.get('error','') or '',\n",
            f"{body_indent}                'stall_timeout_sec': int(_st.get('stall_timeout_sec', 600)),\n",
            f"{body_indent}                'total_timeout_sec': int(_st.get('total_timeout_sec', 7200)),\n",
            f"{body_indent}                'progress_pct': int(_st.get('progress_pct', 0)),\n",
            f"{body_indent}                'stage_index': int(_st.get('stage_index', 0)),\n",
            f"{body_indent}                'stage_total': int(_st.get('stage_total', 0)),\n",
            f"{body_indent}                'stage_name': _st.get('stage_name','') or '',\n",
            f"{body_indent}                'stage_sig': _st.get('stage_sig','0/0||0') or '0/0||0',\n",
            f"{body_indent}                'killed': bool(_st.get('killed', False)),\n",
            f"{body_indent}                'kill_reason': _st.get('kill_reason','') or '',\n",
            f"{body_indent}                'ci_run_dir': _st.get('ci_run_dir','') or '',\n",
            f"{body_indent}                'runner_log': _st.get('runner_log','') or '',\n",
            f"{body_indent}            }})\n",
            f"{body_indent}except Exception:\n",
            f"{body_indent}    pass\n",
            f"{body_indent}# === END {MARK} ===\n",
        ]
        body[1:1] = inject
        lines[a:b] = body
        print("[OK] patched status:", fn)

p.write_text("".join(lines), encoding="utf-8")
print("[DONE] wrote", p)
PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"
echo "[NEXT] Restart 8910"

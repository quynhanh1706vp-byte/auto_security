#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

# Restore best known-good: prefer bak_watchdog_finalize_*, else bak_watchdog_*
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
cp -f "$F" "$F.bak_fix_watchdog_v3_${TS}"
echo "[BACKUP] $F.bak_fix_watchdog_v3_${TS}"

mkdir -p run_api out_ci/ui_req_state

# 1) Write watchdog (unchanged core)
cat > run_api/vsp_watchdog_v1.py <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, signal, subprocess, time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

STAGE_RE = re.compile(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]+", re.IGNORECASE)

def _now() -> int:
    return int(time.time())

def _atomic_write_json(p: Path, obj: Dict[str, Any]) -> None:
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)

def _read_json(p: Path) -> Dict[str, Any]:
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception:
        return {}

def _tail_bytes(path: Path, max_bytes: int = 250_000) -> str:
    try:
        if not path.exists():
            return ""
        size = path.stat().st_size
        with path.open("rb") as f:
            if size > max_bytes:
                f.seek(-max_bytes, os.SEEK_END)
            data = f.read()
        return data.decode("utf-8", errors="ignore")
    except Exception:
        return ""

def _parse_last_marker(text: str) -> Tuple[int,int,str]:
    last = None
    for m in STAGE_RE.finditer(text):
        last = m
    if not last:
        return (0, 0, "")
    return (int(last.group(1)), int(last.group(2)), last.group(3).strip())

def _stage_sig(i: int, t: int) -> str:
    seq = i if i > 0 else 0
    return f"{i}/{t}||{seq}"

def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

def _guess_ci_run_dir(target: str, start_ts: int) -> Optional[str]:
    roots = []
    if target:
        roots += [
            Path(target) / "out_ci",
            Path(target) / "ci" / "VSP_CI_OUTER" / "out_ci",
            Path(target) / "ci" / "out_ci",
        ]
    roots += [Path.cwd() / "out_ci", Path.cwd().parent / "out_ci"]

    cand = []
    for r in roots:
        if not r.exists():
            continue
        for p in r.glob("VSP_CI_*"):
            try:
                mt = int(p.stat().st_mtime)
            except Exception:
                continue
            if mt >= start_ts - 900:
                cand.append((mt, str(p)))
    if not cand:
        return None
    cand.sort()
    return cand[-1][1]

def _pick_runner_log(ci_run_dir: str) -> Optional[str]:
    d = Path(ci_run_dir)
    if not d.exists():
        return None
    preferred = [
        d / "runner.log",
        d / "run.log",
        d / "vsp_ci.log",
        d / "SUMMARY.txt",
        d / "out.log",
        d / "ci.log",
    ]
    for p in preferred:
        if p.exists():
            return str(p)
    for p in [d / "kics" / "kics.log", d / "codeql" / "codeql.log", d / "semgrep" / "semgrep.log"]:
        if p.exists():
            return str(p)
    return None

def _kill(pid: int) -> None:
    if pid <= 0:
        return
    try:
        os.kill(pid, signal.SIGTERM)
        time.sleep(2)
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass

def _finalize_sync(ci_run_dir: Optional[str]) -> str:
    if not ci_run_dir:
        return "skip:missing_ci_run_dir"
    sync = Path.cwd().parent / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
    if not sync.exists():
        return "skip:missing_vsp_ci_sync_to_vsp_v1.sh"
    try:
        subprocess.run([str(sync), ci_run_dir], check=False, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        return "ok"
    except Exception as e:
        return f"err:{e.__class__.__name__}"

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--tick", type=int, default=2)
    args = ap.parse_args()

    sp = Path(args.state)
    st = _read_json(sp)
    start_ts = int(st.get("start_ts") or _now())
    stall_timeout = int(st.get("stall_timeout_sec") or 600)
    total_timeout = int(st.get("total_timeout_sec") or 7200)

    while True:
        st = _read_json(sp)
        if not st:
            time.sleep(args.tick)
            continue
        if st.get("final") is True:
            return

        now = _now()
        pid = int(st.get("pid") or 0)
        target = str(st.get("target") or "")
        last_sig = str(st.get("stage_sig") or "0/0||0")
        last_change_ts = int(st.get("last_sig_change_ts") or start_ts)

        if not st.get("ci_run_dir"):
            g = _guess_ci_run_dir(target, start_ts)
            if g:
                st["ci_run_dir"] = g
        if st.get("ci_run_dir") and not st.get("runner_log"):
            rlog = _pick_runner_log(st["ci_run_dir"])
            if rlog:
                st["runner_log"] = rlog

        if st.get("runner_log"):
            txt = _tail_bytes(Path(st["runner_log"]))
            i, t, name = _parse_last_marker(txt)
            sig = _stage_sig(i, t)
            st["stage_index"] = i
            st["stage_total"] = t
            st["stage_name"] = name
            if t > 0:
                st["progress_pct"] = int(((max(i, 1) - 1) / t) * 100)
            st["stage_sig"] = sig
            if sig != last_sig:
                st["last_sig_change_ts"] = now
                last_change_ts = now

        if now - start_ts > total_timeout:
            st["killed"] = True
            st["kill_reason"] = "TOTAL"
        elif now - last_change_ts > stall_timeout:
            st["killed"] = True
            st["kill_reason"] = "STALL"

        if st.get("killed") is True and st.get("final") is not True:
            st["status"] = "KILLED"
            _kill(pid)
            st["finalize_sync"] = _finalize_sync(st.get("ci_run_dir"))
            st["final"] = True
            st["final_ts"] = now
            _atomic_write_json(sp, st)
            return

        if pid > 0 and not _is_alive(pid):
            st["status"] = "FINISHED"
            st["finalize_sync"] = _finalize_sync(st.get("ci_run_dir"))
            st["final"] = True
            st["final_ts"] = now
            _atomic_write_json(sp, st)
            return

        st["status"] = "RUNNING"
        st["last_poll_ts"] = now
        _atomic_write_json(sp, st)
        time.sleep(args.tick)

if __name__ == "__main__":
    main()
PY
chmod +x run_api/vsp_watchdog_v1.py

# 2) Patch vsp_run_api_v1.py by INDENT-SCAN (avoid “unexpected indent”)
python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
s = p.read_text(encoding="utf-8", errors="ignore")
lines = s.splitlines(True)

def find_def(name):
    pat = re.compile(rf"^(\s*)def\s+{re.escape(name)}\s*\(")
    for i, ln in enumerate(lines):
        m = pat.match(ln)
        if m:
            return i, m.group(1)
    return None, None

def find_route_def(route_fragment):
    # find decorator line containing fragment, then next def
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("@") and route_fragment in ln:
            # find next def after i
            for j in range(i+1, len(lines)):
                if re.match(r"^\s*def\s+\w+\s*\(", lines[j]):
                    m = re.match(r"^(\s*)def\s+(\w+)\s*\(", lines[j])
                    return j, m.group(2), m.group(1)
    return None, None, None

def func_range(def_i, def_indent):
    # function ends when we hit a non-blank line with indent <= def_indent and starts with "def" or "@"
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

def ensure_import(stmt):
    nonlocal_lines = None  # placeholder for clarity

def has_text(t):
    return any(t in ln for ln in lines)

# Ensure imports exist (top-level safe)
imports_need = ["import os", "import json", "import time", "import subprocess", "from pathlib import Path"]
# find last import/from line
last_imp = -1
for i, ln in enumerate(lines):
    if re.match(r"^(import |from ).+\n?$", ln):
        last_imp = i

for imp in imports_need:
    if not has_text(imp):
        ins_at = last_imp + 1
        lines.insert(ins_at, imp + "\n")
        last_imp = ins_at

# Insert helpers once at top-level
HELP_MARK = "VSP_COMM_WATCHDOG_HELPERS_V3"
if not has_text(HELP_MARK):
    helper = f"""
# === {HELP_MARK} ===
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
# === END {HELP_MARK} ===
"""
    # insert after imports block
    ins_at = last_imp + 1
    lines.insert(ins_at, helper if helper.endswith("\n") else helper + "\n")

# Patch run_v1 handler by route (not relying on function name elsewhere)
def_i, fn_name, def_indent = find_route_def("/api/vsp/run_v1")
if def_i is None:
    print("[WARN] cannot find decorator for /api/vsp/run_v1")
else:
    a, b = func_range(def_i, def_indent)
    body = lines[a:b]
    MARK = "VSP_COMM_WATCHDOG_RUN_V3"
    if any(MARK in ln for ln in body):
        print("[OK] run_v1 already patched:", fn_name)
    else:
        body_indent = def_indent + "    "
        # state init insert point: after request_id assignment if found, else after def line
        ip = 1
        for k in range(1, len(body)):
            if re.match(r"^\s*(request_id|req_id)\s*=\s*.+", body[k]):
                ip = k + 1
                break
        inject_state = [
            f"{body_indent}# === {MARK}: init state ===\n",
            f"{body_indent}_rid = locals().get('request_id', locals().get('req_id', ''))\n",
            f"{body_indent}_stall = int(os.environ.get('VSP_STALL_TIMEOUT_SEC','600'))\n",
            f"{body_indent}_total = int(os.environ.get('VSP_TOTAL_TIMEOUT_SEC','7200'))\n",
            f"{body_indent}_state_path = VSP_UIREQ_STATE_DIR / f\"{{_rid}}.json\"\n",
            f"{body_indent}_vsp_atomic_write_json_v1(_state_path, {{\n",
            f"{body_indent}  'req_id': str(_rid),\n",
            f"{body_indent}  'start_ts': int(time.time()),\n",
            f"{body_indent}  'status': 'RUNNING',\n",
            f"{body_indent}  'final': False,\n",
            f"{body_indent}  'killed': False,\n",
            f"{body_indent}  'kill_reason': '',\n",
            f"{body_indent}  'stall_timeout_sec': _stall,\n",
            f"{body_indent}  'total_timeout_sec': _total,\n",
            f"{body_indent}  'progress_pct': 0,\n",
            f"{body_indent}  'stage_index': 0,\n",
            f"{body_indent}  'stage_total': 0,\n",
            f"{body_indent}  'stage_name': '',\n",
            f"{body_indent}  'stage_sig': '0/0||0',\n",
            f"{body_indent}  'last_sig_change_ts': int(time.time()),\n",
            f"{body_indent}  'target': str(locals().get('target', locals().get('target_path','')) or ''),\n",
            f"{body_indent}  'profile': str(locals().get('profile','') or ''),\n",
            f"{body_indent}  'ci_run_dir': '',\n",
            f"{body_indent}  'runner_log': '',\n",
            f"{body_indent}  'pid': 0,\n",
            f"{body_indent}}})\n",
            f"{body_indent}# === END {MARK}: init state ===\n",
        ]
        body[ip:ip] = inject_state

        # find subprocess.Popen assignment and ensure preexec_fn=os.setsid in the call
        popen_var = None
        popen_start = None
        for k in range(0, len(body)):
            m = re.match(r"^\s*(\w+)\s*=\s*subprocess\.Popen\s*\(", body[k])
            if m:
                popen_var = m.group(1)
                popen_start = k
                break

        if popen_var is not None:
            # find end of call by parentheses depth across lines from popen_start
            depth = 0
            end_k = None
            for k in range(popen_start, len(body)):
                ln = body[k]
                # count parens naive
                for ch in ln:
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                if depth == 0 and k > popen_start:
                    end_k = k
                    break

            # add preexec_fn=os.setsid before final ')', if not present anywhere in call block
            if end_k is not None:
                call_block = "".join(body[popen_start:end_k+1])
                if "preexec_fn" not in call_block:
                    body[end_k] = body[end_k].replace(")", ", preexec_fn=os.setsid)")
                # insert attach + spawn AFTER popen call block
                attach = [
                    f"{body_indent}# === {MARK}: attach pid + spawn watchdog ===\n",
                    f"{body_indent}try:\n",
                    f"{body_indent}    _pid = int(getattr({popen_var}, 'pid', 0) or 0)\n",
                    f"{body_indent}    _st = {{}}\n",
                    f"{body_indent}    try:\n",
                    f"{body_indent}        _st = json.loads(_state_path.read_text(encoding='utf-8', errors='ignore')) if _state_path.exists() else {{}}\n",
                    f"{body_indent}    except Exception:\n",
                    f"{body_indent}        _st = {{}}\n",
                    f"{body_indent}    _st['pid'] = _pid\n",
                    f"{body_indent}    _vsp_atomic_write_json_v1(_state_path, _st)\n",
                    f"{body_indent}    _vsp_spawn_watchdog_v1(_state_path)\n",
                    f"{body_indent}except Exception:\n",
                    f"{body_indent}    pass\n",
                    f"{body_indent}# === END {MARK}: attach ===\n",
                ]
                insert_after = (end_k + 1)
                body[insert_after:insert_after] = attach
        else:
            # no popen found -> still spawn watchdog before first return jsonify
            for k in range(0, len(body)):
                if re.match(r"^\s*return\s+jsonify\(", body[k]):
                    body[k:k] = [
                        f"{body_indent}# === {MARK}: spawn watchdog (no popen) ===\n",
                        f"{body_indent}try:\n",
                        f"{body_indent}    _vsp_spawn_watchdog_v1(_state_path)\n",
                        f"{body_indent}except Exception:\n",
                        f"{body_indent}    pass\n",
                        f"{body_indent}# === END {MARK}: spawn watchdog ===\n",
                    ]
                    break

        lines[a:b] = body
        print("[OK] patched run_v1:", fn_name)

# Patch status handler early return from state
def_i, fn_name, def_indent = find_route_def("/api/vsp/run_status_v1")
if def_i is None:
    print("[WARN] cannot find decorator for /api/vsp/run_status_v1")
else:
    a, b = func_range(def_i, def_indent)
    body = lines[a:b]
    MARK = "VSP_COMM_STATUS_FROM_STATE_V3"
    if any(MARK in ln for ln in body):
        print("[OK] status already patched:", fn_name)
    else:
        body_indent = def_indent + "    "
        # insert right after def line (index 1)
        inject = [
            f"{body_indent}# === {MARK} ===\n",
            f"{body_indent}try:\n",
            f"{body_indent}    if str(req_id).startswith('VSP_UIREQ_'):\n",
            f"{body_indent}        _p = VSP_UIREQ_STATE_DIR / f\"{req_id}.json\"\n".replace("{req_id}", "{req_id}"),
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
        print("[OK] patched status:", fn_name)

p.write_text("".join(lines), encoding="utf-8")
print("[DONE] wrote", p)
PY

python3 -m py_compile run_api/vsp_run_api_v1.py run_api/vsp_watchdog_v1.py
echo "[OK] py_compile OK"
echo "[OK] State dir: out_ci/ui_req_state"
echo "[NEXT] Restart 8910 to load patched code."

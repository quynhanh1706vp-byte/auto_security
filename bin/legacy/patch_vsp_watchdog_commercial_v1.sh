#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_watchdog_${TS}"
echo "[BACKUP] $F.bak_watchdog_${TS}"

# 1) Write watchdog implementation (pure python, no deps)
mkdir -p run_api out_ci/ui_req_state bin

cat > run_api/vsp_watchdog_v1.py <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, signal, subprocess, time
from pathlib import Path
from typing import Dict, Any, Optional, Tuple

STAGE_RE = re.compile(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]+", re.IGNORECASE)
# Matches: "===== [3/8] KICS (EXT) =====" (the [] part is enough)

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

def _is_alive(pid: int) -> bool:
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

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
    # LAST-MARKER-WINS
    last = None
    for m in STAGE_RE.finditer(text):
        last = m
    if not last:
        return (0, 0, "")
    i = int(last.group(1))
    t = int(last.group(2))
    name = last.group(3).strip()
    return (i, t, name)

def _compute_stage_sig(i: int, t: int, name: str) -> str:
    # Keep your contract style: "i/t||seq"
    seq = i if i > 0 else 0
    return f"{i}/{t}||{seq}"

def _guess_ci_run_dir(target: str, start_ts: int) -> Optional[str]:
    # Try common layouts (best-effort, no user edits)
    roots = []
    if target:
        roots += [
            Path(target) / "out_ci",
            Path(target) / "ci" / "VSP_CI_OUTER" / "out_ci",
            Path(target) / "ci" / "out_ci",
        ]
    # also allow scanning SECURITY_BUNDLE/out_ci (rare but helpful)
    roots += [Path.cwd() / "out_ci", Path.cwd().parent / "out_ci"]

    candidates = []
    for r in roots:
        if not r.exists():
            continue
        for p in r.glob("VSP_CI_*"):
            try:
                m = int(p.stat().st_mtime)
            except Exception:
                continue
            # Prefer those created around start time (± 15 minutes)
            if m >= start_ts - 900:
                candidates.append((m, str(p)))
    if not candidates:
        return None
    candidates.sort()
    return candidates[-1][1]

def _pick_runner_log(ci_run_dir: str) -> Optional[str]:
    d = Path(ci_run_dir)
    if not d.exists():
        return None
    # priority: a single "main" log if exists, else tool logs
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
    # fallback: if kics hang, kics/kics.log is still useful for stage markers too
    tool_logs = [
        d / "kics" / "kics.log",
        d / "codeql" / "codeql.log",
        d / "semgrep" / "semgrep.log",
        d / "trivy_fs" / "trivy.log",
    ]
    for p in tool_logs:
        if p.exists():
            return str(p)
    return None

def _kill_group(pgid: int, hard_after_sec: int = 10) -> None:
    try:
        os.killpg(pgid, signal.SIGTERM)
    except Exception:
        return
    t0 = time.time()
    while time.time() - t0 < hard_after_sec:
        time.sleep(0.5)
        # nothing reliable here; best-effort
    try:
        os.killpg(pgid, signal.SIGKILL)
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
    ap.add_argument("--state", required=True, help="Path to state json")
    ap.add_argument("--tick", type=int, default=3)
    args = ap.parse_args()

    state_path = Path(args.state)
    state = _read_json(state_path)

    start_ts = int(state.get("start_ts") or _now())
    stall_timeout = int(state.get("stall_timeout_sec") or 600)
    total_timeout = int(state.get("total_timeout_sec") or 7200)

    while True:
        state = _read_json(state_path)
        if not state:
            time.sleep(args.tick)
            continue

        if state.get("final") is True:
            return

        req_id = state.get("req_id", "")
        pid = int(state.get("pid") or 0)
        pgid = int(state.get("pgid") or 0)
        target = str(state.get("target") or "")
        last_sig = str(state.get("stage_sig") or "0/0||0")
        last_change_ts = int(state.get("last_sig_change_ts") or start_ts)

        now = _now()

        # Discover CI_RUN_DIR + runner log (prefer real runner logs)
        ci_run_dir = state.get("ci_run_dir")
        if not ci_run_dir:
            g = _guess_ci_run_dir(target, start_ts)
            if g:
                ci_run_dir = g
                state["ci_run_dir"] = ci_run_dir

        runner_log = state.get("runner_log")
        if (not runner_log) and ci_run_dir:
            rlog = _pick_runner_log(ci_run_dir)
            if rlog:
                runner_log = rlog
                state["runner_log"] = runner_log

        # Parse stage from runner log
        if runner_log:
            txt = _tail_bytes(Path(runner_log))
            i, t, name = _parse_last_marker(txt)
            sig = _compute_stage_sig(i, t, name)
            if t > 0:
                progress = int(((max(i,1)-1) / t) * 100)
            else:
                progress = int(state.get("progress_pct") or 0)

            state["stage_index"] = i
            state["stage_total"] = t
            state["stage_name"] = name
            state["progress_pct"] = progress
            state["stage_sig"] = sig

            if sig != last_sig:
                state["last_sig_change_ts"] = now
                last_change_ts = now

        # Stall / Total checks
        if now - start_ts > total_timeout:
            state["killed"] = True
            state["kill_reason"] = "TOTAL"
        elif now - last_change_ts > stall_timeout:
            state["killed"] = True
            state["kill_reason"] = "STALL"

        # If killed => kill process group + finalize/sync + final
        if state.get("killed") is True and state.get("final") is not True:
            state["status"] = "KILLED"
            if pgid > 0:
                _kill_group(pgid)
            elif pid > 0:
                try:
                    os.kill(pid, signal.SIGTERM)
                except Exception:
                    pass

            state["finalize_sync"] = _finalize_sync(state.get("ci_run_dir"))
            state["final"] = True
            state["final_ts"] = now
            _atomic_write_json(state_path, state)
            return

        # If process ended naturally => finalize/sync + final
        if pid > 0 and not _is_alive(pid):
            state["status"] = "FINISHED"
            state["finalize_sync"] = _finalize_sync(state.get("ci_run_dir"))
            state["final"] = True
            state["final_ts"] = now
            _atomic_write_json(state_path, state)
            return

        state["status"] = "RUNNING"
        state["last_poll_ts"] = now
        _atomic_write_json(state_path, state)
        time.sleep(args.tick)

if __name__ == "__main__":
    main()
PY
chmod +x run_api/vsp_watchdog_v1.py

# 2) Patch vsp_run_api_v1.py:
#    - create per-req_id state file
#    - spawn runner with start_new_session (so pg kill works)
#    - spawn watchdog in background
python3 - <<'PY'
import re, json, time, os
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

need_imports = [
    "import json",
    "import time",
    "import subprocess",
    "from pathlib import Path",
]
for imp in need_imports:
    if imp not in txt:
        # insert after first import block best-effort
        txt = re.sub(r"(^import[^\n]*\n)", r"\1"+imp+"\n", txt, count=1, flags=re.M)

MARK = "VSP_COMM_WATCHDOG_V1"
if MARK in txt:
    print("[OK] watchdog patch already present")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

# Insert helper: state dir + writer
helper = r"""
# === VSP_COMM_WATCHDOG_V1 (state + spawn watchdog) ===
VSP_UIREQ_STATE_DIR = Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state"
VSP_UIREQ_STATE_DIR.mkdir(parents=True, exist_ok=True)

def _vsp_write_req_state_v1(state_path: Path, obj: dict) -> None:
    state_path.parent.mkdir(parents=True, exist_ok=True)
    tmp = state_path.with_suffix(state_path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(state_path)

def _vsp_spawn_watchdog_v1(state_path: Path) -> None:
    wd = Path(__file__).resolve().parent / "vsp_watchdog_v1.py"
    if not wd.exists():
        return
    try:
        subprocess.Popen(
            ["python3", str(wd), "--state", str(state_path)],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
    except Exception:
        pass
# === END VSP_COMM_WATCHDOG_V1 ===
"""

# Put helper near top (after imports)
m = re.search(r"\n\s*# === END VSP_COMM_WATCHDOG_V1 ===\s*\n", txt)
if not m:
    # insert after last import/from block
    ins_at = 0
    for m2 in re.finditer(r"^(import .+|from .+ import .+)\n", txt, flags=re.M):
        ins_at = m2.end()
    txt = txt[:ins_at] + helper + txt[ins_at:]

# Patch run_v1 handler: best-effort injection by locating route or def name
# We add state + watchdog right AFTER request_id is created and BEFORE returning JSON.
# Also: when spawning runner, ensure start_new_session + record pid/pgid.
pat_def = r"(def\s+run_v1\s*\([^)]*\)\s*:\n)"
m = re.search(pat_def, txt)
if not m:
    print("[WARN] cannot find def run_v1(); patch will only add helper + status support")
else:
    # Find a line that looks like request_id assignment (synthetic)
    # We'll inject a robust block after the first occurrence of "request_id" creation inside run_v1.
    start = m.end()
    block = txt[start:]
    # Find likely place: "request_id =" or "req_id ="
    m_id = re.search(r"^\s*(request_id|req_id)\s*=\s*.*\n", block, flags=re.M)
    if m_id:
        insert_pos = start + m_id.end()
        inject = r"""
    # --- VSP_COMM_WATCHDOG_V1: init state file for this req_id ---
    _rid = locals().get("request_id", locals().get("req_id", ""))
    _stall = int(os.environ.get("VSP_STALL_TIMEOUT_SEC", "600"))
    _total = int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC", "7200"))
    _state_path = VSP_UIREQ_STATE_DIR / f"{_rid}.json"
    _vsp_write_req_state_v1(_state_path, {
        "req_id": _rid,
        "start_ts": int(time.time()),
        "status": "RUNNING",
        "final": False,
        "killed": False,
        "kill_reason": "",
        "stall_timeout_sec": _stall,
        "total_timeout_sec": _total,
        "progress_pct": 0,
        "stage_index": 0,
        "stage_total": 0,
        "stage_name": "",
        "stage_sig": "0/0||0",
        "last_sig_change_ts": int(time.time()),
        "target": (locals().get("target") or locals().get("target_path") or ""),
        "profile": (locals().get("profile") or ""),
        "ci_run_dir": "",
        "runner_log": "",
        "pid": 0,
        "pgid": 0,
    })
    # --- END VSP_COMM_WATCHDOG_V1 ---
"""
        txt = txt[:insert_pos] + inject + txt[insert_pos:]
    else:
        print("[WARN] cannot find request_id assignment in run_v1(); skipping state init injection")

# Ensure any Popen in run_v1 uses start_new_session=True and records pid/pgid if possible
# Best-effort: replace "subprocess.Popen(" with start_new_session True only seen inside run_v1 is hard.
# We'll add a safe snippet: if variable 'proc' exists, record pid/pgid to state and spawn watchdog.
inject2 = r"""
    # --- VSP_COMM_WATCHDOG_V1: attach pid/pgid + spawn watchdog (best-effort) ---
    try:
        proc = locals().get("proc", None) or locals().get("popen", None)
        if proc is not None and hasattr(proc, "pid") and int(proc.pid) > 0:
            _pid = int(proc.pid)
            _pgid = 0
            try:
                _pgid = os.getpgid(_pid)
            except Exception:
                _pgid = 0
            _st = json.loads(_state_path.read_text(encoding="utf-8", errors="ignore")) if _state_path.exists() else {}
            _st["pid"] = _pid
            _st["pgid"] = _pgid
            _vsp_write_req_state_v1(_state_path, _st)
        _vsp_spawn_watchdog_v1(_state_path)
    except Exception:
        pass
    # --- END VSP_COMM_WATCHDOG_V1 ---
"""

# Place inject2 right before first "return jsonify" inside run_v1
m = re.search(r"def\s+run_v1\s*\([^)]*\)\s*:\n", txt)
if m:
    sub = txt[m.end():]
    mret = re.search(r"^\s*return\s+jsonify\(", sub, flags=re.M)
    if mret:
        ip = m.end() + mret.start()
        txt = txt[:ip] + inject2 + txt[ip:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched", p)
PY

# 3) Patch run_status_v1: if synthetic => read state file first (authoritative), else fallback
python3 - <<'PY'
import re, json
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_COMM_STATUS_FROM_STATE_V1"
if MARK in txt:
    print("[OK] status-from-state already present")
    raise SystemExit(0)

# Find run_status_v1 handler
m = re.search(r"def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\n", txt)
if not m:
    print("[WARN] cannot find def run_status_v1(req_id); not patched")
    raise SystemExit(0)

start = m.end()
sub = txt[start:]

# insert early-return block right after def line
inject = r"""
    # === VSP_COMM_STATUS_FROM_STATE_V1: state file is source of truth for synthetic req_id ===
    try:
        if str(req_id).startswith("VSP_UIREQ_"):
            state_path = (Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state" / f"{req_id}.json")
            if state_path.exists():
                st = json.loads(state_path.read_text(encoding="utf-8", errors="ignore"))
                # Normalize contract fields (always present)
                return jsonify({
                    "ok": True,
                    "req_id": str(req_id),
                    "status": st.get("status","RUNNING"),
                    "final": bool(st.get("final", False)),
                    "error": st.get("error","") or "",
                    "stall_timeout_sec": int(st.get("stall_timeout_sec", 600)),
                    "total_timeout_sec": int(st.get("total_timeout_sec", 7200)),
                    "progress_pct": int(st.get("progress_pct", 0)),
                    "stage_index": int(st.get("stage_index", 0)),
                    "stage_total": int(st.get("stage_total", 0)),
                    "stage_name": st.get("stage_name","") or "",
                    "stage_sig": st.get("stage_sig","0/0||0") or "0/0||0",
                    "killed": bool(st.get("killed", False)),
                    "kill_reason": st.get("kill_reason","") or "",
                    "ci_run_dir": st.get("ci_run_dir","") or "",
                    "runner_log": st.get("runner_log","") or "",
                })
    except Exception:
        pass
    # === END VSP_COMM_STATUS_FROM_STATE_V1 ===
"""
txt = txt[:start] + inject + txt[start:]

p.write_text(txt, encoding="utf-8")
print("[OK] patched status-from-state", p)
PY

python3 -m py_compile run_api/vsp_run_api_v1.py run_api/vsp_watchdog_v1.py
echo "[OK] py_compile OK"

echo "== NOTE =="
echo "Watchdog state dir: out_ci/ui_req_state/<REQ_ID>.json"
echo "run_status_v1 will now reflect stage/progress/killed from that state."

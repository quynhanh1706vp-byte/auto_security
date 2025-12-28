#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

# 0) Restore from latest bak_watchdog_* (the last known-good before broken indent)
LATEST="$(ls -1 "${F}.bak_watchdog_"* 2>/dev/null | sort | tail -n1 || true)"
if [ -n "$LATEST" ] && [ -f "$LATEST" ]; then
  cp -f "$LATEST" "$F"
  echo "[RESTORE] $F <= $LATEST"
else
  echo "[WARN] no ${F}.bak_watchdog_* found; continue patching current file"
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_watchdog_${TS}"
echo "[BACKUP] $F.bak_fix_watchdog_${TS}"

mkdir -p run_api out_ci/ui_req_state

# 1) Write watchdog (safe, no deps)
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
    # fallback tool logs
    for p in [d / "kics" / "kics.log", d / "codeql" / "codeql.log", d / "semgrep" / "semgrep.log"]:
        if p.exists():
            return str(p)
    return None

def _kill(pid: int, pgid: int) -> None:
    # SAFETY: never kill current server process-group
    my_pgid = 0
    try:
        my_pgid = os.getpgid(0)
    except Exception:
        my_pgid = 0

    if pgid > 0 and my_pgid > 0 and pgid != my_pgid:
        try:
            os.killpg(pgid, signal.SIGTERM)
            time.sleep(2)
            os.killpg(pgid, signal.SIGKILL)
            return
        except Exception:
            pass

    if pid > 0:
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
        pgid = int(st.get("pgid") or 0)
        target = str(st.get("target") or "")
        last_sig = str(st.get("stage_sig") or "0/0||0")
        last_change_ts = int(st.get("last_sig_change_ts") or start_ts)

        # Discover CI dir/log
        if not st.get("ci_run_dir"):
            g = _guess_ci_run_dir(target, start_ts)
            if g:
                st["ci_run_dir"] = g
        if st.get("ci_run_dir") and not st.get("runner_log"):
            rlog = _pick_runner_log(st["ci_run_dir"])
            if rlog:
                st["runner_log"] = rlog

        # Parse stage markers
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

        # Stall/Total
        if now - start_ts > total_timeout:
            st["killed"] = True
            st["kill_reason"] = "TOTAL"
        elif now - last_change_ts > stall_timeout:
            st["killed"] = True
            st["kill_reason"] = "STALL"

        if st.get("killed") is True and st.get("final") is not True:
            st["status"] = "KILLED"
            _kill(pid, pgid)
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

# 2) Patch vsp_run_api_v1.py robustly: detect handler by route string (not function name)
python3 - <<'PY'
import re, json, time, os
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

# Ensure imports exist (top-level)
def ensure_import(line: str):
    nonlocal txt
    if line not in txt:
        # insert after last import/from
        ins = 0
        for m in re.finditer(r"^(import .+|from .+ import .+)\n", txt, flags=re.M):
            ins = m.end()
        txt = txt[:ins] + line + "\n" + txt[ins:]

for imp in ["import os", "import json", "import time", "import subprocess", "from pathlib import Path"]:
    ensure_import(imp)

# Insert helper block once at top-level (indent 0)
MARK_HELP = "VSP_COMM_WATCHDOG_HELPERS_V1"
if MARK_HELP not in txt:
    helper = f"""
# === {MARK_HELP} ===
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
# === END {MARK_HELP} ===
"""
    # place after imports
    ins = 0
    for m in re.finditer(r"^(import .+|from .+ import .+)\n", txt, flags=re.M):
        ins = m.end()
    txt = txt[:ins] + helper + txt[ins:]

def find_handler_by_route(route_fragment: str):
    # find decorator line containing route_fragment, then next def
    m = re.search(rf"^@.*{re.escape(route_fragment)}.*\n", txt, flags=re.M)
    if not m:
        return None
    after = txt[m.end():]
    md = re.search(r"^(?P<indent>[ \t]*)def\s+(?P<name>[A-Za-z_]\w*)\s*\(", after, flags=re.M)
    if not md:
        return None
    # absolute position of def line
    def_pos = m.end() + md.start()
    indent = md.group("indent")
    name = md.group("name")
    return def_pos, indent, name

def slice_func(def_pos: int):
    # find end at next top-level def with same indent (usually 0)
    sub = txt[def_pos:]
    mdef = re.search(r"^(?P<indent>[ \t]*)def\s+[A-Za-z_]\w*\s*\(", sub, flags=re.M)
    if not mdef:
        return None
    # first def is at 0 of sub
    # end = next def at indent length == current indent length
    indent = re.match(r"^([ \t]*)def", sub).group(1)
    it = re.finditer(r"^(?P<indent>[ \t]*)def\s+[A-Za-z_]\w*\s*\(", sub, flags=re.M)
    first = next(it)
    for m in it:
        if m.group("indent") == indent:
            return def_pos, def_pos + m.start()
    return def_pos, def_pos + len(sub)

def patch_run_v1():
    # try both common strings
    info = find_handler_by_route("/api/vsp/run_v1")
    if not info:
        return False, "route '/api/vsp/run_v1' not found"
    def_pos, indent, fn = info
    s = slice_func(def_pos)
    if not s:
        return False, "cannot slice function"
    a, b = s
    body = txt[a:b]

    MARK = "VSP_COMM_WATCHDOG_RUN_V1"
    if MARK in body:
        return True, "already patched"

    # indent for injection inside function
    # normalize: if tabs used, keep tabs; else spaces
    inner = indent + ("    " if "\t" not in indent else "\t")

    # Find request_id assignment; else fallback to before return jsonify
    m_id = re.search(r"^\s*(request_id|req_id)\s*=\s*.+\n", body, flags=re.M)
    insert_at = None
    if m_id:
        insert_at = m_id.end()
    else:
        mret = re.search(r"^\s*return\s+jsonify\(", body, flags=re.M)
        insert_at = mret.start() if mret else len(body)

    inject_state = f"""{inner}# === {MARK}: init state ===
{inner}_rid = locals().get("request_id", locals().get("req_id", ""))
{inner}_stall = int(os.environ.get("VSP_STALL_TIMEOUT_SEC", "600"))
{inner}_total = int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC", "7200"))
{inner}_state_path = VSP_UIREQ_STATE_DIR / f"{{_rid}}.json"
{inner}_vsp_atomic_write_json_v1(_state_path, {{
{inner}    "req_id": str(_rid),
{inner}    "start_ts": int(time.time()),
{inner}    "status": "RUNNING",
{inner}    "final": False,
{inner}    "killed": False,
{inner}    "kill_reason": "",
{inner}    "stall_timeout_sec": _stall,
{inner}    "total_timeout_sec": _total,
{inner}    "progress_pct": 0,
{inner}    "stage_index": 0,
{inner}    "stage_total": 0,
{inner}    "stage_name": "",
{inner}    "stage_sig": "0/0||0",
{inner}    "last_sig_change_ts": int(time.time()),
{inner}    "target": str(locals().get("target", locals().get("target_path", "")) or ""),
{inner}    "profile": str(locals().get("profile","") or ""),
{inner}    "ci_run_dir": "",
{inner}    "runner_log": "",
{inner}    "pid": 0,
{inner}    "pgid": 0,
{inner}}})
{inner}# === END {MARK} ===
"""

    body2 = body[:insert_at] + inject_state + body[insert_at:]

    # Patch first "var = subprocess.Popen(" inside this function:
    m_p = re.search(r"^\s*(?P<var>[A-Za-z_]\w*)\s*=\s*subprocess\.Popen\s*\(", body2, flags=re.M)
    if m_p:
        var = m_p.group("var")
        call_start = m_p.end() - 1  # points to '('
        # find matching closing paren with simple counter
        i = call_start
        depth = 0
        while i < len(body2):
            ch = body2[i]
            if ch == "(":
                depth += 1
            elif ch == ")":
                depth -= 1
                if depth == 0:
                    call_end = i
                    break
            i += 1
        else:
            call_end = None

        if call_end:
            call_text = body2[call_start:call_end+1]
            if "start_new_session" not in call_text:
                # insert before last ')'
                body2 = body2[:call_end] + ", start_new_session=True" + body2[call_end:]
                call_end = call_end + len(", start_new_session=True")

            # insert after call line ends (next newline after call_end)
            nl = body2.find("\n", call_end)
            if nl == -1:
                nl = call_end + 1
            inject_after_popen = f"""{inner}# === {MARK}: attach pid/pgid + spawn watchdog ===
{inner}try:
{inner}    _pid = int(getattr({var}, "pid", 0) or 0)
{inner}    _pgid = 0
{inner}    try:
{inner}        _pgid = os.getpgid(_pid) if _pid > 0 else 0
{inner}    except Exception:
{inner}        _pgid = 0
{inner}    _st = json.loads(_state_path.read_text(encoding="utf-8", errors="ignore")) if _state_path.exists() else {{}}
{inner}    _st["pid"] = _pid
{inner}    _st["pgid"] = _pgid
{inner}    _vsp_atomic_write_json_v1(_state_path, _st)
{inner}    _vsp_spawn_watchdog_v1(_state_path)
{inner}except Exception:
{inner}    pass
{inner}# === END {MARK}: attach ===
"""
            body2 = body2[:nl+1] + inject_after_popen + body2[nl+1:]
    else:
        # still spawn watchdog (no pid), at least stage/progress + stall detection works
        mret = re.search(r"^\s*return\s+jsonify\(", body2, flags=re.M)
        ip = mret.start() if mret else len(body2)
        body2 = body2[:ip] + f"""{inner}# === {MARK}: spawn watchdog (no pid found) ===
{inner}try:
{inner}    _vsp_spawn_watchdog_v1(_state_path)
{inner}except Exception:
{inner}    pass
{inner}# === END {MARK}: spawn watchdog ===
""" + body2[ip:]

    # commit back
    nonlocal txt
    txt = txt[:a] + body2 + txt[b:]
    return True, f"patched handler {fn}"

def patch_status_v1():
    info = find_handler_by_route("/api/vsp/run_status_v1")
    if not info:
        return False, "route '/api/vsp/run_status_v1' not found"
    def_pos, indent, fn = info
    s = slice_func(def_pos)
    if not s:
        return False, "cannot slice status function"
    a, b = s
    body = txt[a:b]
    MARK = "VSP_COMM_STATUS_FROM_STATE_V1"
    if MARK in body:
        return True, "already patched"
    inner = indent + ("    " if "\t" not in indent else "\t")
    # Insert right after def line
    m = re.search(r"^([ \t]*)def\s+[A-Za-z_]\w*\s*\([^)]*\)\s*:\s*\n", body, flags=re.M)
    if not m:
        return False, "cannot locate def line"
    ip = m.end()
    inject = f"""{inner}# === {MARK} ===
{inner}try:
{inner}    if str(req_id).startswith("VSP_UIREQ_"):
{inner}        _p = VSP_UIREQ_STATE_DIR / f"{{req_id}}.json"
{inner}        if _p.exists():
{inner}            _st = json.loads(_p.read_text(encoding="utf-8", errors="ignore"))
{inner}            return jsonify({{
{inner}                "ok": True,
{inner}                "req_id": str(req_id),
{inner}                "status": _st.get("status","RUNNING"),
{inner}                "final": bool(_st.get("final", False)),
{inner}                "error": _st.get("error","") or "",
{inner}                "stall_timeout_sec": int(_st.get("stall_timeout_sec", 600)),
{inner}                "total_timeout_sec": int(_st.get("total_timeout_sec", 7200)),
{inner}                "progress_pct": int(_st.get("progress_pct", 0)),
{inner}                "stage_index": int(_st.get("stage_index", 0)),
{inner}                "stage_total": int(_st.get("stage_total", 0)),
{inner}                "stage_name": _st.get("stage_name","") or "",
{inner}                "stage_sig": _st.get("stage_sig","0/0||0") or "0/0||0",
{inner}                "killed": bool(_st.get("killed", False)),
{inner}                "kill_reason": _st.get("kill_reason","") or "",
{inner}                "ci_run_dir": _st.get("ci_run_dir","") or "",
{inner}                "runner_log": _st.get("runner_log","") or "",
{inner}            }})
{inner}except Exception:
{inner}    pass
{inner}# === END {MARK} ===
"""
    body2 = body[:ip] + inject + body[ip:]
    nonlocal txt
    txt = txt[:a] + body2 + txt[b:]
    return True, f"patched handler {fn}"

ok1, msg1 = patch_run_v1()
ok2, msg2 = patch_status_v1()

p.write_text(txt, encoding="utf-8")
print("[PATCH]", msg1)
print("[PATCH]", msg2)
PY

python3 -m py_compile run_api/vsp_run_api_v1.py run_api/vsp_watchdog_v1.py
echo "[OK] py_compile OK"

echo "[OK] State dir: out_ci/ui_req_state"
echo "[NEXT] Restart 8910 to load patched code."

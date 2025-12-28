#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
APP="vsp_demo_app.py"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }

# 1) Restore vsp_run_api_v1.py to best known-good finalize backup
LATEST="$(ls -1 "${F}.bak_watchdog_finalize_"* 2>/dev/null | sort | tail -n1 || true)"
if [ -z "${LATEST}" ]; then
  LATEST="$(ls -1 "${F}.bak_synth_status_"* 2>/dev/null | sort | tail -n1 || true)"
fi
if [ -z "${LATEST}" ]; then
  echo "[ERR] No suitable backup found for $F (need .bak_watchdog_finalize_* or .bak_synth_status_*)"
  exit 1
fi

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_before_hook_${TS}"
cp -f "$LATEST" "$F"
echo "[RESTORE] $F <= $LATEST"
python3 -m py_compile "$F"
echo "[OK] py_compile restored $F"

mkdir -p run_api out_ci/ui_req_state

# 2) Ensure watchdog exists (create minimal if missing)
if [ ! -f run_api/vsp_watchdog_v1.py ]; then
cat > run_api/vsp_watchdog_v1.py <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, signal, subprocess, time
from pathlib import Path

STAGE_RE = re.compile(r"\[\s*(\d+)\s*/\s*(\d+)\s*\]\s*([^\]]+?)\s*\]+", re.IGNORECASE)

def _now(): return int(time.time())

def _read_json(p: Path):
    try: return json.loads(p.read_text(encoding="utf-8", errors="ignore"))
    except Exception: return {}

def _write_json(p: Path, obj: dict):
    p.parent.mkdir(parents=True, exist_ok=True)
    tmp = p.with_suffix(p.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(p)

def _tail(p: Path, maxb=250_000):
    if not p.exists(): return ""
    b = p.read_bytes()
    if len(b) > maxb: b = b[-maxb:]
    return b.decode("utf-8", errors="ignore")

def _last_marker(txt: str):
    last = None
    for m in STAGE_RE.finditer(txt): last = m
    if not last: return (0,0,"")
    return (int(last.group(1)), int(last.group(2)), last.group(3).strip())

def _guess_ci_dir(target: str, start_ts: int):
    roots = []
    if target:
        roots += [
            Path(target)/"out_ci",
            Path(target)/"ci"/"VSP_CI_OUTER"/"out_ci",
            Path(target)/"ci"/"out_ci",
        ]
    roots += [Path.cwd()/ "out_ci", Path.cwd().parent/"out_ci"]
    cand=[]
    for r in roots:
        if not r.exists(): continue
        for d in r.glob("VSP_CI_*"):
            try:
                mt=int(d.stat().st_mtime)
                if mt >= start_ts-900: cand.append((mt,str(d)))
            except Exception:
                pass
    if not cand: return ""
    cand.sort()
    return cand[-1][1]

def _pick_log(ci_dir: str):
    if not ci_dir: return ""
    d = Path(ci_dir)
    for p in [d/"runner.log", d/"run.log", d/"vsp_ci.log", d/"SUMMARY.txt", d/"out.log", d/"ci.log"]:
        if p.exists(): return str(p)
    for p in [d/"kics"/"kics.log", d/"codeql"/"codeql.log"]:
        if p.exists(): return str(p)
    return ""

def _is_alive(pid: int):
    try: os.kill(pid,0); return True
    except Exception: return False

def _kill(pid: int):
    if pid<=0: return
    try:
        os.kill(pid, signal.SIGTERM)
        time.sleep(2)
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass

def main():
    ap=argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--tick", type=int, default=2)
    args=ap.parse_args()
    sp=Path(args.state)

    while True:
        st=_read_json(sp)
        if not st:
            time.sleep(args.tick); continue
        if st.get("final") is True:
            return

        now=_now()
        start_ts=int(st.get("start_ts") or now)
        stall=int(st.get("stall_timeout_sec") or 600)
        total=int(st.get("total_timeout_sec") or 7200)

        pid=int(st.get("pid") or 0)
        target=str(st.get("target") or "")
        last_sig=str(st.get("stage_sig") or "0/0||0")
        last_chg=int(st.get("last_sig_change_ts") or start_ts)

        if not st.get("ci_run_dir"):
            st["ci_run_dir"]=_guess_ci_dir(target,start_ts) or ""
        if st.get("ci_run_dir") and not st.get("runner_log"):
            st["runner_log"]=_pick_log(st["ci_run_dir"]) or ""

        if st.get("runner_log"):
            t=_tail(Path(st["runner_log"]))
            i,tol,name=_last_marker(t)
            sig=f"{i}/{tol}||{i if i>0 else 0}"
            st["stage_index"]=i; st["stage_total"]=tol; st["stage_name"]=name; st["stage_sig"]=sig
            if tol>0: st["progress_pct"]=int(((max(i,1)-1)/tol)*100)
            if sig!=last_sig:
                st["last_sig_change_ts"]=now
                last_chg=now

        if now-start_ts>total:
            st["killed"]=True; st["kill_reason"]="TOTAL"
        elif now-last_chg>stall:
            st["killed"]=True; st["kill_reason"]="STALL"

        if st.get("killed") and not st.get("final"):
            st["status"]="KILLED"
            _kill(pid)
            st["final"]=True; st["final_ts"]=now
            _write_json(sp, st)
            return

        if pid>0 and not _is_alive(pid):
            st["status"]="FINISHED"
            st["final"]=True; st["final_ts"]=now
            _write_json(sp, st)
            return

        st["status"]="RUNNING"; st["last_poll_ts"]=now
        _write_json(sp, st)
        time.sleep(args.tick)

if __name__=="__main__":
    main()
PY
chmod +x run_api/vsp_watchdog_v1.py
echo "[OK] created run_api/vsp_watchdog_v1.py"
fi

# 3) Write hook module (NO touching vsp_run_api_v1.py)
cat > run_api/vsp_watchdog_hook_v1.py <<'PY'
import json, os, time, subprocess
from pathlib import Path
from flask import jsonify

STATE_DIR = Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state"
STATE_DIR.mkdir(parents=True, exist_ok=True)

def _atomic_write(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def _spawn_watchdog(state_path: Path) -> None:
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

def _find_endpoint(app, suffix: str):
    # accept blueprint endpoints like "vsp.run_v1"
    for k in app.view_functions.keys():
        if k == suffix or k.endswith("." + suffix) or k.endswith(suffix):
            return k
    return None

def install(app):
    ep_run = _find_endpoint(app, "run_v1")
    ep_status = _find_endpoint(app, "run_status_v1")

    if not ep_run:
        print("[VSP_WD_HOOK] cannot find endpoint run_v1 in app.view_functions")
        return

    orig_run = app.view_functions[ep_run]

    def wrapped_run(*args, **kwargs):
        # capture first subprocess.Popen pid used inside run_v1 without editing its source
        import subprocess as _sp
        real_popen = _sp.Popen
        holder = {}

        def popen_proxy(*a, **kw):
            p = real_popen(*a, **kw)
            if "proc" not in holder:
                holder["proc"] = p
            return p

        _sp.Popen = popen_proxy
        try:
            resp = orig_run(*args, **kwargs)
        finally:
            _sp.Popen = real_popen

        try:
            data = resp.get_json(silent=True) if hasattr(resp, "get_json") else None
        except Exception:
            data = None

        if isinstance(data, dict):
            rid = str(data.get("request_id", ""))
            if rid.startswith("VSP_UIREQ_"):
                stall = int(os.environ.get("VSP_STALL_TIMEOUT_SEC", "600"))
                total = int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC", "7200"))
                target = str(data.get("target", "") or "")
                state_path = STATE_DIR / (rid + ".json")
                pid = 0
                try:
                    pid = int(getattr(holder.get("proc"), "pid", 0) or 0)
                except Exception:
                    pid = 0
                _atomic_write(state_path, {
                    "req_id": rid,
                    "start_ts": int(time.time()),
                    "status": "RUNNING",
                    "final": False,
                    "killed": False,
                    "kill_reason": "",
                    "stall_timeout_sec": stall,
                    "total_timeout_sec": total,
                    "progress_pct": 0,
                    "stage_index": 0,
                    "stage_total": 0,
                    "stage_name": "",
                    "stage_sig": "0/0||0",
                    "last_sig_change_ts": int(time.time()),
                    "target": target,
                    "profile": str(data.get("profile","") or ""),
                    "ci_run_dir": "",
                    "runner_log": "",
                    "pid": pid,
                })
                _spawn_watchdog(state_path)
        return resp

    app.view_functions[ep_run] = wrapped_run
    print(f"[VSP_WD_HOOK] installed run_v1 wrapper on endpoint={ep_run}")

    if ep_status:
        orig_status = app.view_functions[ep_status]

        def wrapped_status(req_id, *args, **kwargs):
            rid = str(req_id)
            if rid.startswith("VSP_UIREQ_"):
                sp = STATE_DIR / (rid + ".json")
                if sp.exists():
                    try:
                        st = json.loads(sp.read_text(encoding="utf-8", errors="ignore"))
                        return jsonify({
                            "status": st.get("status","RUNNING"),
                            "final": bool(st.get("final", False)),
                            "progress_pct": int(st.get("progress_pct", 0)),
                            "stage_sig": st.get("stage_sig","0/0||0") or "0/0||0",
                            "runner_log": st.get("runner_log","") or None,
                            "ci_run_dir": st.get("ci_run_dir","") or None,
                            "killed": st.get("killed", None),
                            "kill_reason": st.get("kill_reason", None),
                        })
                    except Exception:
                        pass
            return orig_status(req_id, *args, **kwargs)

        app.view_functions[ep_status] = wrapped_status
        print(f"[VSP_WD_HOOK] installed run_status_v1 wrapper on endpoint={ep_status}")
PY
python3 -m py_compile run_api/vsp_watchdog_hook_v1.py
echo "[OK] py_compile hook OK"

# 4) Patch vsp_demo_app.py to call install(app) right before app.run(...)
cp -f "$APP" "$APP.bak_watchdog_hook_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

app_path = Path("vsp_demo_app.py")
txt = app_path.read_text(encoding="utf-8", errors="ignore").splitlines(True)

# find first "X.run(" to detect app var
appvar = None
run_line = None
for i, ln in enumerate(txt):
    m = re.search(r"^\s*(\w+)\.run\s*\(", ln)
    if m:
        appvar = m.group(1)
        run_line = i
        break

if not appvar or run_line is None:
    raise SystemExit("[ERR] cannot find *.run( in vsp_demo_app.py to inject hook")

hook = [
    "\n",
    "# === VSP_WATCHDOG_HOOK_V1 ===\n",
    "try:\n",
    "    from run_api.vsp_watchdog_hook_v1 import install as _vsp_wd_install\n",
    f"    _vsp_wd_install({appvar})\n",
    "except Exception as _e:\n",
    "    print('[VSP_WD_HOOK] install failed:', _e)\n",
    "# === END VSP_WATCHDOG_HOOK_V1 ===\n",
    "\n",
]

# avoid double insert
if any("VSP_WATCHDOG_HOOK_V1" in ln for ln in txt):
    print("[OK] hook already present in vsp_demo_app.py")
else:
    txt[run_line:run_line] = hook
    app_path.write_text("".join(txt), encoding="utf-8")
    print("[OK] injected hook before", f"{appvar}.run(...)")

PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile vsp_demo_app.py OK"
echo "[DONE] install_watchdog_hook_v1 complete"

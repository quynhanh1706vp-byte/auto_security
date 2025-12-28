#!/usr/bin/env bash
set -euo pipefail

HOOK="run_api/vsp_watchdog_hook_v1.py"
WD="run_api/vsp_watchdog_v1.py"

[ -f "$HOOK" ] || { echo "[ERR] missing $HOOK"; exit 1; }
[ -f "$WD" ] || { echo "[ERR] missing $WD"; exit 1; }

cp -f "$HOOK" "$HOOK.bak_enrich_logs_$(date +%Y%m%d_%H%M%S)"
cp -f "$WD"   "$WD.bak_enrich_logs_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] hook+wd backups created"

# --- 1) overwrite HOOK: capture target/profile from request + extract rid via json or regex ---
cat > "$HOOK" <<'PY'
import json, os, re, time, subprocess
from pathlib import Path
from flask import jsonify, request

STATE_DIR = Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state"
STATE_DIR.mkdir(parents=True, exist_ok=True)

RID_RE = re.compile(r"(VSP_UIREQ_\d{8}_\d{6}_[A-Za-z0-9]+)")

def _dbg(*a):
    if os.environ.get("VSP_WD_DEBUG","0") == "1":
        print("[VSP_WD_HOOK][DBG]", *a)

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
    except Exception as e:
        _dbg("spawn watchdog failed:", e)

def _find_endpoint(app, suffix: str):
    for k in app.view_functions.keys():
        if k == suffix or k.endswith("." + suffix) or k.endswith(suffix):
            return k
    return None

def _extract_json(resp):
    base = resp[0] if isinstance(resp, tuple) and len(resp) > 0 else resp
    try:
        if isinstance(base, dict):
            return base
        if hasattr(base, "get_json"):
            j = base.get_json(silent=True)
            if isinstance(j, dict):
                return j
        if hasattr(base, "get_data"):
            raw = (base.get_data(as_text=True) or "").strip()
            if raw.startswith("{") and raw.endswith("}"):
                return json.loads(raw)
    except Exception:
        return None
    return None

def _extract_rid_any(resp):
    data = _extract_json(resp)
    if isinstance(data, dict):
        rid = str(data.get("request_id","") or "")
        if rid.startswith("VSP_UIREQ_"):
            return rid
    base = resp[0] if isinstance(resp, tuple) and len(resp) > 0 else resp
    try:
        if hasattr(base, "get_data"):
            raw = (base.get_data(as_text=True) or "")
            m = RID_RE.search(raw)
            if m:
                return m.group(1)
    except Exception:
        pass
    return ""

def _guess_pid() -> int:
    needles = ["vsp_ci_outer", "run_all_tools_v2.sh", "VSP_CI_", "SECURITY-10-10-v4", "/home/test/Data/SECURITY-10-10-v4"]
    try:
        out = subprocess.check_output(["ps", "-eo", "pid,etimes,cmd"], text=True, errors="ignore")
        best = None
        for line in out.splitlines()[1:]:
            parts = line.strip().split(None, 2)
            if len(parts) < 3:
                continue
            pid_s, et_s, cmd = parts
            try:
                pid = int(pid_s); et = int(et_s)
            except Exception:
                continue
            if et > 3600:
                continue
            score = sum(1 for n in needles if n in cmd)
            if score >= 2:
                cand = (et, pid)
                if best is None or cand[0] < best[0]:
                    best = cand
        return best[1] if best else 0
    except Exception:
        return 0

def _default_state(rid: str, target: str, profile: str, pid: int) -> dict:
    stall = int(os.environ.get("VSP_STALL_TIMEOUT_SEC","600"))
    total = int(os.environ.get("VSP_TOTAL_TIMEOUT_SEC","7200"))
    now = int(time.time())
    return {
        "req_id": rid,
        "start_ts": now,
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
        "last_sig_change_ts": now,
        "target": target or "",
        "profile": profile or "",
        "ci_run_dir": "",
        "runner_log": "",
        "pid": int(pid or 0),
    }

def install(app):
    ep_run = _find_endpoint(app, "run_v1")
    ep_status = _find_endpoint(app, "run_status_v1")

    if not ep_run:
        print("[VSP_WD_HOOK] cannot find endpoint run_v1")
        return

    orig_run = app.view_functions[ep_run]

    def wrapped_run(*args, **kwargs):
        # capture request body upfront (best effort)
        req = {}
        try:
            req = request.get_json(silent=True) or {}
        except Exception:
            req = {}
        target = str(req.get("target","") or "")
        profile = str(req.get("profile","") or "")

        # capture first subprocess.Popen pid
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

        rid = _extract_rid_any(resp)
        if rid.startswith("VSP_UIREQ_"):
            pid = 0
            try:
                pid = int(getattr(holder.get("proc"), "pid", 0) or 0)
            except Exception:
                pid = 0
            if pid <= 0:
                pid = _guess_pid()

            sp = STATE_DIR / (rid + ".json")

            # merge-enrich if state already exists (lazy-created)
            st = _default_state(rid, target, profile, pid)
            if sp.exists():
                try:
                    old = json.loads(sp.read_text(encoding="utf-8", errors="ignore"))
                    # keep start_ts if existed
                    if "start_ts" in old:
                        st["start_ts"] = old["start_ts"]
                    old.update({k:v for k,v in st.items() if v not in (None,"")})
                    st = old
                except Exception:
                    pass

            _atomic_write(sp, st)
            _spawn_watchdog(sp)
            _dbg("enriched state", rid, "pid=", pid, "target=", target, "profile=", profile)

        return resp

    app.view_functions[ep_run] = wrapped_run
    print(f"[VSP_WD_HOOK] installed run_v1 wrapper on endpoint={ep_run}")

    if ep_status:
        orig_status = app.view_functions[ep_status]

        def wrapped_status(req_id, *args, **kwargs):
            rid = str(req_id)
            if rid.startswith("VSP_UIREQ_"):
                sp = STATE_DIR / (rid + ".json")
                if not sp.exists():
                    pid = _guess_pid()
                    st = _default_state(rid, "", "", pid)
                    _atomic_write(sp, st)
                    _spawn_watchdog(sp)
                try:
                    st = json.loads(sp.read_text(encoding="utf-8", errors="ignore"))
                except Exception:
                    st = _default_state(rid, "", "", 0)
                return jsonify({
                    "status": st.get("status","RUNNING"),
                    "final": bool(st.get("final", False)),
                    "progress_pct": int(st.get("progress_pct", 0)),
                    "stage_sig": st.get("stage_sig","0/0||0") or "0/0||0",
                    "runner_log": st.get("runner_log","") or None,
                    "ci_run_dir": st.get("ci_run_dir","") or None,
                    "killed": st.get("killed", None),
                    "kill_reason": st.get("kill_reason", None),
                    "stall_timeout_sec": int(st.get("stall_timeout_sec", 600)),
                    "total_timeout_sec": int(st.get("total_timeout_sec", 7200)),
                })
            return orig_status(req_id, *args, **kwargs)

        app.view_functions[ep_status] = wrapped_status
        print(f"[VSP_WD_HOOK] installed run_status_v1 wrapper on endpoint={ep_status}")
PY

# --- 2) overwrite WATCHDOG: better runner_log discovery (scan newest, depth<=3, prefer marker) ---
cat > "$WD" <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, signal, time, subprocess
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

def _tail(p: Path, maxb=400_000):
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
    cand=[]
    for r in roots:
        if not r.exists(): continue
        for d in r.glob("VSP_CI_*"):
            try:
                mt=int(d.stat().st_mtime)
                if mt >= start_ts - 1200:
                    cand.append((mt, str(d)))
            except Exception:
                pass
    if not cand: return ""
    cand.sort()
    return cand[-1][1]

def _pick_runner_log_smart(ci_dir: str) -> str:
    if not ci_dir: return ""
    d = Path(ci_dir)
    if not d.exists(): return ""

    # 1) fast common names
    common = [
        d/"runner.log", d/"run.log", d/"vsp_ci.log", d/"ci.log", d/"out.log",
        d/"SUMMARY.txt", d/"SUMMARY.txt",
        d/"kics"/"kics.log", d/"codeql"/"codeql.log",
    ]
    for p in common:
        if p.exists() and p.stat().st_size > 0:
            return str(p)

    # 2) scan newest file depth<=3, prefer ones containing marker
    best = None  # (has_marker, mtime, size, path)
    for p in d.rglob("*"):
        try:
            if p.is_dir(): 
                continue
            rel_depth = len(p.relative_to(d).parts)
            if rel_depth > 3:
                continue
            sz = p.stat().st_size
            if sz <= 0 or sz > 80_000_000:
                continue
            name = p.name.lower()
            if not (name.endswith(".log") or name.endswith(".txt") or "log" in name or "summary" in name):
                continue
            mt = int(p.stat().st_mtime)
            txt = _tail(p, maxb=120_000)
            has_marker = 1 if STAGE_RE.search(txt) else 0
            cand = (has_marker, mt, sz, str(p))
            if best is None or cand > best:
                best = cand
        except Exception:
            continue
    return best[3] if best else ""

def _is_alive(pid: int):
    try:
        os.kill(pid, 0); return True
    except Exception:
        return False

def _kill(pid: int):
    if pid <= 0: return
    try:
        os.kill(pid, signal.SIGTERM)
        time.sleep(2)
        os.kill(pid, signal.SIGKILL)
    except Exception:
        pass

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--state", required=True)
    ap.add_argument("--tick", type=int, default=2)
    args = ap.parse_args()
    sp = Path(args.state)

    while True:
        st = _read_json(sp)
        if not st:
            time.sleep(args.tick); continue
        if st.get("final") is True:
            return

        now = _now()
        start_ts = int(st.get("start_ts") or now)
        stall = int(st.get("stall_timeout_sec") or 600)
        total = int(st.get("total_timeout_sec") or 7200)

        pid = int(st.get("pid") or 0)
        target = str(st.get("target") or "")
        last_sig = str(st.get("stage_sig") or "0/0||0")
        last_chg = int(st.get("last_sig_change_ts") or start_ts)

        if not st.get("ci_run_dir"):
            st["ci_run_dir"] = _guess_ci_dir(target, start_ts) or ""
        if st.get("ci_run_dir") and not st.get("runner_log"):
            st["runner_log"] = _pick_runner_log_smart(st["ci_run_dir"]) or ""

        if st.get("runner_log"):
            txt = _tail(Path(st["runner_log"]))
            i,t,name = _last_marker(txt)
            sig = f"{i}/{t}||{i if i>0 else 0}"
            st["stage_index"]=i; st["stage_total"]=t; st["stage_name"]=name; st["stage_sig"]=sig
            if t>0:
                st["progress_pct"]=int(((max(i,1)-1)/t)*100)
            if sig != last_sig:
                st["last_sig_change_ts"]=now
                last_chg = now

        if now - start_ts > total:
            st["killed"]=True; st["kill_reason"]="TOTAL"
        elif now - last_chg > stall:
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

        st["status"]="RUNNING"
        st["last_poll_ts"]=now
        _write_json(sp, st)
        time.sleep(args.tick)

if __name__ == "__main__":
    main()
PY

python3 -m py_compile "$HOOK"
python3 -m py_compile "$WD"
echo "[OK] py_compile hook+watchdog OK"

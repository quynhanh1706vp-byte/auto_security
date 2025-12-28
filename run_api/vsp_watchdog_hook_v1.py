import json, os, re, time, subprocess
from pathlib import Path
from flask import jsonify, request

STATE_DIR = Path(__file__).resolve().parents[1] / "out_ci" / "ui_req_state"
STATE_DIR.mkdir(parents=True, exist_ok=True)

RID_RE = re.compile(r"(VSP_UIREQ_\d{8}_\d{6}_[A-Za-z0-9]+)")

def _atomic_write(path: Path, obj: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")
    tmp.replace(path)

def _is_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    try:
        os.kill(pid, 0)
        return True
    except Exception:
        return False

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

def _extract_rid(resp) -> str:
    data = _extract_json(resp)
    if isinstance(data, dict):
        rid = str(data.get("request_id","") or "")
        if rid.startswith("VSP_UIREQ_"):
            return rid
    base = resp[0] if isinstance(resp, tuple) and len(resp) > 0 else resp
    try:
        if hasattr(base, "get_data"):
            raw = base.get_data(as_text=True) or ""
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
        best = None  # (etimes, pid)
        for line in out.splitlines()[1:]:
            parts = line.strip().split(None, 2)
            if len(parts) < 3:
                continue
            pid_s, et_s, cmd = parts[0], parts[1], parts[2]
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

def _ensure_watchdog(state_path: Path, st: dict) -> dict:
    wp = int(st.get("watchdog_pid") or 0)
    if _is_alive(wp):
        return st
    wd = Path(__file__).resolve().parent / "vsp_watchdog_v1.py"
    if not wd.exists():
        return st
    try:
        p = subprocess.Popen(
            ["python3", str(wd), "--state", str(state_path), "--tick", "2"],
            stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
            start_new_session=True
        )
        st["watchdog_pid"] = int(p.pid)
    except Exception:
        pass
    return st

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
        "watchdog_pid": 0,
    }

def _find_endpoint(app, suffix: str):
    for k in app.view_functions.keys():
        if k == suffix or k.endswith("." + suffix) or k.endswith(suffix):
            return k
    return None

def install(app):
    ep_run = _find_endpoint(app, "run_v1")
    ep_status = _find_endpoint(app, "run_status_v1")
    if not ep_run:
        print("[VSP_WD_HOOK] cannot find endpoint run_v1")
        return

    orig_run = app.view_functions[ep_run]

    def wrapped_run(*args, **kwargs):
        # request body for enrich
        req = {}
        try:
            req = request.get_json(silent=True) or {}
        except Exception:
            req = {}
        target = str(req.get("target","") or "")
        profile = str(req.get("profile","") or "")

        # capture first Popen pid
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

        rid = _extract_rid(resp)
        if rid.startswith("VSP_UIREQ_"):
            pid = 0
            try:
                pid = int(getattr(holder.get("proc"), "pid", 0) or 0)
            except Exception:
                pid = 0
            if pid <= 0:
                pid = _guess_pid()

            sp = STATE_DIR / (rid + ".json")
            st = _default_state(rid, target, profile, pid)

            if sp.exists():
                try:
                    old = json.loads(sp.read_text(encoding="utf-8", errors="ignore"))
                    if "start_ts" in old:
                        st["start_ts"] = old["start_ts"]
                    old.update({k:v for k,v in st.items() if v not in (None,"")})
                    st = old
                except Exception:
                    pass

            st = _ensure_watchdog(sp, st)
            _atomic_write(sp, st)

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
                    st = _ensure_watchdog(sp, st)
                    _atomic_write(sp, st)

                try:
                    st = json.loads(sp.read_text(encoding="utf-8", errors="ignore"))
                except Exception:
                    st = _default_state(rid, "", "", 0)

                # also ensure watchdog from status path (commercial)
                st = _ensure_watchdog(sp, st)
                _atomic_write(sp, st)

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

#!/usr/bin/env bash
set -euo pipefail
WD="run_api/vsp_watchdog_v1.py"
[ -f "$WD" ] || { echo "[ERR] missing $WD"; exit 1; }
cp -f "$WD" "$WD.bak_commercial_v2_$(date +%Y%m%d_%H%M%S)"
echo "[BACKUP] $WD.bak_commercial_v2_*"

cat > "$WD" <<'PY'
#!/usr/bin/env python3
import argparse, json, os, re, signal, time
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

def _tail(p: Path, maxb=600_000):
    if not p.exists(): return ""
    b = p.read_bytes()
    if len(b) > maxb: b = b[-maxb:]
    return b.decode("utf-8", errors="ignore")

def _last_marker(txt: str):
    last = None
    for m in STAGE_RE.finditer(txt): last = m
    if not last: return (0,0,"")
    return (int(last.group(1)), int(last.group(2)), last.group(3).strip())

def _infer_root_from_pid(pid: int) -> str:
    if pid <= 0: return ""
    try:
        return os.readlink(f"/proc/{pid}/cwd")
    except Exception:
        return ""

def _pick_latest_vsp_ci(out_ci: Path, start_ts: int, window_sec: int = 7200) -> str:
    if not out_ci.exists(): return ""
    cand=[]
    for d in out_ci.glob("VSP_CI_*"):
        try:
            mt=int(d.stat().st_mtime)
            if mt >= start_ts - window_sec:
                cand.append((mt, str(d)))
        except Exception:
            pass
    if not cand: return ""
    cand.sort()
    return cand[-1][1]

def _fallback_scan_home_test_data(start_ts: int) -> str:
    base = Path("/home/test/Data")
    if not base.exists(): return ""
    best=None  # (mtime, path)
    for sub in base.iterdir():
        try:
            if not sub.is_dir():
                continue
            out_ci = sub/"out_ci"
            if not out_ci.exists():
                continue
            d = _pick_latest_vsp_ci(out_ci, start_ts, window_sec=7200)
            if not d:
                continue
            mt = int(Path(d).stat().st_mtime)
            cand = (mt, d)
            if best is None or cand[0] > best[0]:
                best = cand
        except Exception:
            continue
    return best[1] if best else ""

def _pick_runner_log(ci_dir: str) -> str:
    if not ci_dir: return ""
    d = Path(ci_dir)
    if not d.exists(): return ""
    p = d/"runner.log"
    if p.exists():
        return str(p)
    # fallback: pick newest log/txt within depth<=3
    best=None  # (mtime, size, path)
    for p in d.rglob("*"):
        try:
            if p.is_dir():
                continue
            depth = len(p.relative_to(d).parts)
            if depth > 3:
                continue
            name = p.name.lower()
            if not (name.endswith(".log") or name.endswith(".txt") or "log" in name or "summary" in name):
                continue
            sz = p.stat().st_size
            if sz <= 0 or sz > 120_000_000:
                continue
            mt = int(p.stat().st_mtime)
            cand=(mt, sz, str(p))
            if best is None or cand > best:
                best=cand
        except Exception:
            continue
    return best[2] if best else ""

def _is_alive(pid: int):
    try:
        os.kill(pid, 0); return True
    except Exception:
        return False

def _kill_tree(pid: int):
    if pid <= 0: return
    try:
        pgid = os.getpgid(pid)
        os.killpg(pgid, signal.SIGTERM)
        time.sleep(2)
        os.killpg(pgid, signal.SIGKILL)
        return
    except Exception:
        pass
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

    grace = int(os.environ.get("VSP_WD_GRACE_SEC","120"))  # thương mại: 2 phút đầu không stall-kill

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
        last_sig=str(st.get("stage_sig") or "0/0||0")
        last_chg=int(st.get("last_sig_change_ts") or start_ts)

        st["watchdog_pid"] = int(os.getpid())

        # infer ci dir robustly
        if not st.get("ci_root_from_pid"):
            st["ci_root_from_pid"] = _infer_root_from_pid(pid) or ""

        if not st.get("ci_run_dir"):
            root = st.get("ci_root_from_pid") or ""
            if root:
                st["ci_run_dir"] = _pick_latest_vsp_ci(Path(root)/"out_ci", start_ts) or ""
            if not st.get("ci_run_dir"):
                # fallback full scan
                st["ci_run_dir"] = _fallback_scan_home_test_data(start_ts) or ""

        if st.get("ci_run_dir") and not st.get("runner_log"):
            st["runner_log"] = _pick_runner_log(st["ci_run_dir"]) or ""

        # === HEARTBEAT: nếu chưa có marker/log thì vẫn cập nhật last_sig_change_ts trong grace period
        if now - start_ts <= grace and st.get("stage_sig","0/0||0") == "0/0||0":
            st["last_sig_change_ts"] = now
            last_chg = now
            st["stage_name"] = "BOOTSTRAP"
            st["stage_sig"] = "0/0||BOOT"
            st["progress_pct"] = 0

        # parse markers if any
        if st.get("runner_log"):
            txt=_tail(Path(st["runner_log"]))
            i,tol,name=_last_marker(txt)
            if tol > 0:
                sig=f"{i}/{tol}||{i if i>0 else 0}"
                st["stage_index"]=i; st["stage_total"]=tol; st["stage_name"]=name; st["stage_sig"]=sig
                st["progress_pct"]=int(((max(i,1)-1)/tol)*100)
                if sig!=last_sig:
                    st["last_sig_change_ts"]=now
                    last_chg=now

        # total timeout
        if now-start_ts > total:
            st["killed"]=True; st["kill_reason"]="TOTAL"
        # stall timeout (after grace)
        elif now-start_ts > grace and now-last_chg > stall:
            st["killed"]=True; st["kill_reason"]="STALL"

        if st.get("killed") and not st.get("final"):
            st["status"]="KILLED"
            _kill_tree(pid)
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

python3 -m py_compile "$WD"
echo "[OK] watchdog commercial v2 installed + py_compile OK"

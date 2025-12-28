#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

PYF="run_api/vsp_run_api_v1.py"
[ -f "$PYF" ] || { echo "[ERR] missing: $PYF"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp "$PYF" "$PYF.bak_stage_timeout_${TS}"
echo "[BACKUP] $PYF.bak_stage_timeout_${TS}"

cat > "$PYF" << 'PY'
#!/usr/bin/env python3
# VSP Run API v1 (commercial): stage/progress parser + stall/total timeout + sync
import json, os, re, subprocess, uuid, time
from datetime import datetime, timezone
from pathlib import Path
from flask import Blueprint, request, jsonify

bp = Blueprint("vsp_run_api_v1", __name__)

ROOT_UI = Path(__file__).resolve().parents[1]  # .../ui
ROOT_BUNDLE = (ROOT_UI.parents[0]).resolve()   # .../SECURITY_BUNDLE
STATE_DIR = ROOT_UI / "out_ci" / "run_api_state"
STATE_DIR.mkdir(parents=True, exist_ok=True)

# Defaults (can override by env)
TOTAL_TIMEOUT_SEC = int(os.environ.get("VSP_UIREQ_TOTAL_TIMEOUT_SEC", str(2*60*60)))   # 2h
STALL_TIMEOUT_SEC = int(os.environ.get("VSP_UIREQ_STALL_TIMEOUT_SEC", str(20*60)))    # 20m
TAIL_MAX_LINES = int(os.environ.get("VSP_UIREQ_TAIL_LINES", "220"))

# detect tool stages from runner logs
STAGE_RE = re.compile(r"===== \[(\d+)/(\d+)\]\s*([A-Za-z0-9_\-]+).*?=====")
# also accept some tool banners
ALT_TOOL_RE = re.compile(r"^\[(GITLEAKS|SEMGREP|KICS|CODEQL|BANDIT|TRIVY|SYFT|GRYPE)\]", re.M)

TOOLS8 = ["GITLEAKS","SEMGREP","KICS","CODEQL","BANDIT","TRIVY","SYFT","GRYPE"]

def nowz():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00", "Z")

def _load_json(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return None

def _write_json(p: Path, obj):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def state_path(req_id: str) -> Path:
    return STATE_DIR / f"{req_id}.json"

def read_state(req_id: str):
    p = state_path(req_id)
    st = _load_json(p)
    return st if isinstance(st, dict) else None

def write_state(req_id: str, st: dict):
    st["req_id"] = req_id
    _write_json(state_path(req_id), st)

def tail_file(path: str, max_lines: int = 200) -> str:
    if not path or not os.path.exists(path):
        return ""
    try:
        with open(path, "rb") as f:
            f.seek(0, os.SEEK_END)
            size = f.tell()
            # read last ~128KB
            f.seek(max(0, size - 131072))
            data = f.read().decode("utf-8", errors="replace")
        lines = data.splitlines()[-max_lines:]
        return "\n".join(lines) + ("\n" if lines else "")
    except Exception:
        return ""

def parse_stage_progress(text: str):
    # find last stage marker
    m = None
    for m2 in STAGE_RE.finditer(text or ""):
        m = m2
    if m:
        i = int(m.group(1))
        n = int(m.group(2)) if int(m.group(2)) > 0 else 8
        tool = (m.group(3) or "").strip().upper()
        if tool == "KICS":
            tool = "KICS"
        # clamp
        if n <= 0: n = 8
        prog = int(round((i / n) * 100))
        return {"stage": f"{i}/{n}", "tool": tool, "progress": max(0, min(100, prog))}
    # fallback: check last tool tag
    m3 = None
    for m2 in ALT_TOOL_RE.finditer(text or ""):
        m3 = m2
    if m3:
        tool = m3.group(1).upper()
        # approximate progress based on tool order
        try:
            idx = TOOLS8.index(tool) + 1
            prog = int(round((idx / 8) * 100))
        except Exception:
            prog = 0
        return {"stage": "", "tool": tool, "progress": max(0, min(100, prog))}
    return {"stage": "", "tool": "", "progress": 0}

def read_degraded_env(run_dir: str):
    out = {"degraded": 0, "reasons": ""}
    if not run_dir:
        return out
    p = Path(run_dir) / "vsp_degraded.env"
    if not p.exists():
        return out
    try:
        txt = p.read_text(encoding="utf-8", errors="replace")
        d = {}
        for line in txt.splitlines():
            if "=" in line:
                k,v = line.split("=",1)
                d[k.strip()] = v.strip()
        out["degraded"] = int(d.get("degraded","0") or "0")
        out["reasons"] = d.get("reasons","") or ""
        return out
    except Exception:
        return out

def read_summary_severity(run_dir: str):
    sev = {}
    if not run_dir:
        return sev
    p = Path(run_dir) / "report" / "summary_unified.json"
    if not p.exists():
        return sev
    try:
        j = json.loads(p.read_text(encoding="utf-8", errors="replace"))
        # accept either summary_by_severity or by_severity
        if isinstance(j, dict):
            if isinstance(j.get("summary_by_severity"), dict):
                sev = j["summary_by_severity"]
            elif isinstance(j.get("by_severity"), dict):
                sev = j["by_severity"]
        # normalize keys
        out = {}
        for k in ["CRITICAL","HIGH","MEDIUM","LOW","INFO","TRACE"]:
            out[k] = int(sev.get(k, 0) or 0)
        return out
    except Exception:
        return {}

def compute_gate_from_sev(sev: dict):
    # default thresholds (commercial)
    max_crit = int(os.environ.get("VSP_GATE_MAX_CRITICAL", "0"))
    max_high = int(os.environ.get("VSP_GATE_MAX_HIGH", "10"))
    max_med  = int(os.environ.get("VSP_GATE_MAX_MEDIUM", "999999"))
    max_low  = int(os.environ.get("VSP_GATE_MAX_LOW", "999999"))
    max_info = int(os.environ.get("VSP_GATE_MAX_INFO", "999999"))
    # TRACE ignored
    if not sev:
        return ("UNKNOWN", [])
    reasons = []
    if int(sev.get("CRITICAL",0)) > max_crit: reasons.append(f"CRITICAL({sev.get('CRITICAL',0)})>{max_crit}")
    if int(sev.get("HIGH",0)) > max_high: reasons.append(f"HIGH({sev.get('HIGH',0)})>{max_high}")
    if int(sev.get("MEDIUM",0)) > max_med: reasons.append(f"MEDIUM({sev.get('MEDIUM',0)})>{max_med}")
    if int(sev.get("LOW",0)) > max_low: reasons.append(f"LOW({sev.get('LOW',0)})>{max_low}")
    if int(sev.get("INFO",0)) > max_info: reasons.append(f"INFO({sev.get('INFO',0)})>{max_info}")
    return ("FAIL" if reasons else "PASS", reasons)

def spawn_outer(mode: str, profile: str, target_type: str, target: str):
    """
    Spawn CI_OUTER wrapper. Must exist inside target repo:
      <target>/ci/VSP_CI_OUTER/vsp_ci_outer_full_v1.sh
    """
    repo = Path(target).resolve()
    outer = repo / "ci" / "VSP_CI_OUTER" / "vsp_ci_outer_full_v1.sh"
    if not outer.exists():
        raise RuntimeError(f"Missing outer script: {outer}")

    env = os.environ.copy()
    env["VSP_UIREQ"] = "1"
    env["VSP_PROFILE"] = profile or "FULL_EXT"
    env["VSP_MODE"] = mode or "local"
    env["VSP_TARGET_TYPE"] = target_type or "path"
    env["VSP_TARGET"] = str(repo)

    # ensure bundle root visible to outer
    env.setdefault("VSP_BUNDLE_ROOT", str(ROOT_BUNDLE))

    # spawn in new session (killable by pgid)
    proc = subprocess.Popen(
        ["bash", str(outer)],
        cwd=str(outer.parent),
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        bufsize=1,
        start_new_session=True,
    )
    return proc

def sync_to_vsp(run_dir: str) -> (bool, str, str):
    """
    Sync CI run_dir -> SECURITY_BUNDLE/out/RUN_... via vsp_ci_sync_to_vsp_v1.sh
    Returns (ok, vsp_run_id, msg)
    """
    if not run_dir:
        return (False, "", "no run_dir")
    sync = ROOT_BUNDLE / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
    if not sync.exists():
        return (False, "", f"missing sync script: {sync}")
    try:
        # best-effort
        cp = subprocess.run(["bash", str(sync), str(run_dir)], capture_output=True, text=True, timeout=600)
        out = (cp.stdout or "") + "\n" + (cp.stderr or "")
        # run_id hint: "VSP_RUN_DIR = .../out/RUN_VSP_CI_...."
        m = re.search(r"VSP_RUN_DIR\s*=\s*(.+)", out)
        vsp_run_dir = m.group(1).strip() if m else ""
        vsp_run_id = Path(vsp_run_dir).name if vsp_run_dir else ""
        ok = (cp.returncode == 0)
        return (ok, vsp_run_id, out[-2000:])
    except Exception as e:
        return (False, "", f"sync exception: {e}")

def ensure_extras_latest():
    # optional: update extras json so dashboard can show right “latest”
    sh = ROOT_BUNDLE / "bin" / "vsp_build_dashboard_extras_v2.sh"
    if not sh.exists():
        return
    try:
        subprocess.run(["bash", str(sh)], cwd=str(ROOT_BUNDLE), timeout=180, capture_output=True, text=True)
    except Exception:
        pass

@bp.route("/api/vsp/run_v1", methods=["POST"])
def run_v1():
    data = request.get_json(silent=True) or {}
    mode = str(data.get("mode","local"))
    profile = str(data.get("profile","FULL_EXT"))
    target_type = str(data.get("target_type","path"))
    target = str(data.get("target","")).strip()

    if not target:
        return jsonify({"ok": False, "error": "missing target"}), 400
    if target_type != "path":
        return jsonify({"ok": False, "error": "only target_type=path supported"}), 400

    req_id = f"UIREQ_{datetime.now(timezone.utc).strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    log_path = str(ROOT_UI / "out_ci" / f"{req_id}.log")

    st = {
        "created_at": nowz(),
        "started_at": nowz(),
        "finished_at": None,
        "status": "RUNNING",
        "final": False,
        "exit_code": None,
        "gate": "UNKNOWN",
        "reasons": [],
        "mode": mode,
        "profile": profile,
        "target_type": target_type,
        "target": target,
        "log_path": log_path,
        "pid": None,
        "pgid": None,
        "ci_run_dir": "",
        "vsp_run_id": "",
        "sync": {"done": False, "ok": None, "msg": ""},
        "flag": {"has_findings": None},
        "severity": {},
        "stage": {"tool": "", "stage": "", "progress": 0},
        "degraded": {"degraded": 0, "reasons": ""},
        "timeouts": {"total_sec": TOTAL_TIMEOUT_SEC, "stall_sec": STALL_TIMEOUT_SEC},
        "last_log_mtime": None,
    }
    write_state(req_id, st)

    try:
        proc = spawn_outer(mode, profile, target_type, target)
        st["pid"] = proc.pid
        try:
            st["pgid"] = os.getpgid(proc.pid)
        except Exception:
            st["pgid"] = None
        write_state(req_id, st)

        # stream stdout to file and also infer RUN_DIR early
        run_dir = ""
        last_write = time.time()
        with open(log_path, "w", encoding="utf-8", errors="replace") as f:
            f.write(f"[VSP_RUN_API] req_id={req_id}\n")
            f.write(f"[VSP_RUN_API] spawned pid={proc.pid}\n")
            f.flush()

            for line in proc.stdout:
                f.write(line)
                if (time.time() - last_write) > 0.5:
                    f.flush()
                    last_write = time.time()

                # infer RUN_DIR quickly
                if (not run_dir) and ("RUN_DIR" in line) and ("out_ci" in line):
                    m = re.search(r"RUN_DIR\s*=\s*(\S+)", line)
                    if m:
                        run_dir = m.group(1).strip()
                        st = read_state(req_id) or st
                        st["ci_run_dir"] = run_dir
                        write_state(req_id, st)

            # process ended
        rc = proc.wait(timeout=1)

        st = read_state(req_id) or st
        st["exit_code"] = int(rc) if rc is not None else None
        st["finished_at"] = nowz()
        st["final"] = True
        st["status"] = "DONE" if (rc == 0) else "FAIL"

        # post: parse severity + gate if report exists
        if st.get("ci_run_dir"):
            sev = read_summary_severity(st["ci_run_dir"])
            st["severity"] = sev or {}
            gate, reasons = compute_gate_from_sev(sev or {})
            st["gate"] = gate
            st["reasons"] = reasons

            st["degraded"] = read_degraded_env(st["ci_run_dir"])

        write_state(req_id, st)

        # post: sync
        if st.get("ci_run_dir"):
            ok, vsp_run_id, msg = sync_to_vsp(st["ci_run_dir"])
            st = read_state(req_id) or st
            st["sync"] = {"done": True, "ok": bool(ok), "msg": msg[-1200:]}
            st["vsp_run_id"] = vsp_run_id or st.get("vsp_run_id","")
            # refresh extras latest best-effort
            ensure_extras_latest()
            write_state(req_id, st)

        return jsonify({"ok": True, "req_id": req_id}), 200

    except Exception as e:
        st = read_state(req_id) or st
        st["final"] = True
        st["status"] = "FAIL"
        st["exit_code"] = 2
        st["finished_at"] = nowz()
        st["reasons"] = [f"spawn_error:{e}"]
        write_state(req_id, st)
        return jsonify({"ok": False, "error": str(e), "req_id": req_id}), 500


def maybe_timeout_and_finalize(st: dict):
    """
    Called on every status poll: detect total timeout / stall timeout and finalize by killing PGID.
    """
    if not st or st.get("final"):
        return st

    logp = st.get("log_path","")
    now = time.time()

    started_at = st.get("started_at")
    # compute elapsed from started_at iso
    elapsed = None
    try:
        t0 = datetime.fromisoformat(started_at.replace("Z","+00:00")).timestamp()
        elapsed = now - t0
    except Exception:
        elapsed = None

    # compute stall based on log mtime
    stall = None
    try:
        if logp and os.path.exists(logp):
            mtime = os.path.getmtime(logp)
            st["last_log_mtime"] = mtime
            stall = now - mtime
    except Exception:
        stall = None

    # decide timeout
    hit_total = (elapsed is not None and elapsed > TOTAL_TIMEOUT_SEC)
    hit_stall = (stall is not None and stall > STALL_TIMEOUT_SEC)

    if not (hit_total or hit_stall):
        return st

    why = "total_timeout" if hit_total else "stall_timeout"
    st["reasons"] = list(st.get("reasons") or [])
    st["reasons"].append(why)

    # kill process group
    pgid = st.get("pgid")
    try:
        if pgid:
            os.killpg(int(pgid), 15)  # SIGTERM
            time.sleep(1.0)
            os.killpg(int(pgid), 9)   # SIGKILL
    except Exception:
        pass

    st["final"] = True
    st["finished_at"] = nowz()
    st["status"] = "FAIL"
    st["exit_code"] = 124  # like timeout

    # try read severity/gate if report already exists
    if st.get("ci_run_dir"):
        sev = read_summary_severity(st["ci_run_dir"])
        st["severity"] = sev or {}
        gate, reasons = compute_gate_from_sev(sev or {})
        st["gate"] = gate
        # keep timeout reason too
        st["reasons"] = (list(dict.fromkeys((st.get("reasons") or []) + (reasons or []))))
        st["degraded"] = read_degraded_env(st["ci_run_dir"])

    # attempt sync even on timeout if report exists
    if st.get("ci_run_dir"):
        ok, vsp_run_id, msg = sync_to_vsp(st["ci_run_dir"])
        st["sync"] = {"done": True, "ok": bool(ok), "msg": msg[-1200:]}
        st["vsp_run_id"] = vsp_run_id or st.get("vsp_run_id","")
        ensure_extras_latest()

    return st


@bp.route("/api/vsp/run_status_v1/<req_id>", methods=["GET"])
def run_status_v1(req_id: str):
    st = read_state(req_id)
    if not st:
        return jsonify({"ok": False, "error": "not_found"}), 404

    # tail + stage/progress from tail
    t = tail_file(st.get("log_path",""), max_lines=TAIL_MAX_LINES)
    st["tail"] = t
    st["stage"] = parse_stage_progress(t)

    # if we already know run_dir, expose degraded + gate by current report
    if st.get("ci_run_dir"):
        st["degraded"] = read_degraded_env(st["ci_run_dir"]) or {"degraded":0,"reasons":""}

        sev = read_summary_severity(st["ci_run_dir"])
        if sev:
            st["severity"] = sev
            gate, reasons = compute_gate_from_sev(sev)
            # only override gate if still UNKNOWN
            if st.get("gate","UNKNOWN") in ("UNKNOWN",""):
                st["gate"] = gate
            # do not spam; keep unique
            existing = list(st.get("reasons") or [])
            merged = list(dict.fromkeys(existing + (reasons or [])))
            st["reasons"] = merged

    # enforce timeouts on poll
    st = maybe_timeout_and_finalize(st)

    # persist
    write_state(req_id, st)

    # slim response
    resp = {
        "ok": True,
        "req_id": st.get("req_id"),
        "status": st.get("status"),
        "final": bool(st.get("final")),
        "exit_code": st.get("exit_code"),
        "gate": st.get("gate","UNKNOWN"),
        "reasons": st.get("reasons") or [],
        "created_at": st.get("created_at"),
        "started_at": st.get("started_at"),
        "finished_at": st.get("finished_at"),
        "ci_run_dir": st.get("ci_run_dir",""),
        "vsp_run_id": st.get("vsp_run_id",""),
        "flag": st.get("flag") or {"has_findings": None},
        "severity": st.get("severity") or {},
        "degraded": st.get("degraded") or {"degraded":0,"reasons":""},
        "stage": st.get("stage") or {"tool":"","stage":"","progress":0},
        "sync": st.get("sync") or {"done": False, "ok": None},
        "tail": st.get("tail",""),
    }
    return jsonify(resp), 200


# quick marker to confirm registration in ui log
print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")
PY

python3 -m py_compile "$PYF" && echo "[OK] run_api syntax OK"

# restart UI
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
tail -n 3 out_ci/ui_8910.log || true

echo
echo "== SMOKE =="
curl -s -o /dev/null -w "HTTP_CODE=%{http_code}\n" http://localhost:8910/api/vsp/run_v1 || true
echo "[DONE]"

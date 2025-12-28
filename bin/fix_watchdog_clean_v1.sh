#!/usr/bin/env bash
set -euo pipefail

F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

# 1) Restore best known-good
LATEST="$(ls -1 "${F}.bak_watchdog_finalize_"* 2>/dev/null | sort | tail -n1 || true)"
if [ -z "${LATEST}" ]; then
  LATEST="$(ls -1 "${F}.bak_watchdog_"* 2>/dev/null | sort | tail -n1 || true)"
fi
[ -n "${LATEST}" ] && [ -f "${LATEST}" ] || { echo "[ERR] no good backup found (${F}.bak_watchdog_finalize_* or .bak_watchdog_*)."; exit 1; }

cp -f "${LATEST}" "$F"
echo "[RESTORE] $F <= $LATEST"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_fix_watchdog_clean_${TS}"
echo "[BACKUP] $F.bak_fix_watchdog_clean_${TS}"

mkdir -p out_ci/ui_req_state run_api

# 2) Ensure watchdog exists (if you already have it, we keep it)
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
    for r in roots:
        if not r.exists(): continue
        cand = []
        for d in r.glob("VSP_CI_*"):
            try:
                if int(d.stat().st_mtime) >= start_ts - 900:
                    cand.append((int(d.stat().st_mtime), str(d)))
            except Exception:
                pass
        if cand:
            cand.sort()
            return cand[-1][1]
    return ""

def _pick_log(ci_dir: str):
    if not ci_dir: return ""
    d = Path(ci_dir)
    for p in [d/"runner.log", d/"run.log", d/"vsp_ci.log", d/"SUMMARY.txt", d/"out.log", d/"ci.log"]:
        if p.exists(): return str(p)
    for p in [d/"kics"/"kics.log", d/"codeql"/"codeql.log"]:
        if p.exists(): return str(p)
    return ""

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
        if not st: time.sleep(args.tick); continue
        if st.get("final") is True: return

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
            st["runner_log"] = _pick_log(st["ci_run_dir"]) or ""

        if st.get("runner_log"):
            txt = _tail(Path(st["runner_log"]))
            i,t,name = _last_marker(txt)
            sig = f"{i}/{t}||{i if i>0 else 0}"
            st["stage_index"]=i; st["stage_total"]=t; st["stage_name"]=name; st["stage_sig"]=sig
            if t>0: st["progress_pct"]=int(((max(i,1)-1)/t)*100)
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

        st["status"]="RUNNING"; st["last_poll_ts"]=now
        _write_json(sp, st)
        time.sleep(args.tick)

if __name__ == "__main__":
    main()
PY
chmod +x run_api/vsp_watchdog_v1.py
fi

# 3) Patch vsp_run_api_v1.py safely (indent-aware)
python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")
lines = txt.splitlines(True)

def ensure_import(stmt: str):
    nonlocal_lines = None
    if any(stmt in ln for ln in lines):
        return
    last_imp = -1
    for i, ln in enumerate(lines):
        if re.match(r"^(import |from ).+\n?$", ln):
            last_imp = i
    ins = last_imp + 1
    lines.insert(ins, stmt + "\n")

for imp in ["import os", "import json", "import time", "import subprocess", "from pathlib import Path"]:
    ensure_import(imp)

HELP_MARK = "VSP_COMM_WD_HELPERS_CLEAN_V1"
if not any(HELP_MARK in ln for ln in lines):
    # insert after imports
    last_imp = -1
    for i, ln in enumerate(lines):
        if re.match(r"^(import |from ).+\n?$", ln):
            last_imp = i
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
    lines.insert(last_imp+1, helper if helper.endswith("\n") else helper + "\n")

def find_route(route_fragment: str):
    for i, ln in enumerate(lines):
        if ln.lstrip().startswith("@") and route_fragment in ln:
            for j in range(i+1, len(lines)):
                m = re.match(r"^(\s*)def\s+(\w+)\s*\(", lines[j])
                if m:
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

# Patch run_v1: init state + hook pid from first Popen + spawn watchdog
def_i, fn, ind = find_route("/api/vsp/run_v1")
if def_i is not None:
    a,b = func_range(def_i, ind)
    body = lines[a:b]
    MARK = "VSP_COMM_WD_RUN_CLEAN_V1"
    if not any(MARK in ln for ln in body):
        body_indent = ind + "    "
        # insert after request_id assignment if exists
        ip = 1
        for k in range(1, len(body)):
            if re.match(r"^\s*(request_id|req_id)\s*=\s*.+", body[k]):
                ip = k + 1
                break
        body[ip:ip] = [
            f"{body_indent}# === {MARK}: init state ===\n",
            f"{body_indent}_rid = locals().get('request_id', locals().get('req_id',''))\n",
            f"{body_indent}_stall = int(os.environ.get('VSP_STALL_TIMEOUT_SEC','600'))\n",
            f"{body_indent}_total = int(os.environ.get('VSP_TOTAL_TIMEOUT_SEC','7200'))\n",
            f"{body_indent}_state_path = VSP_UIREQ_STATE_DIR / (str(_rid) + '.json')\n",
            f"{body_indent}_vsp_atomic_write_json_v1(_state_path, {{'req_id': str(_rid), 'start_ts': int(time.time()), 'status': 'RUNNING', 'final': False, 'killed': False, 'kill_reason': '', 'stall_timeout_sec': _stall, 'total_timeout_sec': _total, 'progress_pct': 0, 'stage_index': 0, 'stage_total': 0, 'stage_name': '', 'stage_sig': '0/0||0', 'last_sig_change_ts': int(time.time()), 'target': str(locals().get('target', locals().get('target_path','')) or ''), 'profile': str(locals().get('profile','') or ''), 'ci_run_dir': '', 'runner_log': '', 'pid': 0}})\n",
            f"{body_indent}# === END {MARK}: init state ===\n",
        ]
        # hook first "X = subprocess.Popen("
        popen_var = None
        popen_line = None
        for k in range(len(body)):
            m = re.match(r"^\s*(\w+)\s*=\s*subprocess\.Popen\s*\(", body[k])
            if m:
                popen_var = m.group(1)
                popen_line = k
                break
        if popen_var is not None:
            # after popen call ends (find closing paren depth)
            depth = 0
            end_k = None
            for k in range(popen_line, len(body)):
                for ch in body[k]:
                    if ch == "(":
                        depth += 1
                    elif ch == ")":
                        depth -= 1
                if depth == 0 and k > popen_line:
                    end_k = k
                    break
            if end_k is None:
                end_k = popen_line
            body[end_k+1:end_k+1] = [
                f"{body_indent}# === {MARK}: capture pid + spawn watchdog ===\n",
                f"{body_indent}try:\n",
                f"{body_indent}    _st = json.loads(_state_path.read_text(encoding='utf-8', errors='ignore')) if _state_path.exists() else {{}}\n",
                f"{body_indent}    _st['pid'] = int(getattr({popen_var}, 'pid', 0) or 0)\n",
                f"{body_indent}    _vsp_atomic_write_json_v1(_state_path, _st)\n",
                f"{body_indent}    _vsp_spawn_watchdog_v1(_state_path)\n",
                f"{body_indent}except Exception:\n",
                f"{body_indent}    pass\n",
                f"{body_indent}# === END {MARK}: capture ===\n",
            ]
        else:
            # no popen found: still spawn watchdog before return jsonify
            for k in range(len(body)):
                if re.match(r"^\s*return\s+jsonify\(", body[k]):
                    body[k:k] = [
                        f"{body_indent}# === {MARK}: spawn watchdog (no popen) ===\n",
                        f"{body_indent}try:\n",
                        f"{body_indent}    _vsp_spawn_watchdog_v1(_state_path)\n",
                        f"{body_indent}except Exception:\n",
                        f"{body_indent}    pass\n",
                        f"{body_indent}# === END {MARK}: spawn ===\n",
                    ]
                    break
        lines[a:b] = body
        print("[OK] patched run_v1:", fn)
else:
    print("[WARN] cannot find route /api/vsp/run_v1")

# Patch run_status_v1: read state file first
def_i, fn, ind = find_route("/api/vsp/run_status_v1")
if def_i is not None:
    a,b = func_range(def_i, ind)
    body = lines[a:b]
    MARK = "VSP_COMM_WD_STATUS_CLEAN_V1"
    if not any(MARK in ln for ln in body):
        body_indent = ind + "    "
        body[1:1] = [
            f"{body_indent}# === {MARK} ===\n",
            f"{body_indent}try:\n",
            f"{body_indent}    if str(req_id).startswith('VSP_UIREQ_'):\n",
            f"{body_indent}        _p = VSP_UIREQ_STATE_DIR / (str(req_id) + '.json')\n",
            f"{body_indent}        if _p.exists():\n",
            f"{body_indent}            _st = json.loads(_p.read_text(encoding='utf-8', errors='ignore'))\n",
            f"{body_indent}            return jsonify({{\n",
            f"{body_indent}                'status': _st.get('status','RUNNING'),\n",
            f"{body_indent}                'final': bool(_st.get('final', False)),\n",
            f"{body_indent}                'progress_pct': int(_st.get('progress_pct', 0)),\n",
            f"{body_indent}                'stage_sig': _st.get('stage_sig','0/0||0') or '0/0||0',\n",
            f"{body_indent}                'runner_log': _st.get('runner_log','') or None,\n",
            f"{body_indent}                'ci_run_dir': _st.get('ci_run_dir','') or None,\n",
            f"{body_indent}                'killed': _st.get('killed', None),\n",
            f"{body_indent}                'kill_reason': _st.get('kill_reason', None),\n",
            f"{body_indent}            }})\n",
            f"{body_indent}except Exception:\n",
            f"{body_indent}    pass\n",
            f"{body_indent}# === END {MARK} ===\n",
        ]
        lines[a:b] = body
        print("[OK] patched run_status_v1:", fn)
else:
    print("[WARN] cannot find route /api/vsp/run_status_v1")

p.write_text("".join(lines), encoding="utf-8")
print("[DONE] wrote", p)
PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] py_compile OK"
echo "[OK] state dir: out_ci/ui_req_state"
echo "[NEXT] restart 8910"

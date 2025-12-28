#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."

TS="$(date +%Y%m%d_%H%M%S)"
echo "[ROOT] $(pwd)"
echo "[TS]   $TS"

backup() { [ -f "$1" ] && cp "$1" "$1.bak_fixrunv1_${TS}" && echo "[BACKUP] $1.bak_fixrunv1_${TS}"; }

# --- 0) Ensure run_api exists (and force routes = *_v1) ---
mkdir -p run_api
touch run_api/__init__.py

PYF="run_api/vsp_run_api_v1.py"
if [ ! -f "$PYF" ]; then
  echo "[WARN] missing $PYF → create minimal v1 blueprint now"
  cat > "$PYF" << 'PY'
#!/usr/bin/env python3
import json, os, re, subprocess, uuid
from datetime import datetime, timezone
from pathlib import Path
from flask import Blueprint, jsonify, request

bp_vsp_run_api_v1 = Blueprint("vsp_run_api_v1", __name__)
UI_ROOT = Path(__file__).resolve().parents[1]
BUNDLE_ROOT = Path(os.environ.get("VSP_BUNDLE_ROOT", str(UI_ROOT.parent)))
UI_OUT = UI_ROOT / "out_ci" / "req"
UI_OUT.mkdir(parents=True, exist_ok=True)

def _utc():
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat().replace("+00:00","Z")

def _write(p: Path, obj):
    p.parent.mkdir(parents=True, exist_ok=True)
    p.write_text(json.dumps(obj, ensure_ascii=False, indent=2), encoding="utf-8")

def _read(p: Path):
    try:
        return json.loads(p.read_text(encoding="utf-8", errors="replace")) if p.exists() else None
    except Exception:
        return None

def _tail(p: Path, n=9000):
    if not p.exists(): return ""
    b = p.read_bytes()
    return b[-n:].decode("utf-8", errors="replace")

def _parse_ci_run_dir(tail: str) -> str:
    pats = [
        r'Latest\s+RUN_DIR\s*=\s*(/[^ \n]+/out_ci/VSP_CI_[0-9_]+)',
        r'RUN_DIR\s*=\s*(/[^ \n]+/out_ci/VSP_CI_[0-9_]+)',
        r'CI_RUN_DIR\s*=\s*(/[^ \n]+/out_ci/VSP_CI_[0-9_]+)',
    ]
    for pat in pats:
        m = re.search(pat, tail)
        if m: return m.group(1)
    return ""

def _sync(ci_run_dir: str):
    sync = BUNDLE_ROOT / "bin" / "vsp_ci_sync_to_vsp_v1.sh"
    if not sync.exists():
        return {"done": True, "ok": False, "error": f"sync not found: {sync}"}
    cp = subprocess.run(["bash", str(sync), ci_run_dir], capture_output=True, text=True)
    run_id = ""
    m = re.search(r'VSP_RUN_DIR\s*=\s*(\S+)', (cp.stdout or "") + "\n" + (cp.stderr or ""))
    if m: run_id = Path(m.group(1)).name
    return {"done": True, "ok": (cp.returncode == 0), "rc": cp.returncode, "vsp_run_id": run_id,
            "stdout": (cp.stdout or "")[-1500:], "stderr": (cp.stderr or "")[-1500:]}

@bp_vsp_run_api_v1.route("/api/vsp/run_v1", methods=["POST"])
def run_v1():
    body = request.get_json(silent=True) or {}
    target = (body.get("target") or os.environ.get("VSP_DEFAULT_TARGET") or "/home/test/Data/SECURITY-10-10-v4").strip()
    profile = (body.get("profile") or "FULL_EXT").strip()

    outer_root = os.environ.get("VSP_OUTER_ROOT", "/home/test/Data/SECURITY-10-10-v4/ci/VSP_CI_OUTER")
    outer_script = os.environ.get("VSP_OUTER_SCRIPT", str(Path(outer_root) / "vsp_ci_outer_full_v1.sh"))

    req_id = f"UIREQ_{datetime.now().strftime('%Y%m%d_%H%M%S')}_{uuid.uuid4().hex[:6]}"
    req_dir = UI_OUT / req_id
    req_dir.mkdir(parents=True, exist_ok=True)
    logp = req_dir / "outer.log"
    stp  = req_dir / "status.json"
    _write(stp, {"ok": True, "req_id": req_id, "status": "RUNNING", "final": False, "gate": "UNKNOWN",
                 "created_at": _utc(), "started_at": _utc(), "finished_at": None,
                 "exit_code": None, "ci_run_dir": "", "vsp_run_id": "", "sync": {"done": False}})

    env = os.environ.copy()
    env["SRC"] = target
    env["PROFILE"] = profile

    with logp.open("w", encoding="utf-8", errors="replace") as lf:
        subprocess.Popen(["bash", str(outer_script)], cwd=str(Path(outer_root)), env=env, stdout=lf, stderr=subprocess.STDOUT)

    return jsonify({"ok": True, "req_id": req_id, "profile": profile, "target": target, "implemented": True})

@bp_vsp_run_api_v1.route("/api/vsp/run_status_v1/<req_id>", methods=["GET"])
def run_status_v1(req_id: str):
    req_dir = UI_OUT / req_id
    stp = req_dir / "status.json"
    logp = req_dir / "outer.log"
    st = _read(stp) or {"ok": False, "req_id": req_id, "status": "UNKNOWN", "final": True}
    tail = _tail(logp)

    if st.get("final"):
        st["tail"] = tail
        return jsonify(st)

    # finalize if log indicates end (best-effort)
    ci_run_dir = _parse_ci_run_dir(tail)
    if ci_run_dir:
        st["ci_run_dir"] = ci_run_dir
        st["sync"] = _sync(ci_run_dir)
        st["vsp_run_id"] = st["sync"].get("vsp_run_id","")
        st["status"] = "DONE"
        st["final"] = True
        st["finished_at"] = _utc()
        _write(stp, st)

    st["tail"] = tail
    return jsonify(st)
PY
fi

# Force routes in existing file too (avoid mismatch)
backup "$PYF"
python3 - << 'PY'
from pathlib import Path
import re
p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")
# Make sure it exposes *_v1 routes (no /api/vsp/run)
txt = txt.replace('"/api/vsp/run_status/<req_id>"','"/api/vsp/run_status_v1/<req_id>"')
txt = txt.replace("'/api/vsp/run_status/<req_id>'","'/api/vsp/run_status_v1/<req_id>'")
txt = txt.replace('"/api/vsp/run"','"/api/vsp/run_v1"')
txt = txt.replace("'/api/vsp/run'","'/api/vsp/run_v1'")
p.write_text(txt, encoding="utf-8")
print("[OK] ensured routes are *_v1 in run_api/vsp_run_api_v1.py")
PY
python3 -m py_compile "$PYF"
echo "[OK] run_api blueprint syntax OK"

# --- 1) Patch vsp_demo_app.py to ALWAYS register blueprint (append-safe) ---
APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] not found: $APP"; exit 1; }
backup "$APP"

python3 - << 'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="replace").replace("\r\n","\n").replace("\r","\n")

# Remove previous broken blocks if any (avoid duplicates)
txt = re.sub(r'(?s)\n# === VSP_RUN_API_BLUEPRINT_V1 ===.*?# === END VSP_RUN_API_BLUEPRINT_V1 ===\n', "\n", txt)

# Append a guaranteed register block near end (after app is defined)
inject = r'''

# === VSP_RUN_API_BLUEPRINT_V1 ===
try:
    from run_api.vsp_run_api_v1 import bp_vsp_run_api_v1
    app.register_blueprint(bp_vsp_run_api_v1)
    print("[VSP_RUN_API] OK registered: /api/vsp/run_v1 + /api/vsp/run_status_v1/<REQ_ID>")
except Exception as e:
    print("[VSP_RUN_API] ERR register blueprint:", repr(e))
# === END VSP_RUN_API_BLUEPRINT_V1 ===
'''
txt += inject
p.write_text(txt, encoding="utf-8")
print("[OK] appended blueprint register block to vsp_demo_app.py")
PY

python3 -m py_compile "$APP"
echo "[OK] vsp_demo_app.py syntax OK"

# --- 2) Restart UI ---
pkill -f vsp_demo_app.py || true
mkdir -p out_ci
nohup python3 vsp_demo_app.py > out_ci/ui_8910.log 2>&1 &
sleep 1
echo "[OK] restarted UI"
tail -n 30 out_ci/ui_8910.log || true

# --- 3) Verify route existence (should NOT be 404) ---
echo
echo "== CHECK: /api/vsp/run_v1 should be 405 (method) or 400, NOT 404 =="
curl -s -o /dev/null -w "HTTP_CODE=%{http_code}\n" http://localhost:8910/api/vsp/run_v1 || true

echo
echo "== CHECK: blueprint print line should appear in log =="
grep -n "VSP_RUN_API" -n out_ci/ui_8910.log | tail -n 5 || true

echo
echo "[DONE] Now test with POST:"
echo 'REQ_ID="$(curl -s -X POST http://localhost:8910/api/vsp/run_v1 -H "Content-Type: application/json" -d "{\"mode\":\"local\",\"profile\":\"FULL_EXT\",\"target_type\":\"path\",\"target\":\"/home/test/Data/SECURITY-10-10-v4\"}" | jq -r .req_id)"; echo "REQ_ID=$REQ_ID"'

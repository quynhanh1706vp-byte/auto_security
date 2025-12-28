#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
RUNAPI="$ROOT/run_api/vsp_run_api_v1.py"
LOG="$ROOT/out_ci/ui_8910.log"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
[ -f "$RUNAPI" ] || { echo "[ERR] missing $RUNAPI"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK_APP="$APP.bak_fixv2_${TS}"
BAK_RUNAPI="$RUNAPI.bak_fixv2_${TS}"
cp -f "$APP" "$BAK_APP"
cp -f "$RUNAPI" "$BAK_RUNAPI"
echo "[BACKUP] $BAK_APP"
echo "[BACKUP] $BAK_RUNAPI"

restore_all () {
  echo "[RESTORE] restoring backups..."
  cp -f "$BAK_APP" "$APP"
  cp -f "$BAK_RUNAPI" "$RUNAPI"
  echo "[RESTORE] done"
}

compile_or_restore () {
  local f="$1"
  local out=""
  if ! out="$(python3 -m py_compile "$f" 2>&1)"; then
    echo "----- PY_COMPILE_ERROR ($f) -----"
    echo "$out"
    echo "---------------------------------"
    cp -f "$f" "$f.bad_compile_${TS}" || true
    echo "[KEPT] $f.bad_compile_${TS}"
    restore_all
    exit 2
  fi
}

echo
echo "== [1/2] Patch RUNAPI: ensure exported bp_vsp_run_api_v1 exists + alias matches decorators =="

python3 - "$RUNAPI" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")
lines = txt.splitlines(True)

# Detect first decorator like @XYZ.route or @XYZ.get/post/route
dec_name = None
dec_line = None
for i, ln in enumerate(lines):
    m = re.match(r"^\s*@(\w+)\.(route|get|post|put|delete|patch)\b", ln)
    if m:
        dec_name = m.group(1)
        dec_line = i
        break

# Ensure import Blueprint (best-effort)
has_blueprint_import = any(("Blueprint" in ln and ("from flask import" in ln or ln.startswith("import "))) for ln in lines[:250])
if not has_blueprint_import:
    ins = 0
    for i, ln in enumerate(lines[:300]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins = i + 1
    lines.insert(ins, "from flask import Blueprint  # VSP_BP_IMPORT_FIX_V2\n")

txt = "".join(lines)
lines = txt.splitlines(True)

# Ensure bp_vsp_run_api_v1 exists (export name expected by loader)
bp_def_rx = re.compile(r"^\s*bp_vsp_run_api_v1\s*=\s*Blueprint\s*\(", re.M)
if not bp_def_rx.search(txt):
    ins = 0
    for i, ln in enumerate(lines[:350]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins = i + 1
    lines.insert(ins, "bp_vsp_run_api_v1 = Blueprint('vsp_run_api_v1', __name__)  # VSP_BP_DEFINE_FIX_V2\n")
    txt = "".join(lines)
    lines = txt.splitlines(True)
    print("[OK] inserted bp_vsp_run_api_v1 = Blueprint(...)")

# Ensure alias bp = bp_vsp_run_api_v1 (compat)
if not re.search(r"^\s*bp\s*=\s*bp_vsp_run_api_v1\b", txt, flags=re.M):
    # insert right after bp_vsp_run_api_v1 definition line
    for i, ln in enumerate(lines):
        if re.match(r"^\s*bp_vsp_run_api_v1\s*=\s*Blueprint\s*\(", ln):
            lines.insert(i+1, "bp = bp_vsp_run_api_v1  # VSP_BP_ALIAS_FIX_V2\n")
            print("[OK] inserted alias: bp = bp_vsp_run_api_v1")
            break
    txt = "".join(lines)
    lines = txt.splitlines(True)

# If decorators use some other name, alias that name to bp_vsp_run_api_v1 too
if dec_name and dec_name not in ("bp_vsp_run_api_v1",):
    alias_rx = re.compile(rf"^\s*{re.escape(dec_name)}\s*=\s*bp_vsp_run_api_v1\b", re.M)
    if not alias_rx.search(txt):
        # insert right after bp_vsp_run_api_v1 definition (or bp alias)
        insert_at = None
        for i, ln in enumerate(lines):
            if "bp_vsp_run_api_v1 = Blueprint" in ln:
                insert_at = i + 1
        if insert_at is None:
            insert_at = 0
        lines.insert(insert_at, f"{dec_name} = bp_vsp_run_api_v1  # VSP_BP_DECORATOR_ALIAS_FIX_V2\n")
        print(f"[OK] inserted decorator alias: {dec_name} = bp_vsp_run_api_v1")
        txt = "".join(lines)
        lines = txt.splitlines(True)

p.write_text("".join(lines), encoding="utf-8")
print(f"[DONE] RUNAPI patched. decorator_name={dec_name} decorator_line={dec_line}")
PY

compile_or_restore "$RUNAPI"
echo "[OK] RUNAPI compile OK"

echo
echo "== [2/2] Patch APP: replace/insert JSON errorhandlers block safely (no regex braces) =="

python3 - "$APP" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# Find app var
m = re.search(r"^\s*(\w+)\s*=\s*Flask\s*\(", txt, flags=re.M)
appvar = m.group(1) if m else "app"

new_block = f'''
# === VSP_JSON_ERRHANDLERS_V4 ===
# Contract: any /api/vsp/* error must still be JSON so jq never dies.
def _vsp_env_int(name, default):
    try:
        import os
        v = os.getenv(name, "")
        if str(v).strip() == "":
            return int(default)
        return int(float(v))
    except Exception:
        return int(default)

def _vsp_api_json_err(code, msg):
    from flask import jsonify
    stall = _vsp_env_int("VSP_UIREQ_STALL_TIMEOUT_SEC", _vsp_env_int("VSP_STALL_TIMEOUT_SEC", 600))
    total = _vsp_env_int("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _vsp_env_int("VSP_TOTAL_TIMEOUT_SEC", 7200))
    if stall < 1: stall = 1
    if total < 1: total = 1
    payload = {{
        "ok": False,
        "status": "ERROR",
        "final": True,
        "error": msg,
        "http_code": code,
        "stall_timeout_sec": stall,
        "total_timeout_sec": total,
        "progress_pct": 0,
        "stage_index": 0,
        "stage_total": 0,
        "stage_name": "",
        "stage_sig": "",
    }}
    return jsonify(payload), 200

def _vsp_err_404(e):
    try:
        from flask import request
        if request.path.startswith("/api/vsp/"):
            return _vsp_api_json_err(404, "HTTP_404_NOT_FOUND")
    except Exception:
        pass
    return ("Not Found", 404)

def _vsp_err_500(e):
    try:
        from flask import request
        if request.path.startswith("/api/vsp/"):
            return _vsp_api_json_err(500, "HTTP_500_INTERNAL")
    except Exception:
        pass
    return ("Internal Server Error", 500)

{appvar}.register_error_handler(404, _vsp_err_404)
{appvar}.register_error_handler(500, _vsp_err_500)
# === END VSP_JSON_ERRHANDLERS_V4 ===
'''

start = txt.find("# === VSP_JSON_ERRHANDLERS_V4 ===")
end = txt.find("# === END VSP_JSON_ERRHANDLERS_V4 ===")

if start != -1 and end != -1 and end > start:
    end = end + len("# === END VSP_JSON_ERRHANDLERS_V4 ===")
    txt2 = txt[:start] + new_block + txt[end:]  # replace whole block
    p.write_text(txt2, encoding="utf-8")
    print("[OK] replaced existing VSP_JSON_ERRHANDLERS_V4 block")
else:
    # insert before __main__ if possible
    mm = re.search(r"^\s*if\s+__name__\s*==\s*['\"]__main__['\"]\s*:\s*$", txt, flags=re.M)
    if mm:
        txt2 = txt[:mm.start()] + new_block + "\n" + txt[mm.start():]
    else:
        txt2 = txt + "\n" + new_block + "\n"
    p.write_text(txt2, encoding="utf-8")
    print("[OK] inserted new VSP_JSON_ERRHANDLERS_V4 block")
PY

compile_or_restore "$APP"
echo "[OK] APP compile OK"

echo
echo "== Restart 8910 =="
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > "$LOG" 2>&1 &
sleep 1

echo "== Smoke (python pretty, no jq) =="
python3 - <<'PY'
import json, urllib.request
def get(url):
    return json.loads(urllib.request.urlopen(url, timeout=5).read().decode("utf-8","ignore"))
base="http://localhost:8910"
obj = get(base + "/api/vsp/run_status_v1/FAKE_REQ_ID")
keys = ["ok","status","final","error","http_code","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print(json.dumps({k: obj.get(k) for k in keys}, indent=2, ensure_ascii=False))
PY

echo
echo "== Log: must NOT contain bp undefined =="
tail -n 80 "$LOG" | sed -n '1,80p'
echo "[DONE]"

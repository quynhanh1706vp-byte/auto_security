#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
RUNAPI="$ROOT/run_api/vsp_run_api_v1.py"
LOG="$ROOT/out_ci/ui_8910.log"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
[ -f "$RUNAPI" ] || { echo "[ERR] missing $RUNAPI"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK_APP="$APP.bak_fixbp_${TS}"
BAK_RUNAPI="$RUNAPI.bak_fixbp_${TS}"
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
echo "== [1/2] Fix RUNAPI: ensure bp Blueprint exists before any @bp.* decorators =="

python3 - "$RUNAPI" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")
lines = txt.splitlines(True)

# Find first decorator "@bp."
first_dec = None
for i, ln in enumerate(lines):
    if re.match(r"^\s*@bp\.", ln):
        first_dec = i
        break

if first_dec is None:
    print("[INFO] No '@bp.' decorator found. Skipping bp-order fix.")
    p.write_text("".join(lines), encoding="utf-8")
    raise SystemExit(0)

# Find any Blueprint assignment like "<var> = Blueprint("
bp_assign = None
assign_var = None
for i, ln in enumerate(lines):
    m = re.match(r"^\s*(\w+)\s*=\s*Blueprint\s*\(", ln)
    if m:
        bp_assign = i
        assign_var = m.group(1)
        break

# Ensure we import Blueprint (best-effort) if we will insert a Blueprint definition
has_blueprint_import = any(("Blueprint" in ln and ("from flask import" in ln or "import" in ln)) for ln in lines[:250])

# Case A: Found Blueprint assignment but it's AFTER decorators => move it before decorators
if bp_assign is not None and bp_assign > first_dec:
    bp_line = lines[bp_assign]
    del lines[bp_assign]
    lines.insert(first_dec, bp_line)
    print(f"[OK] moved Blueprint assignment up: line {bp_assign+1} -> before decorator line {first_dec+1}")

# Recompute: is there "bp = Blueprint(" before first_dec now?
def find_bp_before(idx):
    for j in range(0, idx):
        if re.match(r"^\s*bp\s*=\s*Blueprint\s*\(", lines[j]):
            return j
    return None

bp_ok = find_bp_before(first_dec)
if bp_ok is None:
    # If there is some "<var> = Blueprint(" before decorator, alias bp = <var>
    found_any = None
    found_var = None
    for j in range(0, first_dec):
        m = re.match(r"^\s*(\w+)\s*=\s*Blueprint\s*\(", lines[j])
        if m:
            found_any = j
            found_var = m.group(1)
            break

    if found_any is not None and found_var != "bp":
        # Insert alias line right after blueprint assignment
        alias = f"bp = {found_var}  # VSP_BP_ALIAS_FIX_V1\n"
        # avoid duplicate alias
        if not any(re.match(rf"^\s*bp\s*=\s*{re.escape(found_var)}\b", x) for x in lines[:first_dec+5]):
            lines.insert(found_any + 1, alias)
            print(f"[OK] inserted alias: bp = {found_var}")
    elif found_any is None:
        # No blueprint assignment before decorators -> insert a correct one
        # Insert after imports block near top
        ins = 0
        for j, ln in enumerate(lines[:300]):
            if ln.startswith("import ") or ln.startswith("from "):
                ins = j + 1
        if not has_blueprint_import:
            lines.insert(ins, "from flask import Blueprint  # VSP_BP_IMPORT_FIX_V1\n")
            ins += 1
        lines.insert(ins, "bp = Blueprint('vsp_run_api_v1', __name__)  # VSP_BP_DEFINE_FIX_V1\n")
        print("[OK] inserted bp Blueprint() definition before decorators")
    else:
        print("[INFO] Blueprint assignment already uses 'bp' but was not before decorators? (unexpected)")

p.write_text("".join(lines), encoding="utf-8")
print("[DONE] RUNAPI bp fix applied")
PY

compile_or_restore "$RUNAPI"
echo "[OK] RUNAPI compile OK"

echo
echo "== [2/2] Improve APP error JSON: include contract fields (timeouts/progress) =="

python3 - "$APP" << 'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

# Only patch if marker exists (from V4); otherwise do nothing (keep safe)
if "VSP_JSON_ERRHANDLERS_V4" not in txt:
    print("[INFO] VSP_JSON_ERRHANDLERS_V4 not present, skip.")
    raise SystemExit(0)

# Replace _vsp_api_json_err function inside the V4 block
pat = re.compile(r"(# === VSP_JSON_ERRHANDLERS_V4 ===[\s\S]*?)def _vsp_api_json_err\([\s\S]*?\n\{0,1}def _vsp_err_404".format(""), re.M)

m = pat.search(txt)
if not m:
    print("[WARN] Cannot locate _vsp_api_json_err to replace, skip.")
    raise SystemExit(0)

prefix = m.group(1)
# rebuild a safer helper (no type annotations to avoid any parser edge)
new_helper = r"""
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
    payload = {
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
    }
    return jsonify(payload), 200

def _vsp_err_404(e):
"""

# Now stitch: replace from marker start up to "def _vsp_err_404" header
txt2 = txt[:m.start()] + new_helper + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] updated APP error JSON helper with contract fields")
PY

compile_or_restore "$APP"
echo "[OK] APP compile OK"

echo
echo "== Restart 8910 =="
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > "$LOG" 2>&1 &
sleep 1

echo "== Smoke (python pretty, no jq noise) =="
python3 - <<'PY'
import json, urllib.request
def get(url):
    return json.loads(urllib.request.urlopen(url, timeout=5).read().decode("utf-8","ignore"))
base="http://localhost:8910"
# 1) run_status fake should be NOT_FOUND (endpoint must exist now, not 404)
obj = get(base + "/api/vsp/run_status_v1/FAKE_REQ_ID")
keys = ["ok","status","final","error","http_code","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print(json.dumps({k: obj.get(k) for k in keys}, indent=2, ensure_ascii=False))
PY

echo
echo "== Quick endpoint existence checks =="
curl -sS -o /dev/null -w "GET /api/vsp/runs_index_v3_fs => HTTP=%{http_code}\n" "http://localhost:8910/api/vsp/runs_index_v3_fs?limit=1&hide_empty=0" || true
curl -sS -o /dev/null -w "POST /api/vsp/run_v1 => HTTP=%{http_code}\n" -X POST "http://localhost:8910/api/vsp/run_v1" || true

echo
echo "== Last 60 log lines =="
tail -n 60 "$LOG" || true
echo "[DONE]"

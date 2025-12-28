#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
RUNAPI="$ROOT/run_api/vsp_run_api_v1.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
[ -f "$RUNAPI" ] || { echo "[ERR] missing $RUNAPI"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK_APP="$APP.bak_contract_v3_${TS}"
BAK_RUNAPI="$RUNAPI.bak_contract_v3_${TS}"
cp -f "$APP" "$BAK_APP"
cp -f "$RUNAPI" "$BAK_RUNAPI"
echo "[BACKUP] $BAK_APP"
echo "[BACKUP] $BAK_RUNAPI"

fail_restore () {
  local why="$1"
  echo "[ERR] $why"
  echo "[RESTORE] restoring backups..."
  cp -f "$BAK_APP" "$APP"
  cp -f "$BAK_RUNAPI" "$RUNAPI"
  echo "[RESTORE] done"
  exit 2
}

compile_one () {
  local f="$1"
  local out=""
  if ! out="$(python3 -m py_compile "$f" 2>&1)"; then
    echo "----- PY_COMPILE_ERROR ($f) -----"
    echo "$out"
    echo "---------------------------------"
    return 1
  fi
  return 0
}

echo
echo "== [1/2] Patch RUNAPI: ensure run_status_v1 always returns contract fields =="

python3 - "$RUNAPI" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_CONTRACT_FIELDS_V3" not in txt:
    block = r'''
# === VSP_CONTRACT_FIELDS_V3 ===
def _vsp_env_int(name, default):
    try:
        import os
        v = os.getenv(name, "")
        if str(v).strip() == "":
            return int(default)
        return int(float(v))
    except Exception:
        return int(default)

def _vsp_clamp_int(v, lo, hi, default):
    try:
        x = int(float(v))
        if x < lo: return lo
        if x > hi: return hi
        return x
    except Exception:
        return default

def _vsp_contract_normalize_status(payload):
    if not isinstance(payload, dict):
        payload = {"ok": False, "status": "ERROR", "final": True, "error": "INVALID_STATUS_PAYLOAD"}

    stall = _vsp_env_int("VSP_UIREQ_STALL_TIMEOUT_SEC", _vsp_env_int("VSP_STALL_TIMEOUT_SEC", 600))
    total = _vsp_env_int("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _vsp_env_int("VSP_TOTAL_TIMEOUT_SEC", 7200))
    if stall < 1: stall = 1
    if total < 1: total = 1

    payload.setdefault("ok", bool(payload.get("ok", False)))
    payload.setdefault("status", payload.get("status") or "UNKNOWN")
    payload.setdefault("final", bool(payload.get("final", False)))
    payload.setdefault("error", payload.get("error") or "")
    payload.setdefault("req_id", payload.get("req_id") or "")

    payload["stall_timeout_sec"] = int(payload.get("stall_timeout_sec") or stall)
    payload["total_timeout_sec"] = int(payload.get("total_timeout_sec") or total)

    payload.setdefault("killed", bool(payload.get("killed", False)))
    payload.setdefault("kill_reason", payload.get("kill_reason") or "")

    payload["progress_pct"] = _vsp_clamp_int(payload.get("progress_pct", 0), 0, 100, 0)
    payload["stage_index"] = _vsp_clamp_int(payload.get("stage_index", 0), 0, 9999, 0)
    payload["stage_total"] = _vsp_clamp_int(payload.get("stage_total", 0), 0, 9999, 0)
    payload.setdefault("stage_name", payload.get("stage_name") or payload.get("stage") or "")

    sig = payload.get("stage_sig") or ""
    if not isinstance(sig, str) or sig.strip() == "":
        sig = f"{payload.get('stage_index','')}/{payload.get('stage_total','')}|{payload.get('stage_name','')}|{payload.get('progress_pct','')}"
    payload["stage_sig"] = sig
    payload.setdefault("updated_at", int(__import__("time").time()))
    return payload
# === END VSP_CONTRACT_FIELDS_V3 ===
'''
    lines = txt.splitlines(True)
    ins = 0
    for i, ln in enumerate(lines[:300]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins = i + 1
    lines.insert(ins, block + "\n")
    txt = "".join(lines)

# Patch ALL "return jsonify(...)" inside run_status_v1 to wrap normalize
def_rx = re.compile(r"^def\s+run_status_v1\s*\(.*\)\s*:\s*$", re.M)
m = def_rx.search(txt)
if not m:
    print("[WARN] run_status_v1 not found; no wrapping applied.")
    p.write_text(txt, encoding="utf-8")
    raise SystemExit(0)

start = m.start()
after = txt[m.end():]
next_m = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
end = m.end() + (next_m.start() if next_m else len(after))
block = txt[start:end]
rest = txt[end:]

blk = block.splitlines(True)
changed = 0

def wrap(line: str) -> str:
    # keep any ", 200" etc not used; this file usually uses jsonify(payload)
    return re.sub(r"(\s*)return\s+jsonify\((.*)\)\s*$",
                  r"\1return jsonify(_vsp_contract_normalize_status(\2))\n", line)

for i, ln in enumerate(blk):
    if "return jsonify(" in ln and "_vsp_contract_normalize_status" not in ln:
        ln2 = wrap(ln)
        if ln2 != ln:
            blk[i] = ln2
            changed += 1

txt2 = "".join(blk) + rest
p.write_text(txt2, encoding="utf-8")
print(f"[OK] wrapped return jsonify in run_status_v1: {changed} line(s)")
PY

if ! compile_one "$RUNAPI"; then
  cp -f "$RUNAPI" "$RUNAPI.bad_compile_${TS}"
  fail_restore "RUNAPI compile failed. kept: $RUNAPI.bad_compile_${TS}"
fi
echo "[OK] RUNAPI compile OK"

echo
echo "== [2/2] Patch APP: ensure /api/vsp/* 404/500 always JSON (jq-safe) =="

python3 - "$APP" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")
if "VSP_JSON_ERRHANDLERS_V3" in txt:
    print("[SKIP] already has VSP_JSON_ERRHANDLERS_V3")
    raise SystemExit(0)

# Find Flask app var name: <name> = Flask(...)
m = re.search(r"^\s*(\w+)\s*=\s*Flask\s*\(", txt, flags=re.M)
if not m:
    print("[WARN] Cannot find '<var> = Flask(...)' in vsp_demo_app.py, skip errorhandlers patch.")
    raise SystemExit(0)

appvar = m.group(1)

patch = f'''
# === VSP_JSON_ERRHANDLERS_V3 ===
# Contract: any /api/vsp/* error must still be JSON so jq never dies.
def _vsp_api_json_err(code: int, msg: str):
    from flask import jsonify
    return jsonify({{"ok": False, "status": "ERROR", "final": True, "error": msg, "http_code": code}}), 200

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
# === END VSP_JSON_ERRHANDLERS_V3 ===
'''

# Insert right after the line "<appvar> = Flask(..."
lines = txt.splitlines(True)
idx = None
for i, ln in enumerate(lines):
    if re.search(rf"^\s*{re.escape(appvar)}\s*=\s*Flask\s*\(", ln):
        idx = i + 1
        break
if idx is None:
    lines.append("\n" + patch + "\n")
else:
    lines.insert(idx, patch + "\n")

p.write_text("".join(lines), encoding="utf-8")
print(f"[OK] inserted JSON errorhandlers V3 for app var '{appvar}'")
PY

if ! compile_one "$APP"; then
  cp -f "$APP" "$APP.bad_compile_${TS}"
  fail_restore "APP compile failed. kept: $APP.bad_compile_${TS}"
fi
echo "[OK] APP compile OK"

echo
echo "[DONE] Commercial contract v3 applied."
echo "Next: restart + smoke."

#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="$ROOT/vsp_demo_app.py"
RUNAPI="$ROOT/run_api/vsp_run_api_v1.py"

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 1; }
[ -f "$RUNAPI" ] || { echo "[ERR] missing $RUNAPI"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
BAK_APP="$APP.bak_commercial_v2_${TS}"
BAK_RUNAPI="$RUNAPI.bak_commercial_v2_${TS}"
cp -f "$APP" "$BAK_APP"
cp -f "$RUNAPI" "$BAK_RUNAPI"
echo "[BACKUP] $BAK_APP"
echo "[BACKUP] $BAK_RUNAPI"

# --- Patch RUNAPI: normalize_run_status_payload + wrap jsonify ---
python3 - "$RUNAPI" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_COMMERCIAL_CONTRACT_V2" not in txt:
    # inject helper near top (after imports)
    helper = r'''
# === VSP_COMMERCIAL_CONTRACT_V2 ===
import os, time as _time

def _env_int(_name, _default):
    try:
        v = os.getenv(_name, "")
        if str(v).strip()=="":
            return int(_default)
        return int(float(v))
    except Exception:
        return int(_default)

def _clamp_int(v, lo, hi, default):
    try:
        x = int(float(v))
        if x < lo: return lo
        if x > hi: return hi
        return x
    except Exception:
        return default

def vsp_contract_normalize_status(payload):
    if not isinstance(payload, dict):
        payload = {"ok": False, "status": "ERROR", "final": True, "error": "INVALID_STATUS_PAYLOAD"}

    stall = _env_int("VSP_UIREQ_STALL_TIMEOUT_SEC", _env_int("VSP_STALL_TIMEOUT_SEC", 600))
    total = _env_int("VSP_UIREQ_TOTAL_TIMEOUT_SEC", _env_int("VSP_TOTAL_TIMEOUT_SEC", 7200))
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

    payload["progress_pct"] = _clamp_int(payload.get("progress_pct", 0), 0, 100, 0)
    payload["stage_index"] = _clamp_int(payload.get("stage_index", 0), 0, 9999, 0)
    payload["stage_total"] = _clamp_int(payload.get("stage_total", 0), 0, 9999, 0)
    payload.setdefault("stage_name", payload.get("stage_name") or payload.get("stage") or "")

    sig = payload.get("stage_sig") or ""
    if not isinstance(sig, str) or sig.strip()=="":
        sig = f"{payload.get('stage_index','')}/{payload.get('stage_total','')}|{payload.get('stage_name','')}|{payload.get('progress_pct','')}"
    payload["stage_sig"] = sig
    payload.setdefault("updated_at", int(_time.time()))
    return payload
# === END VSP_COMMERCIAL_CONTRACT_V2 ===
'''
    lines = txt.splitlines(True)
    ins = 0
    for i, ln in enumerate(lines[:300]):
        if ln.startswith("import ") or ln.startswith("from "):
            ins = i + 1
    lines.insert(ins, helper + "\n")
    txt = "".join(lines)

# Wrap return jsonify(...) inside def run_status_v1
def_rx = re.compile(r"^def\s+run_status_v1\s*\(.*\)\s*:\s*$", re.M)
m = def_rx.search(txt)

def wrap_line(line: str) -> str:
    return re.sub(
        r"(\s*)return\s+jsonify\((.*)\)\s*$",
        r"\1return jsonify(vsp_contract_normalize_status(\2))\n",
        line
    )

changed = False
if m:
    start = m.start()
    after = txt[m.end():]
    next_m = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
    end = m.end() + (next_m.start() if next_m else len(after))
    block = txt[start:end]
    rest = txt[end:]
    blk = block.splitlines(True)
    for i, ln in enumerate(blk):
        if "return jsonify(" in ln and "vsp_contract_normalize_status" not in ln:
            ln2 = wrap_line(ln)
            if ln2 != ln:
                blk[i] = ln2
                changed = True
                break
    txt = "".join(blk) + rest
else:
    # fallback: patch any return jsonify near 'run_status_v1'
    L = txt.splitlines(True)
    out = []
    for i, ln in enumerate(L):
        if "return jsonify(" in ln and "vsp_contract_normalize_status" not in ln:
            win = "".join(L[max(0,i-60):min(len(L), i+60)])
            if "run_status_v1" in win:
                ln2 = wrap_line(ln)
                if ln2 != ln:
                    ln = ln2
                    changed = True
        out.append(ln)
    txt = "".join(out)

p.write_text(txt, encoding="utf-8")
print("[OK] patched run_api/vsp_run_api_v1.py (normalize + wrap jsonify). changed_return=", changed)
PY

# --- Patch APP: JSON errorhandlers for /api/vsp/* (never break jq) ---
python3 - "$APP" << 'PY'
import re, sys, time
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_JSON_ERRHANDLERS_V2" in txt:
    print("[SKIP] already has VSP_JSON_ERRHANDLERS_V2")
    raise SystemExit(0)

# Ensure request/jsonify import exists (best-effort)
if "from flask import request" not in txt or "jsonify" not in txt:
    # extend first "from flask import ..." line
    m = re.search(r"from\s+flask\s+import\s+([^\n]+)\n", txt)
    if m:
        line = m.group(0)
        items = [x.strip() for x in m.group(1).split(",")]
        for need in ["request", "jsonify"]:
            if need not in items:
                items.append(need)
        newline = "from flask import " + ", ".join(items) + "\n"
        txt = txt.replace(line, newline, 1)
    else:
        txt = "from flask import request, jsonify\n" + txt

patch = r'''
# === VSP_JSON_ERRHANDLERS_V2 ===
# Contract: any /api/vsp/* error must still be JSON so jq never dies.
@app.errorhandler(404)
def _vsp_err_404(e):
    try:
        if request.path.startswith("/api/vsp/"):
            return jsonify({"ok": False, "status": "NOT_FOUND", "final": True, "error": "HTTP_404_NOT_FOUND"}), 200
    except Exception:
        pass
    return ("Not Found", 404)

@app.errorhandler(500)
def _vsp_err_500(e):
    try:
        if request.path.startswith("/api/vsp/"):
            return jsonify({"ok": False, "status": "ERROR", "final": True, "error": "HTTP_500_INTERNAL"}), 200
    except Exception:
        pass
    return ("Internal Server Error", 500)
# === END VSP_JSON_ERRHANDLERS_V2 ===
'''

# Insert after "app = Flask(" line
lines = txt.splitlines(True)
idx = None
for i, ln in enumerate(lines):
    if re.search(r"^\s*app\s*=\s*Flask\(", ln):
        idx = i + 1
        break
if idx is None:
    # append at end (still ok)
    lines.append("\n" + patch + "\n")
else:
    lines.insert(idx, patch + "\n")

p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched vsp_demo_app.py with VSP_JSON_ERRHANDLERS_V2")
PY

# --- Syntax check: if fail => restore backups ---
echo "[CHECK] python compile..."
if ! python3 -m py_compile "$APP" "$RUNAPI" >/dev/null 2>&1; then
  echo "[ERR] py_compile failed. Restoring backups..."
  cp -f "$BAK_APP" "$APP"
  cp -f "$BAK_RUNAPI" "$RUNAPI"
  python3 -m py_compile "$APP" "$RUNAPI" >/dev/null 2>&1 || true
  echo "[RESTORED] done"
  exit 2
fi
echo "[OK] py_compile passed"

echo "[DONE] Commercial v2 patch applied safely."

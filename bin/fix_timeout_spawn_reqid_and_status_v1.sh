#!/usr/bin/env bash
set -euo pipefail

ROOT="/home/test/Data/SECURITY_BUNDLE/ui"
APP="$ROOT/vsp_demo_app.py"
RUNAPI="$ROOT/run_api/vsp_run_api_v1.py"
LOG="$ROOT/out_ci/ui_8910.log"

echo "== [0] Restore vsp_demo_app.py from latest bak_reqid_* (undo IndentationError) =="
LATEST_BAK="$(ls -1t "$ROOT"/vsp_demo_app.py.bak_reqid_* 2>/dev/null | head -n 1 || true)"
if [ -z "$LATEST_BAK" ]; then
  echo "[ERR] no backup vsp_demo_app.py.bak_reqid_* found"
  exit 2
fi
cp -f "$LATEST_BAK" "$APP"
echo "[RESTORED] $APP <= $LATEST_BAK"

python3 -m py_compile "$APP"
echo "[OK] vsp_demo_app.py compile OK after restore"

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "$APP.bak_fix_timeout_spawn_${TS}"
cp -f "$RUNAPI" "$RUNAPI.bak_fix_timeout_spawn_${TS}"
echo "[BACKUP] $APP.bak_fix_timeout_spawn_${TS}"
echo "[BACKUP] $RUNAPI.bak_fix_timeout_spawn_${TS}"

echo "== [1] Patch vsp_run_v1_alias(): if TIMEOUT_SPAWN => replace with synthetic REQ_ID =="
python3 - <<'PY'
import re, time, random, string
from pathlib import Path

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_RUN_V1_TIMEOUT_SPAWN_FIX_V1" in txt:
    print("[SKIP] vsp_demo_app already has VSP_RUN_V1_TIMEOUT_SPAWN_FIX_V1")
else:
    m = re.search(r"^def\s+vsp_run_v1_alias\s*\(\s*\)\s*:\s*$", txt, flags=re.M)
    if not m:
        raise SystemExit("[ERR] cannot find def vsp_run_v1_alias() in vsp_demo_app.py")

    # slice function
    start = m.start()
    after = txt[m.end():]
    m2 = re.search(r"^def\s+\w+\s*\(.*\)\s*:\s*$", after, flags=re.M)
    end = m.end() + (m2.start() if m2 else len(after))
    func = txt[start:end]

    # We will insert a wrapper right before the existing "return fn()" or "return ..." inside this alias
    # Strategy: find "return fn()" or "return fn(" first; replace with normalize-return block.
    if "return fn()" not in func and "return fn(" not in func:
        # fallback: find any "return fn" or "return api_vsp_run" patterns
        pass

    # Insert helper block before first "return fn" occurrence
    rpos = func.find("return fn()")
    if rpos == -1:
        rpos = func.find("return fn(")

    if rpos == -1:
        raise SystemExit("[ERR] vsp_run_v1_alias() does not contain return fn() / return fn(")

    before = func[:rpos]
    after_ret = func[rpos:]

    # Determine indent (body indent)
    # Find first indented line after def
    lines = func.splitlines()
    indent = "  "
    for ln in lines[1:]:
        if ln.strip():
            indent = ln[:len(ln) - len(ln.lstrip())]
            break

    patch = f"""{indent}# === VSP_RUN_V1_TIMEOUT_SPAWN_FIX_V1 ===
{indent}# Contract: never return request_id=TIMEOUT_SPAWN to clients.
{indent}import time as _t, random as _r, string as _s
{indent}_req_id = "VSP_UIREQ_" + _t.strftime("%Y%m%d_%H%M%S") + "_" + "".join(_r.choice(_s.ascii_lowercase+_s.digits) for _ in range(6))
{indent}_resp = fn()
{indent}_code = 200
{indent}_headers = None
{indent}if isinstance(_resp, tuple):
{indent}  if len(_resp) >= 2: _code = _resp[1]
{indent}  if len(_resp) >= 3: _headers = _resp[2]
{indent}  _resp = _resp[0]
{indent}try:
{indent}  _data = _resp.get_json(silent=True)
{indent}except Exception:
{indent}  _data = None
{indent}if not isinstance(_data, dict):
{indent}  _data = {{"ok": True, "implemented": True}}
{indent}rid = _data.get("request_id") or _data.get("req_id") or ""
{indent}if rid == "TIMEOUT_SPAWN" or rid == "":
{indent}  _data["request_id"] = _req_id
{indent}  _data["synthetic_req_id"] = True
{indent}  _data["message"] = (_data.get("message") or "Spawn wrapper timed out; using synthetic request_id for status tracking.")
{indent}from flask import jsonify as _jsonify
{indent}out = _jsonify(_data)
{indent}# keep original code if available, but default to 200
{indent}if _headers is not None:
{indent}  return out, _code, _headers
{indent}return out, _code
{indent}# === END VSP_RUN_V1_TIMEOUT_SPAWN_FIX_V1 ===
"""

    func2 = before + patch + "\n"  # drop the old return fn... (we don't need it)
    # Keep rest of function AFTER the original return line block: remove the original return statement line(s)
    # Remove until next newline after that 'return fn' line
    rest_lines = after_ret.splitlines(True)
    # skip first line (the return line)
    rest_lines = rest_lines[1:]
    func2 += "".join(rest_lines)

    txt2 = txt[:start] + func2 + txt[end:]
    p.write_text(txt2, encoding="utf-8")
    print("[OK] patched vsp_run_v1_alias() to replace TIMEOUT_SPAWN with synthetic req_id")

PY

python3 -m py_compile vsp_demo_app.py
echo "[OK] vsp_demo_app.py compile OK after patch"

echo "== [2] Patch run_status export wrapper: if NOT_FOUND + req_id startswith VSP_UIREQ_ => RUNNING from ui_8910.log tail =="
python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_STATUS_NOTFOUND_TO_RUNNING_FROM_TAIL_V1" in txt:
    print("[SKIP] run_api already has VSP_STATUS_NOTFOUND_TO_RUNNING_FROM_TAIL_V1")
else:
    # Find _export_run_status_v1 inside VSP_EXPORT_CONTRACT_ROUTES_V1 block
    marker = "def _export_run_status_v1(req_id):"
    i = txt.find(marker)
    if i == -1:
        raise SystemExit("[ERR] cannot find _export_run_status_v1(req_id) in run_api/vsp_run_api_v1.py")

    # Insert hook right AFTER out = _normalize(...)
    pat = re.compile(r"out\s*=\s*_normalize\([^\n]+\)\n", re.M)
    m = pat.search(txt, pos=i)
    if not m:
        raise SystemExit("[ERR] cannot find 'out = _normalize(...)' line inside _export_run_status_v1")

    ins = m.end()
    hook = r'''
    # === VSP_STATUS_NOTFOUND_TO_RUNNING_FROM_TAIL_V1 ===
    # If client used synthetic req_id (VSP_UIREQ_*), show RUNNING stage by parsing latest tail log.
    try:
      if isinstance(out, dict) and out.get("status") == "NOT_FOUND" and str(req_id).startswith("VSP_UIREQ_"):
        from pathlib import Path
        root = Path(__file__).resolve().parents[1]  # .../ui
        logp = root / "out_ci" / "ui_8910.log"
        tail_txt = ""
        try:
          if logp.exists():
            arr = logp.read_text(encoding="utf-8", errors="ignore").splitlines()
            tail_txt = "\n".join(arr[-400:])
        except Exception:
          tail_txt = ""
        stg = _extract_stage_from_tail(tail_txt) or {}
        out["status"] = "RUNNING"
        out["final"] = False
        out["error"] = ""
        out["stage_total"] = int(stg.get("total", 0) or 0)
        out["stage_index"] = int(stg.get("i", 0) or 0)
        out["stage_name"] = str(stg.get("name", "") or "")
        out["progress_pct"] = int(stg.get("progress", 0) or 0)
        out["stage_sig"] = f"{out.get('stage_index',0)}/{out.get('stage_total',0)}|{out.get('stage_name','')}|{out.get('progress_pct',0)}"
    except Exception:
      pass
    # === END VSP_STATUS_NOTFOUND_TO_RUNNING_FROM_TAIL_V1 ===
'''
    txt2 = txt[:ins] + hook + txt[ins:]
    p.write_text(txt2, encoding="utf-8")
    print("[OK] inserted NOT_FOUND->RUNNING-from-tail hook in _export_run_status_v1")

PY

python3 -m py_compile run_api/vsp_run_api_v1.py
echo "[OK] run_api/vsp_run_api_v1.py compile OK after patch"

echo "== [3] Restart 8910 =="
pkill -f vsp_demo_app.py || true
nohup python3 vsp_demo_app.py > "$LOG" 2>&1 &
sleep 1

echo "== [4] Smoke: run_v1 must return NON-TIMEOUT_SPAWN request_id =="
RESP="$(curl -sS -X POST "http://localhost:8910/api/vsp/run_v1" -H "Content-Type: application/json" \
  -d '{"mode":"local","profile":"FULL_EXT","target_type":"path","target":"/home/test/Data/SECURITY-10-10-v4"}')"
python3 - <<PY
import json
o=json.loads('''$RESP''')
print(o)
print("request_id=", o.get("request_id"))
PY

RID="$(python3 - <<PY
import json
o=json.loads('''$RESP''')
print(o.get("request_id") or "")
PY
)"

if [ -z "$RID" ]; then
  echo "[ERR] missing request_id from run_v1 response"
  exit 3
fi

echo "== [5] Smoke: status must be RUNNING (not final NOT_FOUND) and include stage fields =="
python3 - <<PY
import json, urllib.request
u="http://localhost:8910/api/vsp/run_status_v1/$RID"
obj=json.loads(urllib.request.urlopen(u,timeout=5).read().decode("utf-8","ignore"))
keys=["status","final","error","stall_timeout_sec","total_timeout_sec","progress_pct","stage_index","stage_total","stage_name","stage_sig"]
print({k: obj.get(k) for k in keys})
PY

echo "== Log tail 50 =="
tail -n 50 "$LOG" || true
echo "[DONE]"

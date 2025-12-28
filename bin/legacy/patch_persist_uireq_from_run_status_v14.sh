#!/usr/bin/env bash
set -euo pipefail

UI_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
F="$UI_ROOT/run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_status_v14_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_status_v14_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_FROM_STATUS_V14" in txt:
    print("[OK] already patched V14.")
    raise SystemExit(0)

helper = r'''
# === VSP_UIREQ_PERSIST_FROM_STATUS_V14 ===
from pathlib import Path as _Path
import json as _json
import time as _time
import os as _os

def _uireq_state_dir_v14():
    # ui/run_api/*.py -> parents[1] == ui/
    ui_root = _Path(__file__).resolve().parents[1]
    d = ui_root / "out_ci" / "uireq_v1"
    d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_state_update_v14(req_id: str, payload: dict):
    fp = _uireq_state_dir_v14() / f"{req_id}.json"
    try:
        try:
            cur = _json.loads(fp.read_text(encoding="utf-8"))
        except Exception:
            cur = {"ok": True, "req_id": req_id}

        if not isinstance(payload, dict):
            payload = {}

        # don't overwrite good fields with None/"" (commercial rule)
        for k, v in payload.items():
            if v is None:
                continue
            if k in ("ci_run_dir","runner_log","stage_sig") and v == "":
                continue
            cur[k] = v

        cur["req_id"] = cur.get("req_id") or req_id
        cur["updated_at"] = _time.strftime("%Y-%m-%dT%H:%M:%SZ", _time.gmtime())

        tmp = str(fp) + ".tmp"
        _Path(tmp).write_text(_json.dumps(cur, ensure_ascii=False, indent=2), encoding="utf-8")
        _os.replace(tmp, fp)
        return True
    except Exception:
        try:
            app.logger.exception("[UIREQ][V14] persist update failed")
        except Exception:
            pass
        return False

def vsp_jsonify_persist_uireq_v14(payload):
    # payload must be dict containing req_id; persist then jsonify
    try:
        if isinstance(payload, dict):
            rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
            if rid:
                _uireq_state_update_v14(str(rid), payload)
    except Exception:
        pass
    return jsonify(payload)
# === END VSP_UIREQ_PERSIST_FROM_STATUS_V14 ===
'''.lstrip("\n")

# insert helper near top (after imports best-effort)
m = re.search(r'^(?:import|from)\s+[^\n]+\n(?:import|from)\s+[^\n]+\n', txt, flags=re.M)
if m:
    txt = txt[:m.end()] + "\n" + helper + "\n" + txt[m.end():]
else:
    lines0 = txt.splitlines(True)
    txt = "".join(lines0[:1]) + "\n" + helper + "\n" + "".join(lines0[1:])

# locate run_status_v1 block
mm = re.search(r'^\s*def\s+run_status_v1\s*\(.*\)\s*:\s*$', txt, flags=re.M)
if not mm:
    print("[ERR] cannot find def run_status_v1(...)")
    raise SystemExit(3)

def_start = mm.start()
def_indent = len(mm.group(0)) - len(mm.group(0).lstrip(" \t"))

lines = txt.splitlines(True)

# char offset -> line index
pos = 0
li_def = 0
for i, ln in enumerate(lines):
    if pos <= def_start < pos + len(ln):
        li_def = i
        break
    pos += len(ln)

# find end of function
end = len(lines)
for j in range(li_def + 1, len(lines)):
    ln = lines[j]
    if ln.strip() == "":
        continue
    ind = len(ln) - len(ln.lstrip(" \t"))
    if ind <= def_indent and (ln.lstrip().startswith("def ") or ln.lstrip().startswith("@")):
        end = j
        break

# replace ONLY inside run_status_v1: "return jsonify(" -> "return vsp_jsonify_persist_uireq_v14("
for k in range(li_def, end):
    lines[k] = re.sub(r'^(\s*)return\s+jsonify\s*\(', r'\1return vsp_jsonify_persist_uireq_v14(', lines[k])

p.write_text("".join(lines), encoding="utf-8")
print("[OK] patched run_status_v1: return jsonify(...) -> return vsp_jsonify_persist_uireq_v14(...).")
PY

echo "== PY COMPILE CHECK =="
python3 -m py_compile "$F" && echo "[OK] py_compile passed"

echo "== QUICK GREP (V14) =="
grep -n "VSP_UIREQ_PERSIST_FROM_STATUS_V14" "$F" | head -n 80 || true
grep -n "vsp_jsonify_persist_uireq_v14" "$F" | head -n 40 || true
grep -n "return vsp_jsonify_persist_uireq_v14" "$F" | head -n 40 || true

echo "[DONE] Restart 8910 to load code."

#!/usr/bin/env bash
set -euo pipefail

F="/home/test/Data/SECURITY_BUNDLE/ui/run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_debug_v15_${TS}"
echo "[BACKUP] $F.bak_persist_debug_v15_${TS}"

python3 - "$F" <<'PY'
import re, sys
from pathlib import Path

p = Path(sys.argv[1])
txt = p.read_text(encoding="utf-8", errors="ignore")

if "VSP_UIREQ_PERSIST_DEBUG_V15" in txt:
    print("[OK] already patched V15.")
    raise SystemExit(0)

# We expect V14 already inserted functions. We'll patch inside vsp_jsonify_persist_uireq_v14 and _uireq_state_update_v14
# 1) Ensure we have a debug helper
ins = r'''
# === VSP_UIREQ_PERSIST_DEBUG_V15 ===
import traceback as _traceback

def _uireq_dbg_dir_v15():
    try:
        d = _uireq_state_dir_v14()
    except Exception:
        # fallback: ui/
        d = _Path(__file__).resolve().parents[1] / "out_ci" / "uireq_v1"
        d.mkdir(parents=True, exist_ok=True)
    return d

def _uireq_dbg_append_v15(name: str, line: str):
    try:
        d = _uireq_dbg_dir_v15()
        fp = d / name
        with open(fp, "a", encoding="utf-8") as f:
            f.write(line.rstrip("\n") + "\n")
    except Exception:
        pass
# === END VSP_UIREQ_PERSIST_DEBUG_V15 ===
'''.lstrip("\n")

# Insert debug helpers right after END V14 helper block if present, else after helper start
m = re.search(r'# === END VSP_UIREQ_PERSIST_FROM_STATUS_V14 ===\s*', txt)
if m:
    txt = txt[:m.end()] + "\n" + ins + "\n" + txt[m.end():]
else:
    # fallback: insert near top
    lines = txt.splitlines(True)
    txt = "".join(lines[:5]) + "\n" + ins + "\n" + "".join(lines[5:])

# 2) Patch vsp_jsonify_persist_uireq_v14 to always log a HIT
pat = re.compile(r'(def\s+vsp_jsonify_persist_uireq_v14\s*\(payload\)\s*:\s*\n)([\s\S]*?)(\n\s*return\s+jsonify\s*\(payload\)\s*)', re.M)
m2 = pat.search(txt)
if not m2:
    print("[ERR] cannot find vsp_jsonify_persist_uireq_v14() to patch (is V14 present?).")
    raise SystemExit(2)

head = m2.group(1)
body = m2.group(2)
tail = m2.group(3)

# Replace body with robust logging + try/except capturing
new_body = r'''    # HIT marker: prove this function is executed
    try:
        rid0 = None
        if isinstance(payload, dict):
            rid0 = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
        _uireq_dbg_append_v15("_persist_hits.log", f"hit file={__file__} rid={rid0} keys={(list(payload.keys()) if isinstance(payload, dict) else type(payload))}")
    except Exception:
        pass

    try:
        if isinstance(payload, dict):
            rid = payload.get("req_id") or payload.get("request_id") or payload.get("rid")
            if rid:
                ok = _uireq_state_update_v14(str(rid), payload)
                if not ok:
                    _uireq_dbg_append_v15("_persist_err.log", f"persist_returned_false rid={rid}")
            else:
                _uireq_dbg_append_v15("_persist_err.log", "missing_rid_in_payload")
        else:
            _uireq_dbg_append_v15("_persist_err.log", f"payload_not_dict type={type(payload)}")
    except Exception as e:
        try:
            _uireq_dbg_append_v15("_persist_err.log", "exception=" + repr(e))
            _uireq_dbg_append_v15("_persist_err.log", _traceback.format_exc())
        except Exception:
            pass
'''

txt = txt[:m2.start()] + head + new_body + tail + txt[m2.end():]

p.write_text(txt, encoding="utf-8")
print("[OK] V15 debug injected into vsp_jsonify_persist_uireq_v14().")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile passed"
grep -n "VSP_UIREQ_PERSIST_DEBUG_V15" "$F" | head -n 80 || true
echo "[DONE] restart 8910 and poll run_status; then check _persist_hits.log/_persist_err.log"

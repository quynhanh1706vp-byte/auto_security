#!/usr/bin/env bash
set -euo pipefail
F="vsp_demo_app.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_persist_uireq_${TS}"
echo "[BACKUP] $F.bak_persist_uireq_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("vsp_demo_app.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK_BEG = "# === VSP PERSIST UIREQ V1 ==="
MARK_END = "# === END VSP PERSIST UIREQ V1 ==="
if MARK_BEG in txt:
    print("[OK] persist block already present")
    raise SystemExit(0)

block = f"""
{MARK_BEG}
import json, os, time
from pathlib import Path

_UIREQ_DIR = Path("/home/test/Data/SECURITY_BUNDLE/ui/out_ci/uireq_v1")
_UIREQ_DIR.mkdir(parents=True, exist_ok=True)

def vsp_persist_uireq_state_v1(rid: str, payload: dict) -> None:
    try:
        payload = dict(payload or {{}})
        payload.setdefault("req_id", rid)
        payload.setdefault("rid", rid)
        payload.setdefault("ts_persist", time.strftime("%Y-%m-%dT%H:%M:%S"))
        tmp = _UIREQ_DIR / f".{rid}.json.tmp"
        out = _UIREQ_DIR / f"{rid}.json"
        tmp.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
        os.replace(tmp, out)
    except Exception:
        # never break API response
        pass
{MARK_END}
"""

# Insert block near top after imports (best effort)
m = re.search(r"^from flask .*?$", txt, flags=re.M)
if m:
    ins = m.end()
    txt2 = txt[:ins] + "\n" + block + "\n" + txt[ins:]
else:
    txt2 = block + "\n" + txt

p.write_text(txt2, encoding="utf-8")
print("[OK] inserted persist helper")

# Now patch run_status_v1 route to call persist (best effort by pattern)
txt = p.read_text(encoding="utf-8", errors="ignore")
# pattern: def run_status_v1(...): ... return jsonify(payload)
pat = re.compile(r"(def\s+run_status_v1\s*\(.*?\)\s*:\s*)([\s\S]*?)(return\s+.+?$)", re.M)
m = pat.search(txt)
if not m:
    print("[WARN] cannot locate run_status_v1 function to auto-insert call; please insert manually: vsp_persist_uireq_state_v1(rid, payload)")
    raise SystemExit(0)

head, body, ret = m.group(1), m.group(2), m.group(3)

if "vsp_persist_uireq_state_v1(" in body:
    print("[OK] run_status_v1 already persists")
    raise SystemExit(0)

# Heuristic: find variable name "payload" or "out"
# We inject just before return: if rid variable exists, call with payload dict.
inject = "\n    try:\n        vsp_persist_uireq_state_v1(str(rid), dict(payload if 'payload' in locals() else out if 'out' in locals() else {}))\n    except Exception:\n        pass\n"
body2 = body + inject

txt2 = txt[:m.start()] + head + body2 + ret + txt[m.end():]
p.write_text(txt2, encoding="utf-8")
print("[OK] patched run_status_v1 to persist (heuristic)")
PY

python3 -m py_compile "$F" && echo "[OK] py_compile"

#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_runstatus_uireqdir_v1_${TS}"
echo "[BACKUP] $F.bak_runstatus_uireqdir_v1_${TS}"

python3 - <<'PY'
import re
from pathlib import Path

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="ignore")

MARK = "VSP_RUN_STATUS_READ_UIREQDIR_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
    raise SystemExit(0)

# locate run_status_v1 function
m = re.search(r"^def\s+run_status_v1\s*\(\s*req_id\s*\)\s*:\s*$", txt, flags=re.M)
if not m:
    raise SystemExit("[ERR] cannot find def run_status_v1(req_id):")

# function end = next top-level def
m2 = re.search(r"^def\s+\w+\s*\(", txt[m.end():], flags=re.M)
end = len(txt) if not m2 else (m.end() + m2.start())
fn = txt[m.start():end]

# find first assignment to st = ...
ms = re.search(r"^\s*st\s*=\s*.+$", fn, flags=re.M)
if not ms:
    raise SystemExit("[ERR] cannot find 'st = ...' inside run_status_v1()")

insert_pos = ms.end()

snippet = r'''

  # === VSP_RUN_STATUS_READ_UIREQDIR_V1 ===
  # If main reader produced empty/partial state, fallback to _VSP_UIREQ_DIR/<req_id>.json
  try:
    if (not isinstance(st, dict)) or (not st) or (not (st.get("request_id") or st.get("req_id"))):
      try:
        f2 = _VSP_UIREQ_DIR / f"{req_id}.json"
      except Exception:
        from pathlib import Path as _P
        f2 = _P(__file__).resolve().parents[1] / "ui" / "out_ci" / "uireq_v1" / f"{req_id}.json"
      if f2 and f2.is_file():
        try:
          import json as _json
          st = _json.loads(f2.read_text(encoding="utf-8", errors="replace"))
        except Exception:
          pass
    if isinstance(st, dict):
      st.setdefault("req_id", req_id)
      st.setdefault("request_id", st.get("request_id") or req_id)
      st.setdefault("ok", True)
  except Exception:
    pass
  # === END VSP_RUN_STATUS_READ_UIREQDIR_V1 ===
'''

fn2 = fn[:insert_pos] + snippet + fn[insert_pos:]
txt2 = txt[:m.start()] + fn2 + txt[end:]

p.write_text(txt2, encoding="utf-8")
print("[OK] patched:", MARK)
PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

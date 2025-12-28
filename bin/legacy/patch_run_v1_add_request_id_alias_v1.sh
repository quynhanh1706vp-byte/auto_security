#!/usr/bin/env bash
set -euo pipefail
F="run_api/vsp_run_api_v1.py"
[ -f "$F" ] || { echo "[ERR] missing $F"; exit 1; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "$F.bak_reqid_alias_${TS}"
echo "[BACKUP] $F.bak_reqid_alias_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p = Path("run_api/vsp_run_api_v1.py")
txt = p.read_text(encoding="utf-8", errors="replace")

MARK = "VSP_RUNV1_ADD_REQUEST_ID_ALIAS_V1"
if MARK in txt:
    print("[OK] already patched:", MARK)
else:
    # chèn ngay trước "return __resp, 200" (run_v1)
    pat = r"(\n\s*)return\s+__resp\s*,\s*200\s*\n"
    m = re.search(pat, txt)
    if not m:
        raise SystemExit("[ERR] cannot find 'return __resp, 200' to insert before")

    inject = (
        "\n    # " + MARK + "\n"
        "    try:\n"
        "      if isinstance(__resp, dict):\n"
        "        __resp.setdefault('request_id', __resp.get('req_id') or req_id)\n"
        "        __resp.setdefault('req_id', __resp.get('request_id') or req_id)\n"
        "    except Exception:\n"
        "      pass\n"
    )

    txt = txt[:m.start(1)] + inject + txt[m.start(1):]
    p.write_text(txt, encoding="utf-8")
    print("[OK] patched:", MARK)

PY

python3 -m py_compile "$F"
echo "[OK] py_compile OK"

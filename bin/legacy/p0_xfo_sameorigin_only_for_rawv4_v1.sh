#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_xfo_rawv4_${TS}"
echo "[BACKUP] ${WSGI}.bak_xfo_rawv4_${TS}"

python3 - "$WSGI" <<'PY'
import sys, re
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_XFO_SAMEORIGIN_ONLY_RAWV4_V1"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Find an after_request hook that sets X-Frame-Options (DENY)
# If not found, we append a new after_request hook at EOF that adjusts ONLY when X-VSP-RAW=v4
if "after_request" in s and "X-Frame-Options" in s:
    # safest: append new hook anyway (last hook wins)
    pass

addon = f"""

# --- {marker} ---
try:
    from flask import request
except Exception:
    request = None

@application.after_request
def __vsp_xfo_only_rawv4(resp):
    try:
        # only relax for our raw endpoint
        if resp is not None and resp.headers.get("X-VSP-RAW") == "v4":
            resp.headers["X-Frame-Options"] = "SAMEORIGIN"
    except Exception:
        pass
    return resp
# --- /{marker} ---
"""
p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended after_request XFO adjust for raw v4")
PY

python3 -m py_compile "$WSGI"
echo "[OK] py_compile OK"

sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "== verify XFO for raw v4 =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
curl -i -sS "$BASE/api/vsp/run_file_raw_v4?rid=$RID&path=run_gate_summary.json" | egrep -i 'HTTP/|X-VSP-RAW|X-Frame-Options' || true

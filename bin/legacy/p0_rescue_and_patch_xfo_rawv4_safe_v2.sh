#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

WSGI="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

echo "== [1] restore latest pre-xfo backup (bak_xfo_rawv4_*) =="
bak="$(ls -1t ${WSGI}.bak_xfo_rawv4_* 2>/dev/null | head -n 1 || true)"
if [ -z "$bak" ]; then
  echo "[ERR] no backup found: ${WSGI}.bak_xfo_rawv4_*"
  exit 2
fi
echo "[OK] restore from: $bak"
cp -f "$bak" "$WSGI"

echo "== [2] restart service to recover =="
python3 -m py_compile "$WSGI"
sudo systemctl restart "$SVC"
echo "[OK] service restarted"

echo "== [3] append SAFE XFO hook for raw v4 (register on REAL flask app) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_xfo_safe_${TS}"
echo "[BACKUP] ${WSGI}.bak_xfo_safe_${TS}"

python3 - "$WSGI" <<'PY'
import sys, textwrap
from pathlib import Path

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")
marker="VSP_P0_XFO_SAMEORIGIN_ONLY_RAWV4_SAFE_V2"
if marker in s:
    print("[OK] already patched")
    raise SystemExit(0)

addon=textwrap.dedent(f"""

# --- {marker} ---
def __vsp_find_flask_app_for_xfo__():
    g = globals()
    prefer = ["app", "flask_app", "application"]
    cand_names = prefer + [k for k in g.keys() if k not in prefer]
    for name in cand_names:
        obj = g.get(name)
        if obj is None:
            continue
        # Flask app usually has: add_url_rule, route, after_request
        if hasattr(obj, "after_request") and hasattr(obj, "route") and hasattr(obj, "add_url_rule"):
            return obj, name
    return None, None

def __vsp_xfo_only_rawv4__(resp):
    try:
        if resp is not None and resp.headers.get("X-VSP-RAW") == "v4":
            resp.headers["X-Frame-Options"] = "SAMEORIGIN"
    except Exception:
        pass
    return resp

try:
    __app, __name = __vsp_find_flask_app_for_xfo__()
    if __app is not None:
        __app.after_request(__vsp_xfo_only_rawv4__)
        __VSP_XFO_RAWV4_OK__ = True
        __VSP_XFO_APP_NAME__ = __name
    else:
        __VSP_XFO_RAWV4_OK__ = False
        __VSP_XFO_APP_NAME__ = None
except Exception:
    __VSP_XFO_RAWV4_OK__ = False
    __VSP_XFO_APP_NAME__ = None
# --- /{marker} ---
""")

p.write_text(s + "\n" + addon, encoding="utf-8")
print("[OK] appended SAFE XFO hook")
PY

python3 -m py_compile "$WSGI"
sudo systemctl restart "$SVC"
echo "[OK] restarted after xfo patch"

echo "== [4] verify header behavior =="
RID="$(curl -fsS "$BASE/api/vsp/rid_latest" | python3 -c 'import sys,json; print(json.load(sys.stdin).get("rid",""))')"
echo "RID=$RID"
curl -i -sS "$BASE/api/vsp/run_file_raw_v4?rid=$RID&path=run_gate_summary.json" \
| egrep -i 'HTTP/|X-VSP-RAW|X-Frame-Options|X-VSP-PATH' || true

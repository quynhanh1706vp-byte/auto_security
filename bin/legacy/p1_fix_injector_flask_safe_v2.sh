#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need date; need systemctl; need tail; need grep; need sed

F="wsgi_vsp_ui_gateway.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_8910.error.log"

[ -f "$F" ] || { echo "[ERR] missing $F"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$F" "${F}.bak_injectsafe_${TS}"
echo "[BACKUP] ${F}.bak_injectsafe_${TS}"

python3 - "$F" <<'PY'
from pathlib import Path
import re, sys

p=Path(sys.argv[1])
s=p.read_text(encoding="utf-8", errors="replace")

start = s.find("# --- VSP_P1_AFTER_REQUEST_INJECT_MARKERS_AND_TRENDPOINTS_V1 ---")
end = s.find("# --- end VSP_P1_AFTER_REQUEST_INJECT_MARKERS_AND_TRENDPOINTS_V1 ---", start)
if start == -1 or end == -1:
    print("[ERR] injector block not found; cannot patch safely")
    raise SystemExit(2)

block = s[start:end]
# Replace __vsp__get_flask_app with a safer picker that requires after_request/route attrs.
block2 = re.sub(
    r'(?s)def __vsp__get_flask_app\(\):.*?return None\s*',
    '''def __vsp__get_flask_app():
    # Pick the real Flask app object (must have .after_request and .route)
    g = globals()
    for name in ("app", "flask_app", "application", "application_flask"):
        obj = g.get(name)
        if obj is None:
            continue
        if hasattr(obj, "after_request") and hasattr(obj, "route"):
            return obj
    return None
''',
    block,
    count=1
)

# Also harden the registration check to avoid AttributeError even if picked wrong.
block2 = re.sub(
    r'__vsp__flask\s*=\s*__vsp__get_flask_app\(\)\s*\nif __vsp__flask is not None:\s*\n\s*@__vsp__flask\.after_request',
    '__vsp__flask = __vsp__get_flask_app()\nif __vsp__flask is not None and hasattr(__vsp__flask, "after_request"):\n    @__vsp__flask.after_request',
    block2,
    count=1
)

s2 = s[:start] + block2 + s[end:]
p.write_text(s2, encoding="utf-8")
print("[OK] patched injector block to be Flask-safe")
PY

python3 -m py_compile "$F" >/dev/null 2>&1 && echo "[OK] py_compile OK" || { echo "[ERR] py_compile failed"; exit 2; }

echo "== restart service =="
systemctl restart "$SVC" || true
sleep 0.8
systemctl status "$SVC" -l --no-pager | head -n 70 || true

echo "== tail gunicorn error log (if still failing) =="
if [ -f "$ERRLOG" ]; then
  tail -n 120 "$ERRLOG" || true
else
  echo "[WARN] missing $ERRLOG"
fi

echo "== smoke curl =="
curl -fsS --connect-timeout 1 http://127.0.0.1:8910/runs >/dev/null && echo "[OK] /runs reachable" || echo "[ERR] /runs still not reachable"

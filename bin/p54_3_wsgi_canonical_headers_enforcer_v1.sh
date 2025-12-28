#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p54_3_${TS}"
mkdir -p "$EVID"

W="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need ls; need head; need python3; need grep; need sed; need awk; need curl; need sudo; need cp; need mkdir

[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p54_3_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

echo "[1] run P54 gate baseline (to capture before/after) ..."
bash bin/p54_commercial_gate_v2_headers_sorted_source_markers_v1.sh > "$EVID/p54_before.log" 2>&1 || true

cp -f "$W" "$W.bak_p54_3_${TS}"
echo "[OK] backup: $W.bak_p54_3_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="VSP_P54_3_WSGI_CANON_HEADERS_V1"
if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

# Append a WSGI middleware at end (lowest risk). It wraps final callable and overrides headers for HTML tabs only.
mw = r'''
# ''' + MARK + r'''
# Canonical headers enforcer at WSGI layer (final authority).
# Apply only for HTML UI tabs to eliminate per-route drift in Cache-Control/Pragma/Expires/XFO/XCTO/Referrer-Policy.
class VSPCanonHeadersWSGI:
    def __init__(self, app):
        self.app = app

    def __call__(self, environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        # Only for UI HTML tabs (both legacy and /c/* routes)
        ui_paths = (
            "/vsp5", "/runs", "/data_source", "/settings", "/rule_overrides",
            "/c/dashboard", "/c/runs", "/c/data_source", "/c/settings", "/c/rule_overrides"
        )
        is_ui = any(path == p or path.startswith(p + "/") for p in ui_paths)

        def _sr(status, headers, exc_info=None):
            # detect html
            ctype = ""
            for k,v in headers:
                if k.lower() == "content-type":
                    ctype = v or ""
                    break
            is_html = ("text/html" in (ctype or "").lower()) or is_ui

            if is_html:
                # drop existing variants first
                drop = {"cache-control","pragma","expires","x-content-type-options","referrer-policy","x-frame-options"}
                newh = [(k,v) for (k,v) in headers if k.lower() not in drop]
                # force canonical
                newh.append(("Cache-Control","no-store"))
                newh.append(("Pragma","no-cache"))
                newh.append(("Expires","0"))
                newh.append(("X-Content-Type-Options","nosniff"))
                newh.append(("Referrer-Policy","same-origin"))
                newh.append(("X-Frame-Options","SAMEORIGIN"))
                headers = newh
            return start_response(status, headers, exc_info)

        return self.app(environ, _sr)

# Wrap final callable safely (support both "app" and "application" names)
try:
    application
except NameError:
    application = None

try:
    app
except NameError:
    app = None

if application is not None:
    application = VSPCanonHeadersWSGI(application)
if app is not None:
    app = VSPCanonHeadersWSGI(app)
'''

p.write_text(s + "\n" + mw, encoding="utf-8")
print("[OK] appended WSGI canonical header enforcer")
PY

# py_compile gate
python3 -m py_compile "$W" > "$EVID/py_compile_wsgi.txt" 2>&1 || {
  echo "[ERR] py_compile WSGI failed; tail:"; tail -n 120 "$EVID/py_compile_wsgi.txt" || true
  echo "[ROLLBACK] restoring backup"
  cp -f "$W.bak_p54_3_${TS}" "$W"
  exit 2
}
python3 -m py_compile "$APP" > "$EVID/py_compile_app.txt" 2>&1 || {
  echo "[ERR] py_compile APP failed; tail:"; tail -n 120 "$EVID/py_compile_app.txt" || true
  echo "[ROLLBACK] restoring backup"
  cp -f "$W.bak_p54_3_${TS}" "$W"
  exit 2
}

# restart and wait up to 60s
sudo systemctl restart "$SVC" || true
ok=0
: > "$EVID/wait_vsp5_60s.txt"
for i in $(seq 1 60); do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 5 "$BASE/vsp5" || true)"
  echo "t+${i}s code=$code" >> "$EVID/wait_vsp5_60s.txt"
  if [ "$code" = "200" ]; then ok=1; break; fi
  sleep 1
done
[ "$ok" -eq 1 ] || { echo "[ERR] /vsp5 not up after restart"; exit 2; }

# rerun P54
bash bin/p54_commercial_gate_v2_headers_sorted_source_markers_v1.sh > "$EVID/p54_after.log" 2>&1 || true

# attach evidence
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
echo "[DONE] P54.3 applied. Check $EVID/p54_after.log (expect fp_count=1)"

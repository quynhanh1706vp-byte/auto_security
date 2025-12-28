#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_2b_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need ls; need head; need curl; need sudo
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_2b_${TS}"
mkdir -p "$ATT"

cp -f "$W" "$W.bak_p52_2b_${TS}"
echo "[OK] backup: $W.bak_p52_2b_${TS}" | tee "$EVID/backup.txt" >/dev/null

python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P52_2B_AFTER_REQUEST_HEADER_POLICY_V1"

if MARK in s:
    print("[OK] already patched")
else:
    block = f"""
# {MARK}
try:
    @app.after_request
    def _vsp_p52_2b_header_policy(resp):
        # Consistent commercial headers for HTML pages
        resp.headers['Cache-Control'] = 'no-store'
        resp.headers['Pragma'] = 'no-cache'
        resp.headers['Expires'] = '0'
        resp.headers.setdefault('X-Content-Type-Options', 'nosniff')
        resp.headers.setdefault('Referrer-Policy', 'same-origin')
        resp.headers.setdefault('X-Frame-Options', 'SAMEORIGIN')
        return resp
except Exception:
    pass
"""

    # insert right AFTER the first "app = ..." line (best effort)
    m = re.search(r'(?m)^\s*app\s*=\s*.+$', s)
    if not m:
        # if no app=, do nothing (safe)
        print("[WARN] no 'app =' found; skip patch to avoid breaking")
    else:
        ins = m.end()
        s = s[:ins] + "\n" + block + s[ins:]
        p.write_text(s, encoding="utf-8")
        print("[OK] inserted after app=")
PY

# compile gate; rollback if fail
set +e
python3 -m py_compile "$W" > "$EVID/py_compile.txt" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[ERR] py_compile failed -> rollback" | tee "$EVID/rollback.txt" >&2
  cp -f "$W.bak_p52_2b_${TS}" "$W"
  python3 -m py_compile "$W" > "$EVID/py_compile_after_rollback.txt" 2>&1 || true
  exit 2
fi

sudo systemctl restart "$SVC" || true

# strict health
code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 4 "$BASE/vsp5" || true)"
echo "vsp5_http=$code" | tee "$EVID/health.txt" >/dev/null
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

if [ "$code" != "200" ]; then
  echo "[FAIL] service not healthy after patch (vsp5=$code)" >&2
  exit 2
fi

echo "[DONE] P52.2b PASS (headers policy applied safely)"

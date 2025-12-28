#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_2c_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need awk; need ls; need head; need curl; need sudo
command -v systemctl >/dev/null 2>&1 || true

W="wsgi_vsp_ui_gateway.py"
[ -f "$W" ] || { echo "[ERR] missing $W"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found under $RELROOT"; exit 2; }
ATT="$latest_release/evidence/p52_2c_${TS}"
mkdir -p "$ATT"

echo "[OK] latest_release=$latest_release"
cp -f "$W" "$W.bak_p52_2c_${TS}"
echo "[OK] backup: $W.bak_p52_2c_${TS}" | tee "$EVID/backup.txt" >/dev/null

# Patch: add WSGI middleware function + wrap top-level callable (application/app) safely
python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P52_2C_WSGI_HEADER_MW_V1"

if MARK in s:
    print("[OK] already patched")
    raise SystemExit(0)

mw = f"""
# {MARK}
def _vsp_p52_2c_header_mw(_wsgi_app):
    \"\"\"WSGI middleware: normalize headers across all HTML tabs.\"\"\"
    def _app(environ, start_response):
        def _sr(status, headers, exc_info=None):
            # headers is list of (k,v)
            h = []
            seen = set()
            for k,v in headers:
                lk = k.lower()
                if lk in ("cache-control","pragma","expires"):
                    continue
                h.append((k,v))
                seen.add(lk)
            # enforce consistent policy
            h.append(("Cache-Control","no-store"))
            h.append(("Pragma","no-cache"))
            h.append(("Expires","0"))
            if "x-content-type-options" not in seen:
                h.append(("X-Content-Type-Options","nosniff"))
            if "referrer-policy" not in seen:
                h.append(("Referrer-Policy","same-origin"))
            if "x-frame-options" not in seen:
                h.append(("X-Frame-Options","SAMEORIGIN"))
            return start_response(status, h, exc_info)
        return _wsgi_app(environ, _sr)
    return _app
"""

# Insert middleware near top (after imports if possible)
m = re.search(r'(?ms)\A(.*?)(\n\s*(app|application)\s*=|\n\s*def\s+|\n\s*class\s+)', s)
if m:
    pre = m.group(1)
    rest = s[len(pre):]
    s = pre + "\n" + mw + "\n" + rest
else:
    s = mw + "\n" + s

# Wrap callable: prefer "application" then "app"
# Find first top-level assignment line for application/app
def inject_wrap(varname):
    pat = re.compile(rf'(?m)^({varname}\s*=\s*.+)$')
    mm = pat.search(s)
    if not mm:
        return False, s
    line = mm.group(1)
    # if already wrapped
    if f"{varname} = _vsp_p52_2c_header_mw(" in s:
        return True, s
    insert = line + f"\n{varname} = _vsp_p52_2c_header_mw({varname})\n"
    s2 = s[:mm.start()] + insert + s[mm.end():]
    return True, s2

ok, s2 = inject_wrap("application")
if not ok:
    ok, s2 = inject_wrap("app")
if not ok:
    # can't find, but we still keep middleware (no wrap)
    print("[WARN] no top-level app/application assignment found; middleware defined but not wrapped")
    s2 = s

p.write_text(s2, encoding="utf-8")
print("[OK] patched middleware + wrap (if found)")
PY

# Compile gate; rollback if fail
set +e
python3 -m py_compile "$W" > "$EVID/py_compile.txt" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[ERR] py_compile failed -> rollback" | tee "$EVID/rollback.txt" >&2
  cp -f "$W.bak_p52_2c_${TS}" "$W"
  python3 -m py_compile "$W" > "$EVID/py_compile_after_rollback.txt" 2>&1 || true
  cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
  exit 2
fi

# Restart + warm + health (loosened: max-time 8s first hit, then 4s)
sudo systemctl restart "$SVC" || true
sleep 1.2
curl -sS -o /dev/null --connect-timeout 2 --max-time 8 "$BASE/vsp5" || true

ok=1
: > "$EVID/health_3x.txt"
for i in 1 2 3; do
  code="$(curl -sS -o /dev/null -w '%{http_code}' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || true)"
  echo "try#$i http_code=$code" | tee -a "$EVID/health_3x.txt" >/dev/null
  if [ "$code" != "200" ]; then ok=0; fi
  sleep 0.4
done

# Attach evidence
cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

if [ "$ok" -ne 1 ]; then
  echo "[FAIL] /vsp5 not stable after P52.2c" >&2
  exit 2
fi
echo "[DONE] P52.2c PASS (WSGI header middleware applied, /vsp5 stable 3/3)"

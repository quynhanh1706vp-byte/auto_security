#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
OUT="out_ci"
RELROOT="$OUT/releases"
TS="$(date +%Y%m%d_%H%M%S)"
EVID="$OUT/p52_2f_${TS}"
mkdir -p "$EVID"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need grep; need sed; need awk; need ls; need head; need curl; need sudo; need cp; need mkdir
command -v systemctl >/dev/null 2>&1 || true

APP="vsp_demo_app.py"
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

latest_release="$(ls -1dt "$RELROOT"/RELEASE_UI_* 2>/dev/null | head -n 1 || true)"
[ -n "${latest_release:-}" ] && [ -d "$latest_release" ] || { echo "[ERR] no release found"; exit 2; }
ATT="$latest_release/evidence/p52_2f_${TS}"
mkdir -p "$ATT"
echo "[OK] latest_release=$latest_release"

cp -f "$APP" "$APP.bak_p52_2f_${TS}"
echo "[OK] backup: $APP.bak_p52_2f_${TS}" | tee "$EVID/backup.txt" >/dev/null

python3 - <<'PY'
from pathlib import Path
import re
p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="VSP_P52_2F_AFTER_REQUEST_HEADERS_V1"

if MARK in s:
    print("[OK] already patched"); raise SystemExit(0)

block = f"""
# {MARK}
try:
    from flask import request
except Exception:
    request = None

try:
    @app.after_request
    def _vsp_p52_2f_headers(resp):
        try:
            path = ""
            if request is not None:
                path = getattr(request, "path", "") or ""
            ctype = resp.headers.get("Content-Type","") or ""
            is_html = ctype.lower().startswith("text/html") or path in ("/vsp5","/runs","/data_source","/settings","/rule_overrides")
            if is_html:
                resp.headers["Cache-Control"] = "no-store"
                resp.headers["Pragma"] = "no-cache"
                resp.headers["Expires"] = "0"
                resp.headers.setdefault("X-Content-Type-Options", "nosniff")
                resp.headers.setdefault("Referrer-Policy", "same-origin")
                resp.headers.setdefault("X-Frame-Options", "SAMEORIGIN")
            return resp
        except Exception:
            return resp
except Exception:
    pass
"""

# Insert after first "app =" creation line
m = re.search(r'(?m)^\s*app\s*=\s*Flask\(', s)
if not m:
    # fallback: insert after imports block (safe)
    m = re.search(r'(?ms)\A(.*?\n)\s*(app\s*=)', s)
    if m:
        ins = m.end(1)
        s = s[:ins] + "\n" + block + "\n" + s[ins:]
        p.write_text(s, encoding="utf-8")
        print("[OK] inserted near top (fallback)")
    else:
        raise SystemExit("[ERR] could not locate insertion point")
else:
    # insert right AFTER the app=Flask(...) line end
    line_end = s.find("\n", m.start())
    if line_end == -1:
        line_end = len(s)
    ins = line_end + 1
    s = s[:ins] + block + "\n" + s[ins:]
    p.write_text(s, encoding="utf-8")
    print("[OK] inserted after app=Flask(...)")
PY

# compile gate; rollback if fail
set +e
python3 -m py_compile "$APP" > "$EVID/py_compile.txt" 2>&1
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[ERR] py_compile failed -> rollback" | tee "$EVID/rollback.txt" >&2
  cp -f "$APP.bak_p52_2f_${TS}" "$APP"
  python3 -m py_compile "$APP" > "$EVID/py_compile_after_rollback.txt" 2>&1 || true
  cp -f "$EVID/"* "$ATT/" 2>/dev/null || true
  exit 2
fi

sudo systemctl restart "$SVC" || true
sleep 1.2

# warm + 5x health
curl -sS -o /dev/null --connect-timeout 2 --max-time 12 "$BASE/vsp5" || true
ok=1
: > "$EVID/health_5x.txt"
for i in 1 2 3 4 5; do
  out="$(curl -sS -o /dev/null -w 'code=%{http_code} time=%{time_total}\n' --connect-timeout 2 --max-time 6 "$BASE/vsp5" || echo 'code=000 time=99')"
  echo "try#$i $out" | tee -a "$EVID/health_5x.txt" >/dev/null
  code="$(echo "$out" | awk '{print $1}' | cut -d= -f2)"
  if [ "$code" != "200" ]; then ok=0; fi
  sleep 0.4
done

# snapshot headers per tab
for p in /vsp5 /runs /data_source /settings /rule_overrides; do
  curl -sS -D- -o /dev/null --connect-timeout 2 --max-time 6 "$BASE$p" \
    | awk 'BEGIN{IGNORECASE=1} /^HTTP\/|^Content-Type:|^Cache-Control:|^Pragma:|^Expires:|^X-Content-Type-Options:|^Referrer-Policy:|^X-Frame-Options:/{gsub("\r","");print}' \
    > "$EVID/headers_${p#/}.txt" 2>&1 || true
done

cp -f "$EVID/"* "$ATT/" 2>/dev/null || true

if [ "$ok" -ne 1 ]; then
  echo "[FAIL] /vsp5 not stable after P52.2f" >&2
  exit 2
fi
echo "[DONE] P52.2f PASS"

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need bash; need date; need ls; need head; need grep; need curl; need python3; need node

WSGI="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"

echo "== [0] Backup wsgi/app =="
cp -f "$WSGI" "${WSGI}.bak_rescue_${TS}"
cp -f "$APP"  "${APP}.bak_rescue_${TS}"
echo "[BACKUP] ${WSGI}.bak_rescue_${TS}"
echo "[BACKUP] ${APP}.bak_rescue_${TS}"

echo
echo "== [1] Auto-restore broken JS from nearest good backup (parse by node) =="

python3 - <<'PY'
from pathlib import Path
import subprocess, sys, glob, os, time

JS_DIR=Path("static/js")
bad = [
  "vsp_tabs4_autorid_v1.js",
  "vsp_tabs3_common_v3.js",
  "vsp_dashboard_luxe_v1.js",
  "vsp_dashboard_consistency_patch_v1.js",
  "vsp_rid_switch_refresh_all_v1.js",
  "vsp_bundle_tabs5_v1.js",
  "vsp_data_source_pagination_v1.js",
  "vsp_data_source_lazy_v1.js",
]

def js_ok(path: Path) -> bool:
  try:
    # parse only (no execute) using Function constructor
    subprocess.check_output([
      "node","-e",
      f"const fs=require('fs'); new Function(fs.readFileSync('{path.as_posix()}','utf8')); console.log('OK');"
    ], stderr=subprocess.STDOUT, timeout=6)
    return True
  except subprocess.CalledProcessError as e:
    out = e.output.decode('utf-8','replace')
    print(f"[BAD] {path.name}: {out.splitlines()[0][:160]}")
    return False
  except Exception as e:
    print(f"[BAD] {path.name}: {e}")
    return False

def restore_from_backup(cur: Path) -> bool:
  pats = [
    str(cur)+"*.bak_*",
    str(cur)+".bak_*",
    str(cur.with_name(cur.name+".bak_*")),
  ]
  cands=set()
  for p in pats:
    for f in glob.glob(p):
      cands.add(f)

  # sort by mtime desc
  cand_paths=sorted([Path(x) for x in cands if Path(x).is_file()],
                    key=lambda p: p.stat().st_mtime, reverse=True)

  for b in cand_paths[:60]:
    try:
      if js_ok(b):
        bak_copy = cur.with_name(cur.name+f".bak_autorestore_{time.strftime('%Y%m%d_%H%M%S')}")
        bak_copy.write_text(cur.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        cur.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print(f"[RESTORE] {cur.name} <= {b.name}")
        return True
    except Exception:
      continue
  return False

for name in bad:
  p=JS_DIR/name
  if not p.exists():
    print("[MISS]", name)
    continue
  if js_ok(p):
    print("[OK]", name)
    continue
  if restore_from_backup(p):
    # re-check
    if not js_ok(p):
      print("[ERR] still broken after restore:", name)
      sys.exit(4)
  else:
    print("[WARN] no good backup found for", name)
    # last resort: write safe stub for non-core lazy file only
    if name=="vsp_data_source_lazy_v1.js":
      p.write_text("/* CIO stub: lazy loader disabled */\nwindow.__VSP_DS_LAZY_DISABLED=true;\n", encoding="utf-8")
      print("[STUB] wrote", name)
    else:
      sys.exit(5)

print("[DONE] JS parse rescue complete")
PY

echo
echo "== [2] Fix MIME: if .js accidentally returned as application/json, force application/javascript at gateway =="

python3 - <<'PY'
from pathlib import Path
import re, time

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")
MARK="### === CIO MIME FIX (AUTO) ==="
if MARK in s:
  print("[OK] MIME FIX already present")
  raise SystemExit(0)

# Try to wrap WSGI application-level callable.
# We insert a small wrapper near end: define _cio_mime_fix then set application=_cio_mime_fix(application)
ins = r'''
### === CIO MIME FIX (AUTO) ===
# Ensure static JS is served with a JS MIME type even if upstream mis-tags it as JSON (nosniff would block it).
def _cio_mime_fix(app):
    def _wrap(environ, start_response):
        path = (environ.get("PATH_INFO") or "")
        def _sr(status, headers, exc_info=None):
            try:
                if path.endswith(".js"):
                    # normalize headers to list of tuples
                    h=[]
                    ct=None
                    for k,v in headers:
                        if k.lower()=="content-type":
                            ct=v
                        h.append((k,v))
                    if ct and "application/json" in ct.lower():
                        # replace content-type
                        h=[(k,("application/javascript; charset=utf-8" if k.lower()=="content-type" else v)) for k,v in h]
                    headers=h
            except Exception:
                pass
            return start_response(status, headers, exc_info)
        return app(environ, _sr)
    return _wrap
### === END CIO MIME FIX (AUTO) ===
'''

# Place before the last occurrence of "application =" or at end.
m=re.search(r'(?m)^\s*application\s*=\s*', s)
if m:
  # insert above first application= and then wrap after it
  # add wrapper block near end and then wrap after application defined
  pass

# safest: append block at end + wrap if 'application' exists
s2=s.rstrip()+"\n\n"+ins+"\n"
if re.search(r'(?m)^\s*application\s*=\s*', s2):
  s2 += "\ntry:\n    application = _cio_mime_fix(application)\nexcept Exception:\n    pass\n"
else:
  # common: Flask app variable named app; expose as application
  s2 += "\ntry:\n    application = _cio_mime_fix(app)\nexcept Exception:\n    application = app\n"

p.write_text(s2, encoding="utf-8")
print("[OK] patched wsgi_vsp_ui_gateway.py with MIME FIX")
PY

echo
echo "== [3] Restart service =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo
echo "== [4] Smoke: ensure JS is JS + dashboard endpoint loads =="
echo "-- HEAD /static/js/vsp_data_source_lazy_v1.js"
curl -fsSI "$BASE/static/js/vsp_data_source_lazy_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|x-content-type-options' || true
echo "-- HEAD /static/js/vsp_dashboard_luxe_v1.js"
curl -fsSI "$BASE/static/js/vsp_dashboard_luxe_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|x-content-type-options' || true
echo "-- GET /vsp5 (HTML marker)"
curl -fsS "$BASE/vsp5" | head -c 120; echo

echo
echo "[DONE] Now hard refresh (Ctrl+Shift+R) and confirm Console has 0 red errors."

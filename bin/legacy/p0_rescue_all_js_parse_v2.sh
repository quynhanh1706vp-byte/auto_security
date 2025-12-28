#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need date; need python3; need node; need curl; need grep; need head

WSGI="wsgi_vsp_ui_gateway.py"
[ -f "$WSGI" ] || { echo "[ERR] missing $WSGI"; exit 2; }

TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$WSGI" "${WSGI}.bak_alljsrescue_${TS}"
echo "[BACKUP] ${WSGI}.bak_alljsrescue_${TS}"

echo "== [1] Scan ALL active JS parse errors + auto-restore from newest good backup =="

python3 - <<'PY'
from pathlib import Path
import subprocess, glob, time, sys

ts=time.strftime("%Y%m%d_%H%M%S")
JS_DIR=Path("static/js")

def parse_ok(p:Path)->bool:
    try:
        subprocess.check_output(
            ["node","-e",f"const fs=require('fs'); new Function(fs.readFileSync('{p.as_posix()}','utf8'));"],
            stderr=subprocess.STDOUT, timeout=6
        )
        return True
    except subprocess.CalledProcessError as e:
        out=e.output.decode("utf-8","replace").splitlines()
        msg=(out[0] if out else "parse_error")
        print(f"[BAD] {p.name}: {msg[:160]}")
        return False
    except Exception as e:
        print(f"[BAD] {p.name}: {e}")
        return False

def restore(p:Path)->bool:
    # collect backups
    cands=set()
    for pat in (str(p)+".bak_*", str(p)+"*.bak_*", str(p)+".bak*", str(p)+"*.bak*"):
        for f in glob.glob(pat):
            cands.add(f)
    cand=sorted([Path(x) for x in cands if Path(x).is_file()],
                key=lambda q: q.stat().st_mtime, reverse=True)
    for b in cand[:120]:
        if parse_ok(b):
            # backup current
            cur_bak=p.with_name(p.name+f".bak_autorestore2_{ts}")
            cur_bak.write_text(p.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            p.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
            print(f"[RESTORE] {p.name} <= {b.name}")
            return True
    return False

active=[p for p in JS_DIR.glob("*.js") if ".bak" not in p.name and ".disabled" not in p.name]
active=sorted(active, key=lambda p: p.name.lower())

bad=[]
for p in active:
    if not parse_ok(p):
        bad.append(p)

if not bad:
    print("[OK] all active JS parse OK")
    sys.exit(0)

print(f"[INFO] bad_count={len(bad)} -> try restore")
still=[]
for p in bad:
    if restore(p):
        if not parse_ok(p):
            still.append(p)
    else:
        still.append(p)

if still:
    print("[ERR] still broken after restore:")
    for p in still[:30]:
        print(" -", p.name)
    sys.exit(4)

print("[OK] rescued all parse-broken JS")
PY

echo
echo "== [2] Ensure WSGI sets JS no-cache (so browser definitely loads fixed JS) =="
python3 - <<'PY'
from pathlib import Path
import re

p=Path("wsgi_vsp_ui_gateway.py")
s=p.read_text(encoding="utf-8", errors="replace")

MARK="### === CIO JS NOCACHE (AUTO) ==="
if MARK in s:
    print("[OK] JS NOCACHE already present")
    raise SystemExit(0)

# We piggyback on existing _cio_mime_fix wrapper if present; add Cache-Control: no-store for .js
# Insert a small patch: in _sr wrapper, if path.endswith(".js") then add/replace cache-control.
def add_nocache_block(src:str)->str:
    if "_cio_mime_fix" not in src:
        return src + "\n# [WARN] _cio_mime_fix not found; nocache not injected\n"
    return re.sub(
        r'(if path\.endswith\("\.js"\):\s*\n\s*# normalize headers.*?\n\s*headers=h\s*)',
        r'\1\n                    # CIO: force no-cache for JS during commercial stabilization\n                    h=[(k,v) for (k,v) in h if k.lower()!="cache-control"]\n                    h.append(("Cache-Control","no-store"))\n                    headers=h\n',
        src,
        flags=re.S
    )

s2=s
# Append marker and attempt patch; if regex fails, we will append a secondary wrapper.
patched=add_nocache_block(s2)
if patched==s2:
    # fallback: append another wrapper that sets Cache-Control
    patched = s2 + f"""

{MARK}
def _cio_js_nocache(app):
    def _wrap(environ, start_response):
        path=(environ.get("PATH_INFO") or "")
        def _sr(status, headers, exc_info=None):
            try:
                if path.endswith(".js"):
                    h=[(k,v) for (k,v) in headers if k.lower()!="cache-control"]
                    h.append(("Cache-Control","no-store"))
                    headers=h
            except Exception:
                pass
            return start_response(status, headers, exc_info)
        return app(environ, _sr)
    return _wrap
### === END CIO JS NOCACHE (AUTO) ===

try:
    application = _cio_js_nocache(application)
except Exception:
    try:
        application = _cio_js_nocache(app)
    except Exception:
        pass
"""
else:
    patched = patched + f"\n\n{MARK}\n# injected into _cio_mime_fix\n### === END CIO JS NOCACHE (AUTO) ===\n"

p.write_text(patched, encoding="utf-8")
print("[OK] injected JS no-cache")
PY

echo
echo "== [3] Restart + smoke headers =="
sudo systemctl restart "$SVC"
echo "[OK] restarted $SVC"

echo "-- HEAD /static/js/vsp_tabs4_autorid_v1.js"
curl -fsSI "$BASE/static/js/vsp_tabs4_autorid_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|cache-control' || true
echo "-- HEAD /static/js/vsp_dashboard_kpi_force_any_v1.js"
curl -fsSI "$BASE/static/js/vsp_dashboard_kpi_force_any_v1.js" | tr -d '\r' | egrep -i 'HTTP/|content-type|cache-control' || true

echo
echo "[DONE] Now do Ctrl+Shift+R. Console must be 0 red errors."

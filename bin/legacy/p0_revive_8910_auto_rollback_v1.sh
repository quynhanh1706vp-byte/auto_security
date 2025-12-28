#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3; need systemctl; need ss; need curl; need ls; need head; need tail

SVC="vsp-ui-8910.service"
APP="vsp_demo_app.py"
WSGI="wsgi_vsp_ui_gateway.py"
BASE="http://127.0.0.1:8910"

echo "== [0] current listener =="
ss -ltnp 2>/dev/null | grep ':8910' || echo "[NO LISTENER] 8910"

echo "== [1] quick compile check (current files) =="
python3 - <<'PY' || true
import py_compile
for f in ["vsp_demo_app.py","wsgi_vsp_ui_gateway.py"]:
    try:
        py_compile.compile(f, doraise=True)
        print("[OK] py_compile:", f)
    except Exception as e:
        print("[BAD] py_compile:", f, "->", e)
PY

echo "== [2] auto-rollback vsp_demo_app.py if broken =="
python3 - <<'PY'
from pathlib import Path
import py_compile

app = Path("vsp_demo_app.py")
def comp(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

if comp(app):
    print("[OK] current vsp_demo_app.py compiles; no rollback needed")
    raise SystemExit(0)

baks = sorted(Path(".").glob("vsp_demo_app.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
baks = baks[:80]

for b in baks:
    if comp(b):
        app.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored vsp_demo_app.py from:", b.name)
        raise SystemExit(0)

raise SystemExit("[ERR] no compiling backup found for vsp_demo_app.py (checked last 80)")
PY

echo "== [3] auto-rollback wsgi if broken =="
python3 - <<'PY' || true
from pathlib import Path
import py_compile

w = Path("wsgi_vsp_ui_gateway.py")
def comp(p: Path) -> bool:
    try:
        py_compile.compile(str(p), doraise=True)
        return True
    except Exception:
        return False

if not w.exists():
    print("[WARN] missing wsgi_vsp_ui_gateway.py")
    raise SystemExit(0)

if comp(w):
    print("[OK] current wsgi compiles; no rollback needed")
    raise SystemExit(0)

baks = sorted(Path(".").glob("wsgi_vsp_ui_gateway.py.bak_*"), key=lambda p: p.stat().st_mtime, reverse=True)
baks = baks[:80]

for b in baks:
    if comp(b):
        w.write_text(b.read_text(encoding="utf-8", errors="replace"), encoding="utf-8")
        print("[OK] restored wsgi from:", b.name)
        raise SystemExit(0)

print("[ERR] no compiling backup found for wsgi (checked last 80) — leaving as-is")
PY

echo "== [4] restart service =="
systemctl restart "$SVC" 2>/dev/null || true
sleep 1

echo "== [5] status + last logs =="
systemctl status "$SVC" --no-pager -l | sed -n '1,80p' || true
journalctl -u "$SVC" -n 120 --no-pager | tail -n 120 || true

echo "== [6] verify connect =="
ss -ltnp 2>/dev/null | grep ':8910' || echo "[NO LISTENER] 8910"
curl -sS -I "$BASE/runs" | head -n 8 || true
echo "[DONE]"

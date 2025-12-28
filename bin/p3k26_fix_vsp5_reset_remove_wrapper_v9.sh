#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"
PORT=8910
ERRLOG="/home/test/Data/SECURITY_BUNDLE/ui/out_ci/ui_${PORT}.error.log"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true
command -v sed >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true

echo "== [1] RESTORE gateway clean (vsp5hang backup) =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
cp -f "$BAK" "$W"
echo "[OK] restored $W from $BAK"

echo "== [2] Patch gateway: ONLY skip after_request injector on /vsp5 (NO wrapper edits) =="
python3 - <<'PY'
from pathlib import Path

W = Path("wsgi_vsp_ui_gateway.py")
lines = W.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK_AFTER = "VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"
TAG_AFTER  = "P3K26_SKIP_AFTERREQ_ONLY_V9"

def find_marker(mark: str):
    for i, ln in enumerate(lines):
        if mark in ln:
            return i
    return None

def find_enclosing_def(start_idx: int):
    for j in range(start_idx, -1, -1):
        ln = lines[j]
        if ln.lstrip().startswith("def ") and ln.rstrip().endswith(":"):
            return j
    return None

def insertion_after_def(def_idx: int):
    def_indent = len(lines[def_idx]) - len(lines[def_idx].lstrip())
    body_indent = def_indent + 4
    k = def_idx + 1
    while k < len(lines) and lines[k].strip()=="":
        k += 1
    if k < len(lines) and lines[k].lstrip().startswith(('"""',"'''")):
        q = lines[k].lstrip()[:3]
        k += 1
        while k < len(lines) and q not in lines[k]:
            k += 1
        if k < len(lines): k += 1
    return k, body_indent

if any(TAG_AFTER in ln for ln in lines):
    print("[OK] already patched (no-op)")
    raise SystemExit(0)

mi = find_marker(MARK_AFTER)
if mi is None:
    raise SystemExit(f"[ERR] marker not found: {MARK_AFTER}")

di = find_enclosing_def(mi)
if di is None:
    raise SystemExit("[ERR] cannot locate enclosing def for after_request marker")

ins, body_indent = insertion_after_def(di)
pad = " " * body_indent

snippet = (
    f"{pad}# {TAG_AFTER}: /vsp5 must NOT run injector (avoid hang/reset)\n"
    f"{pad}try:\n"
    f"{pad}    from flask import request as _r\n"
    f"{pad}    if (_r.path or '') == '/vsp5':\n"
    f"{pad}        _loc = locals()\n"
    f"{pad}        if 'response' in _loc: return _loc['response']\n"
    f"{pad}        if 'resp' in _loc: return _loc['resp']\n"
    f"{pad}        if 'r' in _loc: return _loc['r']\n"
    f"{pad}        if 'args' in _loc and isinstance(_loc['args'], tuple) and len(_loc['args'])>0: return _loc['args'][0]\n"
    f"{pad}        for _v in _loc.values(): return _v\n"
    f"{pad}except Exception:\n"
    f"{pad}    pass\n"
)

lines.insert(ins, snippet)
W.write_text("".join(lines), encoding="utf-8")
print("[OK] wrote gateway (after_request skip only)")
PY

echo "== [3] Patch app: ensure /vsp5 HTML route is registered right after app = Flask(...) =="
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p3k26_v9_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v9_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, os

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_VSP5_HTML_ROUTE_V9"
if TAG in s:
    print("[OK] vsp5 route already present (no-op)")
    raise SystemExit(0)

# Ensure imports (best-effort)
if "import os" not in s:
    s = "import os\n" + s

if "from flask import" in s and "Response" not in s:
    s = re.sub(r'(?m)^(from flask import .+)$', r'\1, Response', s, count=1)
if "from flask import" in s and "render_template" not in s:
    s = re.sub(r'(?m)^(from flask import .+)$', r'\1, render_template', s, count=1)

route_block = (
    f"\n# {TAG}: /vsp5 must return HTML shell (never JSON)\n"
    "@app.route('/vsp5')\n"
    "def vsp5():\n"
    "    try:\n"
    "        for cand in (\n"
    "            'vsp_dashboard_2025.html',\n"
    "            'vsp_dashboard_luxe.html',\n"
    "            'vsp_dashboard_2025_luxe.html',\n"
    "            'vsp5.html',\n"
    "        ):\n"
    "            tdir = getattr(app, 'template_folder', None) or 'templates'\n"
    "            if os.path.isfile(os.path.join(tdir, cand)):\n"
    "                return render_template(cand)\n"
    "    except Exception:\n"
    "        pass\n"
    "    html = (\n"
    "        '<!doctype html><html><head><meta charset=\"utf-8\">'\n"
    "        '<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">'\n"
    "        '<title>VSP Dashboard</title>'\n"
    "        '</head><body style=\"margin:0;background:#0b1220;color:#e5e7eb;\">'\n"
    "        '<div id=\"vsp-dashboard-main\"></div>'\n"
    "        '<script src=\"/static/js/vsp_bundle_tabs5_v1.js\"></script>'\n"
    "        '</body></html>'\n"
    "    )\n"
    "    return Response(html, mimetype='text/html')\n"
)

# Insert right after the first "app = Flask(" line (most reliable)
m = re.search(r'(?m)^\s*app\s*=\s*Flask\s*\(.*$', s)
if not m:
    print("[WARN] cannot find app = Flask(...); appending route at end")
    s = s + "\n" + route_block + "\n"
else:
    # insert after that line (and maybe after following config lines? keep simple)
    insert_pos = m.end()
    s = s[:insert_pos] + route_block + s[insert_pos:]
    print("[OK] inserted /vsp5 route right after app = Flask(...)")

p.write_text(s, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

echo "== [4] py_compile =="
python3 -m py_compile "$W" "$APP"
echo "[OK] py_compile OK"

echo "== [5] restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [6] smoke /vsp5 (3s) =="
set +e
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,90p'
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[FAIL] curl rc=$rc"
  echo "== journalctl last 120 =="
  sudo journalctl -u "$SVC" -n 120 --no-pager || true
  echo "== errlog tail 120 =="
  [ -f "$ERRLOG" ] && tail -n 120 "$ERRLOG" || echo "(no $ERRLOG)"
  exit 2
fi

echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true
echo "[DONE] p3k26_fix_vsp5_reset_remove_wrapper_v9"

#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"
APP="vsp_demo_app.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true

echo "== [1] RESTORE gateway from vsp5hang backup (NOT v6) =="
BAK="$(ls -1t "${W}.bak_p3k26_vsp5hang_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find ${W}.bak_p3k26_vsp5hang_*"; exit 2; }
echo "[OK] backup=$BAK"
cp -f "$BAK" "$W"
echo "[OK] restored $W"

echo "== [2] Patch gateway: skip AFTER_REQUEST injector on /vsp5 (signature-agnostic, safe) =="
python3 - <<'PY'
from pathlib import Path

W = Path("wsgi_vsp_ui_gateway.py")
lines = W.read_text(encoding="utf-8", errors="replace").splitlines(True)

MARK_AFTER = "VSP_P2_VSP5_ANCHOR_INJECT_AFTERREQ_SAFE_V2"
TAG_AFTER  = "P3K26_SKIP_AFTERREQ_V8"
MARK_WRAP  = "VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"
TAG_WRAP   = "P3K26_VSP5_PASSTHRU_V8"

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

changed=False

# after_request guard
if any(TAG_AFTER in ln for ln in lines):
    print("[OK] after_request already patched")
else:
    mi = find_marker(MARK_AFTER)
    if mi is None:
        raise SystemExit(f"[ERR] marker not found: {MARK_AFTER}")
    di = find_enclosing_def(mi)
    if di is None:
        raise SystemExit("[ERR] cannot locate enclosing def for after_request marker")
    ins, body_indent = insertion_after_def(di)
    pad = " " * body_indent
    snippet = (
        f"{pad}# {TAG_AFTER}: /vsp5 must NOT run injector (avoid hang)\n"
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
    changed=True
    print("[OK] after_request guard inserted")

# wrapper passthru (optional safety)
if any(TAG_WRAP in ln for ln in lines):
    print("[OK] wrapper already patched")
else:
    mw = find_marker(MARK_WRAP)
    if mw is not None:
        wrap_idx=None
        for i in range(mw, min(len(lines), mw+7000)):
            ln=lines[i]
            if ln.lstrip().startswith("def ") and ("environ" in ln and "start_response" in ln) and ln.rstrip().endswith(":"):
                wrap_idx=i; break
        if wrap_idx is not None:
            ins, body_indent = insertion_after_def(wrap_idx)
            pad=" " * body_indent
            look="".join(lines[wrap_idx: min(len(lines), wrap_idx+250)])
            target = "_app" if "_app(" in look or " _app" in look else "app"
            snippet=(
                f"{pad}# {TAG_WRAP}: /vsp5 passthrough before wrap logic\n"
                f"{pad}try:\n"
                f"{pad}    if (environ.get('PATH_INFO') or '') == '/vsp5':\n"
                f"{pad}        return {target}(environ, start_response)\n"
                f"{pad}except Exception:\n"
                f"{pad}    pass\n"
            )
            lines.insert(ins, snippet)
            changed=True
            print("[OK] wrapper passthru inserted")

if changed:
    W.write_text("".join(lines), encoding="utf-8")
    print("[OK] wrote gateway")
else:
    print("[WARN] no changes applied")
PY

echo "== [3] Patch vsp_demo_app.py: make /vsp5 ALWAYS return HTML =="
[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }
TS="$(date +%Y%m%d_%H%M%S)"
cp -f "$APP" "${APP}.bak_p3k26_v8_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v8_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

p=Path("vsp_demo_app.py")
s=p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_VSP5_HTML_ROUTE_V8"
if TAG in s:
    print("[OK] /vsp5 route already patched")
    raise SystemExit(0)

# Ensure needed imports (safe append near top if missing)
if "from flask import Response" not in s:
    s = re.sub(r'(?m)^(from flask import .+)$', r'\1, Response', s, count=1) if "from flask import" in s else s
if "render_template" not in s:
    s = re.sub(r'(?m)^(from flask import .+)$', r'\1, render_template', s, count=1) if "from flask import" in s else s
if "import os" not in s:
    s = "import os\n" + s

# Replace existing /vsp5 route block
pat = re.compile(r'(?ms)^\s*@app\.route\(\s*[\'"]\/vsp5[\'"][^\)]*\)\s*\n\s*def\s+\w+\s*\([^\)]*\)\s*:\s*\n.*?(?=^\s*@app\.route|\Z)')
m = pat.search(s)
new_block = (
    "@app.route(\"/vsp5\")\n"
    "def vsp5():\n"
    f"    # {TAG}: serve HTML dashboard shell (never JSON)\n"
    "    try:\n"
    "        # Prefer existing templates if present\n"
    "        for cand in (\n"
    "            \"vsp_dashboard_2025.html\",\n"
    "            \"vsp_dashboard_luxe.html\",\n"
    "            \"vsp_dashboard_2025_luxe.html\",\n"
    "            \"vsp5.html\",\n"
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
    "    return Response(html, mimetype=\"text/html\")\n"
)

if m:
    s = s[:m.start()] + new_block + "\n\n" + s[m.end():]
    print("[OK] replaced existing /vsp5 route block")
else:
    # If route not found, append near end
    s += "\n\n" + new_block + "\n"
    print("[WARN] /vsp5 route not found; appended new route at end")

p.write_text(s, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

echo "== [4] py_compile both =="
python3 -m py_compile "$W" "$APP"
echo "[OK] py_compile OK"

echo "== [5] restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [6] smoke /vsp5 (3s) and check Content-Type =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true

echo "[DONE] p3k26_fix_vsp5_root_html_and_restore_gateway_v8"

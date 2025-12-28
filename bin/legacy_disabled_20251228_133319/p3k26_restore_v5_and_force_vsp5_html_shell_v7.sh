#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
W="wsgi_vsp_ui_gateway.py"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true

echo "== [1] restore from latest v6 backup (this is your last known-good v5) =="
BAK="$(ls -1t "${W}.bak_p3k26_v6_"* 2>/dev/null | head -n 1 || true)"
[ -n "$BAK" ] || { echo "[ERR] cannot find ${W}.bak_p3k26_v6_*"; exit 2; }
echo "[OK] backup=$BAK"
cp -f "$BAK" "$W"
echo "[OK] restored $W"

echo "== [2] patch: serve HTML shell directly for /vsp5 inside wrapper =="
python3 - <<'PY'
from pathlib import Path
import os, re

TAG="P3K26_FORCE_VSP5_HTML_SHELL_V7"
W=Path("wsgi_vsp_ui_gateway.py")
lines=W.read_text(encoding="utf-8", errors="replace").splitlines(True)

if any(TAG in ln for ln in lines):
    print("[OK] already patched (no-op)")
    raise SystemExit(0)

# Locate the wrapper def(environ, start_response)
wrap_idx=None
for i,ln in enumerate(lines):
    if ln.lstrip().startswith("def ") and ("environ" in ln and "start_response" in ln) and ln.rstrip().endswith(":"):
        # heuristic: prefer the one near your existing marker if present
        wrap_idx=i
        # keep going to find the most relevant? We'll accept first, but try pick later with marker nearby
        break

# If marker exists, pick wrapper after marker
MARK="VSP_P2_VSP5_ANCHOR_WSGI_WRAP_V1"
m_idx=next((i for i,ln in enumerate(lines) if MARK in ln), None)
if m_idx is not None:
    for i in range(m_idx, min(len(lines), m_idx+8000)):
        ln=lines[i]
        if ln.lstrip().startswith("def ") and ("environ" in ln and "start_response" in ln) and ln.rstrip().endswith(":"):
            wrap_idx=i
            break

if wrap_idx is None:
    raise SystemExit("[ERR] cannot find wrapper def(environ, start_response)")

def_indent = len(lines[wrap_idx]) - len(lines[wrap_idx].lstrip())
body_indent = def_indent + 4

# insert after def + optional docstring
ins = wrap_idx + 1
while ins < len(lines) and lines[ins].strip()=="":
    ins += 1
if ins < len(lines) and lines[ins].lstrip().startswith(('"""',"'''")):
    q = lines[ins].lstrip()[:3]
    ins += 1
    while ins < len(lines) and q not in lines[ins]:
        ins += 1
    if ins < len(lines):
        ins += 1

pad=" " * body_indent

# Try load an existing template if present; fallback to minimal shell that loads bundle tabs 5
snippet = (
f"{pad}# {TAG}: return HTML (text/html) for /vsp5, bypass injectors/wrap loops\n"
f"{pad}try:\n"
f"{pad}    _pi = (environ.get('PATH_INFO') or '')\n"
f"{pad}    if _pi == '/vsp5':\n"
f"{pad}        import os\n"
f"{pad}        _html = None\n"
f"{pad}        for _cand in (\n"
f"{pad}            'templates/vsp_dashboard_2025.html',\n"
f"{pad}            'templates/vsp_dashboard_luxe.html',\n"
f"{pad}            'templates/vsp_dashboard_2025_luxe.html',\n"
f"{pad}            'templates/vsp5.html',\n"
f"{pad}        ):\n"
f"{pad}            if os.path.isfile(_cand):\n"
f"{pad}                try:\n"
f"{pad}                    _html = open(_cand,'r',encoding='utf-8',errors='replace').read()\n"
f"{pad}                    break\n"
f"{pad}                except Exception:\n"
f"{pad}                    _html = None\n"
f"{pad}        if not _html:\n"
f"{pad}            _html = (\n"
f"{pad}              '<!doctype html><html><head><meta charset=\"utf-8\">'\n"
f"{pad}              '<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">'\n"
f"{pad}              '<title>VSP Dashboard</title>'\n"
f"{pad}              '<link rel=\"icon\" href=\"/static/favicon.ico\">'\n"
f"{pad}              '</head><body style=\"margin:0;background:#0b1220;color:#e5e7eb;\">'\n"
f"{pad}              '<div id=\"vsp-dashboard-main\"></div>'\n"
f"{pad}              '<script src=\"/static/js/vsp_bundle_tabs5_v1.js\"></script>'\n"
f"{pad}              '</body></html>'\n"
f"{pad}            )\n"
f"{pad}        _b = _html.encode('utf-8', errors='replace')\n"
f"{pad}        start_response('200 OK', [\n"
f"{pad}            ('Content-Type','text/html; charset=utf-8'),\n"
f"{pad}            ('Cache-Control','no-store'),\n"
f"{pad}            ('X-VSP-MARKERS-FINAL','v4'),\n"
f"{pad}        ])\n"
f"{pad}        return [_b]\n"
f"{pad}except Exception:\n"
f"{pad}    pass\n"
)

lines.insert(ins, snippet)
W.write_text(''.join(lines), encoding='utf-8')
print(f"[OK] inserted HTML-shell handler into wrapper at line {wrap_idx+1}")
PY

echo "== [3] py_compile =="
python3 -m py_compile "$W"
echo "[OK] py_compile OK"

echo "== [4] restart =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [5] smoke /vsp5 headers (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "== [6] first lines =="
head -n 20 /tmp/vsp5.html || true
echo "[DONE] p3k26_restore_v5_and_force_vsp5_html_shell_v7"

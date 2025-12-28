#!/usr/bin/env bash
set -euo pipefail
cd /home/test/Data/SECURITY_BUNDLE/ui

APP="vsp_demo_app.py"
SVC="${VSP_UI_SVC:-vsp-ui-8910.service}"
BASE="${VSP_UI_BASE:-http://127.0.0.1:8910}"
TS="$(date +%Y%m%d_%H%M%S)"

need(){ command -v "$1" >/dev/null 2>&1 || { echo "[ERR] missing: $1"; exit 2; }; }
need python3
command -v systemctl >/dev/null 2>&1 || true
command -v curl >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

echo "== [0] backup =="
cp -f "$APP" "${APP}.bak_p3k26_v10_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v10_${TS}"

python3 - <<'PY'
from pathlib import Path
import re

APP=Path("vsp_demo_app.py")
s=APP.read_text(encoding="utf-8", errors="replace")
TAG="P3K26_VSP5_HTML_ROUTE_V10"

# If prior broken insertion exists (v9), rollback it first by removing that injected block
# We remove from the comment "# P3K26_VSP5_HTML_ROUTE_V9" until the next "@app.route" (exclusive).
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V9.*?(?=^\s*@app\.route|\Z)', '', s)

if TAG in s:
    print("[OK] already patched (no-op)")
    APP.write_text(s, encoding="utf-8")
    raise SystemExit(0)

# Ensure imports
if "import os" not in s:
    s = "import os\n" + s

# Make sure Response/render_template are available
if "from flask import" in s:
    # add Response/render_template into the first flask import line if missing
    def add_to_flask_import(line: str):
        if "Response" not in line: line = line.rstrip() + ", Response\n"
        if "render_template" not in line: line = line.rstrip()[:-1] + ", render_template\n"
        return line
    s = re.sub(r'(?m)^(from flask import .+\n)', lambda m: add_to_flask_import(m.group(1)), s, count=1)

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
"            import os as _os\n"
"            if _os.path.isfile(_os.path.join(tdir, cand)):\n"
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

# SAFE insertion point strategy:
# 1) Find first top-level "@app.route" and insert BEFORE it.
m = re.search(r'(?m)^\s*@app\.route\(', s)
if m:
    pos = m.start()
    s2 = s[:pos] + route_block + "\n\n" + s[pos:]
    print("[OK] inserted /vsp5 route before first @app.route (safe)")
else:
    # 2) Else insert after a completed "app = Flask(...)" statement (line ending with ')')
    lines = s.splitlines(True)
    pos = None
    for i,ln in enumerate(lines):
        if re.match(r'^\s*app\s*=\s*Flask\b', ln):
            # find statement end by tracking parentheses until balanced
            text = "".join(lines[i:i+200])
            # naive: find first line after i where cumulative parens balance back to 0
            bal=0
            found=False
            for j in range(i, min(len(lines), i+200)):
                bal += lines[j].count("(") - lines[j].count(")")
                if j>i and bal<=0:
                    pos = sum(len(x) for x in lines[:j+1])
                    found=True
                    break
            if found:
                break
    if pos is None:
        # last resort: append at end
        s2 = s + "\n\n" + route_block + "\n"
        print("[WARN] inserted /vsp5 route at end (no routes found)")
    else:
        s2 = s[:pos] + route_block + "\n" + s[pos:]
        print("[OK] inserted /vsp5 route after completed app=Flask(...) statement")

APP.write_text(s2, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py")
PY

echo "== [1] py_compile =="
python3 -m py_compile vsp_demo_app.py
echo "[OK] py_compile OK"

echo "== [2] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [3] smoke /vsp5 (3s) =="
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,80p'
echo "== head /tmp/vsp5.html =="
head -n 20 /tmp/vsp5.html || true

echo "[DONE] p3k26_fix_vsp_demo_app_insert_vsp5_route_safe_v10"

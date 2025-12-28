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
command -v ls >/dev/null 2>&1 || true
command -v head >/dev/null 2>&1 || true
command -v tail >/dev/null 2>&1 || true

[ -f "$APP" ] || { echo "[ERR] missing $APP"; exit 2; }

echo "== [0] backup current app =="
cp -f "$APP" "${APP}.bak_p3k26_v12_before_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v12_before_${TS}"

echo "== [1] find a truly clean backup (compile + ast.parse) =="
python3 - <<'PY'
from pathlib import Path
import ast, os, sys, glob

app = Path("vsp_demo_app.py")
cands = sorted(glob.glob(str(app) + ".bak_*"), key=lambda p: os.path.getmtime(p), reverse=True)

def is_clean(path: str) -> bool:
    s = Path(path).read_text(encoding="utf-8", errors="replace")
    try:
        compile(s, path, "exec")
        ast.parse(s)
        return True
    except Exception:
        return False

good = None
for p in cands:
    if is_clean(p):
        good = p
        break

if not good:
    print("[ERR] no clean backup found (compile+parse). Showing current tail+hint.")
    s = app.read_text(encoding="utf-8", errors="replace")
    try:
        compile(s, str(app), "exec")
    except Exception as e:
        print("compile_error:", repr(e))
    print("tail_120:")
    print("\n".join(s.splitlines()[-120:]))
    sys.exit(2)

# restore
Path(good).replace(app)  # atomic move replaces app
print("[OK] restored from:", good)

# verify
s = app.read_text(encoding="utf-8", errors="replace")
compile(s, str(app), "exec")
ast.parse(s)
print("[OK] restored file is clean")
PY

echo "== [2] remove ALL existing /vsp5 routes (even broken/truncated) then insert clean HTML route =="
cp -f "$APP" "${APP}.bak_p3k26_v12_preroute_${TS}"
echo "[BACKUP] ${APP}.bak_p3k26_v12_preroute_${TS}"

python3 - <<'PY'
from pathlib import Path
import re, ast

p = Path("vsp_demo_app.py")
s = p.read_text(encoding="utf-8", errors="replace")

TAG="P3K26_VSP5_HTML_ROUTE_V12"

# 1) Remove any prior injected blocks by tags (v8..v11b) if present
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V8.*?(?=^\s*@app\.route|\Z)', '', s)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V9.*?(?=^\s*@app\.route|\Z)', '', s)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V10.*?(?=^\s*@app\.route|\Z)', '', s)
s = re.sub(r'(?ms)^\s*#\s*P3K26_VSP5_HTML_ROUTE_V11B.*?(?=^\s*@app\.route|\Z)', '', s)

# 2) Remove any @app.route('/vsp5') route blocks (even if body is missing)
#    - normal block removal (until next @app.route or EOF)
s = re.sub(
    r'(?ms)^\s*@app\.route\(\s*[\'"]\/vsp5[\'"][^\)]*\)\s*\n\s*def\s+vsp5\s*\([^\)]*\)\s*:\s*\n.*?(?=^\s*@app\.route|\Z)',
    '',
    s
)

# 3) Remove stray "def vsp5():" at top-level with no body (rare truncation)
s = re.sub(r'(?m)^\s*def\s+vsp5\s*\(\s*\)\s*:\s*$', '', s)

if TAG in s:
    print("[OK] already has v12 route (no-op)")
else:
    route_block = (
        f"\n# {TAG}: /vsp5 must return HTML shell (never JSON)\n"
        "@app.route('/vsp5')\n"
        "def vsp5():\n"
        "    from flask import Response, render_template\n"
        "    import os\n"
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

    # Insert BEFORE the first @app.route (safest at top-level)
    m = re.search(r'(?m)^\s*@app\.route\(', s)
    if m:
        pos = m.start()
        s = s[:pos] + route_block + "\n\n" + s[pos:]
        print("[OK] inserted v12 /vsp5 route before first @app.route")
    else:
        s = s + "\n\n" + route_block + "\n"
        print("[WARN] no @app.route found; appended v12 /vsp5 at end")

# Validate syntax after modifications
compile(s, str(p), "exec")
ast.parse(s)

p.write_text(s, encoding="utf-8")
print("[OK] wrote vsp_demo_app.py with v12 route")
PY

echo "== [3] py_compile =="
python3 -m py_compile "$APP"
echo "[OK] py_compile OK"

echo "== [4] restart service =="
if command -v systemctl >/dev/null 2>&1; then
  sudo systemctl restart "$SVC" || true
  sudo systemctl is-active "$SVC" && echo "[OK] service active" || echo "[WARN] service not active"
fi

echo "== [5] smoke /vsp5 (3s) =="
set +e
curl -sv --connect-timeout 1 --max-time 3 "$BASE/vsp5" -o /tmp/vsp5.html 2>&1 | sed -n '1,90p'
rc=$?
set -e
if [ "$rc" -ne 0 ]; then
  echo "[FAIL] curl rc=$rc"
  sudo journalctl -u "$SVC" -n 120 --no-pager || true
  exit 2
fi

echo "== [6] head /tmp/vsp5.html =="
head -n 30 /tmp/vsp5.html || true
echo "[DONE] p3k26_rescue_vsp_demo_app_clean_restore_and_patch_vsp5_v12"
